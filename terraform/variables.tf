variable "env" {
  description = "Name of the environment"
  # this value is set by bin/.bin/env-wrapper
}
variable "access_key" {
  description = "AWS access key"
  #
  # NOTE: this value comes from terraform.tfvars
  #
}
variable "secret_key" {
  description = "AWS secret key"
  #
  # NOTE: this value comes from terraform.tfvars
  #
}
variable "ssh_keypair_prefix" {
  description = "Prefix of the SSH keypair for logging into instances, to be followed by the env (cluster) name"
  default = "quorum-"
}
variable "tunnel_keypair_name" {
  description = "Name of the SSH keypair for tunneling between quorum nodes within AWS"
  default = "tunnel"
}
variable "project" {
  default = "nocenter-quorum-cluster"
}
variable "instance_types" {
  default = {
    quorum = "m3.large"
    # TODO: other types of nodes, like for metrics or rpc (tx) senders
  }
}
variable "volume_types" {
  default = {
    quorum = "gp2"
  }
}
variable "volume_sizes" {
  default = {
    quorum = "50"
  }
}
variable "local_datadir_root" {
  default = "cluster-data"
}
variable "remote_user" {
  default = "ubuntu"
}
variable "remote_homedir" {
  default = "/home/ubuntu"
}
variable "precreated_global_quorum_iam_instance_profile_id" {
  default = "quorum-cluster.global.ecrAccessor" # This was the output of provisioning the permanent "global" IAM infrastructure.
}

#
# Variables that can be overridden by multi-region settings (see: multi-region-vars/*.tfvars):
#
variable "multi_region" {
  description = "Whether the cluster spans AWS regions. This is a boolean represented as a string until TF supports first-class booleans."
  default = "0"
}
variable "aws_region" {
  description = "AWS region"
  default = "us-west-2"
}
variable "subnet_azs" {
  type = "list"
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}
variable "total_cluster_size" {
  default = 3 # Number of quorum nodes in this cluster across all aws regions.
}
variable "num_instances" {
  default = 3 # This is less than total_cluster_size when we are running a multi-region setup.
}
variable "first_geth_id" {
  description = "Amount to add to the instance's count.index to calculate gethId. This is primarily for supporting multi-region clusters."
  default = 1
}
#
# [End of variables overridden by multi-region settings.]
#
