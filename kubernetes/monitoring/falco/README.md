# 🦅 Falco Runtime Security Setup

This directory contains the configuration for deploying Falco runtime threat detection in your AKS cluster.

## 📋 What is Falco?

Falco is a **runtime security tool** that detects unexpected behavior in your containers and Kubernetes clusters. It acts as a security camera that watches for:

- 🐚 Shell executions in containers
- 🔓 Privilege escalations
- 📁 Sensitive file access
- 🌐 Suspicious network connections
- ⛏️ Crypto mining attempts
- 🔧 Package installations at runtime
- 📦 Container breakout attempts

## 🚀 Quick Start

### Deploy Falco

```powershell
# From the project root
cd c:\Users\ezzdd\Documents\Projects\zero_trust

# Deploy Falco
.\scripts\deploy-falco.ps1
```

### Monitor Alerts

```powershell
# View real-time alerts
kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f

# Filter for critical alerts only
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "CRITICAL"
```

---

## 📂 Files in This Directory

```
kubernetes/monitoring/falco/
├── README.md           # This file
└── values.yaml         # Helm values configuration
```

---

## ⚙️ Configuration Overview

### values.yaml

The values file configures:

1. **Driver Type**: eBPF (efficient, non-invasive kernel monitoring)
2. **Resource Limits**: CPU and memory constraints
3. **Custom Rules**: Zero-trust specific detection rules
4. **Priority Filtering**: Only alert on notice+ severity
5. **Output Format**: JSON for easy parsing
6. **Tolerations**: Run on all nodes (including spot instances)

---

## 🚨 Custom Rules Included

### 1. Shell Spawned in Container
**Priority**: WARNING  
**Detects**: When bash, sh, or other shells are executed in a container  
**Why it matters**: Attackers often spawn shells after exploitation

### 2. Network Scanning Tool Detected
**Priority**: CRITICAL  
**Detects**: Usage of nmap, netcat, masscan, etc.  
**Why it matters**: Scanning tools indicate reconnaissance activity

### 3. Crypto Mining Detected
**Priority**: CRITICAL  
**Detects**: Known mining tools or stratum protocol connections  
**Why it matters**: Prevents resource hijacking

### 4. Unauthorized Kubectl Exec
**Priority**: NOTICE  
**Detects**: kubectl exec into workload namespace pods  
**Why it matters**: Audit access to production containers

### 5. Sensitive File Access
**Priority**: WARNING  
**Detects**: Access to /etc/shadow, /etc/passwd, etc.  
**Why it matters**: Credential theft attempts

### 6. Suspicious Outbound Connection
**Priority**: WARNING  
**Detects**: Connections to non-standard ports from workload namespace  
**Why it matters**: Data exfiltration or C2 communication

### 7. /etc Directory Modified
**Priority**: WARNING  
**Detects**: File modifications in /etc/  
**Why it matters**: Persistence mechanism or configuration tampering

---

## 📊 Monitoring Falco

### View All Falco Pods

```powershell
kubectl get pods -n falco-system -l app.kubernetes.io/name=falco
```

Expected: One pod per node (DaemonSet)

### Check DaemonSet Status

```powershell
kubectl get daemonset -n falco-system
```

### View Logs from All Pods

```powershell
# All pods
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=100

# Specific pod
kubectl logs -n falco-system falco-xxxxx -f
```

### Filter Logs by Priority

```powershell
# Critical only
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "priority=CRITICAL"

# Warning and above
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "priority=WARNING\|priority=CRITICAL"
```

---

## 🧪 Testing Falco

### Test 1: Trigger Shell Alert

```powershell
# Create a test pod
kubectl run falco-test --image=nginx --rm -it -- /bin/bash

# This should trigger: "Shell Spawned in Container" alert

# Check logs
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=20 | findstr "Shell"
```

### Test 2: Trigger Sensitive File Access

```powershell
# Try to read /etc/shadow
kubectl run falco-test --image=alpine --rm -it -- cat /etc/shadow

# Should trigger: "Sensitive File Access in Container" alert
```

### Test 3: Trigger Network Scanning Detection

```powershell
# Install and run nmap (should trigger alert)
kubectl run falco-test --image=alpine --rm -it -- sh -c "apk add nmap && nmap localhost"

# Should trigger: "Network Scanning Tool Detected" alert
```

---

## 🔍 Understanding Falco Alerts

### Alert Format (JSON)

```json
{
  "output": "Shell spawned in container (user=root container=nginx-pod...)",
  "priority": "WARNING",
  "rule": "Shell Spawned in Container",
  "time": "2026-02-11T10:30:15.123456Z",
  "output_fields": {
    "container.name": "nginx-pod",
    "container.image": "nginx:latest",
    "proc.cmdline": "/bin/bash",
    "user.name": "root",
    "k8s.ns.name": "default",
    "k8s.pod.name": "nginx-pod-12345"
  }
}
```

### Priority Levels

| Priority | Meaning | Action Required |
|----------|---------|-----------------|
| EMERGENCY | System unusable | Immediate response |
| ALERT | Immediate action required | Page on-call |
| CRITICAL | Security breach detected | Investigate immediately |
| ERROR | Error condition | Review within hours |
| WARNING | Potential issue | Review within day |
| NOTICE | Audit trail | Log for compliance |
| INFORMATIONAL | General info | Optional review |
| DEBUG | Debugging info | Development only |

