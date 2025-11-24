![containerlab_anycast](containerlab_anycast02.png)

Our next task is to set up BGP anycast routes for MetalLB to distribute workloads between multiple instances of a Kubernetes service. To this end, a new minikube K8s cluster is added to the ContainerLab topology to host the nginx service with the same VIP as the one advertised by MetalLB on the first cluster
