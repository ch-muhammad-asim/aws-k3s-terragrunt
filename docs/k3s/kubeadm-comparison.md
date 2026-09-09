# K3s vs kubeadm

K3s and kubeadm solve related but different operational problems.

- **K3s** packages a lightweight Kubernetes distribution with an opinionated installation and several bundled components.
- **kubeadm** bootstraps an upstream-style Kubernetes cluster and leaves more infrastructure and add-on decisions to the operator.

Neither is universally better. The correct choice depends on topology, operational requirements, and how much Kubernetes internals the team wants to own directly.

## Comparison

| Area | K3s | kubeadm |
|---|---|---|
| Single-node bootstrap | Excellent | Supported, but more setup |
| Small resource footprint | Excellent | Higher operational/component overhead |
| Time to first cluster | Fast | More steps |
| Bundled container runtime | containerd included | Runtime installed/configured separately |
| CNI / common add-ons | Sensible defaults bundled | Operator chooses/installs them |
| Single-server datastore | Embedded SQLite by default | Single local etcd member |
| HA datastore | Embedded etcd or external DB | Stacked etcd or external etcd |
| HA control plane | Straightforward with 3+ K3s servers | Mature, explicit, more moving parts |
| Upstream component visibility | More abstracted | More explicit |
| Fine-grained component customization | Good | Excellent |
| Edge / branch / small server | Excellent fit | Usually heavier than necessary |
| CKA-style learning | Good | Excellent |
| Operational simplicity | Strong advantage | Requires more Kubernetes plumbing knowledge |
| Enterprise standardization | Good when K3s is an accepted distro | Strong where kubeadm/upstream Kubernetes is the standard |

## Scenario recommendations

### One server: only need to run containers

**Recommendation: Docker Compose or Podman Compose.**

Do not introduce Kubernetes only for the label. If the requirement is a handful of containers, restart policies, networks, volumes, and environment variables on one host, a compose-based runtime is simpler and has fewer control-plane components to operate.

Choose K3s instead when you need Kubernetes-native capabilities such as:

- Deployments and rolling updates;
- Services and Ingress;
- Helm charts;
- Kubernetes Secrets/ConfigMaps;
- Jobs/CronJobs;
- GitOps with Argo CD;
- a path to later adding nodes without redesigning the application deployment model.

### One server: Kubernetes is required

**Recommendation: K3s.**

A single-node kubeadm cluster works, but K3s is normally a better operational fit for a small one-server deployment because installation, containerd, networking defaults, kubeconfig, and common components are packaged together.

This repository therefore uses K3s for its initial EC2 profile.

### Multi-node, non-HA

**Recommendation: K3s for most small/medium deployments.**

Use one K3s server and multiple K3s agents when worker capacity needs to scale but control-plane downtime is acceptable.

Use kubeadm when the team specifically needs an upstream kubeadm operating model, custom component configuration, or kubeadm parity with other environments.

### Multi-node HA

There are two strong choices.

**K3s is preferred when:**

- simplicity and fast recovery matter;
- a small platform team owns the cluster;
- embedded etcd is acceptable;
- lower operational overhead is a priority.

**kubeadm is preferred when:**

- the organization standardizes on upstream Kubernetes bootstrap;
- control-plane components need deep/custom configuration;
- the team intentionally wants to own CNI, runtime integration, load-balancing, PKI/bootstrap details, and upgrade procedures at a lower level;
- kubeadm knowledge and runbooks already exist.

Kubeadm supports HA with either stacked control-plane/etcd nodes or an external etcd cluster. K3s supports HA with embedded etcd or an external datastore.

## HA vs non-HA matrix

| Topology | K3s | kubeadm | Recommendation |
|---|---|---|---|
| 1 physical server, 1 node | Very strong fit | Works | **K3s** if Kubernetes is required |
| 1 physical server, several VMs | Easy lab | Good learning lab | **K3s for simplicity**, but neither provides real HA |
| 1 server + several workers | Very simple | Supported | **K3s** for most small clusters |
| 3 independent control-plane servers + workers | Embedded etcd makes this straightforward | Stacked etcd is well established | K3s for simplicity; kubeadm for maximum control |
| External datastore/etcd architecture | Supported | Supported | Depends on existing datastore/platform standards |
| CKA/CKS lab focused on upstream internals | Useful | Closest to exam/admin mechanics | **kubeadm** |

## What "HA" actually requires

High availability is about **independent failure domains**, not the number of VMs.

Three control-plane VMs running on one physical server still share:

- the same motherboard/CPU/RAM failure domain;
- the same power source;
- the same local disks/storage controller;
- the same hypervisor;
- usually the same network uplink.

If that server fails, all three control-plane VMs disappear at once. It is a multi-node topology, but not physical-host HA.

For real HA, place the control-plane nodes on independent servers or cloud failure domains and put a fixed registration/API endpoint in front of them.

## Decision for this repository

The default architecture remains **K3s** because the repository targets a small, cost-efficient, self-managed Kubernetes platform on EC2.

The evolution path is:

```text
Single-node K3s
        |
        v
1 K3s server + N agents
        |
        v
3 K3s servers with embedded etcd + N agents
        |
        v
Multi-AZ / independent failure domains
```

Moving to kubeadm would be justified by an explicit requirement for upstream kubeadm standardization or deeper control-plane customization, not simply because the cluster has multiple nodes.

## Sources

- K3s architecture: https://docs.k3s.io/architecture
- K3s embedded-etcd HA: https://docs.k3s.io/datastore/ha-embedded
- K3s external datastore HA: https://docs.k3s.io/datastore/ha
- kubeadm HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- kubeadm HA etcd: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/
