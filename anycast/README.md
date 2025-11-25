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

The MetalLB speakers are configured to advertise the same address pool from both clusters. See the manifests [metallb-bgp-mk01.yaml](metallb-bgp-mk01.yaml) and [metallb-bgp-mk02.yaml](metallb-bgp-mk02.yaml) for details.

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

Ckeck that the nginx service uses the same VIP 172.24.20.100 to expose the pods running on mkcluster01 and mkcluster02.
```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ minikube profile mkcluster01
* minikube profile was successfully set to mkcluster01
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ kubectl get svc
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1      <none>          443/TCP        65m
nginxhello   LoadBalancer   10.97.167.82   172.24.20.100   80:31963/TCP   25m
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ kubectl get pods -o wide
NAME                          READY   STATUS    RESTARTS   AGE     IP            NODE          NOMINATED NODE   READINESS GATES
nginxhello-85f8846c44-q44mb   1/1     Running   0          4h13m   10.244.0.16   mkcluster01   <none>           <none>
nginxhello-85f8846c44-t6x59   1/1     Running   0          4h13m   10.244.0.17   mkcluster01   <none>           <none>
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ minikube profile mkcluster02
* minikube profile was successfully set to mkcluster02
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ kubectl get svc
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1        <none>          443/TCP        61m
nginxhello   LoadBalancer   10.106.109.191   172.24.20.100   80:30291/TCP   19m
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ kubectl get pods -o wide
NAME                          READY   STATUS    RESTARTS   AGE     IP            NODE          NOMINATED NODE   READINESS GATES
nginxhello-85f8846c44-59mq7   1/1     Running   0          3h52m   10.244.0.21   mkcluster02   <none>           <none>
nginxhello-85f8846c44-7fpzd   1/1     Running   0          3h52m   10.244.0.20   mkcluster02   <none>           <none>
```

Verify that the following anycast routes to the VIP 172.24.20.100 are admitted into the BGP Loc-RIB and installed as ECMP routes on frrspine.

<table>
	<thead>
		<tr>
			<th scope="col">Prefix</th>
			<th scope="col">Next hop</th>
			<th scope="col">AS Path</th>
			<th scope="col">Workload destination</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">172.24.20.100/32</td>
			<td aligh="left">110.0.2.11</td>
			<td aligh="left">65002 65101 i</td>
			<td aligh="left">mkcluster01</td>
		</tr>
		<tr>
			<td aligh="left">172.24.20.100/32</td>
			<td aligh="left">110.0.3.11</td>
			<td aligh="left">65003 65102 i</td>
			<td aligh="left">mkcluster02</td>
		</tr>
	</tbody>
</table>

```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ docker exec frrspine vtysh -c "show bgp summary"

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.255.1, local AS number 64999 vrf-id 0
BGP table version 6
RIB entries 9, using 1728 bytes of memory
Peers 3, using 2151 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.0.1.11       4      65001       121       119        0    0    0 01:45:48            2        5 N/A
10.0.2.11       4      65002       117       117        0    0    0 01:45:48            2        5 N/A
10.0.3.11       4      65003       116       117        0    0    0 01:45:48            2        5 N/A

Total number of neighbors 3
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ docker exec frrspine vtysh -c "show ip bgp"
BGP table version is 6, local router ID is 10.0.255.1, vrf id 0
Default local pref 100, local AS 64999
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*= 172.24.20.100/32 10.0.3.11                              0 65003 65102 i
*>                  10.0.2.11                              0 65002 65101 i
*> 192.168.49.0/24  10.0.2.11                0             0 65002 i
*> 192.168.99.0/24  10.0.3.11                0             0 65003 i
*> 192.168.100.0/24 10.0.1.11                0             0 65001 i
*> 192.168.200.0/24 10.0.1.11                0             0 65001 i

Displayed  5 routes and 6 total paths
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ docker exec frrspine vtysh -c "show ip route"
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
       f - OpenFabric,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure

K>* 0.0.0.0/0 [0/0] via 172.20.20.1, eth0, 01:46:19
C>* 10.0.1.0/24 is directly connected, eth1, 01:46:18
C>* 10.0.2.0/24 is directly connected, eth2, 01:46:18
C>* 10.0.3.0/24 is directly connected, eth3, 01:46:18
C>* 172.20.20.0/24 is directly connected, eth0, 01:46:19
B>* 172.24.20.100/32 [20/0] via 10.0.2.11, eth2, weight 1, 01:46:06
  *                         via 10.0.3.11, eth3, weight 1, 01:46:06
B>* 192.168.49.0/24 [20/0] via 10.0.2.11, eth2, weight 1, 01:46:12
B>* 192.168.99.0/24 [20/0] via 10.0.3.11, eth3, weight 1, 01:46:12
B>* 192.168.100.0/24 [20/0] via 10.0.1.11, eth1, weight 1, 01:46:12
B>* 192.168.200.0/24 [20/0] via 10.0.1.11, eth1, weight 1, 01:46:12
```

In particular, the following lines shows the two anycast routes are admitted into the BGP Loc-RIB on frrspine.
```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ docker exec frrspine vtysh -c "show ip bgp"
:::::
   Network          Next Hop            Metric LocPrf Weight Path
*= 172.24.20.100/32 10.0.3.11                              0 65003 65102 i
*>                  10.0.2.11                              0 65002 65101 i
:::::
```

