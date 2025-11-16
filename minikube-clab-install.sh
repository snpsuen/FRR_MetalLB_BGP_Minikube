#!/bin/bash

curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
systemctl stop docker
rm -rf /var/lib/docker
rm /etc/containerd/config.toml
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
