#!/bin/bash

sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod u+x ./kind
cp -p ./kind /usr/local/bin

kind create cluster --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: istio
nodes:
 - role: control-plane
 - role: worker
EOF

kubectl taint nodes istio-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
kubectl get nodes -o wide

curl -L https://istio.io/downloadIstio | sh -
cd istio*
export PATH=$PWD/bin:$PATH
istioctl version

istioctl install --skip-confirmation -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    cni:
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 0m
            memory: 0Mi
    ztunnel:
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 0m
            memory: 0Mi
    pilot:
      k8s:
        env:
        - name: PILOT_TRACE_SAMPLING
          value: "100"
        - name: PILOT_ENABLE_ALPHA_GATEWAY_API
          value: "true"
        resources:
          requests:
            cpu: 0m
            memory: 0Mi
EOF

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
