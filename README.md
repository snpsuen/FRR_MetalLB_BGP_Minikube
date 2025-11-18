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

### 3. Obtain the name of the Minikube docker bridge

Before calling ContainerLab to lay out the target network topology, we need to fetch the name of the docker bridge that was created ealier by Minikube to link up the mkcluster nodes through a layer 2 network. It will be used to declare the bridge as a Containlab node in the topology template.
```
network_id=$(docker network inspect -f {{.Id}} mkcluster)
bridge_name="br-${network_id:0:12}"
```

The mkcluster bridge name appears in the form of "br-xxxxxxxxxxxx", where the suffix "x...x" comes from the first 12 characters of the mkcluster network id.

### 4. Deploy the target network topology in ContainerLab

Use the mkcluster bridge name to instantiate the environment variable MK_BRIDGE declared in the ContainerLab topology template, [clab_frr_minikube_template.yaml](clab_frr_minikube_template.yaml).

Invoke clab on the instantiated template to deploy the network topology.
```
git clone https://github.com/snpsuen/FRR_MetalLB_BGP_Minikube
cd FRR_MetalLB_BGP_Minikube

export MK_BRIDGE=$bridge_name
envsubst '$MK_BRIDGE' < clab_frr_minikube_template.yaml > clab_frr_minikube_inst.yaml
clab deploy -t clab_frr_minikube_inst.yaml
```

Upon deployment in ContainerLab, the following files are mounted on the FRR switches for configuration of their network and BGP functions.
* [configs/frrspine.conf](configs/frrspine.conf)
* [configs/frrleaf1.conf](configs/frrleaf1.conf)
* [configs/frrleaf2.conf](configs/frrleaf2.conf)
* [configs/frrdaemons](configs/frrdaemons)
* [configs/vtysh.conf](configs/vtysh.conf).

Make sure they are found in the correct locaton relative to the toplogy template.

Inspect the deployed containers of the network topology.
```
ubuntu:~/FRR_MetalLB_BGP_Minikube$ clab inspect -t clab_frr_minikube_inst.yaml
19:34:52 INFO Parsing & checking topology file=clab_frr_minikube_inst.yaml
╭───────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────┬─────────┬───────────────────╮
│      Name     │                                                  Kind/Image                                                 │  State  │   IPv4/6 Address  │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ mkcluster     │ ext-container                                                                                               │ running │ 192.168.49.2      │
│               │ gcr.io/k8s-minikube/kicbase:v0.0.48@sha256:7171c97a51623558720f8e5878e4f4637da093e2f2ed589997bedc6c1549b2b1 │         │ N/A               │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ mkcluster-m02 │ ext-container                                                                                               │ running │ 192.168.49.3      │
│               │ gcr.io/k8s-minikube/kicbase:v0.0.48@sha256:7171c97a51623558720f8e5878e4f4637da093e2f2ed589997bedc6c1549b2b1 │         │ N/A               │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ client        │ linux                                                                                                       │ running │ 172.20.20.5       │
│               │ ghcr.io/hellt/network-multitool                                                                             │         │ 3fff:172:20:20::5 │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrleaf1      │ linux                                                                                                       │ running │ 172.20.20.2       │
│               │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::2 │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrleaf2      │ linux                                                                                                       │ running │ 172.20.20.3       │
│               │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::3 │
├───────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┼─────────┼───────────────────┤
│ frrspine      │ linux                                                                                                       │ running │ 172.20.20.4       │
│               │ frrouting/frr:latest                                                                                        │         │ 3fff:172:20:20::4 │
╰───────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────┴─────────┴───────────────────╯
```

### 5. Checkpoint for verification

Now is the time to verify if the BGP processes are working properly on the FRR fabric to build the effective routes between the client and mkcluster before we go on to install MetalLB. It is observed from the conf files that all the FRR switches are instructed to advertise any native or learnt routes to their external BGP neighbours. 

Inspect the bgp and routing situation on the FRR spine.
```
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrspine vtysh -c "show bgp summary"

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.255.1, local AS number 64999 vrf-id 0
BGP table version 2
RIB entries 3, using 576 bytes of memory
Peers 2, using 1434 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.0.1.11       4      65001         8         8        0    0    0 00:00:45            1        2 N/A
10.0.2.11       4      65002         9         8        0    0    0 00:00:45            1        2 N/A

Total number of neighbors 2
ubuntu:~/FRR_MetalLB_BGP_Minikube$ 
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrspine vtysh -c "show ip bgp"
BGP table version is 2, local router ID is 10.0.255.1, vrf id 0
Default local pref 100, local AS 64999
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*> 192.168.49.0/24  10.0.2.11                0             0 65002 i
*> 192.168.100.0/24 10.0.1.11                0             0 65001 i

Displayed  2 routes and 2 total paths
ubuntu:~/FRR_MetalLB_BGP_Minikube$ 
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrspine vtysh -c "show ip route"
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
       f - OpenFabric,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure

K>* 0.0.0.0/0 [0/0] via 172.20.20.1, eth0, 00:01:17
C>* 10.0.1.0/24 is directly connected, eth1, 00:01:16
C>* 10.0.2.0/24 is directly connected, eth2, 00:01:16
C>* 172.20.20.0/24 is directly connected, eth0, 00:01:17
B>* 192.168.49.0/24 [20/0] via 10.0.2.11, eth2, weight 1, 00:01:06
B>* 192.168.100.0/24 [20/0] via 10.0.1.11, eth1, weight 1, 00:01:06
```

