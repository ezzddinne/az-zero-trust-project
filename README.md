# Azure Zero Trust Architecture

Enterprise-grade Zero Trust security implementation on Microsoft Azure featuring private AKS clusters, hub-spoke networking, GitOps with ArgoCD, and comprehensive security controls.

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-7B42BC?style=flat&logo=terraform)](https://www.terraform.io)
[![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoftazure)](https://azure.microsoft.com)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes)](https://kubernetes.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Overview

This project demonstrates a production-grade Zero Trust architecture designed for organizations migrating containerized workloads to Azure Kubernetes Service (AKS). The implementation follows Microsoft's Zero Trust principles: verify explicitly, least privilege, and assume breach.

## Key Features

- **Private AKS Cluster** - No public endpoints, private control plane with approved private links
- **Hub-Spoke Networking** - Segmented architecture with Azure Firewall for egress control
- **Tailscale VPN** - Secure remote access to private cluster without public exposure
- **Identity-Based Access** - Entra ID integration with RBAC and workload identities
- **Secrets Management** - Azure Key Vault with CSI Secrets Store Provider
- **GitOps** - ArgoCD for declarative Kubernetes deployments
- **Observability** - Prometheus, Grafana, and Falco runtime security
- **CI/CD** - GitHub Actions with OIDC, container scanning, and IaC validation

## Architecture

```
                                    +------------------+
                                    |  Azure Entra ID  |
                                    | MFA + RBAC       |
                                    +--------+---------+
                                             |
        +------------------------------------+------------------------------------+
        |                                    |                                    |
        v                                    v                                    v
+-------------+                    +------------------+                    +-------------+
| Hub VNet   |                    | AKS Spoke VNet   |                    | Data VNet   |
| 10.20.0.0/16|<----------------->| 10.21.0.0/16    |<----------------->| 10.22.0.0/16|
+-------------+                    +------------------+                    +-------------+
| Azure FW   |                    | AKS Private     |                    | Private     |
| Tailscale  |                    | Cluster         |                    | Endpoints   |
| VPN        |                    | Node Pools      |                    | Key Vault   |
+-------------+                    +------------------+                    +-------------+
                                           |
                                    +------+------+
                                    | Monitoring  |
                                    | Prometheus  |
                                    | Grafana     |
                                    | Falco       |
                                    +-------------+

+------------------------------------------------------------------------+
|                     GitHub Actions CI/CD                                |
|  OIDC Auth + Trivy + Checkov + Terraform Plan/Apply                    |
+------------------------------------------------------------------------+
```

## Technologies

| Category | Technology |
|----------|------------|
| Infrastructure as Code | Terraform |
| Container Orchestration | AKS (Kubernetes 1.32) |
| GitOps | ArgoCD |
| Container Registry | Azure Container Registry |
| Secrets Management | Azure Key Vault + CSI Provider |
| Identity | Entra ID + Workload Identity |
| Network Security | Azure Firewall + NSG + Calico + Tailscale |
| Observability | Prometheus + Grafana + Falco |
| CI/CD | GitHub Actions |

## Project Structure

```
.
├── terraform/
│   ├── modules/
│   │   ├── aks/              # AKS cluster configuration
│   │   ├── networking/       # Hub-spoke VNet, firewall, peering
│   │   ├── tailscale-vm/    # Tailscale VPN for remote access
│   │   ├── identity/        # Entra ID, RBAC, managed identities
│   │   ├── keyvault/        # Key Vault with private endpoint
│   │   ├── acr/             # Container Registry
│   │   ├── monitoring/       # Log Analytics
│   │   └── storage/         # Storage Account
│   └── environments/
│       ├── dev/              # Development environment
│       ├── staging/          # Staging environment
│       └── prod/             # Production environment
├── kubernetes/
│   ├── base/
│   │   ├── sample-app/       # Sample secure application
│   │   ├── namespaces/       # Namespace definitions
│   │   ├── rbac/           # Kubernetes RBAC
│   │   └── secrets-store/  # CSI Provider configuration
│   ├── overlays/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── monitoring/           # Prometheus, Grafana, Falco
├── argocd/
│   └── applications/        # ArgoCD Application manifests
├── .github/
│   └── workflows/           # CI/CD pipelines
├── scripts/
│   ├── bootstrap.sh         # Azure backend setup
│   ├── deploy-k8s.sh      # Kubernetes deployment
│   ├── sync-terraform-outputs.sh
│   ├── shutdown-infra.sh   # Cost optimization
│   ├── startup-infra.sh
│   └── rotate-secrets.sh
└── docs/
    └── ARCHITECTURE.md      # Detailed architecture documentation
```

## Getting Started

### Prerequisites

- Azure subscription with Owner access
- Terraform >= 1.6.0
- Azure CLI >= 2.55.0
- kubectl >= 1.28

### Quick Start

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

4. **Deploy Kubernetes Resources**
```bash
./scripts/deploy-k8s.sh dev
```

5. **Setup ArgoCD (Optional)**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd/applications/
```

## Security Features

### Network Security
- Private endpoints for all Azure services
- Azure Firewall for egress filtering
- NSGs with default deny rules
- Calico network policies for pod-to-pod communication
- Tailscale VPN for secure remote access (no bastion exposure)
- No public IPs on workloads

### Identity Security
- Entra ID integration with conditional access
- MFA enforcement
- Workload identity for AKS pods
- Managed identities (no service principal secrets)
- RBAC with least privilege

### Data Security
- Key Vault for all secrets
- Encryption at rest
- CSI Secrets Store Provider
- No secrets in environment variables or Kubernetes manifests

### Runtime Security
- Falco runtime threat detection
- Pod security standards
- Resource limits and quotas

## Environments

| Environment | Purpose | Estimated Monthly Cost |
|-------------|---------|----------------------|
| dev | Development | $85-120 |
| staging | Testing | $150-200 |
| prod | Production | $300-450 |

## Documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation including:

- Network architecture and subnet design
- Identity and access management
- Kubernetes security controls
- Observability stack
- CI/CD pipeline details

## License

MIT License - See [LICENSE](LICENSE) for details.
