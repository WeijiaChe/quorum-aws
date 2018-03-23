#!/bin/bash

set -euo pipefail

gid=$(cat node-id)
p2p_port=$((21000 + $gid))
rpc_port=$((22000 + $gid))
raft_port=$((50400 + $gid))

echo "starting geth ${gid}"

ARGS="--rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum --emitcheckpoints"

sudo docker run -d -p $p2p_port:$p2p_port -p $rpc_port:$rpc_port -p $raft_port:$raft_port -v /home/ubuntu/datadir:/datadir -v /home/ubuntu/password:/password -e PRIVATE_CONFIG='/datadir/constellation.toml' quorum --datadir /datadir $ARGS --port $p2p_port --rpcport $rpc_port --raftport $raft_port --verbosity 3 --nodiscover --rpc --rpccorsdomain "'*'" --rpcaddr '0.0.0.0' --raft --unlock 0 --password /password
