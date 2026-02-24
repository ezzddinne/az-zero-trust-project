#!/usr/bin/env bash

set -euo pipefail

LOCATION="eastus2"
RG_NAME="rg-zt-tfstate"
SA_NAME="stztstate$(openssl rand -hex 3)"
CONTAINER_NAME="tfstate"

echo "Azure Terraform Backend Setup"
echo "Resource Group: $RG_NAME"
echo "Storage Account: $SA_NAME"

az account show > /dev/null 2>&1 || { echo "Run 'az login' first"; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription: $SUBSCRIPTION_ID"

echo "Creating resource group..."
az group create --name "$RG_NAME" --location "$LOCATION" --tags Environment=shared Project=zero-trust --output none

echo "Creating storage account..."
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true \
  --tags Environment=shared Project=zero-trust \
  --output none

echo "Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --enable-versioning true \
  --output none

echo "Creating blob container..."
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$SA_NAME" \
  --auth-mode login \
  --output none

echo "Adding delete lock..."
az lock create \
  --name "prevent-delete" \
  --resource-group "$RG_NAME" \
  --lock-type CanNotDelete \
  --notes "Terraform state storage" \
  --output none

echo ""
echo "Update backend.hcl with:"
echo "  resource_group_name  = \"$RG_NAME\""
echo "  storage_account_name = \"$SA_NAME\""
echo "  container_name       = \"$CONTAINER_NAME\""
