import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/cash_drawer_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/services/cash_drawer_service.dart';
import 'package:goldfish_pos/utils/file_downloader.dart';
import 'package:http/http.dart' as http;

class CashDrawerSettingsScreen extends StatefulWidget {
  const CashDrawerSettingsScreen({super.key});

  @override
  State<CashDrawerSettingsScreen> createState() =>
      _CashDrawerSettingsScreenState();
}

class _CashDrawerSettingsScreenState extends State<CashDrawerSettingsScreen> {
  final _repo = PosRepository();
  final _service = CashDrawerService();
  final _printerNameController = TextEditingController();

  CashDrawerSettings _settings = const CashDrawerSettings();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  // null = not checked yet, true = running, false = not running
  bool? _bridgeOnline;
  bool _checkingBridge = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _printerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _repo.getCashDrawerSettings();
      setState(() {
        _settings = s;
        _printerNameController.text = s.printerName;
        _loading = false;
      });
      _checkBridgeStatus();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkBridgeStatus() async {
    if (_checkingBridge) return;
    setState(() => _checkingBridge = true);
    try {
      final res = await http
          .get(Uri.parse('http://localhost:${_settings.bridgePort}/status'))
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _bridgeOnline = res.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => _bridgeOnline = false);
    } finally {
      if (mounted) setState(() => _checkingBridge = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = _settings.copyWith(
        connectionMode: CashDrawerConnectionMode.localBridge,
        printerName: _printerNameController.text.trim(),
      );
      await _repo.saveCashDrawerSettings(updated);
      setState(() {
        _settings = updated;
        _saving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed to save: $e');
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final result = await _service.openDrawer();
    if (!mounted) return;
    setState(() => _testing = false);
    switch (result) {
      case CashDrawerResult.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash drawer opened!'),
            backgroundColor: Colors.green,
          ),
        );
      case CashDrawerResult.disabled:
        _showError('Enable the cash drawer first.');
      case CashDrawerResult.bridgeNotRunning:
        setState(() => _bridgeOnline = false);
        _showError(
          'The helper app is not running on this computer.\n'
          'Click "Install Helper App" below and follow the steps.',
        );
      case CashDrawerResult.connectionFailed:
        _showError(
          'Connected to the helper app but could not open the drawer.\n'
          'Make sure the receipt printer is on and the cash drawer cable is plugged in.',
        );
      case CashDrawerResult.notConfigured:
      case CashDrawerResult.webNotSupported:
        _showError('Unexpected configuration error. Contact support.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cash Drawer'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Drawer'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save', style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Enable ──────────────────────────────────────────────────────
          Card(
            child: SwitchListTile(
              title: const Text('Enable Cash Drawer',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Opens the cash drawer automatically or on demand.'),
              value: _settings.enabled,
              onChanged: (v) =>
                  setState(() => _settings = _settings.copyWith(enabled: v)),
            ),
          ),

          if (_settings.enabled) ...[
            const SizedBox(height: 12),

            // ── Open on cash payment ───────────────────────────────────
            Card(
              child: SwitchListTile(
                title: const Text('Open on Cash Payment'),
                subtitle: const Text(
                    'Drawer opens automatically when a cash transaction is completed.'),
                value: _settings.openOnCashPayment,
                onChanged: (v) => setState(
                    () => _settings = _settings.copyWith(openOnCashPayment: v)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Printer name ───────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Receipt Printer Name',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text(
                      'Leave blank to use the Windows default printer. '
                      'To find the name: Windows Settings → Bluetooth & devices → Printers & scanners.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _printerNameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g.  EPSON TM-T20III  (leave blank for default)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.print_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Helper app status + install ────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Helper App',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        _BridgeStatusBadge(
                          online: _bridgeOnline,
                          checking: _checkingBridge,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Refresh status',
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _checkingBridge ? null : _checkBridgeStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'A small background app must run on the POS computer to communicate '
                      'with the USB printer and cash drawer. Install it once — '
                      'it starts automatically every time Windows starts.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Install button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download Installer',
                            style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          _downloadInstaller(_settings.bridgePort);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Downloaded! See instructions below to finish setup.',
                              ),
                              duration: Duration(seconds: 4),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Simple steps
                    _InstallStep(
                      number: '1',
                      text:
                          'Click "Download Installer" — two files will appear in your Downloads folder.',
                    ),
                    _InstallStep(
                      number: '2',
                      text:
                          'Right-click  install_bridge_service.ps1  →  "Run with PowerShell".\n'
                          'It installs everything automatically and starts the helper app.',
                    ),
                    _InstallStep(
                      number: '3',
                      text:
                          'Click the refresh icon (↻) above to confirm the status shows Online.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Test button ────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sensors),
                label: Text(_testing ? 'Testing…' : 'Test — Open Drawer Now'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 15),
                ),
                onPressed: _testing ? null : _test,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _BridgeStatusBadge extends StatelessWidget {
  final bool? online;
  final bool checking;
  const _BridgeStatusBadge({required this.online, required this.checking});

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Row(children: [
        SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 6),
        Text('Checking…', style: TextStyle(fontSize: 13)),
      ]);
    }
    if (online == null) {
      return const Text('—', style: TextStyle(color: Colors.grey, fontSize: 13));
    }
    final color = online! ? Colors.green : Colors.red;
    final label = online! ? 'Online' : 'Offline';
    return Row(children: [
      Icon(Icons.circle, color: color, size: 10),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    ]);
  }
}

// ── Install step ──────────────────────────────────────────────────────────────

class _InstallStep extends StatelessWidget {
  final String number;
  final String text;
  const _InstallStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5))),
        ],
      ),
    );
  }
}

