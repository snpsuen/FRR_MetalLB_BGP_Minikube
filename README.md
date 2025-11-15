A handy ContainerLab environment is set up to allow us to experiment with the use of MetalLB in BGP mode. It provids a VIP address for an external client to access a loadbancer-typed Kubenetes service. Central to the setup is a fabric of FRR switches that connect a client network to a minikube K8s cluster through BGP routes.

### TL;DR
![ContainerLab FRR MetalLB Minikube](containerlab_frr_mk02.png)
