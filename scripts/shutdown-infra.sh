#!/bin/bash

set -e

ENVIRONMENT="${1:-dev}"

RESOURCE_GROUP="rg-zt-${ENVIRONMENT}"
AKS_CLUSTER="aks-zt-${ENVIRONMENT}"

echo "Shutting down infrastructure - Environment: ${ENVIRONMENT}"

if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP' not found"
    exit 1
fi

VM_COUNT_RAW=$(az vm list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
VM_COUNT=$(echo "$VM_COUNT_RAW" | grep -o '^[0-9]*$' || echo "0")
if ! [[ "$VM_COUNT" =~ ^[0-9]+$ ]]; then
    VM_COUNT=0
fi

echo "Scaling down AKS workload node pool..."
if az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name workload &>/dev/null; then
    
    AUTOSCALER_ENABLED=$(az aks nodepool show \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name workload \
        --query "enableAutoScaling" -o tsv)
    
    if [ "$AUTOSCALER_ENABLED" == "true" ]; then
        az aks nodepool update \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$AKS_CLUSTER" \
            --name workload \
            --disable-cluster-autoscaler
    fi
    
    az aks nodepool scale \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name workload \
        --node-count 0
    echo "Workload node pool scaled to 0"
fi

echo "Checking for monitoring node pool..."
if az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name monitoring &>/dev/null; then
    
    AUTOSCALER_ENABLED=$(az aks nodepool show \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name monitoring \
        --query "enableAutoScaling" -o tsv)
    
    if [ "$AUTOSCALER_ENABLED" == "true" ]; then
        az aks nodepool update \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$AKS_CLUSTER" \
            --name monitoring \
            --disable-cluster-autoscaler
    fi
    
    az aks nodepool scale \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name monitoring \
        --node-count 0
    echo "Monitoring node pool scaled to 0"
fi

echo "Stopping VMs..."
if [[ "$VM_COUNT" =~ ^[0-9]+$ ]] && [ "$VM_COUNT" -gt 0 ]; then
    VM_NAMES=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
    for VM in $VM_NAMES; do
        az vm deallocate \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM" \
            --no-wait
    done
    echo "VMs deallocated"
fi

echo "Infrastructure shutdown complete"
echo "To restart: bash scripts/startup-infra.sh $ENVIRONMENT"
