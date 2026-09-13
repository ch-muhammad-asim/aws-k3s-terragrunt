# AI Factory on Kubernetes: what it is, where K3s fits, and how to build one

> **Research review:** 2026-09-13. This guide was checked against current NVIDIA AI Factory / AI Enterprise reference material, NVIDIA GPU Operator support, Kubernetes resource-management documentation, Kubeflow, KServe, KubeRay, Kueue, and MLflow documentation.

## Executive summary

An **AI factory** is not one product and it is not simply a Kubernetes cluster with GPUs. It is an operating platform that repeatedly turns **data + compute + models + software** into production AI services, then feeds production telemetry and feedback back into the next development cycle.

A useful mental model is:

```text
Data
  |
  v
Prepare / curate / index
  |
  v
Train / fine-tune / evaluate
  |
  v
Package / register
  |
  v
Deploy / serve / scale
  |
  v
Observe / govern / collect feedback
  |
  +-------------------------------> next iteration
```

Kubernetes is a strong foundation for this because it provides scheduling, self-healing, resource isolation, APIs, operators, namespaces, policy, rollout mechanisms, and a common control plane for CPU and accelerator workloads. NVIDIA's current Enterprise AI Factory guidance explicitly places Kubernetes at the core of the cloud-native platform and uses Kubernetes operators to manage GPUs, networking, and AI services.

**K3s can absolutely be used to build an AI factory**, especially a small-to-medium self-hosted platform, edge AI system, inference platform, development environment, or cost-conscious GPU cluster. It is still Kubernetes, so Kubernetes-native AI software such as GPU Operator, Kubeflow components, KServe, KubeRay, Kueue, MLflow, Prometheus, and Argo CD can run on it when their version and platform requirements are met.

The important qualifier is supportability. As of this review, NVIDIA GPU Operator `26.7.x` lists K3s as validated on Ubuntu 22.04, 24.04, and 26.04 for Kubernetes/K3s versions `1.33` through `1.37`. This repository currently pins K3s `v1.36.4+k3s1`, which falls inside that Kubernetes version range, but the current EC2 node uses Amazon Linux 2023. Amazon Linux 2023 is **not listed in NVIDIA's current K3s validation rows**, so a production GPU worker design should not assume that the current OS is a validated NVIDIA GPU Operator combination.

For this repository, the cleanest evolution is therefore:

```text
Terragrunt
   |
   +--> AWS network / IAM / storage / load balancing
   |
   +--> CPU K3s server nodes
   |
   +--> GPU worker nodes on a validated GPU OS/profile
              |
              v
         K3s / RKE2 / another Kubernetes distribution
              |
              +--> NVIDIA GPU Operator
              +--> optional NVIDIA Network Operator / RDMA stack
              +--> CSI / object / high-throughput storage
              +--> Kueue / batch scheduling
              +--> Kubeflow / MLflow
              +--> KServe / KubeRay / model runtimes
              +--> Prometheus / Grafana / DCGM
              +--> Argo CD / GitOps
```

The repository should continue to use **Terragrunt/Terraform for the infrastructure substrate** and Kubernetes for the AI platform. Kubernetes can manage some external infrastructure through projects such as Crossplane or Cluster API, but using the same cluster to bootstrap every layer of the infrastructure can create circular dependencies and makes disaster recovery harder.

---

## 1. What does "AI factory" mean?

The phrase is used by several vendors, most prominently NVIDIA, but the architectural idea is broader than one vendor. Think of an AI factory as the platform equivalent of a production line for AI:

- raw enterprise data enters the system;
- data is transformed into AI-ready datasets, embeddings, features, or training corpora;
- models are trained, fine-tuned, evaluated, or selected;
- models and application artifacts are versioned;
- inference or agent services are deployed;
- the services are observed for quality, latency, throughput, safety, and cost;
- production data and feedback drive the next model/application iteration.

NVIDIA's 2026 Enterprise AI Factory Design Guide describes an AI factory as a hardware-and-software co-designed system built to industrialize AI deployment, with accelerator capacity, high-speed networking, scalable storage, power/cooling, cloud-native software, security, observability, and automation treated as one system.

Official reference:

- NVIDIA Enterprise AI Factory overview: <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/ai-factory-overview.html>
- NVIDIA AI Factory ecosystem architecture: <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/ecosystem-architecture.html>
- NVIDIA AI Factory deployment strategies: <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/deployment-strategies.html>

### AI factory is more than GPUs

A rack of GPUs is **compute capacity**, not an AI factory by itself.

A Kubernetes cluster is **an orchestration platform**, not an AI factory by itself.

An LLM inference server is **one workload**, not an AI factory by itself.

The AI factory appears when those pieces become an integrated, repeatable platform:

