# Kubernetes platform Helm deployments

These charts are version-pinned and installed after K3s is reachable.

## Deployment order

1. `traefik` - ingress controller and ports 80/443
2. `cert-manager` - certificate lifecycle and ACME support
3. `argocd` - GitOps controller/UI

From the repository root:

```bash
make kubeconfig ENV=dev REGION=us-east-1
export KUBECONFIG=~/.kube/k3s-dev-us-east-1.yaml

make platform-install
make platform-test
```

The root-level interface avoids environment-specific `cd ../../..` paths in operator runbooks and CI.

## Verify

```bash
helm -n traefik list
helm -n cert-manager list
helm -n argocd list
kubectl get ingressclass
kubectl -n traefik get pods,svc
kubectl -n cert-manager get pods
kubectl -n argocd get pods
```

Use the component READMEs for chart-level inspection, manual Helm commands, examples and troubleshooting.
