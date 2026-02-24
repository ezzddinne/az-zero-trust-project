# Resource Quotas & Limit Ranges

## Overview

This directory contains **ResourceQuotas** and **LimitRanges** that protect Kubernetes system components from resource starvation when all workloads share the system node pool.

## Problem Context

With a single system node pool (2 nodes × 2 vCPU × 8 GB RAM):
- **Total Cluster Capacity**: 4 vCPU, 16 GB RAM
- **System Overhead** (kubelet, OS, kube-proxy): ~1 vCPU, ~4 GB RAM
- **Available for pods**: ~3 vCPU, ~12 GB RAM

Without resource limits, application pods or monitoring tools could consume all available resources, starving critical Kubernetes components (API server, kubelet, etcd).

## Resource Allocation Strategy

### Workloads Namespace (Applications)
- **CPU Requests**: 1.5 vCPU max
- **Memory Requests**: 4 GB max
- **CPU Limits**: 2 vCPU max
- **Memory Limits**: 6 GB max
- **Rationale**: Largest allocation for business workloads

### Monitoring Namespace (Prometheus, Grafana)
- **CPU Requests**: 1 vCPU max
- **Memory Requests**: 3 GB max
- **CPU Limits**: 1.5 vCPU max
- **Memory Limits**: 4 GB max
- **Rationale**: Ensure observability without overwhelming cluster

### Falco System Namespace (Runtime Security)
- **CPU Requests**: 0.5 vCPU max
- **Memory Requests**: 1 GB max
- **CPU Limits**: 1 vCPU max
- **Memory Limits**: 2 GB max
- **Rationale**: Lightweight security monitoring

### Ingress Namespace (Traffic Controllers)
- **CPU Requests**: 0.5 vCPU max
- **Memory Requests**: 1 GB max
- **CPU Limits**: 1 vCPU max
- **Memory Limits**: 2 GB max
- **Rationale**: Ingress controllers are typically efficient

## Default Container Limits

If a pod doesn't specify resource requests/limits, **LimitRanges** apply defaults:

| Namespace | Default CPU Request | Default Memory Request | Max CPU | Max Memory |
|-----------|---------------------|------------------------|---------|------------|
| workloads | 100m | 256Mi | 1000m | 2Gi |
| monitoring | 100m | 256Mi | 500m | 1Gi |
| falco-system | 100m | 128Mi | 500m | 1Gi |
| ingress | 50m | 128Mi | 500m | 1Gi |

## Protection Mechanisms

### 1. ResourceQuota
Prevents a namespace from exceeding total resource allocation:
- Aggregates all pod requests/limits in a namespace
- Rejects new pods if quota exceeded

### 2. LimitRange
Enforces constraints on individual pods/containers:
- Sets default requests/limits for pods without resource specs
- Prevents single pods from being too large
- Ensures minimum resource guarantees

## How This Protects System Components

1. **CPU Guarantee**: Total quota requests (3.5 vCPU) < available capacity (~3 vCPU), leaving room for system
2. **Memory Guarantee**: Total quota requests (9 GB) < available capacity (~12 GB), leaving room for system
3. **Pod Density**: Max 55 pods across all namespaces prevents node overload
4. **Individual Limits**: No single pod can consume > 1.5 vCPU or 4 GB

## Applying Quotas

Quotas are automatically applied via Kustomize:

```bash
kubectl apply -k kubernetes/overlays/prod
```

## Verifying Quotas

```bash
# Check quota status for all namespaces
kubectl get resourcequota --all-namespaces

# Check quota details for specific namespace
kubectl describe resourcequota -n workloads

# Check limit ranges
kubectl get limitrange --all-namespaces
kubectl describe limitrange -n monitoring
```

## Monitoring Quota Usage

```bash
# See current vs max allocations
kubectl describe quota workloads-quota -n workloads

# Example output:
# Resource              Used   Hard
# --------              ----   ----
# requests.cpu          500m   1500m
# requests.memory       1Gi    4Gi
```

## Adjusting Quotas

If workloads need more resources:

1. **Option 1**: Increase vCPU quota and add workload/monitoring pools (recommended)
2. **Option 2**: Adjust quotas in [resource-quotas.yaml](resource-quotas.yaml) (may risk system stability)

⚠️ **Warning**: Increasing quotas without adding nodes can lead to:
- Node pressure (MemoryPressure, DiskPressure)
- Pod evictions
- Kubelet/API server instability

## Best Practices

1. **Always specify resource requests/limits** in pod manifests
2. **Monitor quota usage** regularly with `kubectl describe quota`
3. **Use pod disruption budgets** for critical workloads
4. **Test resource constraints** before production deployment
5. **Request vCPU quota increase** if quotas are consistently exceeded

## Related Documentation

- [Kubernetes Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes Limit Ranges](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