```text
Facilities / cloud capacity
        |
Compute + accelerators
        |
High-speed network + storage
        |
Operating system / firmware / drivers
        |
Kubernetes platform
        |
GPU / network / storage operators
        |
Data + ML + inference platform services
        |
CI/CD + GitOps + security + observability
        |
AI applications, models, agents and pipelines
```

---

## 2. Where Kubernetes fits

Kubernetes sits in the middle of the AI factory. It is not the physical infrastructure and it is not the AI model; it is the control plane that connects infrastructure capacity to workloads.

NVIDIA's current AI Enterprise software reference architecture uses **upstream Kubernetes** and `containerd` as the example orchestration/runtime stack. Its documentation describes Kubernetes as the platform for deployment, scaling, multi-tenancy, GPU scheduling, networking operators, and production AI workloads.

Official reference:

- NVIDIA AI Enterprise software stack: <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/software-stack.html>
- NVIDIA AI Enterprise platform overview: <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/platform-overview.html>

Kubernetes contributes the following building blocks.

| Need | Kubernetes capability |
|---|---|
| Place workloads on GPU/CPU nodes | scheduler, labels, taints/tolerations, affinity |
| Expose accelerators | device plugins and Dynamic Resource Allocation (DRA) |
| Multi-tenancy | namespaces, RBAC, quotas, policies |
| Self-healing | controllers, ReplicaSets, StatefulSets, Jobs |
| Rollouts | Deployments, operators, GitOps controllers |
| Batch/training | Jobs plus Kueue/Volcano/other schedulers |
| Inference | Services, Gateway/Ingress, KServe, Ray Serve, custom runtimes |
| Persistent data | CSI, PersistentVolumes, object storage integrations |
| Hardware lifecycle | GPU Operator, Network Operator and vendor operators |
| Observability | Prometheus ecosystem, OpenTelemetry, DCGM Exporter |

### Modern accelerator allocation

Kubernetes Dynamic Resource Allocation (DRA) is now a stable Kubernetes feature. Kubernetes documents it as a way for workloads to request and share hardware devices such as accelerators. DRA became stable in Kubernetes 1.35, and Kubernetes 1.37 added GA support for DRA-backed extended resources.

Official references:

- Kubernetes DRA concept: <https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>
- Kubernetes 1.37 DRA updates: <https://kubernetes.io/blog/2026/09/03/kubernetes-v1-37-dra-updates/>

This matters for AI factories because accelerator scheduling is becoming richer than a simple integer such as `nvidia.com/gpu: 1`.

---

## 3. Can K3s be the Kubernetes layer of an AI factory?

**Yes.** K3s is a conformant Kubernetes distribution. Kubernetes-native AI components generally care about the Kubernetes APIs, container runtime, device exposure, storage/network interfaces, and supported versions rather than whether the control plane binary came from K3s or kubeadm.

The strongest current evidence is the NVIDIA GPU Operator support matrix. NVIDIA GPU Operator `26.7.x` explicitly includes **K3s** in its supported/validated Kubernetes platform table for Ubuntu 22.04, Ubuntu 24.04, and Ubuntu 26.04, covering Kubernetes versions 1.33 through 1.37.

Official reference:

- NVIDIA GPU Operator platform support: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>
- NVIDIA GPU Operator installation: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>

### Important repository-specific caveat

This repository currently uses:

```text
K3s:       v1.36.4+k3s1
OS:        Amazon Linux 2023
Profile:   one EC2 K3s server/worker
Compute:   t3.medium by default
```

K3s `1.36` is within the current NVIDIA GPU Operator K3s version range, but **Amazon Linux 2023 is not listed in the K3s rows of NVIDIA's current validation matrix**.

Therefore:

> Do not describe the existing Amazon Linux 2023 node as a validated NVIDIA GPU Operator AI node.

For a production NVIDIA GPU worker pool, a safer design is to use an OS/distribution combination that appears in the current support matrix, for example Ubuntu 24.04 LTS with a supported K3s/RKE2/Kubernetes version, and validate the exact GPU, driver, kernel, container runtime, and operator release before deployment.

The existing Amazon Linux node can still remain useful as a control-plane or general CPU node if that operational model is desired.

---

## 4. Can Kubernetes build the infrastructure itself?

This question has two different meanings.

### Meaning A: can Kubernetes operate the AI infrastructure once machines exist?

**Yes. This is one of its strongest use cases.**

Once servers, VMs, GPUs, networks, and storage endpoints exist, Kubernetes and operators can manage a large amount of the software infrastructure:

