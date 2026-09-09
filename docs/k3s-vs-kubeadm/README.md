# K3s vs kubeadm — architecture, deployment choices, and K3s in containers

This guide explains **what K3s and kubeadm actually are**, how their architectures differ, when each one makes sense, and what it means to run K3s **natively on Linux**, **inside Docker**, or through **k3d**.

The goal is practical understanding rather than marketing. The recommendations are written for engineers who need to choose a sensible way to run containers or Kubernetes on one server, several servers, or an HA platform.

> **Research review:** 2026-09-09. The technical statements in this document were checked against the official K3s, Kubernetes/kubeadm, and k3d documentation linked at the end.

## Executive summary

If you remember only five points, remember these:

1. **K3s is a Kubernetes distribution.** It packages the Kubernetes control plane, kubelet, containerd, networking defaults, datastore choices, and useful add-ons into a much simpler operational experience.
2. **kubeadm is a Kubernetes bootstrap tool.** It helps initialize and join upstream-style Kubernetes nodes, but you still own more of the surrounding work: container runtime, CNI, load-balancer design, and many operational choices.
3. **For one server that must run Kubernetes, K3s is usually the simpler choice.** A single-node kubeadm cluster works, but requires more setup and an explicit control-plane untaint before normal workloads can schedule there.
4. **For real HA, use independent failure domains.** Three VMs on one physical server are three Kubernetes nodes, but they are still one physical failure domain and therefore are not true HA.
5. **K3s can run inside Docker.** That is useful for labs, local development, demos, and CI. For a long-lived EC2 server, this repository prefers native K3s on Linux instead of adding a privileged Docker-in-Docker-style node layer.

![K3s vs kubeadm architecture overview](architecture.svg)

For the AWS architecture implemented by this repository, also see:

![K3s on AWS platform architecture](../diagrams/k3s-platform-overview.svg)

---

## 1. Start with the requirement, not the tool

A common mistake is deciding "we need Kubernetes" before defining what the server actually needs to do.

### Requirement A — one server only needs to run a few containers

If the server needs to run a small number of containers with:

- restart policies;
- environment variables;
- volumes;
- basic networking;
- a reverse proxy;
- simple operational ownership;

then **Docker Compose or Podman Compose may be enough**.

Kubernetes introduces a control plane, cluster networking, API resources, controllers, certificates, RBAC, upgrades, and more. Those are valuable when you need them, but unnecessary complexity when you do not.

### Requirement B — one server needs Kubernetes APIs

Choose **K3s** when you need capabilities such as:

- Deployments and rolling updates;
- Services and Ingress;
- Helm charts;
- ConfigMaps and Secrets;
- Jobs and CronJobs;
- Kubernetes-native health probes;
- GitOps with Argo CD;
- cert-manager;
- a future path to joining more nodes without changing the application deployment model.

This is the default assumption in this repository.

### Requirement C — the team needs a more upstream/manual Kubernetes operating model

Choose **kubeadm** when the goal includes:

- learning or standardizing on kubeadm itself;
- explicitly selecting and operating the CRI runtime;
- explicitly selecting and operating the CNI;
- deeper control over control-plane bootstrap and PKI mechanics;
- matching an existing enterprise kubeadm platform or runbook;
- learning Kubernetes internals closer to the standard kubeadm administration path.

---

## 2. The simplest mental model

### K3s

Think of K3s as:

```text
Kubernetes + packaging + sensible defaults + simpler installation/operations
```

A K3s **server** runs the control-plane and datastore components. K3s servers also run the agent functionality by default, so they can run normal workloads unless you intentionally taint or otherwise restrict them.

A K3s **agent** is a worker node. It does not host the control-plane datastore components.

K3s servers and agents run the kubelet, container runtime, and CNI components needed by Kubernetes.

### kubeadm

Think of kubeadm as:

```text
A tool that bootstraps and joins Kubernetes control-plane and worker nodes
```

kubeadm does **not** turn the whole Kubernetes platform into one packaged distribution. Before and after `kubeadm init`, the operator still has important responsibilities such as preparing a CRI-compatible container runtime and installing a Pod network/CNI.

This difference explains most of the operational trade-offs.

