#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${PROJECT_ROOT}/kubernetes/overlays/${ENVIRONMENT}"
TF_ENV_DIR="${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"

echo "Deploying Kubernetes resources - Environment: ${ENVIRONMENT}"

if [ ! -d "${OVERLAY_DIR}" ]; then
  echo "Error: Environment '${ENVIRONMENT}' not found"
  exit 1
fi

cd "${TF_ENV_DIR}"

ACR_LOGIN=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
CLIENT_ID=$(terraform output -json 2>/dev/null | grep -o '"workload_identity_client_ids"' > /dev/null 2>&1 && terraform output -json workload_identity_client_ids 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('sample-api', ''))" || echo "00000000-0000-0000-0000-000000000000")
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

if [ -z "$ACR_LOGIN" ] || [ -z "$KV_NAME" ] || [ -z "$TENANT_ID" ]; then
  echo "Error: Missing required Terraform outputs"
  exit 1
fi

echo "ACR: ${ACR_LOGIN}"
echo "Key Vault: ${KV_NAME}"

cd "${OVERLAY_DIR}"

find patches -type f -name "*.yaml" -exec sed -i.bak \
  -e "s|REPLACE_WITH_ACR_LOGIN_SERVER|${ACR_LOGIN}|g" \
  -e "s|REPLACE_WITH_KEY_VAULT_NAME|${KV_NAME}|g" \
  -e "s|REPLACE_WITH_AZURE_TENANT_ID|${TENANT_ID}|g" \
  -e "s|REPLACE_WITH_WORKLOAD_IDENTITY_CLIENT_ID|${CLIENT_ID}|g" \
  {} \;

find patches -name "*.bak" -delete

kubectl apply -k .

echo "Deployment complete"
