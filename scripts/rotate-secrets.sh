#!/usr/bin/env bash

set -euo pipefail

ENVIRONMENT="${1:-dev}"
KEY_VAULT_NAME="${2:-}"
AKS_CLUSTER="${3:-aks-zt-${ENVIRONMENT}}"
RESOURCE_GROUP="rg-zt-${ENVIRONMENT}"

if [ -z "$KEY_VAULT_NAME" ]; then
  echo "Usage: $0 <environment> <keyvault-name> [aks-cluster-name]"
  exit 1
fi

echo "Secret Rotation - $ENVIRONMENT"

NEW_EXPIRY=$(date -u -d "+30 days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+30d +"%Y-%m-%dT%H:%M:%SZ")
az keyvault secret set-attributes \
  --vault-name "$KEY_VAULT_NAME" \
  --name "db-connection-string" \
  --expires "$NEW_EXPIRY" \
  --output none

echo "Waiting for CSI driver sync..."
sleep 120

echo "Restarting deployments..."
az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_CLUSTER" --overwrite-existing
kubectl rollout restart deployment/sample-api -n workloads
kubectl rollout status deployment/sample-api -n workloads --timeout=120s

echo "Secret rotation complete"
