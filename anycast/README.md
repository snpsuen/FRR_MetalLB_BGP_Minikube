![containerlab_anycast](containerlab_anycast02.png)

Our next task is to set up BGP anycast routes for MetalLB to distribute workloads between multiple instances of a Kubernetes service. To this end, a new minikube K8s cluster is added to the ContainerLab topology to host the nginx service with the same virtual IP (VIP) as the one advertised by MetalLB on the first cluster.

### Key success factors

There are three key success factors to accomplish the task. First, MetalLB speakers will be deployed on both minikube clusters to run in the BGP mode to advertise the nginx VIP to the upstream FRR switches. 

In addition, the FRR spine switch will accept the two BGP routes destined to the anycast VIP on the respective minikube clusters and install them as ECMP routes in the kernel FIB table.

Finally, the kernel of the FRR spine switch will use a suitable hash policy to spread different connections to the anycast VIP between the ECMP routes.

### Lab inventory

The [baseline lab](../containerlab_frr_mk02.png) is extended to include a second minikube K8s cluster, mkcluster02 and a third FRR leaf switch, frrleaf3, which connects the new cluster to the FRR fabrics.

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
			<td aligh="left">Client02 workstation</td>
			<td aligh="left">Host IP: 192.168.200.22/24</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Leaf 1</td>
			<td aligh="left">Network Prefix: 192.168.100.0/24 <br>
        Network Prefix: 192.168.200.0/24 <br>
				Network Prefix: 10.0.1.0/24 <br>
				BGP ASN: 65001
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Spine</td>
			<td aligh="left">Network Prefix: 10.0.1.0/24 <br>
				Network Prefix: 10.0.2.0/24 <br>
        Network Prefix: 10.0.3.0/24 <br>
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
		    <td aligh="left">FRR Leaf 3</td>
			<td aligh="left">Network Prefix: 10.0.3.0/24 <br>
				Network Prefix: 192.168.99.0/24 <br>
				BGP ASN: 65003
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
		    <td aligh="left">Minikube docker bridge</td>
			<td aligh="left">Network Prefix (transparent): Network Prefix: 192.168.99.0/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster01 single node</td>
			<td aligh="left">Host IP: 192.168.49.2/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster02 single node</td>
			<td aligh="left">Host IP: 192.168.99.3/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
	</tbody>
</table>

Assume the Minikube and ContainerLab packages have been installed on a suitable Linux platform like Ubuntu 22.04 (jammy). The subsequent steps to be taken to build and test the BGP anycast routes are similar to those performed in the [baseline exercise](../README.md).

### Deploy Minikube K8s clusters

For simplicity and a smaller footprint, both clusters are reduced to a single node each. Moreover, the node of the second cluster, mkcluster02, is to be assigned a user-chosen IP, 192.168.99.2.

```
minikube start --driver=docker --nodes 1 -p mkcluster01 --cpus=1 --force
minikube start --driver=docker --nodes 1 -p mkcluster02 --static-ip 192.168.99.2 --cpus=1 --force
```

```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ minikube profile list
┌─────────────┬────────┬─────────┬──────────────┬─────────┬────────┬───────┬────────────────┬────────────────────┐
│   PROFILE   │ DRIVER │ RUNTIME │      IP      │ VERSION │ STATUS │ NODES │ ACTIVE PROFILE │ ACTIVE KUBECONTEXT │
├─────────────┼────────┼─────────┼──────────────┼─────────┼────────┼───────┼────────────────┼────────────────────┤
│ mkcluster01 │ docker │ docker  │ 192.168.49.2 │ v1.34.0 │ OK     │ 1     │                │                    │
│ mkcluster02 │ docker │ docker  │ 192.168.99.2 │ v1.34.0 │ OK     │ 1     │ *              │ *                  │
└─────────────┴────────┴─────────┴──────────────┴─────────┴────────┴───────┴────────────────┴────────────────────┘
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
```

### Deploy ContainerLab topology

You may download the files from this repo folder and deploy the target topology based on the ContainerLab manifest template [clab_bgp_anycast_template.yaml](clab_bgp_anycast_template.yaml).

```
git clone https://github.com/snpsuen/FRR_MetalLB_BGP_Minikube
cd FRR_MetalLB_BGP_Minikube/anycast

network_id=$(docker network inspect -f {{.Id}} mkcluster01)
bridge_name01="br-${network_id:0:12}"
network_id=$(docker network inspect -f {{.Id}} mkcluster02)
bridge_name02="br-${network_id:0:12}"

export MK_BRIDGE01=$bridge_name01
export MK_BRIDGE02=$bridge_name02
envsubst '$MK_BRIDGE01 $MK_BRIDGE02' < clab_bgp_anycast_template.yaml > clab_bgp_anycast_inst.yaml

clab deploy -t clab_bgp_anycast_inst.yaml
```

```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ sudo clab inspect -t clab_bgp_anycast_inst.yaml                         09:47:03 INFO Parsing & checking topology file=clab_bgp_anycast_inst.yaml
╭─────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────┬─────────┬───────────────────╮
│     Name    │                                                  Kind/Image                                                 │  State  │   IPv4/6 Address  │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ mkcluster01 │ ext-container                                                                                               │ running │ 192.168.49.2      │
│             │ gcr.io/k8s-minikube/kicbase:v0.0.48@sha256:7171c97a51623558720f8e5878e4f4637da093e2f2ed589997bedc6c1549b2b1 │         │ N/A               │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ mkcluster02 │ ext-container                                                                                               │ running │ 192.168.99.2      │
│             │ gcr.io/k8s-minikube/kicbase:v0.0.48@sha256:7171c97a51623558720f8e5878e4f4637da093e2f2ed589997bedc6c1549b2b1 │         │ N/A               │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ client      │ linux                                                                                                       │ running │ 172.20.20.5       │
│             │ ghcr.io/hellt/network-multitool                                                                             │         │ 3fff:172:20:20::5 │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ client02    │ linux                                                                                                       │ running │ 172.20.20.7       │
│             │ ghcr.io/hellt/network-multitool                                                                             │         │ 3fff:172:20:20::7 │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrleaf1    │ linux                                                                                                       │ running │ 172.20.20.3       │
│             │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::3 │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrleaf2    │ linux                                                                                                       │ running │ 172.20.20.2       │
│             │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::2 │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrleaf3    │ linux                                                                                                       │ running │ 172.20.20.4       │
│             │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::4 │
├─────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrspine    │ linux                                                                                                       │ running │ 172.20.20.6       │
│             │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::6 │
╰─────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────┴─────────┴───────────────────╯
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
```

It is specified in the [ContainerLab manifest](clab_bgp_anycast_template.yaml).that the following command will be invoked to set the featured kernel paramete when the frrspine node comes up.
```
sysctl -w net.ipv4.fib_multipath_hash_policy=1
```

It means the switch will hash the 5-tuple L4 headers of an connection flow to determine which ECMP route to take. Accordingly, connection flows that are different in the fields of source port, source IP, destimation port pr destination IP tend to be assigned different ECMP routes.

Another noteworthy point is about these BGP settings found in the frrspine config file, [frrspine.conf](configs/frrspine.conf).
```
bgp bestpath as-path multipath-relax
...
maximum-paths 10
```

The first line means that the switch will treat two or more BGP routes whose AS paths are of the same length as equal-cost routes. In our example, the AS path of the BGP route to the anycast VIP on mkcluster01 is "65002 65101", while the BGP route to the anycast VIP on mkcluster02 takes the AS path "65003 65102". The routes are considered equal in cost as both are two ASNs long.

The second line indicates that the switch will install a maximum of 10 equal-cost routes as ECMP routes.

### Install and configure MetalLB on minikube clusters

Set up MetalLB successively on mkcluster01 and mkcluster02.
```
minikube profile mkcluster01
minikube kubectl -- apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
minikube kubectl -- apply -f metallb-bgp-mk01.yaml

minikube profile mkcluster02
minikube kubectl -- apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
minikube kubectl -- apply -f metallb-bgp-mk02.yaml
```

The MetalLB speakers are configured to advertise the same address pool from both cluster. See the manifests [metallb-bgp-mk01.yaml](metallb-bgp-mk01.yaml) and [metallb-bgp-mk02.yaml](metallb-bgp-mk02.yaml) for details.

<table>
	<thead>
		<tr>
			<th scope="col">Minikube</th>
			<th scope="col">Advertised IP Pool</th>
			<th scope="col">MetalLB ASN</th>
			<th scope="col">Peer ASN</th>
			<th scope="col">External BGP peer</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">mkcluster01</td>
			<td aligh="left">172.24.20.100-172.24.20.110</td>
			<td aligh="left">65101</td>
			<td aligh="left">65002</td>
			<td aligh="left">192.168.49.101</td>
		</tr>
		<tr>
			<td aligh="left">mkcluster02</td>
			<td aligh="left">172.24.20.100-172.24.20.110</td>
			<td aligh="left">65102</td>
			<td aligh="left">65003</td>
			<td aligh="left">192.168.99.101</td>
		</tr>
	</tbody>
</table>

### Anycast routing to Nginx

Apply [nginx.yaml](nginx.yaml) to deploy a nginx K8s servce on both minikube clusters
```
minikube profile mkcluster01
minikube kubectl -- apply -f nginx.yaml

minikube profile mkcluster02
minikube kubectl -- apply -f nginx.yaml
```


