#!/bin/bash

curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH

istioctl install --set components.pilot.k8s.resources.requests.cpu=0 --set components.pilot.k8s.resources.requests.memory=0 \
--set components.ztunnel.k8s.resources.requests.cpu=0 --set components.ztunnel.k8s.resources.requests.memory=0 \
--set values.pilot.env.PILOT_ENABLE_ALPHA_GATEWAY_API=true --set profile=ambient --skip-confirmation

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
kubectl -n istio-system get pods

kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f samples/bookinfo/platform/kube/bookinfo-versions.yaml
kubectl apply -f samples/bookinfo/gateway-api/bookinfo-gateway.yaml
kubectl get gtw
kubectl get HTTPRoute
kubectl get pods -o wide
kubectl get svc

kubectl label namespace default istio.io/dataplane-mode=ambient
istioctl waypoint apply --enroll-namespace --wait
kubectl get gtw
kubectl get pods -o wide
kubectl get svc

kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: reviews
spec:
  parentRefs:
  - group: ""
    kind: Service
    name: reviews
    port: 9080
  rules:
  - backendRefs:
    - name: reviews-v1
      port: 9080
      weight: 90
    - name: reviews-v2
      port: 9080
      weight: 10
EOF
kubectl get HTTPRoute

kubectl apply -f samples/curl/curl.yaml
kubectl get pods -o wide
kubectl get svc
