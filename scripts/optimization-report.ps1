# Performance and right-sizing report: reads real CPU and memory utilization from Cloud Monitoring,
# then recommends whether each VM is over-sized, well-sized or under-sized. Writes reports\performance-report.md.
# Run from the project folder AFTER `terraform apply` (needs a few minutes of data; more history = better advice):
#     powershell -ExecutionPolicy Bypass -File scripts\optimization-report.ps1 -Hours 1
# Options:  -Hours 24   how far back to look (default 1)

param([int]$Hours = 1)

$ErrorActionPreference = "Stop"

$project = (gcloud config get-value project 2>$null).Trim()
if (-not $project) { throw "No gcloud project set. Run: gcloud config set project YOUR_PROJECT_ID" }
$token   = (gcloud auth print-access-token).Trim()
$headers = @{ Authorization = "Bearer $token"; "x-goog-user-project" = $project }

$end   = (Get-Date).ToUniversalTime()
$start = $end.AddHours(-$Hours)
$fmt   = "yyyy-MM-ddTHH:mm:ssZ"

# Machine types in the e2 shared-core / standard family, smallest to largest: name, vCPUs, memory in MB.
$sizes = @(
    @{ Name = "e2-micro";      Cpu = 2; MemMB = 1024 },
    @{ Name = "e2-small";      Cpu = 2; MemMB = 2048 },
    @{ Name = "e2-medium";     Cpu = 2; MemMB = 4096 },
    @{ Name = "e2-standard-2"; Cpu = 2; MemMB = 8192 },
    @{ Name = "e2-standard-4"; Cpu = 4; MemMB = 16384 }
)

function Get-Series($filter, $aligner) {
    $q = @(
        "filter=$([uri]::EscapeDataString($filter))",
        "interval.startTime=$($start.ToString($fmt))",
        "interval.endTime=$($end.ToString($fmt))",
        "aggregation.alignmentPeriod=300s",
        "aggregation.perSeriesAligner=$aligner"
    ) -join "&"
    $resp = Invoke-RestMethod -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project/timeSeries?$q"
    return $resp.timeSeries
}

function Percentile($values, $p) {
    if (-not $values -or $values.Count -eq 0) { return $null }
    $sorted = $values | Sort-Object
    $idx = [math]::Min($sorted.Count - 1, [math]::Ceiling($p / 100 * $sorted.Count) - 1)
    return $sorted[[math]::Max(0, $idx)]
}

Write-Host "Reading utilization for project $project over the last $Hours hour(s)..." -ForegroundColor Cyan

$cpuSeries = Get-Series 'metric.type="compute.googleapis.com/instance/cpu/utilization" AND resource.type="gce_instance"' "ALIGN_MEAN"
$memSeries = Get-Series 'metric.type="agent.googleapis.com/memory/percent_used" AND metric.labels.state="used" AND resource.type="gce_instance"' "ALIGN_MEAN"

$memById = @{}
foreach ($s in $memSeries) { $memById[$s.resource.labels.instance_id] = $s }

$rows = @()
foreach ($s in $cpuSeries) {
    $id   = $s.resource.labels.instance_id
    $zone = $s.resource.labels.zone
    $cpu  = @($s.points | ForEach-Object { [double]$_.value.doubleValue * 100 })
    $mem  = @()
    if ($memById.ContainsKey($id)) { $mem = @($memById[$id].points | ForEach-Object { [double]$_.value.doubleValue }) }

    $cpuAvg = [math]::Round(($cpu | Measure-Object -Average).Average, 1)
    $cpuP95 = [math]::Round((Percentile $cpu 95), 1)
    $cpuMax = [math]::Round(($cpu | Measure-Object -Maximum).Maximum, 1)
    $memAvg = if ($mem.Count) { [math]::Round(($mem | Measure-Object -Average).Average, 1) } else { $null }
    $memP95 = if ($mem.Count) { [math]::Round((Percentile $mem 95), 1) } else { $null }

    # Right-sizing rules of thumb: keep p95 CPU between ~20% and ~75%, and memory p95 under ~80%.
    if ($cpuP95 -gt 75 -or ($memP95 -ne $null -and $memP95 -gt 80)) {
        $verdict = "UNDER-SIZED: resize up or add instances"
    } elseif ($cpuP95 -lt 20 -and ($memP95 -eq $null -or $memP95 -lt 50)) {
        $verdict = "OVER-SIZED: downsize or schedule it to stop when idle"
    } else {
        $verdict = "WELL-SIZED"
    }

    $rows += [pscustomobject]@{
        Zone = $zone; InstanceId = $id
        CpuAvgPct = $cpuAvg; CpuP95Pct = $cpuP95; CpuMaxPct = $cpuMax
        MemAvgPct = $memAvg; MemP95Pct = $memP95
        Verdict = $verdict
    }
}

if (-not $rows) {
    Write-Host "No CPU data yet. Wait 5-10 minutes after deployment and run again." -ForegroundColor Yellow
    return
}

Write-Host ""
$rows | Format-Table -AutoSize

# Google's own recommendations (need roughly a day of history, so they are often empty on a fresh demo).
Write-Host "Google Cloud Recommender (machine type right-sizing and idle VMs):" -ForegroundColor Cyan
$recs = @()
$zones = $rows | Select-Object -ExpandProperty Zone -Unique
foreach ($z in $zones) {
    foreach ($rec in @("google.compute.instance.MachineTypeRecommender", "google.compute.instance.IdleResourceRecommender")) {
        $json = gcloud recommender recommendations list --recommender=$rec --location=$z --project=$project --format=json 2>$null
        if ($json) { $recs += ($json | ConvertFrom-Json) }
    }
}
if ($recs.Count -eq 0) {
    Write-Host "  none yet (the Recommender needs about 24 hours of data)." -ForegroundColor DarkGray
} else {
    $recs | ForEach-Object { Write-Host "  - $($_.description)" }
}

# Save a shareable Markdown report.
New-Item -ItemType Directory -Force -Path "reports" | Out-Null
$md = @()
$md += "# Performance and right-sizing report"
$md += ""
$md += "Project: $project  |  Window: last $Hours hour(s)  |  Generated: $($end.ToString('u'))"
$md += ""
$md += "| Zone | Instance | CPU avg % | CPU p95 % | CPU max % | Memory avg % | Memory p95 % | Verdict |"
$md += "|---|---|---|---|---|---|---|---|"
foreach ($r in $rows) {
    $md += "| $($r.Zone) | $($r.InstanceId) | $($r.CpuAvgPct) | $($r.CpuP95Pct) | $($r.CpuMaxPct) | $($r.MemAvgPct) | $($r.MemP95Pct) | $($r.Verdict) |"
}
$md += ""
$md += "Rules: UNDER-SIZED when CPU p95 > 75% or memory p95 > 80%; OVER-SIZED when CPU p95 < 20% and memory p95 < 50%; otherwise WELL-SIZED."
$md += "Machine types considered: " + (($sizes | ForEach-Object { "$($_.Name) ($($_.Cpu) vCPU, $([int]($_.MemMB/1024)) GB)" }) -join ", ") + "."
$md | Set-Content -Path "reports\performance-report.md" -Encoding utf8
Write-Host ""
Write-Host "Report saved to reports\performance-report.md" -ForegroundColor Green
