# ==============================================================
# Goldfish POS — New Client Deployment Script
# Client   : TestCompany
# Owner    : Duc Le (ducle84@gmail.com)
# Firebase : testcompany
# URL      : https://testcompany.goldfishpos.com  (custom domain — set up after deploy)
# Fallback : https://testcompany.web.app
# Generated: 2026-03-11 23:11
# ==============================================================
#
# HOW TO RUN:
#   1. Save this file as deploy-client.ps1 in your goldfish_pos folder
#   2. Open PowerShell in that folder
#   3. Run: .\deploy-client.ps1
#   DO NOT paste this script directly into the terminal —
#   error-exit commands only work correctly when run as a file.
#
# PREREQUISITES — install once:
#   npm install -g firebase-tools
#   dart pub global activate flutterfire_cli
#   firebase login
# ==============================================================

# Stop immediately on any unhandled error
$ErrorActionPreference = 'Stop'

$PROJECT_ID    = "testcompany-75043"
$SALON_NAME    = "TestCompany"
$ADMIN_EMAIL   = "testcompany.75043@goldfish.internal"
$TEMP_PASSWORD = "Open4408"
$ADMIN_PIN     = "1234"
$SYSADMIN_PIN  = "0000"
$SLUG          = "testcompany-75043"
$BASE_DOMAIN   = "goldfishpos.com"

# ── Step 1: Create the Firebase project ─────────────────────────────────────
Write-Host "`n[1/8] Creating Firebase project '$PROJECT_ID'..." -ForegroundColor Cyan
firebase projects:create $PROJECT_ID --display-name $SALON_NAME
if ($LASTEXITCODE -ne 0) { throw "Step 1 FAILED: Project creation failed. Check that the project ID 'testcompany' is globally unique and your account has permissions." }

# ── Step 2: Enable Blaze (pay-as-you-go) billing ────────────────────────────
Write-Host ""
Write-Host "[2/8] ACTION REQUIRED: Enable Blaze billing plan" -ForegroundColor Yellow
Write-Host "      Open this URL and link a billing account:"
Write-Host "      https://console.firebase.google.com/project/$PROJECT_ID/usage/details" -ForegroundColor Blue
Write-Host ""
Read-Host "      Press Enter once billing is enabled"

# ── Step 3: Configure FlutterFire ───────────────────────────────────────────
Write-Host "[3/8] Configuring FlutterFire for project '$PROJECT_ID'..." -ForegroundColor Cyan
$originalConfig = Get-Content lib\firebase_options.dart -Raw
flutterfire configure --project=$PROJECT_ID --platforms=web --yes
if ($LASTEXITCODE -ne 0) { throw "Step 3 FAILED: FlutterFire configure failed." }

# ── Step 4: Build Flutter web ────────────────────────────────────────────────
Write-Host "[4/8] Building Flutter web app (release)..." -ForegroundColor Cyan
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Set-Content lib\firebase_options.dart $originalConfig
    throw "Step 4 FAILED: Flutter build failed. firebase_options.dart has been restored."
}

# ── Step 5: Deploy to Firebase Hosting ──────────────────────────────────────
Write-Host "[5/8] Deploying to Firebase Hosting..." -ForegroundColor Cyan
firebase use $PROJECT_ID
firebase deploy --only hosting --project $PROJECT_ID
if ($LASTEXITCODE -ne 0) {
    Set-Content lib\firebase_options.dart $originalConfig
    throw "Step 5 FAILED: Firebase deploy failed. firebase_options.dart has been restored."
}

# ── Step 6: Create the admin Firebase Auth user ──────────────────────────────
Write-Host "[6/8] Creating admin user '$ADMIN_EMAIL'..." -ForegroundColor Cyan
$webAppId = (firebase apps:list WEB --project $PROJECT_ID --json | ConvertFrom-Json).result[0].appId
$sdkConfig = (firebase apps:sdkconfig WEB $webAppId --project $PROJECT_ID --json | ConvertFrom-Json).result.sdkConfig
$API_KEY = $sdkConfig.apiKey

$authBody = @{
    email             = $ADMIN_EMAIL
    password          = $TEMP_PASSWORD
    returnSecureToken = $true
} | ConvertTo-Json -Compress

$authResp = $null
try {
    $authResp = Invoke-RestMethod `
        -Method Post `
        -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$API_KEY" `
        -Body $authBody `
        -ContentType "application/json"
    Write-Host "   Admin user created. UID: $($authResp.localId)" -ForegroundColor Green
} catch {
    Write-Host "   WARNING: Could not auto-create admin user: $_" -ForegroundColor Yellow
    Write-Host "   ACTION : Enable Email/Password auth in Firebase Console, then" -ForegroundColor Yellow
    Write-Host "            create the user manually: Authentication > Add user" -ForegroundColor Yellow
    Write-Host "            Email: $ADMIN_EMAIL   Password: $TEMP_PASSWORD" -ForegroundColor Yellow
}

# ── Step 7: Seed Admin & Sys-Admin PINs in Firestore ────────────────────────
Write-Host "[7/8] Seeding PINs in Firestore..." -ForegroundColor Cyan

if ($authResp -and $authResp.idToken) {
    $idToken = $authResp.idToken
    $firestoreBase = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents"

    function Write-FirestoreDoc($path, $fields) {
        $docBody = @{ fields = $fields } | ConvertTo-Json -Depth 5 -Compress
        Invoke-RestMethod -Method Patch `
            -Uri "$firestoreBase/$path" `
            -Headers @{ Authorization = "Bearer $idToken" } `
            -Body $docBody `
            -ContentType "application/json" | Out-Null
    }

    try {
        Write-FirestoreDoc "settings/admin" @{ pin = @{ stringValue = $ADMIN_PIN } }
        Write-FirestoreDoc "settings/systemAdmin" @{ pin = @{ stringValue = $SYSADMIN_PIN } }
        Write-Host "   PINs seeded." -ForegroundColor Green
    } catch {
        Write-Host "   WARNING: Could not seed PINs: $_" -ForegroundColor Yellow
        Write-Host "   ACTION : Set PINs manually in Firestore:" -ForegroundColor Yellow
        Write-Host "            settings/admin.pin = $ADMIN_PIN" -ForegroundColor Yellow
        Write-Host "            settings/systemAdmin.pin = $SYSADMIN_PIN" -ForegroundColor Yellow
    }
} else {
    Write-Host "   Skipping PIN seed (no auth token — set PINs manually in Firestore)." -ForegroundColor Yellow
}

# ── Step 8: Restore your dev firebase_options.dart ──────────────────────────
Write-Host "[8/8] Restoring your development firebase_options.dart..." -ForegroundColor Cyan
Set-Content lib\firebase_options.dart $originalConfig
Write-Host "   Restored." -ForegroundColor Green

# ── Custom domain reminder ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
Write-Host " CLIENT ONBOARDED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host " Salon     : $SALON_NAME"
Write-Host " Temp URL  : https://$PROJECT_ID.web.app"
Write-Host " Admin     : $ADMIN_EMAIL"
Write-Host " Temp Pass : $TEMP_PASSWORD"
Write-Host ""
Write-Host " Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add custom domain '$SLUG.$BASE_DOMAIN' in Firebase Hosting:"
Write-Host "     https://console.firebase.google.com/project/$PROJECT_ID/hosting/sites" -ForegroundColor Blue
Write-Host "  2. Point DNS: CNAME $SLUG.$BASE_DOMAIN => $PROJECT_ID.web.app"
Write-Host "  3. Send client their login credentials and instruct them"
Write-Host "     to change their password and PINs on first login."
Write-Host ""
