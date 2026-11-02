# Generates controlled load against the demo servers so you can WATCH the monitoring react:
#   CPU climbs on the dashboard -> CPU WARNING alert -> latency alert -> error alert -> notification email.
# Run from the project folder AFTER `terraform apply`:
#     powershell -ExecutionPolicy Bypass -File scripts\generate-load.ps1
# Options:  -Minutes 6   how long to keep generating load (default 6; alerts need ~2-3 minutes to fire)
#           -Stage all   all (= cpu + latency + errors) | cpu | latency | errors | memory
#           -MemMB 1400  megabytes held by the memory stage (about 70% of an e2-small plus the OS)

param(
    [int]$Minutes = 6,
    [ValidateSet("all", "cpu", "latency", "errors", "memory")] [string]$Stage = "all",
    [int]$MemMB = 1400
)

$ErrorActionPreference = "Stop"

function Banner($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

$urls  = (terraform output -json app_urls | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Value }
$token = terraform output -raw demo_token
$seconds = $Minutes * 60

Banner "Targets"
$urls | ForEach-Object { Write-Host $_ }

function Call($url, $path) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "$url$path&token=$token" -TimeoutSec 15
        return $r.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return "no-response"
    }
}

if ($Stage -in @("all", "cpu")) {
    Banner "1. CPU: burning all cores on every server for $Minutes minutes"
    foreach ($u in $urls) { Write-Host "$u -> $(Call $u "/cpu?seconds=$seconds")" }
}

# Memory is a separate stage (not part of "all"): holding ~1.4 GB on a 2 GB e2-small can trigger the kernel's
# out-of-memory killer, so run it on its own:  -Stage memory
if ($Stage -eq "memory") {
    Banner "2. Memory: holding $MemMB MB on every server for $Minutes minutes"
    foreach ($u in $urls) { Write-Host "$u -> $(Call $u "/mem?mb=$MemMB&seconds=$seconds")" }
}

if ($Stage -in @("all", "latency", "errors")) {
    Banner "3. Application: slow requests and server errors for $Minutes minutes"
    $end = (Get-Date).AddSeconds($seconds)
    $n = 0
    while ((Get-Date) -lt $end) {
        foreach ($u in $urls) {
            if ($Stage -in @("all", "latency")) { $null = Call $u "/slow?ms=900" }
            if ($Stage -in @("all", "errors"))  { $null = Call $u "/error?x=1" }
            $null = Call $u "/healthz?x=1"
        }
        $n++
        if ($n % 5 -eq 0) {
            $left = [int](($end - (Get-Date)).TotalSeconds)
            Write-Host "  $n rounds sent, $left s left..." -ForegroundColor DarkGray
        }
        Start-Sleep -Milliseconds 700
    }
}

Banner "Done"
Write-Host "Now open the dashboard and Monitoring > Alerting:" -ForegroundColor Green
Write-Host (terraform output -raw dashboard_url) -ForegroundColor Green
Write-Host "Alerts fire after the condition holds for the configured duration (default 2 minutes)." -ForegroundColor Green
