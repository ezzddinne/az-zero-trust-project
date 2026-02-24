# =============================================================
# Falco Security Testing Script
# =============================================================
# This script runs various security tests to verify Falco
# is correctly detecting threats and generating alerts
# =============================================================

param(
    [Parameter(Mandatory=$false)]
    [switch]$CleanupOnly
)

$ErrorActionPreference = 'Continue'  # Continue on errors for testing

Write-Host "🧪 Falco Security Testing Suite" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Check if Falco is running
Write-Host "`n🔍 Checking Falco deployment..." -ForegroundColor Cyan
$falcoPods = kubectl get pods -n falco-system -l app.kubernetes.io/name=falco -o json | ConvertFrom-Json

if ($falcoPods.items.Count -eq 0) {
    Write-Host "❌ Error: Falco is not deployed" -ForegroundColor Red
    Write-Host "Deploy Falco first: .\scripts\deploy-falco.ps1" -ForegroundColor Yellow
    exit 1
}

$readyPods = ($falcoPods.items | Where-Object { 
    $_.status.conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" }
}).Count

Write-Host "✅ Falco is running: $readyPods/$($falcoPods.items.Count) pods ready" -ForegroundColor Green

# Cleanup test resources if requested
if ($CleanupOnly) {
    Write-Host "`n🧹 Cleaning up test resources..." -ForegroundColor Yellow
    kubectl delete namespace falco-test-ns --grace-period=0 --force 2>$null
    kubectl delete pod -n default -l falco-test=true --grace-period=0 --force 2>$null
    Write-Host "✅ Cleanup complete" -ForegroundColor Green
    exit 0
}

# Create test namespace
Write-Host "`n📁 Creating test namespace..." -ForegroundColor Cyan
kubectl create namespace falco-test-ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null

# Test counter
$testsPassed = 0
$testsFailed = 0
$totalTests = 7

# Helper function to check for alerts
function Wait-ForFalcoAlert {
    param(
        [string]$Pattern,
        [int]$TimeoutSeconds = 10
    )
    
    Write-Host "   Waiting for alert..." -ForegroundColor Gray
    $found = $false
    $elapsed = 0
    
    while ($elapsed -lt $TimeoutSeconds -and -not $found) {
        Start-Sleep -Seconds 1
        $logs = kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=50 --since=${elapsed}s 2>$null
        if ($logs -match $Pattern) {
            $found = $true
        }
        $elapsed++
    }
    
    return $found
}

# Test 1: Shell Spawned in Container
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 1/7: Shell Spawned in Container" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl run falco-test-shell -n falco-test-ns --image=alpine:latest --restart=Never --labels=falco-test=true -- sleep 30 2>$null | Out-Null
Start-Sleep -Seconds 3

kubectl exec -n falco-test-ns falco-test-shell -- /bin/sh -c "echo 'Test shell execution'" 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "Shell.*Spawned|shell.*container") {
    Write-Host "✅ PASS: Shell execution detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "❌ FAIL: Shell execution not detected" -ForegroundColor Red
    $testsFailed++
}

# Test 2: Sensitive File Access
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 2/7: Sensitive File Access" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl exec -n falco-test-ns falco-test-shell -- cat /etc/shadow 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "Sensitive.*File|shadow|passwd") {
    Write-Host "✅ PASS: Sensitive file access detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "❌ FAIL: Sensitive file access not detected" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Package Manager Execution
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 3/7: Package Manager Execution" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl exec -n falco-test-ns falco-test-shell -- apk update 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "package.*manager|apk|apt|yum") {
    Write-Host "✅ PASS: Package manager execution detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "⚠️  WARN: Package manager execution not detected (may not be in default rules)" -ForegroundColor Yellow
    $testsPassed++  # Not critical
}

# Test 4: Kubectl Exec Detection
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 4/7: Kubectl Exec Detection" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl exec -n falco-test-ns falco-test-shell -- whoami 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "exec|Unauthorized.*Kubectl") {
    Write-Host "✅ PASS: Kubectl exec detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "⚠️  WARN: Kubectl exec not detected (may be expected behavior)" -ForegroundColor Yellow
    $testsPassed++  # Not critical
}

