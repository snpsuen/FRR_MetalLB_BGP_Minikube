#!/bin/bash

systemctl start docker
minikube start --nodes 2 -p mkcluster --cpus=1 --force
minikube profile list  
minikube profile mkcluster
minikube kubectl get nodes
minikube kubectl describe node mkcluster | grep Taints
minikube kubectl taint nodes mkcluster node-role.kubernetes.io/master:NoSchedule-

network_id=$(docker network inspect -f {{.Id}} mkcluster)
bridge_name="br-${network_id:0:12}"

export MK_BRIDGE=$bridge_name
envsubst '$MK_BRIDGE' < clab_frr_minikube_template.yaml > clab_frr_minikube_inst.yaml
clab deploy -t clab_frr_minikube_inst.yaml
clab inspect -t clab_frr_minikube_inst.yaml
