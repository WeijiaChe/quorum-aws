provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.aws_region}"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "quorum_cluster" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} vpc"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_internet_gateway" "quorum_cluster" {
  vpc_id = "${aws_vpc.quorum_cluster.id}"

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} internet gateway"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_subnet" "subnet" {
  count = "${length(var.subnet_azs)}"

  vpc_id = "${aws_vpc.quorum_cluster.id}"

  cidr_block = "10.0.${count.index + 1}.0/24"
  availability_zone = "${element(var.subnet_azs, count.index)}"

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} subnet ${count.index + 1}"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_route_table" "quorum_cluster" {
  vpc_id = "${aws_vpc.quorum_cluster.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.quorum_cluster.id}"
  }

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} route table"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_route_table_association" "rta" {
  count = "${length(var.subnet_azs)}"

  subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.quorum_cluster.id}"
}

resource "aws_security_group" "ssh_open" {
  name = "${var.project} ${var.env} ssh access"
  description = "Allow ssh connections"
  vpc_id = "${aws_vpc.quorum_cluster.id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} ssh access"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_security_group" "rpc_sender" {
  name = "${var.project} ${var.env} rpc sender"
  description = "Can send RPC traffic to ${var.project} quorum nodes"
  vpc_id = "${aws_vpc.quorum_cluster.id}"

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} rpc sender"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "aws_security_group" "quorum_instance" {
  name = "${var.project} ${var.env} quorum instance"
  description = "Allow eth p2p from other quorum nodes and RPC traffic from designated nodes"
  vpc_id = "${aws_vpc.quorum_cluster.id}"

  # Geth P2P traffic
  ingress {
    from_port = 21000
    to_port = 21900
    protocol = "tcp"
    self = true # incoming traffic comes from this same security group
  }

  # Geth admin RPC traffic
  ingress {
    from_port = 22000
    to_port = 22900
    protocol = "tcp"
    security_groups = ["${aws_security_group.rpc_sender.id}"]
  }

  # Raft HTTP traffic
  ingress {
    from_port = 50400
    to_port = 50900
    protocol = "tcp"
    self = true # incoming traffic comes from this same security group
  }

  # Constellation traffic
  ingress {
    from_port = 9000
    to_port = 9900
    protocol = "tcp"
    self = true # incoming traffic comes from this same security group
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} quorum instance"
    Environment = "${var.env}"
    Terraformed = "true"
  }
}

resource "null_resource" "cluster_datadirs" {
  triggers {
    num_instances = "${var.num_instances}"
    subnet_azs = "${join(",", var.subnet_azs)}"
    local_datadir_root = "${var.local_datadir_root}"
  }

  provisioner "local-exec" {
    command = "${var.multi_region ? (var.first_geth_id == "1" ? "stack exec -- aws-bootstrap --cluster-size ${var.total_cluster_size} --subnets ${length(var.subnet_azs)} --path ${var.local_datadir_root} --multi-region" : "echo skipping datadir creation for multi-region cluster beyond the first region") : "stack exec -- aws-bootstrap --cluster-size ${var.total_cluster_size} --subnets ${length(var.subnet_azs)} --path ${var.local_datadir_root}" }"
  }
}

resource "aws_key_pair" "quorum" {
  key_name = "${var.ssh_keypair_prefix}${var.env}"
  public_key = "${file("secrets/ec2-keys/${var.ssh_keypair_prefix}${var.env}.pub")}"
}

