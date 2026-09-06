# Kubernetes platform Helm deployments

These charts are intentionally version-pinned. Deploy them after the K3s infrastructure is reachable.

## Deployment order

1. `traefik` - ingress controller and ports 80/443
2. `cert-manager` - certificate lifecycle and ACME support
3. `argocd` - GitOps controller/UI

```bash
export KUBECONFIG=~/.kube/k3s-dev.yaml
kubectl get nodes -o wide

cd kubernetes/helm/traefik
./install.sh
./test.sh

cd ../cert-manager
./install.sh
./test.sh

cd ../argocd
./install.sh
```

## Verify the platform

```bash
helm -n traefik list
helm -n cert-manager list
helm -n argocd list
kubectl get ingressclass
kubectl -n traefik get pods,svc
kubectl -n cert-manager get pods
kubectl -n argocd get pods
```

See each component README and the repository-level `VERSIONS.md` for pinned versions and upgrade procedures.
