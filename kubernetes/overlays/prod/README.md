# Production Overlay

Production-specific Kustomize overlay with high availability configuration.

## Features

- **5 replicas** for high availability
- **Error-level logging** for production
- Production ACR image registry
- Production Key Vault integration

## Usage

```bash
# Preview production manifests
kubectl kustomize kubernetes/overlays/prod

# Apply to production cluster
kubectl apply -k kubernetes/overlays/prod
```

## Prerequisites

Before deploying, update the following placeholders in patch files:
- `REPLACE_WITH_ACR_LOGIN_SERVER` - Your production ACR
- `REPLACE_WITH_KEY_VAULT_NAME` - Your production Key Vault
- `REPLACE_WITH_WORKLOAD_IDENTITY_CLIENT_ID` - Workload Identity client ID
- `REPLACE_WITH_AZURE_TENANT_ID` - Azure AD tenant ID

Or use the deployment script:
```powershell
.\scripts\deploy-k8s.ps1 -Environment prod
```
