# ==============================================================
# Goldfish POS — Deploy Code Update to ALL Client Projects
# ==============================================================
# Run this whenever you push a code change and want all clients
# to get the latest version.
#
# HOW TO USE:
#   1. Add each client to client-projects.json (set "active": true)
#   2. Run: .\deploy-all-clients.ps1
#      Optional: target specific clients only:
#      .\deploy-all-clients.ps1 -Only "city-nails-project","pro-top-nails"
# ==============================================================

param(
    [string[]] $Only = @()   # If provided, only deploy to these project IDs
)

$ErrorActionPreference = 'Stop'

# ── Load client registry ─────────────────────────────────────────────────────
$registryPath = Join-Path $PSScriptRoot "client-projects.json"
if (-not (Test-Path $registryPath)) {
    throw "client-projects.json not found. Create it in your project root."
}

$allClients = Get-Content $registryPath -Raw | ConvertFrom-Json
$clients = $allClients | Where-Object { $_.active -eq $true }

if ($Only.Count -gt 0) {
    $clients = $clients | Where-Object { $Only -contains $_.projectId }
}

if ($clients.Count -eq 0) {
    Write-Host "No active clients found in client-projects.json." -ForegroundColor Yellow
    Write-Host "Set 'active': true for each client you want to deploy to." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Goldfish POS — Batch Client Deploy" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Deploying to $($clients.Count) client project(s):" -ForegroundColor Cyan
foreach ($c in $clients) {
    Write-Host "   • $($c.name)  ($($c.projectId))" -ForegroundColor Cyan
}
Write-Host ""

# ── Save original firebase_options.dart ──────────────────────────────────────
$originalConfig = Get-Content lib\firebase_options.dart -Raw

# ── Build once per client (each needs its own firebase_options.dart) ──────────
$results = @()
$failed = @()

foreach ($client in $clients) {
    $projectId = $client.projectId
    $name = $client.name

    Write-Host ""
    Write-Host "──────────────────────────────────────────────────────" -ForegroundColor White
    Write-Host " Client : $name" -ForegroundColor White
    Write-Host " Project: $projectId" -ForegroundColor White
    Write-Host "──────────────────────────────────────────────────────" -ForegroundColor White

    try {
        # Configure FlutterFire for this client
        Write-Host "[1/3] Configuring FlutterFire..." -ForegroundColor Cyan
        flutterfire configure --project=$projectId --platforms=web --yes
        if ($LASTEXITCODE -ne 0) { throw "FlutterFire configure failed for $projectId" }

        # Build Flutter web
        Write-Host "[2/3] Building Flutter web..." -ForegroundColor Cyan
        flutter build web --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter build failed for $projectId" }

        # Deploy to Firebase Hosting
        Write-Host "[3/3] Deploying to Firebase Hosting..." -ForegroundColor Cyan
        firebase deploy --only hosting --project $projectId
        if ($LASTEXITCODE -ne 0) { throw "Firebase deploy failed for $projectId" }

        $results += [PSCustomObject]@{ Name = $name; ProjectId = $projectId; Status = "OK" }
        Write-Host " ✓ $name deployed successfully!" -ForegroundColor Green

    }
    catch {
        $results += [PSCustomObject]@{ Name = $name; ProjectId = $projectId; Status = "FAILED: $_" }
        $failed += $projectId
        Write-Host " ✗ $name FAILED: $_" -ForegroundColor Red
        Write-Host "   Continuing to next client..." -ForegroundColor Yellow
    }
    finally {
        # Always restore original firebase_options.dart before moving on
        Set-Content lib\firebase_options.dart $originalConfig
    }
}

# ── Final report ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " DEPLOY COMPLETE — Results Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -eq "OK") { "Green" } else { "Red" }
    $icon = if ($r.Status -eq "OK") { "✓" } else { "✗" }
    Write-Host " $icon $($r.Name.PadRight(30)) $($r.Status)" -ForegroundColor $color
}
Write-Host ""

if ($failed.Count -gt 0) {
    Write-Host " $($failed.Count) project(s) failed. To retry failed only:" -ForegroundColor Yellow
    $failedList = ($failed | ForEach-Object { "`"$_`"" }) -join ","
    Write-Host " .\deploy-all-clients.ps1 -Only $failedList" -ForegroundColor Yellow
    Write-Host ""
}
