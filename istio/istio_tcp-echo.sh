
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

kubectl label namespace default istio.io/dataplane-mode=ambient
kubectl apply -f samples/curl/curl.yaml
kubectl apply -f samples/tcp-echo/tcp-echo-services.yaml
sleep 5

kubectl apply -f samples/tcp-echo/gateway-api/tcp-echo-all-v1.yaml
kubectl get pods
kubectl get svc
kubectl get gtw
kubectl get tcproute

istioctl waypoint apply --enroll-namespace --overwrite --wait
kubectl -n istio-io-tcp-traffic-shifting apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TCPRoute
metadata:
  name: tcp-echo-ew
spec:
  parentRefs:
  - group: ""
    kind: Service
    name: tcp-echo
  rules:
  - backendRefs:
    - name: tcp-echo-v1
      port: 9000
      weight: 90
    - name: tcp-echo-v2
      port: 9000
      weight: 10
EOF

kubectl get pods
kubectl get svc
kubectl get gtw
kubectl get tcproute