Run the same vtysh commands on the FRR leaf switches to display the relevant information.
```
ubuntu:~/FRR_MetalLB_BGP_Miniku$ docker exec frrleaf1 vtysh -c "show bgp summary"

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.255.11, local AS number 65001 vrf-id 0
BGP table version 2
RIB entries 3, using 576 bytes of memory
Peers 1, using 717 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.0.1.1        4      64999         9         9        0    0    0 00:01:18            1        2 N/A

Total number of neighbors 1
ubuntu:~/FRR_MetalLB_BGP_Miniku$ 
ubuntu:~/FRR_MetalLB_BGP_Miniku$ docker exec frrleaf1 vtysh -c "show ip bgp"
BGP table version is 2, local router ID is 10.0.255.11, vrf id 0
Default local pref 100, local AS 65001
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*> 192.168.49.0/24  10.0.1.1                               0 64999 65002 i
*> 192.168.100.0/24 0.0.0.0                  0         32768 i

Displayed  2 routes and 2 total paths
ubuntu:~/FRR_MetalLB_BGP_Miniku$ 
ubuntu:~/FRR_MetalLB_BGP_Miniku$ docker exec frrleaf1 vtysh -c "show ip route"
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
       f - OpenFabric,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure

K>* 0.0.0.0/0 [0/0] via 172.20.20.1, eth0, 00:02:52
C>* 10.0.1.0/24 is directly connected, eth1, 00:02:51
C>* 172.20.20.0/24 is directly connected, eth0, 00:02:52
B>* 192.168.49.0/24 [20/0] via 10.0.1.1, eth1, weight 1, 00:01:38
C>* 192.168.100.0/24 is directly connected, eth2, 00:02:44
```
```
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrleaf2 vtysh -c "show bgp summary"

IPv4 Unicast Summary (VRF default):
BGP router identifier 10.0.255.12, local AS number 65002 vrf-id 0
BGP table version 2
RIB entries 3, using 576 bytes of memory
Peers 3, using 2151 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.0.2.1        4      64999         9        10        0    0    0 00:01:47            1        2 N/A
192.168.49.2    4      65101         0         0        0    0    0    never       Active        0 N/A
192.168.49.3    4      65101         0         0        0    0    0    never       Active        0 N/A

Total number of neighbors 3
ubuntu:~/FRR_MetalLB_BGP_Minikube$ 
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrleaf2 vtysh -c "show ip bgp"
BGP table version is 2, local router ID is 10.0.255.12, vrf id 0
Default local pref 100, local AS 65002
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*> 192.168.49.0/24  0.0.0.0                  0         32768 i
*> 192.168.100.0/24 10.0.2.1                               0 64999 65001 i

Displayed  2 routes and 2 total paths
ubuntu:~/FRR_MetalLB_BGP_Minikube$  
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec frrleaf2 vtysh -c "show ip route"
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
       f - OpenFabric,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure

K>* 0.0.0.0/0 [0/0] via 172.20.20.1, eth0, 00:03:20
C>* 10.0.2.0/24 is directly connected, eth1, 00:03:20
C>* 172.20.20.0/24 is directly connected, eth0, 00:03:20
C>* 192.168.49.0/24 is directly connected, eth2, 00:03:13
B>* 192.168.100.0/24 [20/0] via 10.0.2.1, eth1, weight 1, 00:02:07
```

Verify the BGP connectivity by ping from the client to the mkcluster nodes.
```
ubuntu:~/FRR_MetalLB_BGP_Minikube docker exec client ping -c 3 192.168.49.2
PING 192.168.49.2 (192.168.49.2) 56(84) bytes of data.
64 bytes from 192.168.49.2: icmp_seq=1 ttl=61 time=0.126 ms
64 bytes from 192.168.49.2: icmp_seq=2 ttl=61 time=0.164 ms
64 bytes from 192.168.49.2: icmp_seq=3 ttl=61 time=0.066 ms

--- 192.168.49.2 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2064ms
rtt min/avg/max/mdev = 0.066/0.118/0.164/0.040 ms
ubuntu:~/FRR_MetalLB_BGP_Minikube$ 
ubuntu:~/FRR_MetalLB_BGP_Minikube$ docker exec client ping -c 3 192.168.49.3
PING 192.168.49.3 (192.168.49.3) 56(84) bytes of data.
64 bytes from 192.168.49.3: icmp_seq=1 ttl=61 time=0.094 ms
64 bytes from 192.168.49.3: icmp_seq=2 ttl=61 time=0.148 ms
64 bytes from 192.168.49.3: icmp_seq=3 ttl=61 time=0.086 ms
```