- GPU drivers/runtime/device exposure through NVIDIA GPU Operator;
- networking components through NVIDIA Network Operator or other CNIs/operators;
- storage through CSI operators;
- model serving through KServe or Ray Serve;
- ML pipelines through Kubeflow components;
- queues and quotas through Kueue;
- telemetry through Prometheus/DCGM/OpenTelemetry;
- GitOps through Argo CD;
- certificates through cert-manager;
- application ingress/gateway through Traefik or another Gateway/Ingress implementation.

### Meaning B: should Kubernetes provision every lower infrastructure layer too?

**It is possible, but it should not automatically be the default.**

Projects such as Crossplane and Cluster API let Kubernetes APIs manage cloud and cluster infrastructure, but the bootstrap problem remains: something must first create the management cluster, IAM access, networking, state/storage and recovery path.

For this repository, the clearer separation is:

```text
Layer 1 - Infrastructure substrate
Terragrunt / Terraform
  -> VPC
  -> subnets
  -> security groups
  -> IAM
  -> EC2 / GPU EC2
  -> disks / object storage / load balancers

Layer 2 - Kubernetes
K3s / RKE2 / kubeadm / OpenShift / another distribution
  -> cluster control plane
  -> CPU workers
  -> GPU workers

Layer 3 - AI platform
Kubernetes operators + Helm/GitOps
  -> GPU Operator
  -> storage/network operators
  -> Kueue
  -> Kubeflow components
  -> MLflow
  -> KServe
  -> KubeRay
  -> observability

Layer 4 - AI products
  -> model APIs
  -> RAG
  -> agents
  -> batch inference
  -> fine tuning
  -> distributed training
```

This separation makes disaster recovery easier because infrastructure can be rebuilt without requiring the AI cluster to already be healthy.

NVIDIA's current deployment-strategy guidance follows a similar separation: IaC for repeatable provisioning, automation for platform software, Helm/operators for Kubernetes services, and GitOps for ongoing application configuration.

Official reference:

- NVIDIA AI Factory deployment strategies: <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/deployment-strategies.html>

---

## 5. A practical AI factory architecture using K3s

For a **small-to-medium self-hosted AI factory**, a sensible target is:

```text
                           Developers / CI / GitOps
                                  |
                                  v
                         API / ingress / gateway
                                  |
                         +--------+---------+
                         | Kubernetes API  |
                         +--------+---------+
                                  |
               +------------------+------------------+
               |                  |                  |
        K3s server 1       K3s server 2       K3s server 3
        CPU / etcd          CPU / etcd          CPU / etcd
               |                  |                  |
               +---------- control-plane HA --------+
                                  |
            +---------------------+-----------------------+
            |                                             |
     CPU worker pool                               GPU worker pool
     general services                              AI workloads
            |                                             |
            |                                  NVIDIA GPU Operator
            |                                  DCGM / telemetry
            |                                  optional MIG / sharing
            |                                             |
            +---------------------+-----------------------+
                                  |
            +---------------------+-----------------------+
            |                     |                       |
         Storage              AI platform             Serving
   object / CSI / NVMe      Kubeflow / MLflow       KServe / Ray
            |                     |                       |
            +---------------------+-----------------------+
                                  |
                         Argo CD / GitOps
                                  |
                    monitoring / policy / security
```

### Why keep control-plane nodes mostly CPU-only?

GPU machines are expensive. etcd, the API server, scheduler, controllers, ingress control components, GitOps controllers and certificate controllers do not require a high-end GPU.

Separating the pools lets you:

- upgrade or drain GPU nodes independently;
- scale GPU capacity independently;
- use cheaper CPU instances for the control plane;
- isolate expensive accelerators from normal platform pods;
- apply taints such as `accelerator=nvidia:NoSchedule` and allow only GPU workloads onto those workers;
- choose different operating-system/kernel policies for GPU nodes.

For a very small lab, one GPU-capable K3s server/worker can run everything. That is useful for learning, but it is not the topology I would use for a production HA AI factory.

---

## 6. AI platform components you can run on K3s/Kubernetes

The following projects are examples, not a requirement to install every tool.

### NVIDIA GPU Operator

Purpose: automate GPU driver/runtime/device plugin/DCGM-related Kubernetes integration.

NVIDIA describes GPU Operator as the lifecycle manager for the software required to expose NVIDIA GPUs to Kubernetes.

- Docs: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/>
- Platform support: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>

### NVIDIA Network Operator

Purpose: automate NVIDIA networking components and enable high-performance networking configurations, including use cases involving RDMA/GPUDirect RDMA.

This becomes important for multi-node training, where east-west GPU traffic can dominate performance.

- Docs: <https://docs.nvidia.com/networking/display/kubernetes2612/getting-started-with-kubernetes.html>
- NVIDIA AI Enterprise networking context: <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/networking.html>

For small single-node inference, you may not need this complexity.

### Kubeflow

