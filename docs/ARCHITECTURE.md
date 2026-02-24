# Azure Zero Trust Architecture - Production Implementation

A production-grade Zero Trust security architecture on Microsoft Azure, implementing enterprise-level security controls for containerized workloads on AKS.

## Executive Summary

This project demonstrates a complete Zero Trust architecture designed for organizations migrating to Azure Kubernetes Service (AKS). The implementation follows Microsoft's Zero Trust principles—verify explicitly, least privilege, and assume breach—while maintaining operational efficiency through GitOps and infrastructure as code.

### Key Highlights

- **Private AKS Cluster** with no public endpoints
- **Hub-Spoke Networking** with Azure Firewall for egress control
- **Tailscale VPN** for secure remote access (replaces traditional bastion)
- **Workload Identity** for passwordless Azure resource access
- **GitOps with ArgoCD** for declarative deployments
- **Comprehensive Observability** with Prometheus, Grafana, and Falco

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AZURE CLOUD (East US 2)                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ RESOURCE GROUP: rg-zt-prod                                                                  │  │
│  │                                                                                             │  │
│  │  ┌──────────────────────────────────────────────────────────────────────────────────────┐    │  │
│  │  │ VIRTUAL NETWORKS                                                                          │    │  │
│  │  │                                                                                          │    │  │
│  │  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                  │    │  │
│  │  │  │   Hub VNet      │    │  AKS Spoke VNet  │    │  Data Spoke VNet│                  │    │  │
│  │  │  │   10.0.0.0/16   │◄──►│   10.1.0.0/16    │◄─►│   10.2.0.0/16    │                  │    │  │
│  │  │  │                  │    │                  │    │                  │                  │    │  │
│  │  │  │ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌──────────────┐ │                  │    │  │
│  │  │  │ │   Azure     │ │    │ │    AKS       │ │    │ │    Azure    │ │                  │    │  │
│  │  │  │ │  Firewall   │ │    │ │   Cluster    │ │    │ │  Private   │ │                  │    │  │
│  │  │  │ │ 10.20.1.4  │ │    │ │ 10.21.0.0/24│ │    │ │  Endpoints   │ │                  │    │  │
│  │  │  │ └─────────────┘ │    │ └──────────────┘ │    │ └──────────────┘ │                  │    │  │
│  │  │  └──────────────────┘    └──────────────────┘    └──────────────────┘                  │    │  │
│  │  └──────────────────────────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │  │
│  │  │   AKS      │  │ Tailscale   │  │    Key     │  │     ACR    │  │  Log       │     │  │
│  │  │  Cluster   │  │    VPN      │  │   Vault    │  │             │  │  Analytics │     │  │
│  │  │  v1.32     │  │  Ubuntu    │  │  Secrets   │  │  Private   │  │             │     │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │  │
│  │                                                                                             │  │
│  │  ┌──────────────────────────────────────────────────────────────────────────────────────┐    │  │
│  │  │ GITOPS & CI/CD                                                                           │    │  │
│  │  │                                                                                          │    │  │
│  │  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                  │    │  │
│  │  │  │     ArgoCD       │    │ GitHub Actions   │    │     OIDC        │                  │    │  │
│  │  │  │  Auto-Sync       │    │ Plan/Apply/Scan │    │  Federation     │                  │    │  │
│  │  │  └──────────────────┘    └──────────────────┘    └──────────────────┘                  │    │  │
│  │  └──────────────────────────────────────────────────────────────────────────────────────┘    │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ EXTERNAL CONNECTIONS                                                                         │  │
│  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                  │  │
│  │  │     GitHub       │    │  Developer       │    │    Internet     │                  │  │
│  │  │    Repository    │    │   (Tailscale)    │    │    Egress       │                  │  │
│  │  └──────────────────┘    └──────────────────┘    └──────────────────┘                  │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Category | Technology | Version |
|----------|------------|---------|
| Infrastructure as Code | Terraform | 1.6+ |
| Container Orchestration | AKS | 1.32 |
| GitOps | ArgoCD | Latest |
| Container Registry | Azure Container Registry | Premium |
| Secrets Management | Azure Key Vault | Standard |
| Identity | Entra ID + Workload Identity | - |
| Network Security | Azure Firewall + NSG + Calico | - |
| VPN | Tailscale | Latest |
| Observability | Prometheus + Grafana + Falco | - |
| CI/CD | GitHub Actions | - |

