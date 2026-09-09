# K3s architecture and deployment guidance

This section documents the recommended K3s topologies for this repository and the research-backed decision points for choosing K3s, kubeadm, or a simpler container runtime workflow.

## Current platform architecture

![K3s on AWS platform architecture](../diagrams/k3s-platform-overview.svg)

The rendered SVG above represents the repository's current single-node AWS profile. Detailed topology diagrams and the K3s vs kubeadm research are maintained separately so the operational decision record stays reviewable and version-controlled.

## Documents

- [`architecture.md`](architecture.md) - single-node, multi-node non-HA, multi-node HA, external-datastore HA, and single-physical-host lab topologies.
- [`kubeadm-comparison.md`](kubeadm-comparison.md) - K3s vs kubeadm decision matrix, trade-offs, and scenario recommendations.
- [`../diagrams/`](../diagrams/) - rendered architecture assets used by GitHub documentation.

## Repository position

This repository uses K3s intentionally because the current target is a cost-conscious self-managed Kubernetes platform on EC2 with a small operational footprint. K3s remains conformant Kubernetes while packaging common cluster components and simplifying bootstrap and upgrades.

The choice is not universal:

- use **Docker Compose / Podman Compose** when the requirement is only to run a few containers on one server and Kubernetes APIs are not needed;
- use **K3s** when Kubernetes features are required on one server, on a small multi-node cluster, or when simplified HA operations are valuable;
- use **kubeadm** when the objective is a more explicit upstream Kubernetes bootstrap, deeper component-level customization, or kubeadm-specific operational standardization.

## Quick decision

| Requirement | Recommended starting point |
|---|---|
| One server, only run containers | Docker Compose / Podman Compose |
| One server, Kubernetes required | K3s |
| Multi-node, one control-plane server | K3s |
| Multi-node HA, small/medium self-managed platform | K3s with 3 server nodes and embedded etcd |
| Multi-node HA, maximum upstream bootstrap control | kubeadm |
| Several VMs on one physical host | K3s for lab/testing; **not true HA** |

See the comparison guide for the reasoning behind each recommendation.

## Upstream references

- K3s architecture: https://docs.k3s.io/architecture
- K3s HA embedded etcd: https://docs.k3s.io/datastore/ha-embedded
- K3s HA external datastore: https://docs.k3s.io/datastore/ha
- Kubernetes kubeadm HA: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