Kubeflow describes itself as a **Cloud Native AI platform** composed of modular open-source projects for data, AI/ML, and HPC workloads on Kubernetes.

Use it when you need a broader Kubernetes-native ML platform rather than only model serving.

- Introduction: <https://www.kubeflow.org/docs/started/introduction/>
- Installation/distributions: <https://www.kubeflow.org/docs/started/installing-kubeflow/>

Do not install the whole Kubeflow ecosystem just because it exists. Select the modules that solve actual platform requirements.

### KServe

Purpose: production model inference on Kubernetes.

KServe's administrator documentation describes it as a Kubernetes model-inference platform supporting predictive and generative inference.

- Admin guide: <https://kserve.github.io/website/docs/admin-guide/overview>
- Quickstart: <https://kserve.github.io/website/docs/getting-started/quickstart-guide>

### KubeRay / Ray

Purpose: distributed Python/AI compute, training, data processing and Ray Serve workloads on Kubernetes.

KubeRay is the Kubernetes operator for Ray and manages `RayCluster`, `RayJob`, `RayService`, and related resources.

- Ray on Kubernetes: <https://docs.ray.io/en/latest/cluster/kubernetes/index.html>
- KubeRay getting started: <https://docs.ray.io/en/latest/cluster/kubernetes/getting-started.html>

### Kueue

Purpose: Kubernetes-native queueing, quotas, admission and fair sharing for batch/AI jobs.

Kueue is especially useful when several teams compete for scarce GPU capacity.

- Overview: <https://kueue.sigs.k8s.io/docs/overview/>
- Documentation: <https://kueue.sigs.k8s.io/docs/>

### MLflow

Purpose: experiment tracking, model metadata/registry-related workflows and ML lifecycle tooling.

MLflow now provides a Kubernetes Helm deployment path for self-hosted environments.

- Kubernetes deployment: <https://mlflow.org/docs/latest/self-hosting/kubernetes-helm>

### DCGM Exporter

Purpose: expose NVIDIA GPU telemetry in Prometheus format.

A production AI factory should observe accelerator utilization, memory, temperature, errors and workload-level metrics rather than only CPU/memory metrics.

- NVIDIA DCGM Exporter: <https://docs.nvidia.com/datacenter/dcgm/latest/installation/install-dcgm-exporter.html>

---

## 7. Storage is a first-class design decision

AI workloads can be far more storage-sensitive than ordinary web services.

Different data has different access patterns:

| Data | Typical requirement |
|---|---|
| training datasets | high sequential throughput, parallel reads |
| model checkpoints | large writes + reliable persistence |
| model weights | fast startup/read path |
| embeddings | vector database / high IOPS depending design |
| artifacts | object storage is often appropriate |
| experiment metadata | relational database / durable service |
| hot temporary data | local NVMe can be valuable |

A simple development cluster can use normal CSI-backed block storage and S3-compatible object storage. Large distributed training may require a much more deliberate storage architecture, parallel filesystems, NVMe tiers, or GPUDirect Storage-capable designs.

NVIDIA's AI Factory guidance treats storage as part of the co-designed system rather than an afterthought.

Reference:

- AI Factory overview: <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/ai-factory-overview.html>

### Practical rule

Do not place the only copy of valuable training data or model artifacts on Kubernetes node-local storage.

Use node-local NVMe as a cache/scratch layer when appropriate, and keep authoritative artifacts on durable storage.

---

## 8. Networking: inference and training have different requirements

A web/API inference service may work perfectly well on standard Ethernet.

Distributed training across many GPUs is very different. Workers exchange gradients/parameters and can become network-bound. High-end AI architectures may use high-bandwidth Ethernet/InfiniBand, RDMA/RoCE, GPUDirect RDMA and carefully designed east-west fabrics.

NVIDIA's current AI factory reference material distinguishes GPU compute east-west traffic, storage traffic, north-south/customer traffic and management traffic.

References:

- NVIDIA AI Enterprise networking: <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/networking.html>
- NVIDIA Network Operator: <https://docs.nvidia.com/networking/display/kubernetes2612/getting-started-with-kubernetes.html>

For this repository's initial AI-factory evolution, do not add RDMA complexity until a workload actually requires multi-node GPU communication.

---

## 9. Scheduling GPU workloads

For a small cluster, the default Kubernetes scheduler plus NVIDIA GPU resources may be enough.

As the platform grows, typical requirements include:

- team quotas;
- job queues;
- gang/co-scheduling;
- priorities and preemption;
- heterogeneous GPU types;
- reserved versus shared pools;
- GPU fractions/sharing;
- topology-aware scheduling;
- batch versus latency-sensitive inference priorities.

Possible solutions include Kueue, Volcano, Run:ai, or other specialized schedulers depending operational and commercial requirements.