---

## Network Architecture

### Hub-Spoke Topology

The implementation uses a hub-spoke network topology for Zero Trust network segmentation:

| VNet | Address Space | Purpose |
|------|--------------|---------|
| vnet-hub-prod | 10.0.0.0/16 | Central hub (shared services) |
| vnet-aks-prod | 10.1.0.0/16 | AKS workload network |
| vnet-data-prod | 10.2.0.0/16 | Data services network |

### Subnet Design

#### Hub VNet (10.0.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| AzureFirewallSubnet | 10.0.1.0/26 | Azure Firewall |
| snet-mgmt | 10.0.2.0/24 | Management resources |

#### AKS Spoke VNet (10.1.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| snet-aks-system | 10.1.0.0/24 | System node pool |
| snet-aks-workload | 10.1.1.0/24 | Workload node pool |
| snet-aks-lb | 10.1.2.0/24 | Internal LoadBalancer |

#### Data Spoke VNet (10.2.0.0/16)

| Subnet | CIDR | Purpose |
|--------|------|---------|
| snet-pe | 10.2.1.0/24 | Private endpoints |

### VNet Peering

All VNets are peered to enable private communication:
- Hub ↔ AKS Spoke
- Hub ↔ Data Spoke
- AKS Spoke ↔ Data Spoke

---

## Kubernetes Architecture

### Cluster Configuration

| Setting | Value |
|---------|-------|
| Kubernetes Version | 1.32 |
| API Server | Private (no public endpoint) |
| Network Plugin | Azure CNI |
| Network Policy | Calico |
| Outbound Type | UserDefinedRouting |

### Node Pools

| Pool Name | VM Size | Nodes | Purpose |
|-----------|---------|-------|---------|
| system | Standard_D2s_v3 | 1-3 | Kubernetes system components |
| workload | Standard_D4s_v3 | 0-10 | Application workloads |
| monitoring | Standard_D2s_v3 | 0-2 | Observability stack |

### Pod Security

All deployments implement security best practices:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

---

## Security Implementation

### Zero Trust Principles

| Principle | Implementation |
|-----------|---------------|
| Verify Explicitly | Entra ID + Conditional Access + MFA |
| Least Privilege | RBAC, managed identities, JIT access |
| Assume Breach | Network segmentation, Falco monitoring |

### Network Security

- **Azure Firewall**: Centralized egress control with FQDN filtering
- **NSGs**: Default deny all inbound traffic
- **Calico Network Policies**: Pod-to-pod micro-segmentation
- **Private Endpoints**: All Azure services inaccessible from internet

### Identity Security

- **Entra ID Integration**: Azure AD authentication for cluster access
- **Workload Identity**: Passwordless access to Azure resources
- **Managed Identities**: No service principal credentials in code
- **RBAC**: Least privilege role assignments

### Data Security

- **Key Vault**: All secrets stored in Azure Key Vault
- **CSI Provider**: Secrets mounted directly into pods
- **Encryption**: At rest and in transit
- **No Secrets in Code**: Environment variables never contain secrets

---

## Tailscale VPN

Replaces traditional bastion host for secure remote access:

| Component | Configuration |
|-----------|---------------|
| VM | Ubuntu 22.04 LTS, Standard_B2s |
| Public IP | None (fully private) |
| Authentication | Ephemeral auth keys |
| Features | Subnet router enabled |

### Benefits Over Bastion

- No public IP exposure
- WireGuard encryption
- MFA through Tailscale
- Granular access control
- Audit logging of all connections

