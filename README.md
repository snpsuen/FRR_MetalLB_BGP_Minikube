![ContainerLab FRR MetalLB Minikube](containerlab_frr_mk02.png)

A handy ContainerLab environment is set up to allow us to experiment with the use of MetalLB in BGP mode. It is provisioned as a load balancer to manage access from an external client to a Kubenetes service via a VIP address.

Central to the lab is a FRR fabric that connects a client network to a minikube K8s cluster through BGP routes. The topology looks like a miniture Internet connection. 

The upstream FFR leaf switches behave as Internet service providers for the client and Kubernetes while the FRR spine switch assumes the role of an Internet backbone. Altogether they cooperate to establish BGP connectivity end to end, similar to what is being achieved on the Internet at large.

### Summary of the container inventory in ContainerLab
<table>
	<thead>
		<tr>
			<th scope="col">ContainerLab Node</th>
			<th scope="col">Network Configuration</th>
			<th scope="col">Creator</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">Client workstation</td>
			<td aligh="left">Host IP: 192.168.100.11/24</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Leaf 1</td>
			<td aligh="left">Network Prefix: 192.168.100.0/24 <br>
				Network Prefix: 10.0.1.0/24 <br>
				BGP ASN: 65001
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Spine</td>
			<td aligh="left">Network Prefix: 10.0.1.0/24 <br>
				Network Prefix: 10.0.2.0/24 <br>
				BGP ASN: 64999
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
		    <td aligh="left">FRR Leaf 2</td>
			<td aligh="left">Network Prefix: 10.0.2.0/24 <br>
				Network Prefix: 192.168.49.0/24 <br>
				BGP ASN: 65002
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube docker bridge</td>
			<td aligh="left">Network Prefix (transparent): Network Prefix: 192.168.49.0/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster node 1</td>
			<td aligh="left">Host IP: 192.168.49.2/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster node 2</td>
			<td aligh="left">Host IP: 192.168.49.3/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
	</tbody>
</table>

### 1. Install Minikube and ContainterLab

In this example, we opt to run the lab in a Killercoda Ubuntu playground with minimal system requirements.
```
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
```

If your platform is already running docker, like a Ubuntu playground on Killercoda, it is necessary to clean up certain existing docker data before installing ContainerLab, which also includes the docker engine.
```
systemctl stop docker
rm -rf /var/lib/docker
rm /etc/containerd/config.toml
curl -sL https://containerlab.dev/setup | sudo -E bash -s "all"
```

### 2. Set up a Minikube Kubernetes cluster

Create a 2-node K8s cluster named mkcluster on Minikube.
```
systemctl start docker
minikube start --nodes 2 -p mkcluster --cpus=1 --force
minikube profile list  
minikube profile mkcluster
minikube kubectl get nodes
minikube kubectl describe node mkcluster | grep Taints
minikube kubectl taint nodes mkcluster node-role.kubernetes.io/master:NoSchedule-
```

