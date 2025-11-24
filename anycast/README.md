![containerlab_anycast](containerlab_anycast02.png)

Our next task is to set up BGP anycast routes for MetalLB to distribute workloads between multiple instances of a Kubernetes service. To this end, a new minikube K8s cluster is added to the ContainerLab topology to host the nginx service with the same virtual IP (VIP) as the one advertised by MetalLB on the first cluster.

### Key success factors

There are three key success factors to accomplish the task. First, MetalLB speakers will be deployed on both minikube clusters to run in the BGP mode to advertise the nginx VIP to the upstream FRR switches. 

In addition, the FRR spine switch will accept the two BGP routes destined to the anycast VIP on the respective minikube clusters and install them as ECMP routes in the kernel FIB table.

Finally, the kernel of the FRR spine switch will use a suitable hash policy to spread different connections to the anycast VIP between the ECMP routes.

### Lab inventory

The setup is
