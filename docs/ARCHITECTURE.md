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
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AZURE CLOUD (East US 2)                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │ RESOURCE GROUP: rg-zt-prod                                                                          │   │
│  │                                                                                                      │   │
│  │  ┌────────────────────────────────────────────────────────────────────────────────────────────────┐  │   │
│  │  │                         HUB-AND-SPOKE NETWORK BACKBONE                                        │  │   │
│  │  │                                                                                                │  │   │
│  │  │     ╔═══════════════════════════════════════════════════════════════════════════════════════╗  │   │
│  │  │     ║                                                                                          ║  │   │
│  │  │     ║    ┌─────────────────────────────────────────────────────────────────────────────┐    ║  │   │
│  │  │     ║    │                         HUB VNET (Transit)                                       │    ║  │   │
│  │  │     ║    │                          10.0.0.0/16                                            │    ║  │   │
│  │  │     ║    │                                                                                   │    ║  │   │
│  │  │     ║    │    ┌─────────────────┐      ┌─────────────────┐                                 │    ║  │   │
│  │  │     ║    │    │   Azure         │      │   Tailscale     │                                 │    ║  │   │
│  │  │     ║    │    │   Firewall      │      │   VM (Bastion)  │                                 │    ║  │   │
│  │  │     ║    │    │   fw-zt-prod    │      │  vm-tailscale   │                                 │    ║  │   │
│  │  │     ║    │    │  + Public IP    │      │  (Secure Dev    │                                 │    ║  │   │
│  │  │     ║    │    │  pip-fw-prod    │      │   Access)       │                                 │    ║  │   │
│  │  │     ║    │    └─────────────────┘      └─────────────────┘                                 │    ║  │   │
│  │  │     ║    └─────────────────────────────────────────────────────────────────────────────┘    ║  │   │
│  │  │     ║                              ▲           ▲                                               ║  │   │
│  │  │     ║                              │           │                                               ║  │   │
│  │  │     ║    ═════════════════════════╪═══════════╪═══════════════════════════════════════════════╣  │   │
│  │  │     ║                              │ VNet Peering (Hub as Transit) │                         ║  │   │
│  │  │     ║                              │           │                    │                         ║  │   │
│  │  │     ║                              ▼           │                    ▼                         ║  │   │
│  │  │     ║                   ┌────────────────────────┐  │  ┌────────────────────────┐            ║  │   │
│  │  │     ║                   │     AKS SPOKE          │  │  │     DATA SPOKE         │            ║  │   │
│  │  │     ║                   │   vnet-aks-prod        │  │  │  vnet-data-prod        │            ║  │   │
│  │  │     ║                   │     10.1.0.0/16        │  │  │    10.2.0.0/16         │            ║  │   │
│  │  │     ║                   │                        │  │  │                        │            ║  │   │
│  │  │     ║                   │  ┌──────────────────┐  │  │  │  ┌──────────────────┐  │            ║  │   │
│  │  │     ║                   │  │    AKS Cluster   │◄─┴──┴──┴─►│  │   Key Vault      │  │            ║  │   │
│  │  │     ║                   │  │   aks-zt-prod    │          │  │   kv-zt-prod      │  │            ║  │   │
│  │  │     ║                   │  │   (Private)      │          │  │  (Private EP)     │  │            ║  │   │
│  │  │     ║                   │  └──────────────────┘          │  └──────────────────┘  │            ║  │   │
│  │  │     ║                   │                               │                        │            ║  │   │
│  │  │     ║                   │  ┌──────────────────┐          │  ┌──────────────────┐  │            ║  │   │
│  │  │     ║                   │  │   Pods           │          │  │   ACR            │  │            ║  │   │
│  │  │     ║                   │  │   workloads      │          │  │   acrztprod      │  │            ║  │   │
│  │  │     ║                   │  │                  │          │  │  (Private EP)    │  │            ║  │   │
│  │  │     ║                   │  └──────────────────┘          │  └──────────────────┘  │            ║  │   │
│  │  │     ║                   │                               │                        │            ║  │   │
│  │  │     ║                   └────────────────────────┬───────┘                        └────────────┘            ║  │   │
│  │  │     ║                                            │ All traffic via Hub                                      ║  │   │
│  │  │     ╚════════════════════════════════════════════════════════════════════════════════════════════════════╝  │   │
│  │  └────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│  │                                                                                                              │
│  │  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐    │
│  │  │ IDENTITY & SECRETS                                                                                  │    │
│  │  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                           │    │
│  │  │  │ id-aks-prod      │    │ id-sample-api    │    │ kv-zt-prod       │                           │    │
│  │  │  │ (Cluster Identity)│    │ (Workload ID)    │    │ (Secrets Store)  │                           │    │
│  │  │  └──────────────────┘    └──────────────────┘    └──────────────────┘                           │    │
│  │  └────────────────────────────────────────────────────────────────────────────────────────────────────┘    │
│  │                                                                                                              │
│  │  ┌────────────────────────────────────────────────────────────────────────────────────────────────────┐    │
│  │  │ OBSERVABILITY                                                                                       │    │
│  │  │  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐                           │    │
│  │  │  │ Log Analytics    │    │    Prometheus    │    │     Falco       │                           │    │
│  │  │  │ law-zt-prod      │    │   + Grafana      │    │ (Runtime Sec)    │                           │    │
│  │  │  └──────────────────┘    └──────────────────┘    └──────────────────┘                           │    │
│  │  └────────────────────────────────────────────────────────────────────────────────────────────────────┘    │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
│                                                                                                                    │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  │ EXTERNAL CONNECTIONS                                                                                           │
│  │                                                                                                                │
│  │  ╔══════════════════════════════════════════════════════════════════════════════════════════════════════════╗  │
│  │  ║  VERIFIED TRAFFIC FLOWS                                                                                    ║  │
│  │  ║                                                                                                            ║  │
│  │  ║  Egress: Pod → AKS → Hub → Firewall → Internet (All traffic inspected)                                 ║  │
│  │  ║  Private: Pod → Hub → Data → Key Vault (Private Link, no public exposure)                               ║  │
│  │  ║  Management: Dev → Tailscale → Hub → AKS API (No public endpoint)                                       ║  │
│  │  ╚══════════════════════════════════════════════════════════════════════════════════════════════════════════╝  │
│  │                                                                                                                │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
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