resource "aws_instance" "quorum" {
  count = "${var.num_instances}"
  depends_on = ["null_resource.cluster_datadirs"]

  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${lookup(var.instance_types, "quorum")}"
  iam_instance_profile = "${var.precreated_global_quorum_iam_instance_profile_id}"
  #
  # NOTE: rpc_sender is in this list temporarily, until we provision nodes that are dedicated to send txes
  #
  vpc_security_group_ids = ["${aws_security_group.quorum_instance.id}", "${aws_security_group.ssh_open.id}", "${aws_security_group.rpc_sender.id}"]
  key_name = "${var.ssh_keypair_prefix}${var.env}"
  associate_public_ip_address = true

  availability_zone = "${element(aws_subnet.subnet.*.availability_zone, count.index % length(aws_subnet.subnet.*.id))}"
  subnet_id =         "${element(aws_subnet.subnet.*.id,                count.index % length(aws_subnet.subnet.*.id))}"

  private_ip = "${cidrhost(element(aws_subnet.subnet.*.cidr_block, count.index % length(aws_subnet.subnet.*.id)), 101 + (count.index / length(aws_subnet.subnet.*.id)))}"

  root_block_device {
    volume_type = "${lookup(var.volume_types, "quorum")}"
    volume_size = "${lookup(var.volume_sizes, "quorum")}"
    delete_on_termination = "true"
  }

  tags {
    Project = "${var.project}"
    Name = "${var.project} ${var.env} node ${count.index + 1}"
    Environment = "${var.env}"
    Terraformed = "true"
  }

  connection {
    user = "${var.remote_user}"
    host = "${self.public_ip}"
    timeout = "1m"
    private_key = "${file("secrets/ec2-keys/${var.ssh_keypair_prefix}${var.env}.pem")}"
  }

  provisioner "file" {
    source = "${var.local_datadir_root}/geth${var.first_geth_id + count.index}"
    destination = "${var.remote_homedir}/datadir"
  }

  provisioner "file" {
    source = "secrets/${var.tunnel_keypair_name}"
    destination = "${var.remote_homedir}/.ssh/${var.tunnel_keypair_name}"
  }

  provisioner "file" {
    source = "secrets/${var.tunnel_keypair_name}.pub"
    destination = "${var.remote_homedir}/.ssh/${var.tunnel_keypair_name}.pub"
  }

  provisioner "file" {
    source = "scripts/install/spam.sh"
    destination = "${var.remote_homedir}/spam"
  }

  provisioner "file" {
    source = "scripts/install/attach.sh"
    destination = "${var.remote_homedir}/attach"
  }

  provisioner "file" {
    source = "scripts/install/follow.sh"
    destination = "${var.remote_homedir}/follow"
  }

  provisioner "file" {
    source = "scripts/install/start-tunnels.sh"
    destination = "${var.remote_homedir}/.start-tunnels"
  }

  provisioner "file" {
    source = "scripts/install/start-constellation.sh"
    destination = "${var.remote_homedir}/.start-constellation"
  }

  provisioner "file" {
    source = "scripts/install/start-quorum.sh"
    destination = "${var.remote_homedir}/.start-quorum"
  }

  provisioner "file" {
    source = "scripts/install/start.sh"
    destination = "${var.remote_homedir}/start"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x spam",
      "chmod +x attach",
      "chmod +x follow",
      "chmod +x .start-tunnels",
      "chmod +x .start-constellation",
      "chmod +x .start-quorum",
      "chmod +x start",
      "echo '${var.first_geth_id + count.index}' >node-id",
      "echo 'abcd' >password",
      "echo '${var.multi_region ? "multi-region" : "single-region"}' >cluster-type",
      "echo '${var.total_cluster_size}' >cluster-size",
      "echo '${length(var.subnet_azs)}' >num-subnets"
    ]
  }

  provisioner "remote-exec" {
    scripts = [
      "scripts/provision/prepare.sh",
      "scripts/provision/fetch-images.sh",
      "scripts/provision/start-single-region-cluster.sh"
    ]
  }
}

#
# If this is a multi-region cluster, we allocate an EIP for each instance in the region
#

resource "aws_eip" "static_ip" {
  count = "${ var.multi_region ? "${var.num_instances}" : "0"}"
  vpc = true
}

resource "aws_eip_association" "quorum_eip_association" {
  count = "${ var.multi_region ? "${var.num_instances}" : "0"}"
  instance_id = "${element(aws_instance.quorum.*.id, count.index)}"
  allocation_id = "${element(aws_eip.static_ip.*.id, count.index)}"
}
