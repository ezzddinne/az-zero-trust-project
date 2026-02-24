#!/bin/bash

set -e

ENVIRONMENT="${1:-dev}"

RESOURCE_GROUP="rg-zt-${ENVIRONMENT}"
AKS_CLUSTER="aks-zt-${ENVIRONMENT}"

echo "Starting infrastructure - Environment: ${ENVIRONMENT}"

if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "Resource group '$RESOURCE_GROUP' not found"
    exit 1
fi

if ! az aks show --name "$AKS_CLUSTER" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "AKS cluster '$AKS_CLUSTER' not found"
    exit 1
fi

VM_COUNT_RAW=$(az vm list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
VM_COUNT=$(echo "$VM_COUNT_RAW" | grep -o '^[0-9]*$' || echo "0")
if ! [[ "$VM_COUNT" =~ ^[0-9]+$ ]]; then
    VM_COUNT=0
fi

echo "Scaling up AKS workload node pool..."
if az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name workload &>/dev/null; then
    
    az aks nodepool scale \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name workload \
        --node-count 1
    
    az aks nodepool update \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name workload \
        --enable-cluster-autoscaler \
        --min-count 0 \
        --max-count 3
    
    echo "Workload node pool scaled to 1"
fi

echo "Checking for monitoring node pool..."
if az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$AKS_CLUSTER" \
    --name monitoring &>/dev/null; then
    
    CURRENT_COUNT=$(az aks nodepool show \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$AKS_CLUSTER" \
        --name monitoring \
        --query "count" -o tsv)
    
    if [ "$CURRENT_COUNT" -eq 0 ]; then
        az aks nodepool scale \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$AKS_CLUSTER" \
            --name monitoring \
            --node-count 1
        
        az aks nodepool update \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$AKS_CLUSTER" \
            --name monitoring \
            --enable-cluster-autoscaler \
            --min-count 0 \
            --max-count 2
        
        echo "Monitoring node pool scaled to 1"
    fi
fi

echo "Starting VMs..."
if [[ "$VM_COUNT" =~ ^[0-9]+$ ]] && [ "$VM_COUNT" -gt 0 ]; then
    VM_NAMES=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
    for VM in $VM_NAMES; do
        POWER_STATE=$(az vm show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM" \
            --show-details \
            --query "powerState" -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$POWER_STATE" == *"deallocated"* ]] || [[ "$POWER_STATE" == *"stopped"* ]]; then
            az vm start \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VM" \
                --no-wait
        fi
    done
    echo "VMs started"
fi

echo "Waiting for AKS nodes..."
WAIT_COUNT=0
MAX_WAIT=60
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    READY_NODES=$(kubectl get nodes -l agentpool=workload --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    if [ "$READY_NODES" -gt 0 ]; then
        echo "Nodes ready"
        break
    fi
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

echo "Infrastructure startup complete"