Hub-and-spoke architecture with Hub as the transit network. All traffic between AKS and Data spokes must flow through the Hub:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                         ZERO TRUST NETWORK BACKBONE                                   │
│                         Hub-and-Spoke with Transit via Hub                           │
└────────────────────────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────────────┐
                    │              HUB VNET (Transit)                   │
                    │               10.0.0.0/16                        │
                    │                                                    │
                    │  ┌─────────────────────────────────────────────┐  │
                    │  │          Azure Firewall                     │  │
                    │  │    (fw-zt-prod + pip-fw-prod)              │  │
                    │  │    All egress must pass through here        │  │
                    │  └─────────────────────────────────────────────┘  │
                    │                                                    │
                    │  ┌─────────────────────────────────────────────┐  │
                    │  │    Tailscale VM (vm-tailscale-prod)        │  │
                    │  │    Secure management gateway                │  │
                    │  └─────────────────────────────────────────────┘  │
                    └──────────────────────┬──────────────────────────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
                    ▼                      │                      ▼
         ┌────────────────────┐            │          ┌────────────────────┐
         │   AKS SPOKE       │            │          │   DATA SPOKE       │
         │  vnet-aks-prod    │            │          │  vnet-data-prod    │
         │   10.1.0.0/16     │            │          │   10.2.0.0/16      │
         │                    │            │          │                    │
         │ ┌──────────────┐  │            │          │ ┌──────────────┐  │
         │ │ AKS Cluster  │  │            │          │ │Key Vault     │  │
         │ │ aks-zt-prod  │  │            │          │ │kv-zt-prod    │  │
         │ │ (Private)    │  │            │          │ │(Private EP)  │  │
         │ └──────────────┘  │            │          │ └──────────────┘  │
         │                    │            │          │                    │
         │ ┌──────────────┐  │            │          │ ┌──────────────┐  │
         │ │ Pods         │──┴────────────┴───────────│ │ ACR          │  │
         │ │ workloads    │  (via Hub transit)        │ │acrztprod     │  │
         │ └──────────────┘                           │ │(Private EP)  │  │
         │                                            │ └──────────────┘  │
         └────────────────────┐                      │                    │
                              │                      │ ┌──────────────┐  │
                              └──────────────────────┘ │ Storage      │  │
                                          (via Hub)    │ stztprod     │  │
                                                       │(Private EP)  │  │
                                                       └──────────────┘  │
