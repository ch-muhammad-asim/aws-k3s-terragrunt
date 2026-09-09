# K3s architecture and deployment guidance

This section documents the K3s topologies used or considered by this repository.

![K3s on AWS platform architecture](../diagrams/k3s-platform-overview.svg)

## Start here

For the full, human-readable research and decision guide — including **K3s vs kubeadm, K3s as a Docker container, k3d, single-node, multi-node, HA/non-HA, networking, storage and security** — use:

**[`../k3s-vs-kubeadm/README.md`](../k3s-vs-kubeadm/README.md)**

## K3s-specific documents

- [`architecture.md`](architecture.md) - detailed K3s topology diagrams for single-node, multi-node non-HA, embedded-etcd HA, external datastore HA, single-host VM labs and independent failure domains.
- [`../k3s-vs-kubeadm/README.md`](../k3s-vs-kubeadm/README.md) - canonical comparison/research guide and K3s-in-containers documentation.

## Repository position

This repository uses **native K3s on the EC2 Linux host** intentionally. The current target is a cost-conscious self-managed Kubernetes platform with a small operational footprint.

The production/default model is:

```text
EC2 Linux host
└── K3s service
    └── embedded containerd
        └── Kubernetes workload containers
```

K3s can also run inside Docker using the official `rancher/k3s` image, and k3d is purpose-built for running K3s nodes as Docker containers. Those modes are documented in the comparison guide and are recommended mainly for development, CI, labs and specialized testing rather than as an extra container layer around this repository's long-lived EC2 K3s node.

## Quick decision

| Requirement | Recommended starting point |
|---|---|
| One server, only run containers | Docker Compose / Podman Compose |
| One server, Kubernetes required | K3s |
| Local/CI Kubernetes in Docker | k3d |
| Multi-node, one control-plane server | K3s |
| Multi-node HA, small/medium self-managed platform | K3s with 3 independent server nodes and embedded etcd |
| Multi-node HA, maximum upstream bootstrap control | kubeadm |
| Several VMs/containers on one physical host | Lab/testing only; **not true HA** |

## Upstream references

- K3s architecture: https://docs.k3s.io/architecture
- K3s quick start: https://docs.k3s.io/quick-start
- K3s advanced options / running in Docker: https://docs.k3s.io/advanced
- K3s HA embedded etcd: https://docs.k3s.io/datastore/ha-embedded
- K3s HA external datastore: https://docs.k3s.io/datastore/ha
- Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- Kubernetes kubeadm HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
