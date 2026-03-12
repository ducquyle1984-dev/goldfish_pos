import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:goldfish_pos/models/client_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// Four-step wizard for onboarding a new nail salon client.
///
/// Step 1 — Business Info  : salon name, owner, contact details
/// Step 2 — Technical Setup: slug → Firebase project ID, base domain
/// Step 3 — Access & Plan  : admin credentials, PINs, plan tier
/// Step 4 — Review & Deploy: summary + generated PowerShell deployment script
class ClientOnboardingScreen extends StatefulWidget {
  const ClientOnboardingScreen({super.key});

  @override
  State<ClientOnboardingScreen> createState() => _ClientOnboardingScreenState();
}

class _ClientOnboardingScreenState extends State<ClientOnboardingScreen> {
  final _repo = PosRepository();

  int _step = 0; // 0–3
  bool _saving = false;
  bool _saved = false;
  String? _savedClientId;

  // ── Form keys per step ───────────────────────────────────────────────────
  final _key1 = GlobalKey<FormState>();
  final _key2 = GlobalKey<FormState>();
  final _key3 = GlobalKey<FormState>();

  // ── Step 1 controllers ───────────────────────────────────────────────────
  final _salonNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  // ── Step 2 controllers ───────────────────────────────────────────────────
  final _slugCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _domainCtrl = TextEditingController(text: 'goldfishpos.com');