```

#### Peering Configuration (Hub as Transit Router)

| Peering Name | From VNet | To VNet | Allow Gateway Transit | Allow Forwarded Traffic |
|-------------|-----------|---------|----------------------|------------------------|
| hub-to-aks | vnet-hub-prod | vnet-aks-prod | **Yes** | Yes |
| aks-to-hub | vnet-aks-prod | vnet-hub-prod | No | Yes |
| hub-to-data | vnet-hub-prod | vnet-data-prod | **Yes** | Yes |
| data-to-hub | vnet-data-prod | vnet-hub-prod | No | Yes |

**Note:** There is NO direct peering between AKS Spoke and Data Spoke. All traffic must flow through the Hub for inspection and control.

### Network Security Groups (NSG)

NSGs applied at subnet level enforce Zero Trust - default deny all, explicit allow:

| NSG | Subnet | Purpose |
|-----|--------|---------|
| nsg-aks-system-prod | snet-aks-system | System node pool |
| nsg-aks-workload-prod | snet-aks-workload | Workload node pool |
| nsg-tailscale-prod | snet-tailscale | Tailscale gateway |
| nsg-pe-prod | snet-pe | Private Endpoints |

#### NSG Security Rules

```hcl
# AKS Workload Subnet NSG - Zero Trust: Default Deny All
resource "azurerm_network_security_group" "aks_workload" {
  name = "nsg-aks-workload-prod"

  # OUTBOUND: Pod → Internet (via Hub/Firewall)
  security_rule {
    name                       = "Allow-Egress-To-Hub"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                    = "Tcp"
    source_address_prefix      = "10.1.1.0/24"  # Workload subnet
    destination_address_prefix = "10.0.0.0/16"  # Hub VNet (for Firewall inspection)
  }

  # OUTBOUND: Pod → Key Vault (Private Endpoint via Hub)
  security_rule {
    name                       = "Allow-Egress-To-KeyVault"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                    = "Tcp"
    source_address_prefix      = "10.1.1.0/24"  # Workload subnet
    destination_address_prefix = "10.2.1.0/24"  # PE Subnet
  }

  # INBOUND: Allow health checks from Hub
  security_rule {
    name                       = "Allow-Ingress-From-Hub"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                    = "Tcp"
    source_address_prefix      = "10.0.0.0/16"  # Hub VNet
    destination_address_prefix = "10.1.1.0/24"  # Workload subnet
    destination_port_range     = "443"
  }

  # DEFAULT DENY ALL
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                    = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
```

#### Verified Traffic Flows

| Flow | Source → Destination | Path | Security |
|------|---------------------|------|----------|
| **Egress (Pod→Internet)** | Pod → AKS → Hub → Firewall → Internet | AKS (10.1.1.x) → Hub (10.0.x) → Firewall → Public IP | All traffic inspected |
| **Pod→Key Vault** | Pod → Key Vault (Private Endpoint) | AKS (10.1.1.x) → Hub (10.0.x) → Data (10.2.1.x) → KV | Private Link, no public exposure |
| **Pod→ACR** | Pod → ACR (Private Endpoint) | AKS (10.1.1.x) → Hub (10.0.x) → Data (10.2.1.x) → ACR | Private Link |
| **Dev→AKS API** | Developer → AKS API Server | Tailscale → Hub → AKS Private Endpoint | No public AKS endpoint |
| **GitHub→Terraform** | GitHub Actions → Azure | OIDC → Hub → Private Endpoint | Federated identity |

| Source | Destination | Path |
|--------|------------|------|
| AKS Pod → Key Vault | Private Endpoint | AKS → Hub (peering) → Data (peering) → Key Vault |
| AKS Pod → Internet | via Firewall | AKS → Hub → Firewall → Internet |
| AKS Pod → ACR | Private Endpoint | AKS → Hub (peering) → Data (peering) → ACR |
| Developer → AKS API | via Tailscale | Tailscale VM → Hub → AKS API Server |
| GitHub Actions → Terraform | via OIDC | Internet → Hub → Private Endpoint |

#### DNS Resolution

- **Private DNS Zones**: Azure Private Link resources use private DNS zones
- **VNet Integration**: DNS zones linked to all three VNets
- **Resolution**: Components resolve to private IPs, not public endpoints

| Service | Private DNS Zone | Record |
|---------|-----------------|--------|
| Key Vault | `privatelink.vaultcore.azure.net` | `kv-zt-prod.vaultcore.azure.net` |
| ACR | `privatelink.azurecr.io` | `acrztprod.azurecr.io` |
| Storage | `privatelink.blob.core.windows.net` | `stztprod.blob.core.windows.net` |

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
