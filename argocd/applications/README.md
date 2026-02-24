# ArgoCD Applications

This directory contains ArgoCD Application manifests for GitOps deployment.

## Quick Start

```bash
# 1. Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Sync Terraform outputs
.\scripts\sync-terraform-outputs.ps1 -Environment dev

# 3. Deploy ArgoCD applications
kubectl apply -f argocd/applications/

# 4. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
```

## Files

- `dev-app.yaml` - Development environment application
- `staging-app.yaml` - Staging environment application  
- `prod-app.yaml` - Production environment application
- `README.md` - Complete installation and usage guide

## How It Works

1. **ArgoCD watches** `kubernetes/overlays/{env}` in Git
2. **On changes**, ArgoCD automatically applies Kustomize overlays
3. **Terraform values** come from ConfigMap (`terraform-outputs-{env}`)
4. **No manual scripts needed** - everything is automated via Git

See [README.md](README.md) for detailed setup instructions.