---

## GitOps Implementation

### ArgoCD

Declarative Kubernetes deployments with automatic synchronization:

- Monitors Git repository for changes
- Auto-syncs deployments every 3 minutes
- Health checks and automatic rollback
- Environment-specific configurations (dev/staging/prod)

### Application Structure

```
kubernetes/
├── base/                    # Base manifests
│   ├── sample-app/         # Sample application
│   ├── namespaces/         # Namespace definitions
│   └── secrets-store/     # CSI configuration
└── overlays/               # Environment overlays
    ├── dev/                # Development
    ├── staging/            # Staging
    └── prod/               # Production
```

---

## CI/CD Pipeline

### GitHub Actions Workflows

#### Terraform Plan (Pull Request)
- Security scanning with Checkov and tfsec
- Environment detection
- Terraform plan with PR comment

#### Terraform Apply (Push to Main)
- OIDC authentication (no stored secrets)
- Environment-specific deployments
- Drift detection

#### Container Build
- Docker build with multi-stage builds
- Trivy vulnerability scanning
- Cosign image signing
- Push to private ACR

### OIDC Authentication

Federated identity between GitHub and Azure:
- No long-lived credentials stored
- Short-lived tokens
- Automatic credential rotation

---

## Observability Stack

### Prometheus + Grafana

- Metrics collection via kube-prometheus-stack
- Custom dashboards for cluster and application metrics
- Alertmanager for notifications

### Falco

- Runtime security monitoring
- Kubernetes audit log analysis
- Custom security rules
- Alert notifications

### Log Analytics

- Centralized logging for all Azure resources
- 90-day retention
- Security audit trails

---

## Resource Inventory

### Azure Resources

| Resource | Type | Purpose |
|----------|------|---------|
| rg-zt-prod | Resource Group | Container for all resources |
| vnet-hub-prod | Virtual Network | Hub network |
| vnet-aks-prod | Virtual Network | AKS network |
| vnet-data-prod | Virtual Network | Data services network |
| fw-zt-prod | Azure Firewall | Egress filtering |
| aks-zt-prod | AKS Cluster | Kubernetes cluster |
| kv-zt-prod | Key Vault | Secrets management |
| acrztprod | Container Registry | Image storage |
| stztprod | Storage Account | Blob storage |
| la-zt-prod | Log Analytics | Logging |
| vm-tailscale-prod | Virtual Machine | VPN gateway |

### Kubernetes Resources

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| sample-api Deployment | workloads | Sample application |
| sample-api Service | workloads | Internal service |
| sa-sample-api | workloads | ServiceAccount |
| NetworkPolicy | workloads | Traffic rules |
| SecretProviderClass | workloads | Key Vault integration |

---

## Environments

| Environment | Purpose | Monthly Cost |
|-------------|---------|--------------|
| dev | Development | $85-120 |
| staging | Testing | $150-200 |
| prod | Production | $300-450 |

---

## Getting Started

### Prerequisites

- Azure subscription with Owner access
- Terraform >= 1.6.0
- Azure CLI >= 2.55.0
- kubectl >= 1.28

### Deployment Steps

1. **Bootstrap Azure Backend**
   ```bash
   ./scripts/bootstrap.sh
   ```

2. **Deploy Infrastructure**
   ```bash
   cd terraform/environments/dev
   terraform init -backend-config=backend.hcl
   terraform apply
   ```

3. **Configure kubectl**
   ```bash
   az aks get-credentials --resource-group rg-zt-dev --name aks-zt-dev
   ```

4. **Deploy Applications**
   ```bash
   ./scripts/deploy-k8s.sh dev
   ```

---

## Security Compliance

This architecture implements controls for:

- Network segmentation (Zero Trust)
- Identity and access management
- Data encryption
- Audit logging
- Incident response
- Vulnerability management

---

## License

MIT License - See [LICENSE](LICENSE) for details.
