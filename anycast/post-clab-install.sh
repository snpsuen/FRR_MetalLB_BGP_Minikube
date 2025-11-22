#!/bin/bash

systemctl start docker
minikube start --driver=docker --nodes 1 -p mkcluster01 --cpus=1 --force
minikube profile list  
minikube profile mkcluster01
minikube kubectl -- get nodes -o wide

minikube start --driver=docker --nodes 1 -p mkcluster02 --static-ip 192.168.99.2 --cpus=1 --force
minikube profile list  
minikube profile mkcluster02
minikube kubectl -- get nodes -o wide

network_id=$(docker network inspect -f {{.Id}} mkcluster01)
bridge_name01="br-${network_id:0:12}"
network_id=$(docker network inspect -f {{.Id}} mkcluster02)
bridge_name02="br-${network_id:0:12}"

export MK_BRIDGE01=$bridge_name01
export MK_BRIDGE02=$bridge_name02
envsubst '$MK_BRIDGE01 $MK_BRIDGE02' < clab_bgp_anycast_template.yaml > clab_bgp_anycast_inst.yaml

clab deploy -t clab_bgp_anycast_inst.yaml
clab inspect -t clab_bgp_anycast_inst.yaml
