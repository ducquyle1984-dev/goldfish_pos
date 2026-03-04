#Requires -Version 5.1
<#
.SYNOPSIS
    One-command deploy: bumps BUILD_VERSION, flutter build web, firebase deploy.

.DESCRIPTION
    Run this script every time you want to push a new web build.
    It will:
      1. Auto-generate a BUILD_VERSION based on today's date + an incrementing
         counter (e.g. "2026-03-03-v1", "2026-03-03-v2", …)
      2. Patch web/index.html with the new version
      3. Run: flutter build web --release
      4. Patch build/web/index.html with the new version (flutter overwrites it)
      5. Run: firebase deploy --only hosting
      6. Commit + push to GitHub

.USAGE
    .\deploy.ps1
    .\deploy.ps1 -SkipGit        # skip the git commit/push step
    .\deploy.ps1 -SkipDeploy     # build only, no firebase deploy
#>

param(
    [switch]$SkipGit,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'

$RootDir = $PSScriptRoot
$SourceHtml = Join-Path $RootDir 'web\index.html'
$BuildHtml = Join-Path $RootDir 'build\web\index.html'

# ── 1. Compute new BUILD_VERSION ──────────────────────────────────────────────
$today = Get-Date -Format 'yyyy-MM-dd'

# Read the current version from web/index.html
$currentContent = Get-Content $SourceHtml -Raw
if ($currentContent -match 'BUILD_VERSION\s*=\s*"(\d{4}-\d{2}-\d{2})-v(\d+)"') {
    $storedDate = $Matches[1]
    $storedBuild = [int]$Matches[2]
}
else {
    $storedDate = ''
    $storedBuild = 0
}

# Same day → increment counter; new day → reset to v1
if ($storedDate -eq $today) {
    $newBuild = $storedBuild + 1
}
else {
    $newBuild = 1
}

$newVersion = "$today-v$newBuild"
Write-Host ""
Write-Host "  BUILD_VERSION  :  $newVersion" -ForegroundColor Cyan
Write-Host ""

# ── 2. Patch web/index.html ───────────────────────────────────────────────────
$newSourceContent = $currentContent -replace `
    'BUILD_VERSION\s*=\s*"[^"]*"', `
    "BUILD_VERSION = `"$newVersion`""
[System.IO.File]::WriteAllText($SourceHtml, $newSourceContent, [System.Text.Encoding]::UTF8)
Write-Host "  [1/5] Patched web/index.html" -ForegroundColor Green

# ── 3. flutter build web --release ───────────────────────────────────────────
Write-Host "  [2/5] Building..." -ForegroundColor Cyan
Push-Location $RootDir
try {
    flutter build web --release --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
}
finally {
    Pop-Location
}
Write-Host "  [2/5] Build complete." -ForegroundColor Green

# ── 4. Patch build/web/index.html (flutter overwrites it from web/index.html, ─
#       so BUILD_VERSION should already be there — but patch again to be safe)
if (Test-Path $BuildHtml) {
    $builtContent = Get-Content $BuildHtml -Raw
    $newBuiltContent = $builtContent -replace `
        'BUILD_VERSION\s*=\s*"[^"]*"', `
        "BUILD_VERSION = `"$newVersion`""
    [System.IO.File]::WriteAllText($BuildHtml, $newBuiltContent, [System.Text.Encoding]::UTF8)
    Write-Host "  [3/5] Patched build/web/index.html" -ForegroundColor Green
}

# ── 5. firebase deploy ────────────────────────────────────────────────────────
if (-not $SkipDeploy) {
    Write-Host "  [4/5] Deploying to Firebase..." -ForegroundColor Cyan
    Push-Location $RootDir
    try {
        firebase deploy --only hosting
        if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
    Write-Host "  [4/5] Deployed." -ForegroundColor Green
}
else {
    Write-Host "  [4/5] Skipped Firebase deploy (-SkipDeploy)." -ForegroundColor Yellow
}

# ── 6. git commit + push ──────────────────────────────────────────────────────
if (-not $SkipGit) {
    Write-Host "  [5/5] Committing and pushing to GitHub..." -ForegroundColor Cyan
    Push-Location $RootDir
    try {
        git add web/index.html
        git commit -m "chore: deploy $newVersion"
        git push origin main
    }
    finally {
        Pop-Location
    }
    Write-Host "  [5/5] Pushed." -ForegroundColor Green
}
else {
    Write-Host "  [5/5] Skipped git (-SkipGit)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Done!  Live at https://goldfish-pos.web.app" -ForegroundColor Green
Write-Host ""