// ── Download helper ───────────────────────────────────────────────────────────

void _downloadInstaller(int port) {
  const installer = r"""
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$TaskName   = 'GoldfishPOS_CashDrawerBridge'
$AppDir     = "$env:APPDATA\GoldfishPOS"
$ScriptName = 'cash_drawer_bridge.py'
$ScriptSrc  = Join-Path $PSScriptRoot $ScriptName
$ScriptDest = Join-Path $AppDir $ScriptName

function Write-Step { param($msg) Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Err  { param($msg) Write-Host "`n  ERROR: $msg`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '  Goldfish POS — Cash Drawer Setup' -ForegroundColor Cyan
Write-Host ''

# 1. Find Python
Write-Step 'Looking for Python 3...'
$pythonExe = $null
try { $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}
if (-not $pythonExe) {
    foreach ($g in @("$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe","C:\Python3*\python.exe","C:\Program Files\Python3*\python.exe")) {
        $hit = Get-Item $g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { $pythonExe = $hit.FullName; break }
    }
}
if (-not $pythonExe) { Write-Err 'Python 3 not found. Install from https://python.org (check "Add to PATH") then re-run.' }
Write-Ok "Python: $pythonExe"

$pythonwExe = Join-Path (Split-Path $pythonExe) 'pythonw.exe'
if (-not (Test-Path $pythonwExe)) { $pythonwExe = $pythonExe }

# 2. Install pywin32
Write-Step 'Installing pywin32...'
$pipExe = Join-Path (Split-Path $pythonExe) 'Scripts\pip.exe'
if (-not (Test-Path $pipExe)) { $pipExe = 'pip' }
& $pipExe install pywin32 | Out-Host

# 3. pywin32 post-install (registers DLLs)
Write-Step 'Registering pywin32 DLLs...'
$postInstall = Join-Path (Split-Path $pythonExe) 'Scripts\pywin32_postinstall.py'
if (Test-Path $postInstall) { & $pythonExe $postInstall -install 2>&1 | Out-Null }

$check = & $pythonExe -c "import win32print; print('ok')" 2>&1
if ("$check".Trim() -ne 'ok') { Write-Err "win32print import failed: $check" }
Write-Ok 'pywin32 ready.'

# 4. Copy script
Write-Step "Copying to $AppDir..."
if (-not (Test-Path $ScriptSrc)) { Write-Err "cash_drawer_bridge.py not found next to this installer." }
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $ScriptSrc $ScriptDest -Force
Write-Ok 'Script installed.'

# 5. Register startup task
Write-Step 'Registering startup task...'
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
$action    = New-ScheduledTaskAction -Execute $pythonwExe -Argument "`"$ScriptDest`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Ok 'Startup task registered.'

# 6. Start now
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$state = (Get-ScheduledTask -TaskName $TaskName).State
if ($state -eq 'Running') { Write-Ok 'Helper app is running!' }
else { Write-Host "  Helper app state: '$state' — will start on next login." -ForegroundColor Yellow }

Write-Host ''
Write-Host '  Done! Go back to the POS app and click Refresh to confirm Online.' -ForegroundColor Green
Write-Host ''
Read-Host 'Press Enter to close'
""";

  final bridge = '''#!/usr/bin/env python3
"""
Goldfish POS Cash Drawer Bridge
Installed automatically by install_bridge_service.ps1
Log: %APPDATA%\\GoldfishPOS\\bridge.log
"""
import sys, json, os, logging
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = $port
PRINTER_NAME = ""
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])

_log_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bridge.log')
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[logging.FileHandler(_log_path, encoding='utf-8'), logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger('bridge')


def open_drawer():
    try:
        import win32print  # type: ignore[import]
        printer = PRINTER_NAME or win32print.GetDefaultPrinter()
        log.info('Opening drawer — printer: %s', printer)
        h = win32print.OpenPrinter(printer)
        try:
            win32print.StartDocPrinter(h, 1, ('Cash Drawer', None, 'RAW'))
            try:
                win32print.StartPagePrinter(h)
                win32print.WritePrinter(h, KICK_COMMAND)
                win32print.EndPagePrinter(h)
            finally:
                win32print.EndDocPrinter(h)
        finally:
            win32print.ClosePrinter(h)
        log.info('Drawer opened OK.')
        return True, 'ok'
    except Exception as e:
        log.error('open_drawer: %s', e)
        return False, str(e)


class _H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): log.debug(fmt, *a)
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()
    def do_GET(self):
        if self.path == '/status':
            body = json.dumps({'ok': True, 'port': PORT}).encode()
            self.send_response(200); self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path == '/open-drawer':
            ok, msg = open_drawer()
            body = json.dumps({'ok': ok, 'message': msg}).encode()
            self.send_response(200 if ok else 500); self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(404); self.end_headers()


if __name__ == '__main__':
    log.info('Cash Drawer Bridge starting — port %d — log: %s', PORT, _log_path)
    try:
        HTTPServer(('localhost', PORT), _H).serve_forever()
    except OSError as e:
        log.critical('Cannot bind port %d: %s', PORT, e); sys.exit(1)
    except KeyboardInterrupt:
        log.info('Stopped.'); sys.exit(0)
    except Exception as e:
        log.critical('Fatal: %s', e, exc_info=True); sys.exit(1)
''';

  downloadTextFile('install_bridge_service.ps1', installer);
  downloadTextFile('cash_drawer_bridge.py', bridge);
}
