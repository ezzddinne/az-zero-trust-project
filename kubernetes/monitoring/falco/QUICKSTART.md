# 🦅 Falco Quick Start Guide

## Step 1: Deploy Falco (2 minutes)

```powershell
# From project root
cd c:\Users\ezzdd\Documents\Projects\zero_trust

# Deploy Falco to your AKS cluster
.\scripts\deploy-falco.ps1
```

**Expected Output:**
```
🦅 Deploying Falco Runtime Security — Environment: dev
=============================================================
✅ Connected to cluster with 3 node(s)
📦 Adding Falco Helm repository...
✅ Helm repository added and updated
📁 Creating falco-system namespace...
✅ Namespace ready
🚀 Installing Falco...
✅ Falco install completed successfully
✅ All Falco pods are ready (3/3)
🎉 Falco Deployment Complete!
```

---

## Step 2: Verify Falco is Working (1 minute)

```powershell
# Check pods are running
kubectl get pods -n falco-system

# Should show one pod per node, all Running
# NAME          READY   STATUS    RESTARTS   AGE
# falco-xxxxx   1/1     Running   0          1m
# falco-yyyyy   1/1     Running   0          1m
# falco-zzzzz   1/1     Running   0          1m
```

---

## Step 3: Run Security Tests (3 minutes)

```powershell
# Test all Falco detection rules
.\kubernetes\monitoring\falco\test-falco.ps1
```

**Expected Output:**
```
🧪 Falco Security Testing Suite
================================================================
✅ Falco is running: 3/3 pods ready

Test 1/7: Shell Spawned in Container
✅ PASS: Shell execution detected

Test 2/7: Sensitive File Access
✅ PASS: Sensitive file access detected

...

📊 Test Results Summary
Total Tests:  7
Passed:       7
Failed:       0
Pass Rate:    100%
✅ ALL TESTS PASSED
```

---

## Step 4: Monitor Real-Time Alerts

### View All Alerts

```powershell
kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f
```

### Filter by Priority

```powershell
# Critical only
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "CRITICAL"

# Critical and Warning
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "CRITICAL\|WARNING"
```

### View Specific Pod

```powershell
# List all Falco pods
kubectl get pods -n falco-system

# View logs from specific pod
kubectl logs -n falco-system falco-xxxxx -f
```

---

## Step 5: Integrate with Azure Monitor

### Query Falco Alerts in Log Analytics

```powershell
# Get your workspace ID
cd terraform/environments/dev
$workspaceId = terraform output -raw log_analytics_workspace_id

# Query recent Falco alerts
$query = @"
ContainerLog
| where LogEntry contains "Falco"
| where LogEntry contains "priority"
| extend Priority = extract("priority=(\w+)", 1, LogEntry)
| where Priority in ("CRITICAL", "WARNING", "ERROR")
| project TimeGenerated, Priority, LogEntry
| order by TimeGenerated desc
| take 50
"@

az monitor log-analytics query -w $workspaceId --analytics-query $query --output table
```

### Create Azure Alert

```powershell
# Alert on critical Falco events
az monitor scheduled-query create `
  --name "Falco-Critical-Security-Event" `
  --resource-group rg-zt-dev `
  --scopes /subscriptions/<sub-id>/resourceGroups/rg-zt-dev/providers/Microsoft.OperationalInsights/workspaces/law-zt-dev `
  --condition "count 'Falco_CL' > 0" `
  --condition-query "ContainerLog | where LogEntry contains 'Falco' and LogEntry contains 'priority=CRITICAL'" `
  --description "Falco detected a critical security event" `
  --evaluation-frequency 5m `
  --window-size 5m `
  --severity 1 `
  --action-groups /subscriptions/<sub-id>/resourceGroups/rg-zt-dev/providers/microsoft.insights/actionGroups/ag-security-alerts
```

---

## Common Use Cases

### 1. Detect Someone Accessing Your Pods

```powershell
# Watch for kubectl exec
kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f | findstr "exec"
```

**Alert Example:**
```json
{
  "priority": "NOTICE",
  "rule": "Unauthorized Kubectl Exec",
  "output": "Process spawned via exec in workloads namespace (user=john pod=api-pod-12345)"
}
```

### 2. Catch Crypto Mining Attempts

```powershell
# Monitor for mining activity
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "mining\|crypto"
```

**Alert Example:**
```json
{
  "priority": "CRITICAL",
  "rule": "Crypto Mining Detected",
  "output": "Crypto mining detected (process=xmrig container=nginx-pod)"
}
```

### 3. Audit Sensitive File Access