Similarly, the output section below is highlighted to indicate both anycast routes are installed as ECMP routes on the Frrspine kernal FIB.
```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ docker exec frrspine vtysh -c "show ip route"
:::::
B>* 172.24.20.100/32 [20/0] via 10.0.2.11, eth2, weight 1, 01:46:06
  *                         via 10.0.3.11, eth3, weight 1, 01:46:06
:::::
```

### End to end test out

Recall the anycast VIP 172.24.20.100 is advertised by MetalLB to represent the nginx pods running on mkcluster01 and mkcluster02 as follows.

<table>
	<thead>
		<tr>
			<th scope="col">Minikube</th>
			<th scope="col">Pod</th>
			<th scope="col">Local IP</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">mkcluster01</td>
			<td aligh="left">nginxhello-85f8846c44-q44mb</td>
			<td aligh="left">10.244.0.16</td>
		</tr>
		<tr>
			<td aligh="left">mkcluster01</td>
			<td aligh="left">nginxhello-85f8846c44-t6x59</td>
			<td aligh="left">10.244.0.17</td>
		</tr>
		<tr>
			<td aligh="left">mkcluster02</td>
			<td aligh="left">nginxhello-85f8846c44-7fpzd</td>
			<td aligh="left">10.244.0.20</td>
		</tr>
		<tr>
			<td aligh="left">mkcluster02</td>
			<td aligh="left">nginxhello-85f8846c44-59mq7</td>
			<td aligh="left">10.244.0.21</td>
		</tr>
	</tbody>
</table>

Issue curl -s http://172.24.20.100 from client, 192.168.100.11, in a loop, Observe that the HTTP traffic is spread between the mkcluster01 for nginx pods (10.244.0.16/17) on mkcluster02 for nginx pods (10.244.0.20/21) in a fairly even manner.
```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ for i in {1..10}; do docker exec client curl -s http://172.24.20.100; sleep 3; done
Server address: 10.244.0.20:80
Server name: nginxhello-85f8846c44-7fpzd
Date: 25/Nov/2025:00:07:54 +0000
URI: /
Request ID: 5298cefc7f7ef880b3ae8794fec86110
Server address: 10.244.0.16:80
Server name: nginxhello-85f8846c44-q44mb
Date: 25/Nov/2025:00:07:58 +0000
URI: /
Request ID: a7999c719c8625b8d2570ab9ca532211
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:08:02 +0000
URI: /
Request ID: d25024813da78370e016d70dc8fe2776
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:08:06 +0000
URI: /
Request ID: bdcef07087e5f6ebe02923104b1ec601
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:08:10 +0000
URI: /
Request ID: c53abe468fc3d0b5899e0fdadb7fe055
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:08:14 +0000
URI: /
Request ID: 1f686588cb701368b459e0d9bce691c8
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:08:18 +0000
URI: /
Request ID: d1632ca8d05715850630ff1eb5030b5a
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:08:22 +0000
URI: /
Request ID: f32567640bc623db1b9b931cd4332afa
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:08:26 +0000
URI: /
Request ID: d5f3bc96d2c1ba72fe305181cb49efed
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:08:30 +0000
URI: /
Request ID: 70fcb7eeb5238684c735c202c2e144d5
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
```

Similar load balancing findings are observed from client02, 192.168.200.22, issuing curl -s http://172.24.20.100.
```
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$ for i in {1..10}; do docker exec client02 curl -s http://172.24.20.100; sleep 3; done
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:09:30 +0000
URI: /
Request ID: 8c9f3cc0d2cb45ce99f7390ed2ceff58
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:09:34 +0000
URI: /
Request ID: 9247c577a9c3dbb1e0154cd839ca7df9
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:09:38 +0000
URI: /
Request ID: 9805410dfef96115b6ace87a0546d08f
Server address: 10.244.0.20:80
Server name: nginxhello-85f8846c44-7fpzd
Date: 25/Nov/2025:00:09:42 +0000
URI: /
Request ID: 8101075068ff79b5c7085a2451015a47
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:09:46 +0000
URI: /
Request ID: 30e33bb1d995e972aca69dd16a77f5be
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:09:50 +0000
URI: /
Request ID: d9f6364cfc3a679a35bdc17525842757
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:09:54 +0000
URI: /
Request ID: 3c3060dd8dbbf362082aa78fc1054818
Server address: 10.244.0.21:80
Server name: nginxhello-85f8846c44-59mq7
Date: 25/Nov/2025:00:09:58 +0000
URI: /
Request ID: 37d5f0f4386cba4e32977b6bb76f9a9f
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:10:02 +0000
URI: /
Request ID: fe5ef19903b21933f850b9b16d2503c9
Server address: 10.244.0.17:80
Server name: nginxhello-85f8846c44-t6x59
Date: 25/Nov/2025:00:10:06 +0000
URI: /
Request ID: 463ff071e74cc9a50b35a6e92dfb4db7
keyuser@ubunclone:~/FRR_MetalLB_BGP_Minikube/anycast$
```



