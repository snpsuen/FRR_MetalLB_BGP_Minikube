#!/bin/bash

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: l2policy01
spec:
# serviceSelector:
#   matchLabels:
#     color: blue
  nodeSelector:
    matchExpressions:
    - key: node-role.kubernetes.io/control-plane
      operator: DoesNotExist
  interfaces:
  - ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
EOF

kubectl apply -f - <<EOF
apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "lbpool01"
spec:
  blocks:
  - start: "10.20.0.10"
    stop: "10.20.0.20"
EOF