```powershell
# Watch for /etc/shadow, /etc/passwd access
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "shadow\|passwd"
```

**Alert Example:**
```json
{
  "priority": "WARNING",
  "rule": "Sensitive File Access in Container",
  "output": "Sensitive file accessed (file=/etc/shadow user=root pod=app-123)"
}
```

### 4. Detect Network Reconnaissance

```powershell
# Watch for scanning tools
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "nmap\|scan"
```

---

## Customizing Detection Rules

### Add Your Own Rule

Edit `kubernetes/monitoring/falco/values.yaml`:

```yaml
customRules:
  zero-trust-rules.yaml: |-
    # ... existing rules ...
    
    # NEW: Detect when someone modifies your app config
    - rule: Application Config Modified
      desc: Detect modification of app configuration files
      condition: >
        modify
        and container
        and fd.name startswith /app/config/
        and k8s.ns.name = workloads
      output: >
        Application config modified
        (user=%user.name file=%fd.name pod=%k8s.pod.name)
      priority: WARNING
      tags: [filesystem, config, custom]
```

### Apply Updated Rules

```powershell
# Upgrade Falco with new rules
helm upgrade falco falcosecurity/falco `
  -n falco-system `
  -f kubernetes/monitoring/falco/values.yaml
```

---

## Troubleshooting

### No Alerts Appearing?

```powershell
# 1. Check Falco is running
kubectl get pods -n falco-system

# 2. Check for errors in logs
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=100 | findstr "error\|ERROR\|failed"

# 3. Verify eBPF driver loaded
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "eBPF\|driver"

# Should see: "eBPF probe loaded successfully"

# 4. Test manually
kubectl run test --image=alpine --rm -it -- /bin/sh
# Then check: kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=20
```

### Pods Crashing?

```powershell
# Check pod events
kubectl describe pod -n falco-system falco-xxxxx

# Common issues:
# - eBPF not supported → Switch to kernel module in values.yaml
# - Resources too low → Increase CPU/memory limits
# - Node kernel too old → Update AKS version
```

### Too Many Alerts?

```powershell
# Increase priority threshold in values.yaml:
# Change from:
#   priority: notice
# To:
#   priority: warning  # Only WARNING and above
```

---

## Performance Tuning

### Reduce CPU Usage

Edit `values.yaml`:

```yaml
resources:
  requests:
    cpu: 50m      # Lower (was 100m)
    memory: 128Mi # Lower (was 256Mi)
  limits:
    cpu: 200m     # Lower (was 500m)
    memory: 256Mi # Lower (was 512Mi)
```

### Exclude Noisy Namespaces

Add to your custom rules:

```yaml
- rule: Shell Spawned in Container
  condition: >
    spawned_process
    and container
    and proc.name in (bash, sh)
    and not k8s.ns.name in (kube-system, falco-system)  # Exclude system namespaces
```

---

## Daily Operations

### Morning Check (1 minute)

```powershell
# Quick status check
kubectl get pods -n falco-system
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --since=24h | findstr "CRITICAL\|ERROR"
```

### Weekly Review (5 minutes)

```powershell
# Review all alerts from past week
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --since=168h > falco-weekly.log

# Analyze in Azure Monitor
# Run Log Analytics query for trend analysis
```

### Update Falco (once a month)

```powershell
# Check current version
helm list -n falco-system

# Update Helm repo
helm repo update

# Upgrade Falco
helm upgrade falco falcosecurity/falco `
  -n falco-system `
  -f kubernetes/monitoring/falco/values.yaml

# Verify
kubectl rollout status daemonset/falco -n falco-system
```

---

## Uninstall (if needed)

```powershell
# Quick uninstall
.\scripts\deploy-falco.ps1 -Uninstall

# Or manually
helm uninstall falco -n falco-system
kubectl delete namespace falco-system
```

---

## What's Next?

1. ✅ **Set up alerting** → Create Azure Monitor alerts for critical events
2. ✅ **Integrate with SIEM** → Forward Falco alerts to your security tool
3. ✅ **Create runbooks** → Document response procedures for each alert type
4. ✅ **Tune rules** → Adjust rules based on your application behavior
5. ✅ **Test incident response** → Run security drills using Falco alerts

---

## Need Help?

- 📖 **Full Documentation**: `kubernetes/monitoring/falco/README.md`
- 🧪 **Run Tests**: `.\kubernetes\monitoring\falco\test-falco.ps1`
- 📊 **View Logs**: `kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f`
- 🔍 **Debug**: `kubectl describe pod -n falco-system falco-xxxxx`

**Happy hunting! 🦅🔒**