NVIDIA's 2026 AI Factory guidance explicitly mentions sophisticated schedulers such as Kueue and Volcano as optional extensions for efficient multi-tenant AI environments.

### GPU sharing: understand the isolation model

NVIDIA GPU Operator supports technologies including MIG and time-slicing.

- **MIG** partitions supported GPUs into hardware-isolated GPU instances with memory/fault isolation characteristics.
- **Time-slicing** increases utilization by sharing a GPU across workloads but does not provide the same memory/fault isolation as MIG.

Do not treat every GPU-sharing mode as equivalent multi-tenant isolation.

Reference:

- GPU Operator with MIG: <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html>

---

## 10. Observability for an AI factory

Normal Kubernetes monitoring is necessary but insufficient.

You should observe at least:

```text
Infrastructure
  CPU / RAM / disk / network

Kubernetes
  node health / pods / deployments / Jobs / API / etcd

GPU
  utilization / memory / temperature / power / ECC/XID errors

Training
  job queue time / GPU hours / progress / checkpoint health

Inference
  latency / throughput / tokens per second / queue depth / errors

Model / application
  quality / drift / evaluation / safety / feedback

Business
  cost per request / cost per model / utilization / SLO
```

NVIDIA DCGM Exporter publishes GPU telemetry in Prometheus format and can be managed by GPU Operator.

Reference:

- DCGM Exporter installation: <https://docs.nvidia.com/datacenter/dcgm/latest/installation/install-dcgm-exporter.html>

For an open platform, a common direction is Prometheus + Grafana for infrastructure metrics and OpenTelemetry for application traces/logs/metrics, combined with model-specific telemetry.

---

## 11. Security and multi-tenancy

An AI factory frequently contains valuable data, models, API credentials and expensive accelerator capacity. Treat it as a security-sensitive platform.

At minimum consider:

- Kubernetes RBAC and least privilege;
- namespace isolation;
- NetworkPolicies;
- Pod Security admission/policies;
- encrypted secrets and external secret management;
- image provenance/scanning/signing;
- admission policy;
- private registries;
- audit logs;
- secure access to model artifacts;
- per-team quotas;
- GPU isolation strategy;
- separate production and experimentation boundaries where appropriate;
- encryption for storage and network paths;
- backup/restore for cluster state and model/data metadata.

For regulated environments, distribution/vendor support, validated combinations, FIPS requirements and lifecycle guarantees may become more important than minimizing Kubernetes overhead.

---

## 12. K3s advantages for an AI factory

### Pros

**Low operational overhead.** K3s packages Kubernetes into a simpler operational model, useful when the platform team is small.

**Good fit for edge and smaller GPU clusters.** AI inference at remote sites, factories, labs or branch locations can benefit from K3s's small footprint.

**Conformant Kubernetes APIs.** Most Kubernetes-native AI operators and CRDs can use the same APIs they use on other distributions, subject to their support matrices.

**Containerd included.** The default runtime aligns well with common GPU/Kubernetes tooling.

**Fast path from one node to multi-node.** You can start with a small environment and evolve to server/agent separation.

**Current NVIDIA GPU Operator validation exists.** K3s is explicitly present in NVIDIA's current platform-support matrix on supported Ubuntu versions.

**Cost efficiency.** The Kubernetes management layer consumes less infrastructure than some heavier enterprise platforms.

### Cons

**The distribution does not solve AI hardware design.** K3s does not provide GPUs, RDMA, high-throughput storage, power/cooling or an AI data platform.

**Support matrix matters.** The current repository OS is not in the current NVIDIA K3s GPU Operator validation rows.

**Large GPU fabrics need deeper engineering.** Multi-node distributed training requires serious networking, topology, storage and scheduling work regardless of how lightweight the Kubernetes distribution is.

**Enterprise validation may favor another platform.** OpenShift, RKE2, upstream Kubernetes or a vendor-certified stack may have stronger alignment with a company's support/compliance requirements.

**K3s defaults may need adjustment.** Bundled components that are convenient for general-purpose clusters may be replaced/disabled in a specialized AI platform.

**Small operational footprint is not the same as large-scale AI efficiency.** GPU utilization and data movement dominate AI economics; saving a little control-plane RAM does not matter if expensive accelerators sit idle.

---

## 13. Other Kubernetes distributions for AI factories

No distribution is universally best. The right choice is driven by scale, support, security/compliance, hardware ecosystem and the team's operating model.