---

## 🔧 Customizing Rules

### Add a New Rule

Edit `values.yaml` in the `customRules` section:

```yaml
customRules:
  zero-trust-rules.yaml: |-
    - rule: My Custom Rule
      desc: Description of what this detects
      condition: >
        spawned_process
        and container
        and proc.name = "suspicious-binary"
      output: >
        Suspicious binary executed
        (user=%user.name container=%container.name)
      priority: CRITICAL
      tags: [custom, mitre_execution]
```

### Apply Changes

```powershell
# Upgrade Falco with new rules
helm upgrade falco falcosecurity/falco `
  -n falco-system `
  -f kubernetes/monitoring/falco/values.yaml
```

---

## 🔗 Integration with Azure Monitor

### Send Falco Alerts to Log Analytics

Falco logs are automatically collected by the OMS agent on each node.

#### Query Falco Alerts in Log Analytics

```kusto
ContainerLog
| where LogEntry contains "Falco"
| where LogEntry contains "priority"
| extend Priority = extract(@"priority=(\w+)", 1, LogEntry)
| extend Rule = extract(@"rule=([^)]+)", 1, LogEntry)
| where Priority in ("CRITICAL", "WARNING", "ERROR")
| project TimeGenerated, Computer, Priority, Rule, LogEntry
| order by TimeGenerated desc
```

### Create Alert Rule in Azure Monitor

```powershell
# Create alert when CRITICAL Falco events occur
az monitor metrics alert create `
  --name "Falco-Critical-Alert" `
  --resource-group rg-zt-dev `
  --scopes /subscriptions/<sub-id>/resourceGroups/rg-zt-dev/providers/Microsoft.OperationalInsights/workspaces/law-zt-dev `
  --condition "count > 0" `
  --description "Falco detected a critical security event"
```

---

## 🔄 Updating Falco

### Check Current Version

```powershell
helm list -n falco-system
```

### Upgrade to Latest Version

```powershell
# Update Helm repo
helm repo update

# Upgrade Falco
helm upgrade falco falcosecurity/falco `
  -n falco-system `
  -f kubernetes/monitoring/falco/values.yaml
```

### Rollback if Needed

```powershell
helm rollback falco -n falco-system
```

---

## 🛠️ Troubleshooting

### Pods Not Starting

```powershell
# Check pod status
kubectl describe pod -n falco-system falco-xxxxx

# Common issues:
# - Node selector not matching
# - Resource limits too restrictive
# - eBPF driver failed to load
```

### No Alerts Appearing

```powershell
# 1. Check Falco is running
kubectl get pods -n falco-system

# 2. Check logs for errors
kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=50

# 3. Verify rules are loaded
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr "rules"

# 4. Test with known trigger
kubectl run test --image=alpine --rm -it -- /bin/sh
```

### High CPU Usage

```powershell
# Check resource usage
kubectl top pods -n falco-system

# If too high, reduce monitoring:
# Edit values.yaml:
#   resources.limits.cpu: 200m  # Instead of 500m
```

### eBPF Driver Issues

```powershell
# Check driver status
kubectl logs -n falco-system falco-xxxxx | findstr "eBPF"

# If issues, switch to kernel module:
# Edit values.yaml:
#   driver.kind: module  # Instead of ebpf
```

---

## 📈 Performance Impact

### Resource Usage (Per Node)

- **CPU**: 100-200m (0.1-0.2 cores) typical
- **Memory**: 256-512 MB typical
- **Network**: Minimal (only alerts, not actual traffic)
- **Disk**: Negligible (in-memory processing)

### Overhead

- **Container startup**: <100ms additional overhead
- **System calls**: ~1-2% overhead with eBPF
- **Network**: No impact (Falco doesn't proxy traffic)

---

## 🔒 Security Considerations

### Falco Runs with Privileges

Falco DaemonSet requires host-level access to monitor:
- `/dev`: For eBPF/kernel module loading
- `/proc`: For process monitoring
- `/etc`: For reading kernel config

This is **by design** - Falco needs kernel visibility to detect threats.

### Minimize Attack Surface

1. **Run only on necessary nodes** (use node selectors if not all nodes need monitoring)
2. **Keep Falco updated** (security patches)
3. **Limit custom rules** (complex rules = more CPU)
4. **Use network policies** (restrict Falco egress to only logging endpoints)

---

## 📚 Additional Resources

- [Falco Documentation](https://falco.org/docs/)
- [Falco Rules Repository](https://github.com/falcosecurity/rules)
- [MITRE ATT&CK Framework](https://attack.mitre.org/) (for understanding tags)
- [Falco Best Practices](https://falco.org/docs/best-practices/)

---

## 🎯 Next Steps

1. ✅ Deploy Falco using the script
2. ✅ Verify alerts are being generated
3. ✅ Integrate with Azure Monitor
4. ✅ Set up alerting for critical events
5. ✅ Customize rules for your workloads
6. ✅ Test incident response procedures

---

**Questions? Issues?**  
Check the troubleshooting section or review Falco logs for detailed error messages.

**Happy monitoring! 🦅🔒**
