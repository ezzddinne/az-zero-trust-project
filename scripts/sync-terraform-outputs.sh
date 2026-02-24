#!/bin/bash

set -euo pipefail

parse_tf_json() {
    local json_input="$1"
    local key="$2"
    
    if command -v jq &>/dev/null; then
        echo "$json_input" | jq -r ".\"${key}\"" 2>/dev/null || echo ""
    else
        echo "$json_input" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null | \
            sed -E 's/"[^"]+"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/' || echo ""
    fi
}

ENVIRONMENT="${1:-}"
ENV_REGEX='^(dev|staging|prod)$'

if [[ ! "$ENVIRONMENT" =~ $ENV_REGEX ]]; then
    echo "Usage: ./sync-terraform-outputs.sh <environment>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_ENV_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"

if [[ ! -f "$TF_ENV_DIR/terraform.tfstate" ]] && [[ ! -f "$TF_ENV_DIR/.terraform/terraform.tfstate" ]]; then
    echo "Terraform state not found for $ENVIRONMENT"
    exit 1
fi

cd "$TF_ENV_DIR"

ACR_LOGIN=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
WORKLOAD_IDS=$(terraform output -json workload_identity_client_ids 2>/dev/null || echo "{}")
CLIENT_ID=$(parse_tf_json "$WORKLOAD_IDS" "sample-api")
TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")

cd - > /dev/null

if [[ -z "$ACR_LOGIN" ]] || [[ -z "$KV_NAME" ]] || [[ -z "$TENANT_ID" ]]; then
    echo "Missing required Terraform outputs"
    exit 1
fi

if [[ -z "$CLIENT_ID" ]] || [[ "$WORKLOAD_IDS" == "{}" ]]; then
    CLIENT_ID="NOT_CONFIGURED"
fi

echo "Syncing Terraform outputs to cluster: $ENVIRONMENT"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: terraform-outputs-$ENVIRONMENT
  namespace: workloads
  labels:
    app: zero-trust
    environment: $ENVIRONMENT
    managed-by: terraform
data:
  ACR_LOGIN: "$ACR_LOGIN"
  KV_NAME: "$KV_NAME"
  CLIENT_ID: "$CLIENT_ID"
  TENANT_ID: "$TENANT_ID"
  ENVIRONMENT: "$ENVIRONMENT"
EOF

echo "ConfigMap created: terraform-outputs-$ENVIRONMENT"