| Platform | AI factory fit | Strengths | Trade-offs |
|---|---|---|---|
| **K3s** | small/medium self-hosted, edge, inference, labs | lightweight, simple, NVIDIA GPU Operator validation on supported Ubuntu/K8s versions | fewer enterprise defaults; validate OS/GPU/operator combinations carefully |
| **RKE2** | enterprise/self-hosted with stronger security posture | SUSE/Rancher ecosystem, closer enterprise posture, current NVIDIA GPU Operator validation | more footprint/operations than K3s |
| **Upstream Kubernetes / kubeadm** | teams wanting explicit upstream architecture | maximum component control; aligns with NVIDIA's generic software RA example | more lifecycle work owned by platform team |
| **OpenShift** | regulated/enterprise AI platforms | strong enterprise lifecycle, policy, integrated ecosystem, NVIDIA support paths | licensing/cost and operational complexity |
| **k0s** | lightweight alternative | small operational surface; appears in current NVIDIA GPU Operator platform matrix on supported combinations | smaller ecosystem mindshare than mainstream enterprise choices |
| **MicroK8s** | Canonical/Ubuntu-centered environments | simple packaging; present in current NVIDIA GPU Operator matrix on supported combinations | Snap/Canonical operating model may not fit every organization |
| **Talos Linux + Kubernetes** | immutable dedicated Kubernetes nodes | strong API-driven immutable-node model | verify AI/GPU vendor support for the exact stack; not listed like K3s/RKE2 in the current NVIDIA GPU Operator matrix reviewed here |
| **EKS/GKE/AKS** | cloud AI platform where managed control plane is desired | reduces control-plane operations; strong cloud integrations | cloud cost/lock-in and different self-hosted goals |

For the broader Kubernetes distribution comparison, see [`../kubernetes-platform-comparison/README.md`](../kubernetes-platform-comparison/README.md).

---

## 14. Which distribution would I choose?

### Small/medium self-hosted AI platform

```text
K3s
+ validated Ubuntu GPU workers
+ GPU Operator
+ Argo CD
+ Kueue when sharing GPUs
+ KServe/KubeRay/MLflow as required
```

This is a strong pragmatic design.

### Security/compliance-heavy self-hosted enterprise

```text
RKE2 or OpenShift
+ vendor-supported GPU stack
+ hardened policies
+ enterprise lifecycle/support
```

### Large custom GPU cluster with a strong platform engineering team

```text
Upstream Kubernetes / kubeadm or a validated enterprise distribution
+ explicit CNI/network fabric
+ specialized scheduler
+ high-performance storage
+ GPU/network operators
```

At this scale, the Kubernetes distribution is only one part of the engineering problem.

### Edge AI / branch / factory-floor inference

```text
K3s
+ one/few GPU nodes
+ GitOps
+ local inference service
+ central model/artifact delivery
```

K3s is particularly attractive here.

---

## 15. How this repository can evolve into an AI-factory foundation

The current repository already has several useful platform patterns:

```text
Terragrunt
  -> VPC
  -> EC2
  -> K3s
  -> Traefik
  -> cert-manager
  -> Argo CD
```

It also uses map-driven `for_each` EC2 resources, which is a useful starting point for separate node roles.

However, the current default `t3.medium` single server/worker is **not an AI compute platform**. A production AI-factory evolution should deliberately introduce node roles instead of merely changing the primary EC2 instance type to a GPU instance.

### Phase 1 - GPU proof of concept

Keep the existing CPU control node and add one dedicated GPU worker profile.

Target concept:

```text
primary
  role: server/control-plane
  CPU instance

gpu-01
  role: agent/worker
  GPU instance
  validated OS
```

Then install/test:

1. K3s agent join flow;
2. NVIDIA GPU Operator;
3. a CUDA validation pod;
4. DCGM telemetry;
5. a simple inference workload.

### Phase 2 - real HA control plane

Move from one K3s server to three independent server nodes with embedded etcd and a stable API endpoint.

```text
server-01 ---+
server-02 ---+--> API VIP/LB
server-03 ---+

GPU workers join through the stable registration endpoint.
```

Do not call three VMs/containers on one physical machine true infrastructure HA.

### Phase 3 - split CPU and GPU pools

```text
CPU server/control-plane pool
CPU general worker pool
GPU worker pool(s)
```

Use labels/taints to keep ordinary services away from expensive GPU capacity.

Example conceptual labels:

```text
node-role.kubernetes.io/control-plane
workload.platform/general
accelerator.nvidia.com/class=<gpu-class>
```

### Phase 4 - AI platform services

Add only what the workloads require:

```text
GPU Operator
DCGM metrics
object/artifact storage integration
Kueue
MLflow
KServe and/or KubeRay
Kubeflow components if needed
```

Manage those through the same Terragrunt/Helm-provider or Argo CD/GitOps philosophy already established in this repository.

### Phase 5 - production controls

Add:

