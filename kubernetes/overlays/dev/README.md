# Dev Environment Overlay

## Quick Setup

After deploying infrastructure with Terraform:

```bash
# 1. Get Terraform outputs
cd terraform/environments/dev
ACR_LOGIN=$(terraform output -raw acr_login_server)
KV_NAME=$(terraform output -raw key_vault_name)
CLIENT_ID=$(terraform output -json workload_identity_client_ids | jq -r '.["sample-api"]')
TENANT_ID=$(az account show --query tenantId -o tsv)

# 2. Update patches with actual values
cd ../../../kubernetes/overlays/dev

# Update ACR image
sed -i "s|REPLACE_WITH_ACR_LOGIN_SERVER|${ACR_LOGIN}|g" patches/sample-app-image.yaml

# Update Key Vault details
sed -i "s|REPLACE_WITH_KEY_VAULT_NAME|${KV_NAME}|g" patches/secret-provider-class.yaml
sed -i "s|REPLACE_WITH_AZURE_TENANT_ID|${TENANT_ID}|g" patches/secret-provider-class.yaml
sed -i "s|REPLACE_WITH_WORKLOAD_IDENTITY_CLIENT_ID|${CLIENT_ID}|g" patches/secret-provider-class.yaml
sed -i "s|REPLACE_WITH_WORKLOAD_IDENTITY_CLIENT_ID|${CLIENT_ID}|g" patches/workload-identity.yaml

# 3. Preview what will be applied
kubectl kustomize . | less

# 4. Apply to cluster
kubectl apply -k .
```

## Verify Deployment

```bash
# Check pods
kubectl get pods -n workloads

# Check secrets mounted
kubectl exec -it deployment/sample-api -n workloads -- ls -la /mnt/secrets

# Check workload identity
kubectl describe sa sa-sample-api -n workloads
```