---

## 3. Single-node architecture

### K3s single node

A single K3s server is already a complete Kubernetes cluster. On that one machine you have, conceptually:

```text
Linux host
└── K3s server
    ├── Kubernetes API server
    ├── controller manager
    ├── scheduler
    ├── datastore (SQLite by default on a single server)
    ├── kubelet
    ├── containerd (default runtime)
    ├── CNI/networking
    └── workload Pods
```

The official K3s quick-start documentation explicitly describes a single server as a fully functional cluster containing the datastore, control plane, kubelet, and container runtime needed to host workloads.

### kubeadm single node

A single-machine kubeadm cluster is also possible, but the workflow is more explicit:

```text
Linux host
├── CRI runtime (for example containerd)
├── kubelet
├── kubeadm
└── Kubernetes control plane
    ├── API server
    ├── controller manager
    ├── scheduler
    ├── local etcd member
    └── CNI installed separately by the operator
```

By default kubeadm taints control-plane nodes with `node-role.kubernetes.io/control-plane:NoSchedule`. For a single-machine cluster where the control plane must also run applications, the official Kubernetes documentation instructs you to remove that taint:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

That is a small example of the broader difference: kubeadm exposes more of Kubernetes' normal building blocks directly, while K3s deliberately reduces setup friction.

### Single-node recommendation

| Requirement | Better starting point |
|---|---|
| Only run containers | Docker Compose / Podman Compose |
| Kubernetes required on one server | **K3s** |
| Learn kubeadm / upstream bootstrap mechanics | **kubeadm** |
| CKA-style administration lab | **kubeadm** is usually more educational |

---

## 4. Multi-node without HA

A multi-node cluster is not automatically an HA cluster.

A very common non-HA K3s design is:

```text
K3s server (control plane + datastore)
├── K3s agent / worker 1
├── K3s agent / worker 2
└── K3s agent / worker 3
```

This adds workload capacity and lets applications spread across multiple workers, but the single K3s server remains a control-plane single point of failure.

The equivalent kubeadm idea is one control-plane node plus multiple workers. It has the same fundamental availability limitation: one control plane means one control-plane failure domain.

### What happens when the single control plane fails?

Existing workloads on healthy workers may continue running for some time, but Kubernetes loses the API/control-loop functions needed for normal cluster management:

- no new scheduling decisions;
- no normal reconciliation of desired state;
- no new API changes;
- controllers cannot perform normal cluster operations;
- failed workloads may not be replaced as expected.

### Recommendation

For a small or medium multi-node cluster where control-plane downtime is acceptable, **K3s is generally simpler to operate**. Choose kubeadm when there is an explicit requirement for the kubeadm operating model rather than simply because there are several nodes.

---

## 5. Real HA architecture

### K3s HA with embedded etcd

K3s supports HA with embedded etcd. The official K3s documentation requires **three or more server nodes**, and the embedded-etcd server count should be odd so etcd can maintain quorum efficiently.

The normal small HA topology is:

```text
              Fixed API / registration address
                         |
              +----------+----------+
              |          |          |
          Server 1   Server 2   Server 3
          CP + etcd  CP + etcd  CP + etcd
              \          |          /
               \------ quorum -----/

          optional agent / worker nodes
```

With three servers, quorum is two, so one server can fail while the control plane remains available.

K3s also supports an **external datastore** topology. In that model, multiple K3s servers share an external etcd, PostgreSQL, MySQL, or MariaDB datastore. This can be useful when the organization already has a strong external database operating model, but it also means operating another critical system.

### kubeadm HA

The Kubernetes kubeadm documentation describes two main HA control-plane patterns:

1. **Stacked etcd** — etcd members are co-located with the control-plane nodes.
2. **External etcd** — etcd runs on separate machines from the control-plane nodes.

A load-balanced control-plane endpoint is placed in front of the API servers.

kubeadm's external-etcd model can provide very explicit separation, but it requires more infrastructure and more operational ownership.

### HA recommendation