- HA API endpoint;
- etcd backup/restore testing;
- durable model/data storage;
- secrets management;
- network policy;
- GPU quotas/queues;
- platform SLOs;
- capacity/cost monitoring;
- disaster recovery;
- upgrade matrix for OS + kernel + Kubernetes + GPU driver + GPU Operator + AI platform components.

That compatibility matrix is critical. GPU platforms fail when components are upgraded independently without checking driver/kernel/Kubernetes/operator compatibility.

---

## 16. Recommended Terragrunt responsibility boundaries

Do not collapse the entire AI factory into one Terraform state.

A maintainable structure would eventually look conceptually like:

```text
infrastructure/live/dev/us-east-1/
  vpc/
  control-plane-compute/
  gpu-compute/
  k3s/
  gpu-operator/
  storage-platform/
  observability/
  traefik/
  cert-manager/
  argocd/
  ai-platform/
```

The exact unit names can change, but the lifecycle boundaries matter.

For example, changing a KServe chart version should not replace GPU EC2 instances. Replacing a GPU worker should not recreate the VPC. Upgrading K3s should not implicitly destroy model storage.

### Recommended ownership

| Layer | Preferred owner |
|---|---|
| VPC/subnets/IAM/security groups | Terragrunt/Terraform |
| EC2 CPU/GPU nodes | Terragrunt/Terraform |
| K3s/RKE2 bootstrap | immutable/user-data/image pipeline or explicit cluster lifecycle automation |
| NVIDIA operators | Kubernetes package lifecycle via Terragrunt Helm provider or Argo CD |
| AI platform controllers | Argo CD / Helm / Kubernetes operators |
| AI applications/models | GitOps / deployment pipelines |
| datasets/model artifacts | external durable data platform/object storage |

---

## 17. Benefits of building an AI factory on Kubernetes

### Portability

The workload API is less tied to one VM layout. The same application model can move between self-hosted and cloud clusters more easily than a bespoke collection of systemd services.

### Resource efficiency

CPU, RAM and GPU workloads can share a controlled resource pool. Queues and quotas improve utilization of expensive accelerators.

### Repeatability

Operators, Helm and GitOps create a reproducible platform rather than a collection of hand-configured servers.

### Multi-tenancy

Namespaces, RBAC, quotas and policy provide a foundation for multiple development teams.

### Elasticity

Workers and workloads can scale independently when the underlying infrastructure supports it.

### Ecosystem

Most modern AI infrastructure vendors provide Kubernetes operators/charts or Kubernetes deployment paths.

### Standard operations

Health probes, rollout patterns, service discovery, secret integration, audit and observability can use cloud-native patterns already familiar to SRE teams.

---

## 18. Costs and disadvantages

### Complexity moves rather than disappears

Kubernetes solves orchestration but introduces a control plane, operators, CRDs, cluster upgrades, policy, networking and storage lifecycle.

### GPU debugging crosses many layers

A failed GPU workload can involve:

```text
hardware
-> firmware
-> Linux kernel
-> NVIDIA driver
-> container toolkit
-> containerd
-> GPU Operator/device plugin/DRA driver
-> kubelet
-> scheduler
-> pod
-> CUDA/framework
-> model
```

### Idle accelerators are expensive

The biggest financial mistake in an AI factory is often poor GPU utilization, not Kubernetes overhead.

### Distributed training is infrastructure intensive

A cluster that works for one-GPU inference may perform badly for multi-node training because networking and storage were not designed for collective communication and checkpoint traffic.

### Compatibility management is mandatory

Kernel, driver, CUDA, container runtime, Kubernetes and operators have support matrices. Pinning and testing versions is a core platform responsibility.

### Kubernetes is unnecessary for some very small deployments

If the requirement is only one workstation running one local model server, Docker/Podman/systemd can be simpler. Adopt Kubernetes when orchestration, multi-tenancy, lifecycle, scaling or platform standardization justify it.

---

## 19. Decision table

| Requirement | Recommendation |
|---|---|
| One developer workstation, one model | Docker/Podman may be enough |
| One/few self-hosted GPU machines, Kubernetes desired | K3s is a strong choice |
| Edge inference sites | K3s is a strong choice |
| Small/medium HA private AI platform | K3s with three servers + dedicated GPU workers |
| Enterprise security/support focus | Evaluate RKE2/OpenShift |
| Very large multi-node training | prioritize validated networking/storage/scheduler design; distribution is secondary |
| NVIDIA GPU Operator required | choose a combination listed in current NVIDIA platform support matrix |
| Many teams sharing GPUs | Kubernetes + Kueue/other GPU-aware scheduling/quotas |
| Production generative inference | Kubernetes + KServe/Ray/custom serving layer depending model/runtime |
| Full ML platform | consider Kubeflow modules + MLflow + serving/scheduling components |