  // ── Step 3 controllers ───────────────────────────────────────────────────
  final _adminEmailCtrl = TextEditingController();
  final _tempPassCtrl = TextEditingController();
  final _adminPinCtrl = TextEditingController();
  final _sysAdminPinCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _plan = 'Starter';
  bool _obscurePass = true;

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _generatePassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$';
    final rng = math.Random.secure();
    return List.generate(14, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _slugifyName(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  String _projectIdFromSlug(String slug) {
    // Firebase project IDs: 6–30 chars, lowercase, letters, digits, hyphens.
    final raw = 'gnp-$slug';
    final safe = raw
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-+'), '-');
    return safe.length > 30 ? safe.substring(0, 30) : safe;
  }

  @override
  void initState() {
    super.initState();
    _tempPassCtrl.text = _generatePassword();

    // Auto-populate slug and project ID when salon name changes.
    _salonNameCtrl.addListener(_onSalonNameChanged);

    // Auto-populate slug → project ID.
    _slugCtrl.addListener(() {
      final slug = _slugCtrl.text.trim();
      final pid = _projectIdFromSlug(slug);
      if (_projectIdCtrl.text != pid) _projectIdCtrl.text = pid;
    });

    // Keep admin email in sync with owner email initially.
    _ownerEmailCtrl.addListener(() {
      if (_adminEmailCtrl.text.isEmpty ||
          _adminEmailCtrl.text == _ownerEmailCtrl.text) {
        _adminEmailCtrl.text = _ownerEmailCtrl.text;
      }
    });
  }

  void _onSalonNameChanged() {
    final slug = _slugifyName(_salonNameCtrl.text);
    if (_slugCtrl.text != slug) {
      _slugCtrl.text = slug;
    }
  }

  @override
  void dispose() {
    _salonNameCtrl.removeListener(_onSalonNameChanged);
    for (final c in [
      _salonNameCtrl,
      _ownerNameCtrl,
      _ownerEmailCtrl,
      _phoneCtrl,
      _addressCtrl,
      _cityCtrl,
      _stateCtrl,
      _zipCtrl,
      _slugCtrl,
      _projectIdCtrl,
      _domainCtrl,
      _adminEmailCtrl,
      _tempPassCtrl,
      _adminPinCtrl,
      _sysAdminPinCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _next() {
    final valid = switch (_step) {
      0 => _key1.currentState!.validate(),
      1 => _key2.currentState!.validate(),
      2 => _key3.currentState!.validate(),
      _ => true,
    };
    if (valid) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Save to Firestore ─────────────────────────────────────────────────────

  Future<void> _saveRecord() async {
    if (_saved) {
      _showSnack('Client record already saved.', isError: false);
      return;
    }
    setState(() => _saving = true);
    try {
      final client = _buildRecord();
      final id = await _repo.createClientRecord(client);
      if (mounted) {
        setState(() {
          _saved = true;
          _savedClientId = id;
          _saving = false;
        });
        _showSnack('Client record saved!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('Save failed: $e');
      }
    }
  }

  ClientRecord _buildRecord() => ClientRecord(
    salonName: _salonNameCtrl.text.trim(),
    ownerName: _ownerNameCtrl.text.trim(),
    ownerEmail: _ownerEmailCtrl.text.trim(),
    phone: _phoneCtrl.text.trim(),
    address: _addressCtrl.text.trim(),
    city: _cityCtrl.text.trim(),
    state: _stateCtrl.text.trim(),
    zip: _zipCtrl.text.trim(),
    slug: _slugCtrl.text.trim(),
    firebaseProjectId: _projectIdCtrl.text.trim(),
    baseDomain: _domainCtrl.text.trim(),
    adminEmail: _adminEmailCtrl.text.trim(),
    tempPassword: _tempPassCtrl.text.trim(),
    plan: _plan,
    notes: _notesCtrl.text.trim(),
    onboardedAt: DateTime.now(),
  );

  // ── Script generator ──────────────────────────────────────────────────────

  String _generateScript() {
    final projectId = _projectIdCtrl.text.trim();
    final salonName = _salonNameCtrl.text.trim();
    final adminEmail = _adminEmailCtrl.text.trim();
    final tempPass = _tempPassCtrl.text.trim();
    final adminPin = _adminPinCtrl.text.trim();
    final sysPin = _sysAdminPinCtrl.text.trim();
    final slug = _slugCtrl.text.trim();
    final domain = _domainCtrl.text.trim();
    final date = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final ownerName = _ownerNameCtrl.text.trim();
    final ownerEmail = _ownerEmailCtrl.text.trim();

    return '''
# ==============================================================
# Goldfish POS — New Client Deployment Script
# Client   : $salonName
# Owner    : $ownerName ($ownerEmail)
# Firebase : $projectId
# URL      : https://$slug.$domain  (custom domain — set up after deploy)
# Fallback : https://$projectId.web.app
# Generated: $date
# ==============================================================
#
# PREREQUISITES — install once:
#   npm install -g firebase-tools
#   dart pub global activate flutterfire_cli
#   firebase login
#
# Run this script from your goldfish_pos project root directory.
# ==============================================================

\$PROJECT_ID    = "$projectId"
\$SALON_NAME    = "$salonName"
\$ADMIN_EMAIL   = "$adminEmail"
\$TEMP_PASSWORD = "$tempPass"
\$ADMIN_PIN     = "$adminPin"
\$SYSADMIN_PIN  = "$sysPin"
\$SLUG          = "$slug"
\$BASE_DOMAIN   = "$domain"

# ── Step 1: Create the Firebase project ─────────────────────────────────────
Write-Host "`n[1/8] Creating Firebase project '\$PROJECT_ID'..." -ForegroundColor Cyan
firebase projects:create \$PROJECT_ID --display-name \$SALON_NAME
if (\$LASTEXITCODE -ne 0) { Write-Error "Project creation failed. It may already exist."; exit 1 }

# ── Step 2: Enable Blaze (pay-as-you-go) billing ────────────────────────────
Write-Host ""
Write-Host "[2/8] ACTION REQUIRED: Enable Blaze billing plan" -ForegroundColor Yellow
Write-Host "      Open this URL and link a billing account:"
Write-Host "      https://console.firebase.google.com/project/\$PROJECT_ID/usage/details" -ForegroundColor Blue
Write-Host ""
Read-Host "      Press Enter once billing is enabled"

# ── Step 3: Configure FlutterFire ───────────────────────────────────────────
Write-Host "[3/8] Configuring FlutterFire for project '\$PROJECT_ID'..." -ForegroundColor Cyan
\$originalConfig = Get-Content lib\\firebase_options.dart -Raw
flutterfire configure --project=\$PROJECT_ID --platforms=web --yes
if (\$LASTEXITCODE -ne 0) { Write-Error "FlutterFire configure failed."; exit 1 }

# ── Step 4: Build Flutter web ────────────────────────────────────────────────
Write-Host "[4/8] Building Flutter web app (release)..." -ForegroundColor Cyan
flutter build web --release
if (\$LASTEXITCODE -ne 0) {
    # Restore config before exiting
    Set-Content lib\\firebase_options.dart \$originalConfig
    Write-Error "Flutter build failed."
    exit 1
}

# ── Step 5: Deploy to Firebase Hosting ──────────────────────────────────────
Write-Host "[5/8] Deploying to Firebase Hosting..." -ForegroundColor Cyan
firebase use \$PROJECT_ID
firebase deploy --only hosting --project \$PROJECT_ID
if (\$LASTEXITCODE -ne 0) {
    Set-Content lib\\firebase_options.dart \$originalConfig
    Write-Error "Firebase deploy failed."
    exit 1
}

# ── Step 6: Create the admin Firebase Auth user ──────────────────────────────
Write-Host "[6/8] Creating admin user '\$ADMIN_EMAIL'..." -ForegroundColor Cyan
\$webAppId = (firebase apps:list WEB --project \$PROJECT_ID --json | ConvertFrom-Json).result[0].appId
\$sdkConfig = (firebase apps:sdkconfig WEB \$webAppId --project \$PROJECT_ID --json | ConvertFrom-Json).result.sdkConfig
\$API_KEY = \$sdkConfig.apiKey

\$body = @{
    email            = \$ADMIN_EMAIL
    password         = \$TEMP_PASSWORD
    returnSecureToken = \$true
} | ConvertTo-Json -Compress

try {
    \$authResp = Invoke-RestMethod `
        -Method Post `
        -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\$API_KEY" `
        -Body \$body `
        -ContentType "application/json"
    Write-Host "   Admin user created. UID: \$(\$authResp.localId)" -ForegroundColor Green
} catch {
    Write-Warning "Could not auto-create admin user: \$_"
    Write-Warning "Create the user manually in Firebase Console > Authentication."
}

# ── Step 7: Seed Admin & Sys-Admin PINs in Firestore ────────────────────────
Write-Host "[7/8] Seeding PINs in Firestore..." -ForegroundColor Cyan
\$idToken = \$authResp.idToken   # use admin's token to write the PIN docs

\$firestoreBase = "https://firestore.googleapis.com/v1/projects/\$PROJECT_ID/databases/(default)/documents"

function Write-FirestoreDoc(\$path, \$fields) {
    \$body = @{ fields = \$fields } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Method Patch `
        -Uri "\$firestoreBase/\$path" `
        -Headers @{ Authorization = "Bearer \$idToken" } `
        -Body \$body `
        -ContentType "application/json" | Out-Null
}

Write-FirestoreDoc "settings/admin" @{
    pin = @{ stringValue = \$ADMIN_PIN }
}
Write-FirestoreDoc "settings/systemAdmin" @{
    pin = @{ stringValue = \$SYSADMIN_PIN }
}
Write-Host "   PINs seeded." -ForegroundColor Green

# ── Step 8: Restore your dev firebase_options.dart ──────────────────────────
Write-Host "[8/8] Restoring your development firebase_options.dart..." -ForegroundColor Cyan
Set-Content lib\\firebase_options.dart \$originalConfig
Write-Host "   Restored." -ForegroundColor Green

# ── Custom domain reminder ───────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
Write-Host " CLIENT ONBOARDED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host " Salon     : \$SALON_NAME"
Write-Host " Temp URL  : https://\$PROJECT_ID.web.app"
Write-Host " Admin     : \$ADMIN_EMAIL"
Write-Host " Temp Pass : \$TEMP_PASSWORD"
Write-Host ""
Write-Host " Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add custom domain '\$SLUG.\$BASE_DOMAIN' in Firebase Hosting:"
Write-Host "     https://console.firebase.google.com/project/\$PROJECT_ID/hosting/sites" -ForegroundColor Blue
Write-Host "  2. Point DNS: CNAME \$SLUG.\$BASE_DOMAIN => \$PROJECT_ID.web.app"
Write-Host "  3. Send client their login credentials and instruct them"
Write-Host "     to change their password and PINs on first login."
Write-Host ""
''';
  }

  void _copyScript() {
    Clipboard.setData(ClipboardData(text: _generateScript()));
    _showSnack('Deployment script copied to clipboard!', isError: false);
  }

  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Client Onboarding'),
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: Column(
        children: [
          // ── Step indicator ────────────────────────────────────────────────
          _StepIndicator(currentStep: _step),
          const Divider(height: 1),

          // ── Step content ──────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _buildStepContent(),
                  ),
                ),
              ),
            ),
          ),

          // ── Navigation bar ────────────────────────────────────────────────
          const Divider(height: 1),
          _NavBar(
            step: _step,
            onBack: _step > 0 ? _back : null,
            onNext: _step < 3 ? _next : null,
            onSave: _step == 3 ? _saveRecord : null,
            onCopyScript: _step == 3 ? _copyScript : null,
            saving: _saving,
            saved: _saved,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    return switch (_step) {
      0 => _buildStep1(),
      1 => _buildStep2(),
      2 => _buildStep3(),
      _ => _buildStep4(),
    };
  }

  // ── Step 1: Business Information ──────────────────────────────────────────

  Widget _buildStep1() {
    return Form(
      key: _key1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionBanner(
            icon: Icons.storefront_outlined,
            color: Colors.deepPurple,
            title: 'Business Information',
            subtitle:
                'Enter the new client\'s salon details exactly as they should appear in the app.',
          ),
          const SizedBox(height: 24),

          // Salon info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('Salon Details'),
                  const SizedBox(height: 16),
                  _Field(
                    ctrl: _salonNameCtrl,
                    label: 'Salon Name *',
                    hint: 'e.g. City Nails & Spa',
                    icon: Icons.storefront_outlined,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    ctrl: _ownerNameCtrl,
                    label: 'Owner Full Name *',
                    hint: 'e.g. Jenny Nguyen',
                    icon: Icons.person_outline,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    ctrl: _ownerEmailCtrl,
                    label: 'Owner Email *',
                    hint: 'e.g. jenny@citynails.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    ctrl: _phoneCtrl,
                    label: 'Phone *',
                    hint: 'e.g. (713) 555-0100',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: _required,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Address card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('Business Address'),
                  const SizedBox(height: 16),
                  _Field(
                    ctrl: _addressCtrl,
                    label: 'Street Address',
                    hint: 'e.g. 1234 Main Street, Suite 5',
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _Field(
                          ctrl: _cityCtrl,
                          label: 'City',
                          hint: 'e.g. Houston',
                          icon: Icons.location_city_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          ctrl: _stateCtrl,
                          label: 'State',
                          hint: 'TX',
                          icon: Icons.map_outlined,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z]'),
                            ),
                            LengthLimitingTextInputFormatter(2),
                            _UpperCaseFormatter(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          ctrl: _zipCtrl,
                          label: 'ZIP',
                          hint: '77001',
                          icon: Icons.pin_drop_outlined,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Technical Setup ───────────────────────────────────────────────

  Widget _buildStep2() {
    return Form(
      key: _key2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionBanner(
            icon: Icons.dns_outlined,
            color: Colors.teal,
            title: 'Technical Setup',
            subtitle:
                'These values define the client\'s Firebase project and URL. '
                'They are auto-populated from the salon name — review and adjust if needed.',
          ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('URL & Firebase Project'),
                  const SizedBox(height: 16),

                  // Slug
                  _Field(
                    ctrl: _slugCtrl,
                    label: 'Client Slug *',
                    hint: 'e.g. city-nails',
                    icon: Icons.link_outlined,
                    helperText:
                        'Lowercase letters, digits, and hyphens only. '
                        'Used as the subdomain.',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v)) {
                        return 'Only lowercase letters, digits, and hyphens';
                      }
                      return null;
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Firebase project ID
                  _Field(
                    ctrl: _projectIdCtrl,
                    label: 'Firebase Project ID *',
                    hint: 'e.g. gnp-city-nails',
                    icon: Icons.cloud_outlined,
                    helperText:
                        'Must be globally unique (6–30 chars, lowercase, '
                        'letters/digits/hyphens). Will be auto-prefixed with "gnp-".',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 6) return 'Must be at least 6 characters';
                      if (v.length > 30) return 'Must be 30 characters or less';
                      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v)) {
                        return 'Only lowercase letters, digits, and hyphens';
                      }
                      return null;
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
                      LengthLimitingTextInputFormatter(30),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Base domain
                  _Field(
                    ctrl: _domainCtrl,
                    label: 'Your Base Domain *',
                    hint: 'e.g. goldfishpos.com',
                    icon: Icons.language_outlined,
                    helperText:
                        'The root domain you own. The client\'s URL will be '
                        '[slug].[domain].',
                    validator: _required,
                  ),
                  const SizedBox(height: 20),

                  // URL Preview
                  _UrlPreview(
                    slug: _slugCtrl,
                    domain: _domainCtrl,
                    projectId: _projectIdCtrl,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info card about DNS
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'DNS setup: Add a wildcard CNAME record '
                    '"*.[domain] → [domain].web.app" in your DNS provider. '
                    'Firebase Hosting will issue SSL automatically for each '
                    'subdomain once traffic reaches it.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Access & Plan ─────────────────────────────────────────────────

  Widget _buildStep3() {
    return Form(
      key: _key3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionBanner(
            icon: Icons.admin_panel_settings_outlined,
            color: Colors.orange,
            title: 'Access & Plan',
            subtitle:
                'Set up the initial admin credentials and select the client\'s '
                'subscription plan. These values are embedded in the deployment script.',
          ),
          const SizedBox(height: 24),

          // Admin login credentials card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('Admin Login Credentials'),
                  const SizedBox(height: 4),
                  Text(
                    'The client uses these to log in to the app on day one. '
                    'Instruct them to change their password immediately after first login.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    ctrl: _adminEmailCtrl,
                    label: 'Admin Login Email *',
                    hint: 'e.g. admin@citynails.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tempPassCtrl,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Temporary Password *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      helperText:
                          'Auto-generated. Click refresh to get a new one.',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: _obscurePass ? 'Show' : 'Hide',
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Generate new password',
                            onPressed: () => setState(
                              () => _tempPassCtrl.text = _generatePassword(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // PINs card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('In-App PINs'),
                  const SizedBox(height: 4),
                  Text(
                    'These PINs protect sensitive admin areas within the POS app. '
                    'They are seeded into the client\'s Firestore automatically by '
                    'the deployment script.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          ctrl: _adminPinCtrl,
                          label: 'Admin PIN *',
                          hint: 'e.g. 1234',
                          icon: Icons.pin_outlined,
                          helperText:
                              'Min 4 digits. For admin settings access.',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) {
                            if (v == null || v.length < 4) {
                              return 'At least 4 digits';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _Field(
                          ctrl: _sysAdminPinCtrl,
                          label: 'Sys Admin PIN *',
                          hint: 'e.g. 9999',
                          icon: Icons.admin_panel_settings_outlined,
                          helperText: 'Min 4 digits. For system-level access.',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) {
                            if (v == null || v.length < 4) {
                              return 'At least 4 digits';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Plan & notes card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader('Subscription Plan'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _plan,
                    decoration: const InputDecoration(
                      labelText: 'Plan',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.workspace_premium_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Starter',
                        child: Text('Starter'),
                      ),
                      DropdownMenuItem(
                        value: 'Professional',
                        child: Text('Professional'),
                      ),
                      DropdownMenuItem(
                        value: 'Enterprise',
                        child: Text('Enterprise'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _plan = v ?? _plan),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Internal Notes',
                      hintText:
                          'Contract date, referral source, special requirements…',
                      border: OutlineInputBorder(),
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.notes_outlined),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 4: Review & Deploy ───────────────────────────────────────────────

  Widget _buildStep4() {
    final salon = _salonNameCtrl.text.trim();
    final owner = _ownerNameCtrl.text.trim();
    final email = _ownerEmailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final slug = _slugCtrl.text.trim();
    final projectId = _projectIdCtrl.text.trim();
    final domain = _domainCtrl.text.trim();
    final adminEmail = _adminEmailCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionBanner(
          icon: Icons.rocket_launch_outlined,
          color: Colors.green.shade700,
          title: 'Review & Deploy',
          subtitle:
              'Confirm the details below, save the record, then copy and run '
              'the PowerShell deployment script on your development machine.',
        ),
        const SizedBox(height: 24),

        // Summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardHeader('Client Summary'),
                const SizedBox(height: 16),
                _ReviewRow(Icons.storefront_outlined, 'Salon', salon),
                _ReviewRow(Icons.person_outline, 'Owner', '$owner  ·  $email'),
                _ReviewRow(Icons.phone_outlined, 'Phone', phone),
                if (_addressCtrl.text.isNotEmpty)
                  _ReviewRow(
                    Icons.location_on_outlined,
                    'Address',
                    [
                      _addressCtrl.text.trim(),
                      [
                        _cityCtrl.text.trim(),
                        _stateCtrl.text.trim(),
                        _zipCtrl.text.trim(),
                      ].where((s) => s.isNotEmpty).join(', '),
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
                const Divider(height: 24),
                _ReviewRow(Icons.link_outlined, 'Slug', slug),
                _ReviewRow(Icons.cloud_outlined, 'Firebase Project', projectId),
                _ReviewRow(
                  Icons.language_outlined,
                  'Client URL',
                  'https://$slug.$domain',
                ),
                _ReviewRow(
                  Icons.bolt_outlined,
                  'Fallback URL',
                  'https://$projectId.web.app',
                ),
                const Divider(height: 24),
                _ReviewRow(Icons.email_outlined, 'Admin Login', adminEmail),
                _ReviewRow(Icons.workspace_premium_outlined, 'Plan', _plan),
                if (_notesCtrl.text.isNotEmpty)
                  _ReviewRow(
                    Icons.notes_outlined,
                    'Notes',
                    _notesCtrl.text.trim(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Save status banner
        if (_saved) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Client record saved to Firestore (ID: $_savedClientId). '
                    'Now copy and run the deployment script.',
                    style: TextStyle(color: Colors.green.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Script preview card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal, color: Colors.grey.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'PowerShell Deployment Script',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _copyScript,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Script'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _generateScript(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Color(0xFFD4D4D4),
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        color: Colors.amber.shade800,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Run this script from your goldfish_pos project directory. '
                          'It will temporarily overwrite lib/firebase_options.dart '
                          'during the build, then restore it automatically. '
                          'Commit any pending changes before running.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Validators ────────────────────────────────────────────────────────────

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  static const _labels = [
    'Business Info',
    'Technical',
    'Access & Plan',
    'Review & Deploy',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: List.generate(_labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIndex = i ~/ 2;
            final done = currentStep > stepIndex;
            return Expanded(
              child: Container(
                height: 2,
                color: done ? cs.primary : Colors.grey.shade300,
              ),
            );
          }
          // Step circle
          final stepIndex = i ~/ 2;
          final done = currentStep > stepIndex;
          final active = currentStep == stepIndex;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || active ? cs.primary : Colors.grey.shade300,
                ),
                alignment: Alignment.center,
                child: done
                    ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                    : Text(
                        '${stepIndex + 1}',
                        style: TextStyle(
                          color: active ? cs.onPrimary : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[stepIndex],
                style: TextStyle(
                  fontSize: 11,
                  color: active ? cs.primary : Colors.grey.shade600,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.step,
    required this.onBack,
    required this.onNext,
    required this.onSave,
    required this.onCopyScript,
    required this.saving,
    required this.saved,
  });

  final int step;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSave;
  final VoidCallback? onCopyScript;
  final bool saving;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          if (onBack != null)
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
            ),
          const Spacer(),
          if (onNext != null)
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Next'),
            ),
          if (step == 3) ...[
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(saved ? Icons.check : Icons.save_outlined, size: 16),
              label: Text(saved ? 'Saved' : 'Save Record'),
              style: saved
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onCopyScript,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Script'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionBanner extends StatelessWidget {
  const _SectionBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.hint,
    this.helperText,
    this.keyboardType,
    this.validator,
    this.inputFormatters,
  });

  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final String? helperText;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      validator: validator,
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live URL preview that rebuilds as the user types.
class _UrlPreview extends StatefulWidget {
  const _UrlPreview({
    required this.slug,
    required this.domain,
    required this.projectId,
  });

  final TextEditingController slug;
  final TextEditingController domain;
  final TextEditingController projectId;

  @override
  State<_UrlPreview> createState() => _UrlPreviewState();
}

class _UrlPreviewState extends State<_UrlPreview> {
  @override
  void initState() {
    super.initState();
    widget.slug.addListener(_rebuild);
    widget.domain.addListener(_rebuild);
    widget.projectId.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.slug.removeListener(_rebuild);
    widget.domain.removeListener(_rebuild);
    widget.projectId.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.slug.text.trim();
    final domain = widget.domain.text.trim();
    final pid = widget.projectId.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'URL Preview',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          _UrlLine(
            label: 'Custom URL',
            url: slug.isNotEmpty && domain.isNotEmpty
                ? 'https://$slug.$domain'
                : '(fill in slug & domain)',
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 4),
          _UrlLine(
            label: 'Firebase URL',
            url: pid.isNotEmpty
                ? 'https://$pid.web.app'
                : '(fill in project ID)',
            color: Colors.blue.shade700,
          ),
        ],
      ),
    );
  }
}

class _UrlLine extends StatelessWidget {
  const _UrlLine({required this.label, required this.url, required this.color});
  final String label;
  final String url;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        Text(
          url,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Forces text to uppercase as the user types (for state field).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