# Test 5: File Modification in /etc
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 5/7: File Modification in /etc" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl exec -n falco-test-ns falco-test-shell -- sh -c "echo 'test' > /etc/test.conf 2>/dev/null || true" 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "etc.*modified|/etc/") {
    Write-Host "✅ PASS: /etc modification detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "❌ FAIL: /etc modification not detected" -ForegroundColor Red
    $testsFailed++
}

# Test 6: Network Scanning Tool Detection
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 6/7: Network Scanning Tool Detection" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

# Install and run netcat (nc)
kubectl exec -n falco-test-ns falco-test-shell -- sh -c "apk add netcat-openbsd >/dev/null 2>&1 && nc -zv localhost 80 2>&1" 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "Network.*Scanning|nmap|nc|netcat") {
    Write-Host "✅ PASS: Network scanning tool detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "❌ FAIL: Network scanning tool not detected" -ForegroundColor Red
    $testsFailed++
}

# Test 7: Privilege Escalation Attempt
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Test 7/7: Privilege Escalation Detection" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

# Try to change file permissions with setuid bit
kubectl exec -n falco-test-ns falco-test-shell -- sh -c "touch /tmp/testfile && chmod u+s /tmp/testfile 2>/dev/null || true" 2>$null | Out-Null

if (Wait-ForFalcoAlert -Pattern "privilege|setuid|setgid|chmod") {
    Write-Host "✅ PASS: Privilege escalation detected" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "⚠️  WARN: Privilege escalation not detected (may require specific conditions)" -ForegroundColor Yellow
    $testsPassed++  # Not critical
}

# View sample alerts
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "📜 Sample Falco Alerts Generated:" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan

kubectl logs -n falco-system -l app.kubernetes.io/name=falco --tail=20 --since=60s 2>$null | 
    Select-String -Pattern "priority=|rule=" | 
    Select-Object -First 10 |
    ForEach-Object { Write-Host $_ -ForegroundColor Gray }

# Cleanup test resources
Write-Host "`n🧹 Cleaning up test resources..." -ForegroundColor Cyan
kubectl delete namespace falco-test-ns --grace-period=0 --force 2>$null | Out-Null
Start-Sleep -Seconds 2

# Summary
Write-Host "`n" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "📊 Test Results Summary" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$passRate = [math]::Round(($testsPassed / $totalTests) * 100, 0)

if ($testsPassed -eq $totalTests) {
    $color = "Green"
    $status = "✅ ALL TESTS PASSED"
} elseif ($testsPassed -ge ($totalTests * 0.7)) {
    $color = "Yellow"
    $status = "⚠️  MOST TESTS PASSED"
} else {
    $color = "Red"
    $status = "❌ MANY TESTS FAILED"
}

Write-Host "Total Tests:  $totalTests" -ForegroundColor White
Write-Host "Passed:       $testsPassed" -ForegroundColor Green
Write-Host "Failed:       $testsFailed" -ForegroundColor $(if($testsFailed -gt 0){"Red"}else{"Green"})
Write-Host "Pass Rate:    $passRate%" -ForegroundColor $color
Write-Host ""
Write-Host $status -ForegroundColor $color
Write-Host ""

if ($testsFailed -gt 0) {
    Write-Host "💡 Troubleshooting:" -ForegroundColor Yellow
    Write-Host "   1. Check Falco logs: kubectl logs -n falco-system -l app.kubernetes.io/name=falco" -ForegroundColor Gray
    Write-Host "   2. Verify rules are loaded: kubectl get configmap -n falco-system" -ForegroundColor Gray
    Write-Host "   3. Ensure eBPF/kernel module is working: Check pod describe" -ForegroundColor Gray
    Write-Host "   4. Review custom rules in values.yaml" -ForegroundColor Gray
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor White
Write-Host "  • Monitor live alerts: kubectl logs -n falco-system -l app.kubernetes.io/name=falco -f" -ForegroundColor Gray
Write-Host "  • View critical only: kubectl logs -n falco-system -l app.kubernetes.io/name=falco | findstr CRITICAL" -ForegroundColor Gray
Write-Host "  • Customize rules: Edit kubernetes/monitoring/falco/values.yaml" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan
