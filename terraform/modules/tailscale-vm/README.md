# Tailscale VM Module

This module deploys a lightweight Ubuntu VM with Tailscale for secure, zero-trust remote access to private Azure resources, including the private AKS cluster.

## Overview

**Purpose**: Replace expensive Azure Bastion (~$140/month) with a more cost-effective Tailscale-based access solution (~$70/month) while maintaining or improving security posture.

**Security Model**: Zero-trust mesh network with device authentication, encrypted connections, and subnet routing to access entire Azure VNet.

## Features

- ✅ **Cost-effective**: ~$70/month (Standard_D2s_v3)
- ✅ **Zero-trust**: Device authentication via Tailscale
- ✅ **Encrypted mesh**: End-to-end encrypted connections
- ✅ **Subnet routing**: Access entire Azure VNet from any device
- ✅ **Pre-configured**: Cloud-init installs Azure CLI, kubectl, Helm, ArgoCD
- ✅ **SSH options**: Tailscale SSH or traditional SSH with Key Vault-stored keys
- ✅ **Managed identity**: System-assigned identity for Azure resource access

## Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────┐
│  Your Device    │────────▶│  Tailscale VM    │────────▶│ Private AKS │
│  (Tailscale)    │  Mesh   │  (Hub VNet)      │  VNet   │   Cluster   │
└─────────────────┘         └──────────────────┘         └─────────────┘
      100.x.x.x                  10.20.3.x                   10.21.x.x
                                                                  │
                                                                  ├─ ACR
                                                                  ├─ Key Vault
                                                                  └─ Storage
```

## Resources Created

1. **Virtual Machine**: Standard_D2s_v3 Ubuntu 22.04 LTS (2 vCPU, 8 GB RAM)
2. **Network Interface**: With dynamic private IP
3. **Network Security Group**: Tailscale traffic + VNet access
4. **Managed Identity**: System-assigned for Key Vault access
5. **SSH Key Pair** (optional): Auto-generated and stored in Key Vault

## Usage

### Basic Configuration

```hcl
module "tailscale_vm" {
  source = "../../modules/tailscale-vm"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  environment         = "prod"
  tags                = local.tags
  subnet_id           = module.networking.mgmt_subnet_id
  key_vault_id        = module.keyvault.key_vault_id
}
```

### With Custom SSH Key

```hcl
module "tailscale_vm" {
  source = "../../modules/tailscale-vm"

  # ... other required params ...
  
  ssh_public_key = file("~/.ssh/id_rsa.pub")
}
```

### With Tailscale Auth Key (Auto-connect)

```hcl
module "tailscale_vm" {
  source = "../../modules/tailscale-vm"

  # ... other required params ...
  
  tailscale_authkey = var.tailscale_auth_key  # From Terraform variables
}
```

## Post-Deployment Setup

### 1. Get Tailscale Auth Key

```bash
# Go to: https://login.tailscale.com/admin/settings/keys
# Generate a reusable auth key
```

### 2. Configure VM with Tailscale

```bash
# Run via Azure CLI
az vm run-command invoke \
  --resource-group rg-zt-prod \
  --name vm-tailscale-prod \
  --command-id RunShellScript \
  --scripts "sudo tailscale up --authkey='YOUR_KEY' --advertise-routes=10.20.0.0/16,10.21.0.0/16,10.22.0.0/16 --accept-routes --ssh"
```

### 3. Approve Subnet Routes

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/machines)
2. Find `vm-tailscale-prod`
3. Edit route settings → Approve subnets

### 4. Connect from Your Device

```bash
# Install Tailscale on your device
# macOS
brew install tailscale

# Connect to Tailscale network
tailscale up

# SSH to the VM
ssh vm-tailscale-prod

# Or get kubectl access directly from your machine
az aks get-credentials --resource-group rg-zt-prod --name aks-zt-prod
kubectl get nodes  # Works through Tailscale routing!
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `resource_group_name` | Resource group name | string | - | yes |
| `location` | Azure region | string | - | yes |
| `environment` | Environment (dev/staging/prod) | string | - | yes |
| `subnet_id` | Management subnet ID | string | - | yes |
| `vm_size` | VM size | string | `"Standard_D2s_v3"` | no |
| `admin_username` | Admin username | string | `"azureuser"` | no |
| `ssh_public_key` | SSH public key (empty = auto-generate) | string | `""` | no |
| `tailscale_authkey` | Tailscale auth key for auto-connect | string | `""` | no |
| `key_vault_id` | Key Vault ID for SSH key storage | string | `null` | no |
| `tags` | Resource tags | map(string) | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | VM resource ID |
| `vm_name` | VM name |
| `private_ip_address` | Private IP in Azure VNet |
| `vm_identity_principal_id` | Managed identity principal ID |
| `ssh_private_key_secret_name` | Key Vault secret name (if generated) |

## Installed Tools (Cloud-Init)

The VM comes pre-configured with:
- Azure CLI
- kubectl (latest stable)
- Helm 3
- ArgoCD CLI
- Tailscale
- jq, git, curl, wget

## Security Considerations

✅ **What's secure:**
- No public IP address on VM
- Zero-trust mesh network authentication
- End-to-end encrypted connections
- SSH key stored in Key Vault
- Managed identity for Azure access
- NSG restricts traffic to Tailscale + VNet only

⚠️ **Important notes:**
- Subnet routing requires approval in Tailscale admin console
- Keep Tailscale auth keys secure (use as Terraform secrets)
- Rotate SSH keys regularly
- Monitor Tailscale connection logs

## Cost Optimization

| Resource | Monthly Cost |
|----------|-------------|
| Standard_D2s_v3 VM (730 hrs) | ~$70.08 |
| Premium SSD 30GB | ~$0.60 |
| **Total** | **~$70.68/month** |

**Comparison:**
- Azure Bastion: ~$140/month
- VPN Gateway: ~$25-100/month
- Tailscale VM: ~$70/month

**Savings**: ~$70/month vs Azure Bastion

## Troubleshooting

### VM won't connect to Tailscale

```bash
# Check Tailscale status
az vm run-command invoke \
  --resource-group rg-zt-prod \
  --name vm-tailscale-prod \
  --command-id RunShellScript \
  --scripts "tailscale status"

# Restart Tailscale
az vm run-command invoke \
  --resource-group rg-zt-prod \
  --name vm-tailscale-prod \
  --command-id RunShellScript \
  --scripts "sudo systemctl restart tailscaled && sudo tailscale up --authkey='YOUR_KEY' --advertise-routes=10.20.0.0/16,10.21.0.0/16,10.22.0.0/16"
```

### Can't access private AKS from local machine

```bash
# Verify subnet routes are approved
tailscale status

# Check Tailscale is routing subnets
ip route | grep 10.2

# Verify connectivity to AKS API
nc -zv <AKS_PRIVATE_IP> 443
```

### SSH key not found

```bash
# Retrieve from Key Vault
az keyvault secret show \
  --vault-name <KV_NAME> \
  --name tailscale-vm-ssh-private-key-prod \
  --query "value" -o tsv > ~/.ssh/tailscale-key
chmod 600 ~/.ssh/tailscale-key
```

## References

- [Tailscale Subnet Routers](https://tailscale.com/kb/1019/subnets/)
- [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh/)
- [Azure VM Sizes](https://docs.microsoft.com/azure/virtual-machines/sizes-b-series-burstable)
