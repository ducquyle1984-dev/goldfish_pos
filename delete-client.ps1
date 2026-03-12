# ==============================================================
# Goldfish POS - Delete a Client Firebase Project
# ==============================================================
# WARNING: This permanently deletes the Firebase project and all
# its data (Firestore, Auth users, Hosting). This cannot be undone.
#
# HOW TO USE:
#   .\delete-client.ps1 -ProjectId "city-nails"
#
# To also remove from client-projects.json:
#   .\delete-client.ps1 -ProjectId "city-nails" -RemoveFromRegistry
# ==============================================================

param(
    [Parameter(Mandatory = $true)]
    [string] $ProjectId,

    [switch] $RemoveFromRegistry
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=======================================================' -ForegroundColor Red
Write-Host ' Goldfish POS - DELETE Client Project' -ForegroundColor Red
Write-Host '=======================================================' -ForegroundColor Red
Write-Host ''
Write-Host " Project ID : $ProjectId" -ForegroundColor Yellow
Write-Host ''
Write-Host ' WARNING: This will permanently delete the Firebase' -ForegroundColor Red
Write-Host '    project and ALL its data (Firestore, Auth, Hosting).' -ForegroundColor Red
Write-Host '    This action CANNOT be undone.' -ForegroundColor Red
Write-Host ''

$confirm = Read-Host ' Type the project ID to confirm deletion'
if ($confirm -ne $ProjectId) {
    Write-Host ' Confirmation did not match. Aborted.' -ForegroundColor Yellow
    exit 0
}

Write-Host ''
Write-Host "[1/2] Deleting Firebase project '$ProjectId'..." -ForegroundColor Cyan

$consoleUrl = "https://console.firebase.google.com/project/$ProjectId/settings/general"
$apiUrl     = "https://cloudresourcemanager.googleapis.com/v1/projects/$ProjectId"

# Read the cached OAuth2 token from firebase-tools configstore
$configPath = Join-Path $env:APPDATA 'configstore\firebase-tools.json'
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path $env:USERPROFILE '.config\configstore\firebase-tools.json'
}

$fbConfig    = $null
$accessToken = $null
if (Test-Path $configPath) {
    try {
        $fbConfig    = Get-Content $configPath -Raw | ConvertFrom-Json
        $accessToken = $fbConfig.tokens.access_token
    } catch { }
}

function Invoke-ProjectDelete($token) {
    Invoke-RestMethod -Method Delete `
        -Uri $apiUrl `
        -Headers @{ Authorization = "Bearer $token" } | Out-Null
}

if ($accessToken) {
    $deleted = $false
    try {
        Invoke-ProjectDelete $accessToken
        $deleted = $true
    } catch {
        $refreshToken = if ($fbConfig) { $fbConfig.tokens.refresh_token } else { $null }
        if ($refreshToken) {
            try {
                Write-Host '   Access token expired, refreshing...' -ForegroundColor Gray
                $refreshBody = "grant_type=refresh_token&refresh_token=$refreshToken" +
                    '&client_id=563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com' +
                    '&client_secret=j9iVZfS8ggxc72q_jESTyA'
                $refreshed = Invoke-RestMethod -Method Post `
                    -Uri 'https://oauth2.googleapis.com/token' `
                    -Body $refreshBody `
                    -ContentType 'application/x-www-form-urlencoded'
                Invoke-ProjectDelete $refreshed.access_token
                $deleted = $true
            } catch {
                Write-Host " Token refresh failed: $_" -ForegroundColor Red
            }
        }
    }
    if ($deleted) {
        Write-Host " Deleted Firebase project '$ProjectId'." -ForegroundColor Green
    } else {
        Write-Host ' Automatic deletion failed. Delete manually:' -ForegroundColor Yellow
        Write-Host " $consoleUrl" -ForegroundColor Blue
    }
} else {
    Write-Host " Could not read Firebase token. Run 'firebase login' first, or delete manually:" -ForegroundColor Yellow
    Write-Host " $consoleUrl" -ForegroundColor Blue
}

# ── Remove from client-projects.json ─────────────────────────────────────────
if ($RemoveFromRegistry) {
    $registryPath = Join-Path $PSScriptRoot 'client-projects.json'
    if (Test-Path $registryPath) {
        Write-Host "[2/2] Removing '$ProjectId' from client-projects.json..." -ForegroundColor Cyan
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $updated  = $registry | Where-Object { $_.projectId -ne $ProjectId }
        $updated | ConvertTo-Json -Depth 5 | Set-Content $registryPath
        Write-Host ' Removed from registry.' -ForegroundColor Green
    } else {
        Write-Host '[2/2] client-projects.json not found - skipping registry update.' -ForegroundColor Yellow
    }
} else {
    Write-Host '[2/2] Use -RemoveFromRegistry to also remove from client-projects.json.' -ForegroundColor Gray
}

Write-Host ''
Write-Host ' Done.' -ForegroundColor Green
Write-Host ''