| Situation | Recommendation |
|---|---|
| Small platform team, simpler self-managed HA | **K3s with 3 servers + embedded etcd** |
| Existing organization standard on kubeadm | **kubeadm** |
| Need deeper explicit control-plane customization | **kubeadm** |
| Existing external datastore/platform standard | Evaluate K3s external DB vs kubeadm external etcd |
| Three VMs on one physical server | Lab only; **not true HA** |

---

## 6. Why several VMs on one physical server are not true HA

Suppose one powerful physical server runs six VMs:

```text
Physical server
├── VM 1 - K3s server
├── VM 2 - K3s server
├── VM 3 - K3s server
├── VM 4 - K3s agent
├── VM 5 - K3s agent
└── VM 6 - K3s agent
```

Kubernetes will see six nodes. Embedded etcd can form quorum among the three server VMs. This is useful for learning and testing.

But all six VMs still depend on the same:

- physical CPU and memory;
- motherboard;
- power supply;
- hypervisor;
- local storage/controller;
- often the same network uplink.

If the physical host dies, every Kubernetes node disappears together.

So this is:

- **multi-node:** yes;
- **good HA lab:** yes;
- **real host-level HA:** no.

Real HA requires independent physical/cloud failure domains.

---

# 7. K3s and containers — four different concepts people often mix up

The phrase "run K3s with Docker" can mean several different things. Keeping these separate prevents a lot of confusion.

## Model 1 — K3s installed natively on Linux, using embedded containerd

This is the normal/default K3s model and the model closest to this repository.

```text
Linux / EC2
└── K3s process/service
    └── embedded containerd
        └── Kubernetes workload containers
```

K3s includes containerd and uses it by default.

For a long-lived EC2 server, this is usually the cleanest design because there is no extra privileged Docker node-container layer between the OS and Kubernetes.

## Model 2 — K3s installed natively, but using Docker as the Kubernetes runtime

This is **not the same** as running K3s itself inside Docker.

K3s has a `--docker` runtime option that uses `cri-dockerd` instead of the default embedded containerd.

Conceptually:

```text
Linux
├── dockerd
└── K3s service
    ├── kubelet
    └── cri-dockerd -> Docker
```

Use this only when there is a clear requirement for Docker as the node runtime. containerd is the simpler default for K3s.

## Model 3 — run the K3s node itself as a Docker container

The official K3s documentation provides `rancher/k3s` images that can run a K3s server or agent inside Docker.

Conceptually:

```text
Linux host
└── Docker
    └── privileged K3s node container
        ├── K3s server/agent
        ├── kubelet
        ├── containerd
        └── Kubernetes workload containers
```

This is effectively a containerized Kubernetes node. It is useful for development and testing, but the node container needs broad privileges.

## Model 4 — k3d

k3d is a wrapper designed specifically to make K3s-in-Docker easy.

Conceptually:

```text
Linux/macOS/Windows host
└── Docker
    ├── k3d load-balancer container
    ├── K3s server container(s)
    └── K3s agent container(s)
```

For local development and CI, **k3d is usually preferable to hand-assembling K3s Docker containers yourself**.

---

# 8. Running K3s directly inside Docker

The official K3s docs support this. The important details are:

- use the official `rancher/k3s` image;
- specify an **exact K3s version**;
- the `latest` tag is not maintained;
- Docker image tags replace the `+` in K3s release names with `-`;
- the container normally requires `--privileged`;
- expose the API server if kubectl outside the container needs access;
- persist cluster state if you want the cluster to survive container recreation.

This repository pins K3s to:

```text
v1.36.4+k3s1
```

The corresponding Docker image tag format is:

```text
rancher/k3s:v1.36.4-k3s1
```

## 8.1 Minimal single-node Docker example

Create persistent volumes:

```bash
docker volume create k3s-server-data
docker volume create k3s-server-etc
```

Start one K3s server container:

```bash
docker run -d \
  --privileged \
  --name k3s-server-1 \
  --hostname k3s-server-1 \
  -p 6443:6443 \
  -v k3s-server-data:/var/lib/rancher/k3s \
  -v k3s-server-etc:/etc/rancher/k3s \
  rancher/k3s:v1.36.4-k3s1 \
  server
```

Check it:

```bash
docker ps
docker logs -f k3s-server-1
```

Copy the admin kubeconfig to the host:

```bash
mkdir -p ~/.kube
docker cp k3s-server-1:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-docker.yaml
chmod 600 ~/.kube/k3s-docker.yaml
```

Use it:

```bash
export KUBECONFIG=~/.kube/k3s-docker.yaml
kubectl get nodes -o wide
kubectl get pods -A
```

Because port `6443` is mapped to the Docker host, the kubeconfig's loopback API address works when kubectl runs on the same Docker host.

### Repository-specific note

This repository manages Traefik separately with Helm. If you are using the Docker example to mimic the repository behavior, disable the K3s-bundled Traefik:

```bash
docker run -d \
  --privileged \
  --name k3s-server-1 \
  --hostname k3s-server-1 \
  -p 6443:6443 \
  -v k3s-server-data:/var/lib/rancher/k3s \
  -v k3s-server-etc:/etc/rancher/k3s \
  rancher/k3s:v1.36.4-k3s1 \
  server --disable=traefik
```

## 8.2 Persisting state matters

Without a persistent `/var/lib/rancher/k3s` volume, deleting the K3s server container can also delete the datastore and cluster state that lived inside that container filesystem.

For disposable development clusters this may be acceptable. For anything that matters, treat the datastore as persistent state and have a backup/recovery plan.

## 8.3 Direct Docker multi-node lab

For learning, create a Docker network and run K3s node containers on it:

```bash
docker network create k3s-lab
```

Start a server:

```bash
docker run -d \
  --privileged \
  --network k3s-lab \
  --name k3s-server-1 \
  --hostname k3s-server-1 \
  -p 6443:6443 \
  rancher/k3s:v1.36.4-k3s1 \
  server
```

Get the cluster token:

```bash
K3S_TOKEN="$(docker exec k3s-server-1 cat /var/lib/rancher/k3s/server/node-token)"
```

Start an agent:

```bash
docker run -d \
  --privileged \
  --network k3s-lab \
  --name k3s-agent-1 \
  --hostname k3s-agent-1 \
  -e K3S_URL=https://k3s-server-1:6443 \
  -e K3S_TOKEN="$K3S_TOKEN" \
  rancher/k3s:v1.36.4-k3s1 \
  agent
```

Then verify from the server container:

```bash
docker exec k3s-server-1 kubectl get nodes -o wide
```

This is useful for understanding server/agent registration. For routine local multi-node environments, use k3d instead of maintaining this wiring manually.

---

# 9. Running K3s in Docker with k3d

k3d exists specifically to create K3s clusters where the K3s nodes are Docker containers on a shared Docker network.

A simple cluster:

```bash
k3d cluster create dev
```

One server and two agents:

```bash
k3d cluster create dev --servers 1 --agents 2
```

Pin the K3s node image explicitly:

```bash
k3d cluster create dev \
  --servers 1 \
  --agents 2 \
  --image rancher/k3s:v1.36.4-k3s1
```

A three-server lab that exercises embedded-etcd behavior:

```bash
k3d cluster create ha-lab \
  --servers 3 \
  --image rancher/k3s:v1.36.4-k3s1
```

Then:

```bash
kubectl get nodes -o wide
k3d cluster list
```

### Important: three k3d server containers are still not physical HA

If all three server containers run on one laptop or one EC2 instance, losing that host loses the entire cluster. This is an **HA topology lab**, not independent-failure-domain HA.

### Where k3d is an excellent fit

- local Kubernetes development;
- automated integration tests;
- CI pipelines;
- Helm chart testing;
- reproducing multi-node behavior quickly;
- teaching K3s server/agent concepts.

### Where native K3s is normally better

- a long-lived single EC2 server;
- edge servers;
- bare-metal production nodes;
- small self-managed production clusters;
- environments where you want host networking/storage behavior without a Docker node-container abstraction.

---

# 10. Why `--privileged` changes the risk model

Running a Kubernetes node inside a Docker container is not equivalent to running an ordinary isolated application container.

K3s needs to manage low-level node functions such as:

- namespaces/cgroups;
- networking;
- mounts;
- kubelet operations;
- nested workload containers.

The documented direct Docker approach therefore uses `--privileged`.

A privileged K3s node container should **not** be treated as a strong security boundary from the Docker host. If that node container is compromised, the impact can be much closer to host-level compromise than a normal least-privileged application container.

For that reason, "put K3s in Docker for security" is not a sound default assumption.

---

# 11. Networking when K3s runs in Docker

There are two networking layers to keep in mind:

```text
Host network
└── Docker network
    └── K3s node container
        └── Kubernetes Pod/Service network
```

For a simple direct Docker setup:

- map `6443` for the Kubernetes API;
- map application/ingress ports only when required;
- make all K3s node containers share the same Docker network for direct node-name reachability;
- avoid publishing internal Kubernetes networking ports to the public Internet.

For local development, k3d handles much of this Docker-side node networking automatically and provides a load-balancer container for cluster entry points.

---

# 12. Storage when K3s runs in Docker

There are also multiple storage layers:

```text
Host filesystem / Docker volumes
└── K3s node container filesystem
    └── Kubernetes volumes / local-path storage
```

For disposable CI clusters, ephemeral storage is usually fine.

For a reusable direct-Docker K3s server, persist at least the K3s state directory:

```text
/var/lib/rancher/k3s
```

You may also persist configuration under:

```text
/etc/rancher/k3s
```

Do not confuse persistence of the **K3s node container** with production-grade persistent storage for application workloads. Stateful application design still requires its own storage and backup strategy.

---

# 13. Native K3s vs containerized K3s on an EC2 server

For this repository, the preferred design is **native K3s on the EC2 operating system**.

| Area | Native K3s on EC2 | K3s inside Docker on EC2 |
|---|---|---|
| Process layers | Fewer | Extra Docker node-container layer |
| Privileged node container | Not required | Usually required |
| systemd integration | Natural | Docker manages node container instead |
| Host networking | Direct | Additional Docker networking layer |
| Host storage paths | Direct | Additional bind/volume layer |
| Local dev portability | Lower | Higher |
| CI/test convenience | Good | Excellent with k3d |
| Long-lived small server | **Preferred** | Possible, usually unnecessary |

The repository therefore keeps this architecture:

```text
AWS EC2
└── Linux
    └── K3s service
        └── containerd
            └── workload containers
```

rather than:

```text
AWS EC2
└── Linux
    └── Docker
        └── privileged K3s container
            └── containerd
                └── workload containers
```

Both work. The first has fewer operational layers for a server whose primary job is to be a K3s node.

---

# 14. K3s vs kubeadm detailed comparison

| Area | K3s | kubeadm |
|---|---|---|
| What it is | Lightweight Kubernetes distribution | Kubernetes bootstrap/join tool |
| Single-node experience | Very simple | Supported but more explicit setup |
| Runtime | containerd bundled/default | CRI runtime prepared separately |
| Pod network | defaults packaged | CNI chosen/installed separately |
| Single-node datastore | SQLite by default | local etcd member |
| Server also runs workloads | Yes by default | control plane is tainted by default |
| HA | 3+ servers with embedded etcd, or external DB | stacked etcd or external etcd |
| Load-balanced API for HA | Required/recommended fixed endpoint | Required/recommended control-plane endpoint |
| Operational abstraction | Higher | Lower / more explicit |
| Component-level control | Strong, but opinionated defaults | Maximum explicit upstream-style control |
| Edge/small server suitability | Excellent | Often more work than necessary |
| Lab for kubeadm skills | Not the same workflow | Excellent |
| K3s in Docker | Official image; k3d purpose-built | Not the normal kubeadm operating model |
| This repository | **Selected** | Documented as an alternative |

---

# 15. Important kubeadm single-node detail if HA may come later

The official kubeadm documentation recommends setting a shared `--control-plane-endpoint` during initial cluster creation if you may later convert the cluster to HA.

Why this matters: converting a single-control-plane kubeadm cluster that was created **without** a control-plane endpoint into an HA cluster is not supported by kubeadm.

This is a good example of why kubeadm benefits from more up-front architecture planning.

---

# 16. Decision tree

Use this as the fast decision path:

```text
Do you only need to run containers on one server?
|
+-- Yes --> Docker Compose / Podman Compose
|
+-- No, Kubernetes is required
    |
    +-- Is this one server or a small simple cluster?
    |   |
    |   +-- Yes --> K3s
    |
    +-- Do you specifically need kubeadm/upstream bootstrap mechanics,
        custom control-plane ownership, or an existing kubeadm standard?
        |
        +-- Yes --> kubeadm
        |
        +-- No --> K3s is the simpler default

Need HA?
|
+-- No --> single K3s server or 1 server + agents
|
+-- Yes --> independent failure domains
          |
          +-- simpler self-managed HA --> 3 K3s servers + embedded etcd
          |
          +-- maximum explicit upstream control --> kubeadm HA
```

---

# 17. Recommended topologies by use case

| Use case | Recommendation | Reason |
|---|---|---|
| Developer laptop | k3d | Fast disposable K3s-in-Docker |
| CI integration test | k3d | Reproducible containerized nodes |
| One Linux/EC2 server, Kubernetes required | Native K3s | Low operational overhead |
| One Linux/EC2 server, only containers required | Compose | Avoid unnecessary Kubernetes control plane |
| Small cluster, control-plane downtime acceptable | 1 K3s server + agents | Simple scaling |
| Small production HA | 3 K3s servers + optional agents | Embedded etcd and simpler ops |
| HA lab on one workstation | k3d with 3 servers | Learn quorum/topology; not true HA |
| Enterprise kubeadm standard | kubeadm | Align with existing runbooks/platform ownership |
| CKA/admin mechanics practice | kubeadm | Closer to upstream manual/bootstrap path |

---

# 18. How this relates to this repository

This repository deliberately separates lifecycle ownership:

```text
VPC -> EC2 -> K3s -> Traefik -> cert-manager -> Argo CD
```

The EC2 module owns compute. The K3s module owns Kubernetes installation/configuration through AWS Systems Manager. K3s is installed on the Linux node rather than being wrapped in an additional Docker node container.

That design is intentional because the current target is a long-lived, cost-conscious EC2 Kubernetes server, not a disposable local test cluster.

If a future requirement is local/CI testing, add k3d as a **test environment**, not as a replacement for the production EC2 topology.

---

# 19. Operational checks

## Native K3s

```bash
systemctl status k3s
k3s --version
kubectl get nodes -o wide
kubectl get pods -A
```

## Direct Docker K3s

```bash
docker ps --filter name=k3s
docker logs k3s-server-1
docker exec k3s-server-1 kubectl get nodes -o wide
```

## k3d

```bash
k3d cluster list
kubectl get nodes -o wide
kubectl get pods -A
```

## kubeadm

```bash
kubeadm version
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

---

# 20. Final recommendation for this project

For the AWS EC2 platform in this repository:

- keep **K3s native on Linux** as the production/default design;
- keep **EC2 and K3s as separate Terraform/Terragrunt lifecycle modules**;
- use **k3d** when a containerized K3s environment is useful for local development or CI;
- use direct `rancher/k3s` Docker containers for learning, debugging, or specialized testing rather than as the default EC2 production architecture;
- move to **3 independent K3s server nodes with embedded etcd** when real control-plane HA becomes a requirement;
- choose kubeadm only when there is a concrete requirement for kubeadm/upstream bootstrap standardization or deeper component-level ownership.

That keeps the design simple today without blocking a professional HA evolution path later.

---

## Official research sources

### K3s

- Architecture: https://docs.k3s.io/architecture
- Quick start: https://docs.k3s.io/quick-start
- Advanced options, including running K3s in Docker: https://docs.k3s.io/advanced
- Configuration with container image: https://docs.k3s.io/installation/configuration
- K3s server reference: https://docs.k3s.io/cli/server
- K3s agent reference: https://docs.k3s.io/cli/agent
- HA embedded etcd: https://docs.k3s.io/datastore/ha-embedded
- HA external datastore: https://docs.k3s.io/datastore/ha

### kubeadm / Kubernetes

- Creating a cluster with kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- kubeadm HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- kubeadm implementation details: https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/

### k3d

- k3d: https://k3d.io/
- k3d CLI: https://k3d.io/stable/usage/commands/k3d/
- k3d configuration: https://k3d.io/stable/usage/configfile/
