#!/bin/bash

sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod u+x ./kind
cp -p ./kind /usr/local/bin

kind create cluster --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cilium
nodes:
 - role: control-plane
 - role: worker
EOF

kubectl taint nodes cilium-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
kubectl describe node cilium-worker | grep Taints

kubectl delete daemonset -n kube-system kube-proxy
docker exec cilium-control-plane rm -rf /etc/cni/net.d/*
docker exec cilium-worker rm -rf /etc/cni/net.d/*