---

## 20. Recommendation for this repository

For this repository, I would **keep K3s as the default Kubernetes distribution** while treating AI Factory support as a new profile rather than changing the existing general-purpose cluster into a GPU machine.

Recommended direction:

```text
Current general profile
-----------------------
Amazon Linux 2023
CPU EC2
K3s
Traefik
cert-manager
Argo CD

AI factory profile
------------------
3 x CPU K3s servers for HA (when production HA is needed)
+
N x GPU K3s agents on an NVIDIA-validated OS/platform combination
+
NVIDIA GPU Operator
+
DCGM observability
+
Kueue when GPU contention exists
+
KServe / KubeRay / MLflow / selected Kubeflow modules as workload needs dictate
+
Durable object/high-throughput storage
+
Argo CD GitOps
```

I would **not** start by installing every AI project. Start with a single real workload and add platform capabilities only when that workload demonstrates a requirement.

For example, an inference-first roadmap could be:

```text
GPU worker
  -> GPU Operator
  -> GPU validation
  -> DCGM monitoring
  -> model runtime/KServe
  -> ingress + TLS
  -> autoscaling
  -> Argo CD
  -> model/artifact storage
  -> quotas/queueing when more teams arrive
```

A training-first roadmap would prioritize storage throughput, network topology and batch scheduling much earlier.

---

## 21. Source links and further reading

### AI Factory / NVIDIA reference architecture

- Enterprise AI Factory Overview  
  <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/ai-factory-overview.html>
- Enterprise AI Factory Ecosystem Architecture  
  <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/ecosystem-architecture.html>
- Enterprise AI Factory Deployment Strategies  
  <https://docs.nvidia.com/ai-enterprise/planning-resource/ai-factory-white-paper/latest/deployment-strategies.html>
- NVIDIA AI Enterprise Software Reference Architecture - introduction  
  <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/introduction.html>
- NVIDIA AI Enterprise software stack  
  <https://docs.nvidia.com/ai-enterprise/reference-architecture/latest/software-stack.html>
- NVIDIA HGX AI Factory reference architecture overview  
  <https://docs.nvidia.com/enterprise-reference-architectures/hgx-ai-factory-h100-h200-b200/latest/overview.html>

### Kubernetes accelerator infrastructure

- NVIDIA GPU Operator platform support  
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html>
- NVIDIA GPU Operator  
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/>
- NVIDIA GPU Operator installation  
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html>
- NVIDIA GPU Operator MIG  
  <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html>
- NVIDIA Network Operator  
  <https://docs.nvidia.com/networking/display/kubernetes2612/getting-started-with-kubernetes.html>
- Kubernetes Dynamic Resource Allocation  
  <https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/>
- Kubernetes 1.37 DRA updates  
  <https://kubernetes.io/blog/2026/09/03/kubernetes-v1-37-dra-updates/>

### Cloud-native AI platform

- Kubeflow introduction  
  <https://www.kubeflow.org/docs/started/introduction/>
- Kubeflow installation/distributions  
  <https://www.kubeflow.org/docs/started/installing-kubeflow/>
- KServe administrator guide  
  <https://kserve.github.io/website/docs/admin-guide/overview>
- Ray on Kubernetes / KubeRay  
  <https://docs.ray.io/en/latest/cluster/kubernetes/index.html>
- Kueue overview  
  <https://kueue.sigs.k8s.io/docs/overview/>
- MLflow Kubernetes Helm deployment  
  <https://mlflow.org/docs/latest/self-hosting/kubernetes-helm>
- NVIDIA DCGM Exporter  
  <https://docs.nvidia.com/datacenter/dcgm/latest/installation/install-dcgm-exporter.html>

### Related repository research

- [Kubernetes platform comparison](../kubernetes-platform-comparison/README.md)
- [K3s vs kubeadm](../k3s-vs-kubeadm/README.md)
- [K3s architecture guidance](../k3s/README.md)
- [Terragrunt-only workflow](../terragrunt-workflow/README.md)

---

## Final takeaway

An AI factory is a **repeatable AI production system**, not a GPU server and not a Kubernetes distribution.

Kubernetes is an excellent control plane for that system because it standardizes how compute, accelerators, storage, networking, operators and AI workloads are managed. K3s can provide that Kubernetes layer and is currently present in NVIDIA GPU Operator's support matrix on specific validated Ubuntu/Kubernetes combinations.

For this repository, the best path is to preserve the existing Terragrunt infrastructure boundaries, evolve from a single CPU K3s node toward separate HA server and GPU worker pools, use a validated GPU operating-system/Kubernetes combination, and then add AI services such as GPU Operator, Kueue, KServe, KubeRay, MLflow or Kubeflow only where a real workload requires them.
