import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:goldfish_pos/models/cash_drawer_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/services/cash_drawer_service.dart';
import 'package:goldfish_pos/utils/file_downloader.dart';

/// Admin screen to configure and test the cash drawer connection.
class CashDrawerSettingsScreen extends StatefulWidget {
  const CashDrawerSettingsScreen({super.key});

  @override
  State<CashDrawerSettingsScreen> createState() =>
      _CashDrawerSettingsScreenState();
}

class _CashDrawerSettingsScreenState extends State<CashDrawerSettingsScreen> {
  final _repo = PosRepository();
  final _service = CashDrawerService();

  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _bridgePortController = TextEditingController();
  final _printerNameController = TextEditingController();

  CashDrawerSettings _settings = const CashDrawerSettings();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _bridgePortController.dispose();
    _printerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _repo.getCashDrawerSettings();
      setState(() {
        _settings = s;
        _hostController.text = s.host;
        _portController.text = s.port.toString();
        _bridgePortController.text = s.bridgePort.toString();
        _printerNameController.text = s.printerName;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Failed to load settings: $e');
      }
    }
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9100;
    final bridgePort = int.tryParse(_bridgePortController.text.trim()) ?? 8765;
    final printerName = _printerNameController.text.trim();

    if (_settings.enabled &&
        _settings.connectionMode == CashDrawerConnectionMode.tcpNetwork &&
        host.isEmpty) {
      _showError('Please enter the printer IP address.');
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = _settings.copyWith(
        host: host,
        port: port,
        bridgePort: bridgePort,
        printerName: printerName,
      );
      await _repo.saveCashDrawerSettings(updated);
      setState(() {
        _settings = updated;
        _saving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cash drawer settings saved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed to save: $e');
    }
  }

  Future<void> _testDrawer() async {
    await _save();
    if (!mounted) return;

    setState(() => _testing = true);
    try {
      final testSettings = _settings.copyWith(enabled: true);
      await _repo.saveCashDrawerSettings(testSettings);
      setState(() => _settings = testSettings);

      final result = await _service.openDrawer();
      if (!mounted) return;

      switch (result) {
        case CashDrawerResult.success:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cash drawer opened successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        case CashDrawerResult.bridgeNotRunning:
          _showError(
            'Cash drawer bridge is not running on this PC.\n\n'
            'Fix: Re-run install_bridge_service.ps1 (right-click → Run with PowerShell).\n\n'
            'Then check: %AppData%\\GoldfishPOS\\bridge.log for details.',
          );
        case CashDrawerResult.connectionFailed:
          _showError(
            'Could not connect to the printer. '
            'Check the IP address, port, and network connection.',
          );
        case CashDrawerResult.notConfigured:
          _showError('Printer IP address is not configured.');
        case CashDrawerResult.disabled:
          _showError('Cash drawer is disabled.');
        case CashDrawerResult.webNotSupported:
          _showError(
            'TCP mode is not supported in the web app. '
            'Switch to Local Bridge mode.',
          );
      }
    } catch (e) {
      if (mounted) _showError('Test failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBridge =
        _settings.connectionMode == CashDrawerConnectionMode.localBridge;

    return Scaffold(
      appBar: AppBar(title: const Text('Cash Drawer Setup'), elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable Cash Drawer',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Allow the POS to open the cash drawer.',
                        ),
                        value: _settings.enabled,
                        onChanged: (val) => setState(
                          () => _settings = _settings.copyWith(enabled: val),
                        ),
                        secondary: Icon(
                          Icons.point_of_sale,
                          color: _settings.enabled ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Connection mode
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Connection Method',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ModeOption(
                            selected: isBridge,
                            icon: Icons.usb,
                            title:
                                'Local Bridge  (recommended — USB printer / web app)',
                            description:
                                'Run a small Python script on this PC. Works with '
                                'USB printers and works from the web browser.',
                            onTap: () => setState(
                              () => _settings = _settings.copyWith(
                                connectionMode:
                                    CashDrawerConnectionMode.localBridge,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ModeOption(
                            selected: !isBridge,
                            icon: Icons.lan_outlined,
                            title:
                                'TCP Network  (network printer, desktop app only)',
                            description:
                                'Sends commands directly to a network printer over TCP. '
                                'Does NOT work from the web browser.',
                            onTap: () => setState(
                              () => _settings = _settings.copyWith(
                                connectionMode:
                                    CashDrawerConnectionMode.tcpNetwork,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mode-specific settings
                  if (isBridge)
                    _BridgeSetupCard(
                      bridgePortController: _bridgePortController,
                      printerNameController: _printerNameController,
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Network Printer Settings',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _hostController,
                              decoration: const InputDecoration(
                                labelText: 'Printer IP Address *',
                                hintText: 'e.g. 192.168.1.50',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lan_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'TCP Port',
                                hintText: '9100',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.settings_ethernet),
                                helperText:
                                    'Most ESC/POS printers use port 9100.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Auto-open
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Auto-open on Cash Payment',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Automatically opens the drawer when a cash payment is processed.',
                        ),
                        value: _settings.openOnCashPayment,
                        onChanged: (val) => setState(
                          () => _settings = _settings.copyWith(
                            openOnCashPayment: val,
                          ),
                        ),
                        secondary: const Icon(Icons.autorenew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.science_outlined),
                          label: Text(
                            _testing ? 'Testing...' : 'Test Open Drawer',
                          ),
                          onPressed: (_saving || _testing) ? null : _testDrawer,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save Settings'),
                          onPressed: (_saving || _testing) ? null : _save,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ModeOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ModeOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = selected ? primary : Colors.grey.shade400;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? primary.withOpacity(0.05) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: primary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Download helper — triggered by the "Download Setup Files" button.
// Generates both files with the current port baked in and saves them to the
// browser's default download folder.
// ---------------------------------------------------------------------------

void _downloadBridgeSetupFiles(int port) {
  // ── 1. Python bridge script (port embedded) ─────────────────────────────
  final bridgeScript =
      '''#!/usr/bin/env python3
"""
cash_drawer_bridge.py  —  Goldfish POS Cash Drawer Bridge
Receives HTTP requests from the POS app and sends an ESC/POS kick command
to the USB receipt printer via Windows.

Requirements:
  pip install pywin32

Run with:
  pythonw cash_drawer_bridge.py   (no console window)
  python  cash_drawer_bridge.py   (with console window)

The installer script registers this to run automatically at Windows login.
"""

import sys
import json
import os
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = $port          # Must match Bridge Port in Admin > Cash Drawer Settings
PRINTER_NAME = ""     # Leave blank for Windows default printer
                      # Or set e.g.: PRINTER_NAME = "EPSON TM-T20III"

# ESC/POS kick command — opens drawer on port 0 with ~50 ms pulse
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])

# Logging — writes to bridge.log next to this script
_log_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bridge.log')
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-7s  %(message)s',
    handlers=[logging.FileHandler(_log_path, encoding='utf-8'), logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger('bridge')


def open_drawer():
    try:
        import win32print
        printer = PRINTER_NAME or win32print.GetDefaultPrinter()
        log.info('Opening drawer on printer: %s', printer)
        handle = win32print.OpenPrinter(printer)
        try:
            win32print.StartDocPrinter(handle, 1, ('Cash Drawer', None, 'RAW'))
            try:
                win32print.StartPagePrinter(handle)
                win32print.WritePrinter(handle, KICK_COMMAND)
                win32print.EndPagePrinter(handle)
            finally:
                win32print.EndDocPrinter(handle)
        finally:
            win32print.ClosePrinter(handle)
        log.info('Drawer opened successfully.')
        return True, 'ok'
    except Exception as e:
        log.error('open_drawer failed: %s', e)
        return False, str(e)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.info(fmt, *args)

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == '/status':
            body = json.dumps({'ok': True, 'port': PORT, 'log': _log_path}).encode()
            self.send_response(200)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/open-drawer':
            ok, msg = open_drawer()
            body = json.dumps({'ok': ok, 'message': msg}).encode()
            self.send_response(200 if ok else 500)
            self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    log.info('Goldfish POS Cash Drawer Bridge starting — port %d — log: %s', PORT, _log_path)
    try:
        server = HTTPServer(('localhost', PORT), _Handler)
        server.serve_forever()
    except OSError as e:
        log.critical('Cannot bind to port %d: %s — is another instance running?', PORT, e)
        sys.exit(1)
    except KeyboardInterrupt:
        log.info('Stopped.')
        sys.exit(0)
    except Exception as e:
        log.critical('Unexpected error: %s', e, exc_info=True)
        sys.exit(1)
''';

  // ── 2. PowerShell installer script (fully static) ────────────────────────
  const installerScript = r"""
#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Goldfish POS cash drawer bridge as a Windows startup task.
    Run ONCE — the bridge then starts automatically every time Windows starts.
#>

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
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Goldfish POS  --  Cash Drawer Bridge Installer ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# 1. Locate python.exe
Write-Step 'Looking for Python 3...'
$pythonExe = $null
try { $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}
if (-not $pythonExe) {
    $globs = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "C:\Python3*\python.exe",
        "C:\Program Files\Python3*\python.exe",
        "C:\Program Files (x86)\Python3*\python.exe"
    )
    foreach ($g in $globs) {
        $hit = Get-Item $g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { $pythonExe = $hit.FullName; break }
    }
}
if (-not $pythonExe) {
    Write-Err 'Python 3 not found. Install from https://python.org (tick "Add to PATH"), then re-run this script.'
}
Write-Ok "Found Python: $pythonExe"

$pythonwExe = Join-Path (Split-Path $pythonExe) 'pythonw.exe'
if (-not (Test-Path $pythonwExe)) { $pythonwExe = $pythonExe }

# 2. Ensure pywin32 is installed
Write-Step 'Checking for pywin32...'
$importTest = & $pythonExe -c "import win32print; print('ok')" 2>&1
if ("$importTest".Trim() -ne 'ok') {
    Write-Step 'Installing pywin32 (may take a minute)...'
    $pipExe = Join-Path (Split-Path $pythonExe) 'Scripts\pip.exe'
    if (-not (Test-Path $pipExe)) { $pipExe = 'pip' }
    & $pipExe install pywin32 | Out-Host
}
Write-Ok 'pywin32 installed.'

# 2b. Run pywin32 post-install (registers DLLs — required on some systems)
Write-Step 'Running pywin32 post-install step...'
$postInstall = Join-Path (Split-Path $pythonExe) 'Scripts\pywin32_postinstall.py'
if (Test-Path $postInstall) {
    & $pythonExe $postInstall -install 2>&1 | Out-Null
    Write-Ok 'pywin32 post-install complete.'
} else {
    Write-Host '  (post-install script not found — skipping)' -ForegroundColor Yellow
}
$importTest = & $pythonExe -c "import win32print; print('ok')" 2>&1
if ("$importTest".Trim() -ne 'ok') { Write-Err "win32print cannot be imported: $importTest" }
Write-Ok 'win32print import verified.'

# 3. Copy bridge script to permanent location
Write-Step "Installing bridge script to: $AppDir"
if (-not (Test-Path $ScriptSrc)) {
    Write-Err "Cannot find $ScriptSrc.`nMake sure cash_drawer_bridge.py is in the same folder as this installer."
}
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $ScriptSrc $ScriptDest -Force
Write-Ok "Script copied to: $ScriptDest"

# 4. Register scheduled task
Write-Step 'Registering Windows startup task...'
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

$action    = New-ScheduledTaskAction -Execute $pythonwExe -Argument "`"$ScriptDest`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 5 `
                 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null
Write-Ok "Task '$TaskName' registered — runs silently at every Windows logon."

# 5. Start the bridge right now
Write-Step 'Starting the bridge...'
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$taskState = (Get-ScheduledTask -TaskName $TaskName).State
if ($taskState -eq 'Running') { Write-Ok 'Bridge is running now!' }
else { Write-Host "  Bridge state: '$taskState' — will start on next logon." -ForegroundColor Yellow }

Write-Host ''
Write-Host '==================================================' -ForegroundColor Green
Write-Host '  Setup complete! Cash drawer bridge will start   ' -ForegroundColor Green
Write-Host '  automatically at every Windows login.           ' -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Green
Write-Host ''
Read-Host 'Press Enter to close'
""";

  downloadTextFile('cash_drawer_bridge.py', bridgeScript);
  downloadTextFile('install_bridge_service.ps1', installerScript);
}

// ---------------------------------------------------------------------------

class _BridgeSetupCard extends StatelessWidget {
  final TextEditingController bridgePortController;
  final TextEditingController printerNameController;

  const _BridgeSetupCard({
    required this.bridgePortController,
    required this.printerNameController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fields
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bridge Settings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bridgePortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Bridge Port',
                    hintText: '8765',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.electrical_services),
                    helperText:
                        'Port the bridge script listens on (default 8765).',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: printerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Windows Printer Name (optional)',
                    hintText: 'Leave blank to use the default printer',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.print_outlined),
                    helperText:
                        'Exact name from Windows > Devices and Printers.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Instructions + Download button
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Automatic Setup — Run Once on the POS Computer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'After setup the bridge starts silently at every Windows login — completely hands-off.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                ),
                const SizedBox(height: 16),

                // ── Download button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (ctx) => ElevatedButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'Download Setup Files',
                        style: TextStyle(fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        final port =
                            int.tryParse(bridgePortController.text) ?? 8765;
                        _downloadBridgeSetupFiles(port);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '2 files downloaded — right-click the .ps1 file and choose "Run with PowerShell".',
                            ),
                            duration: Duration(seconds: 5),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _Step(
                  n: '1',
                  text:
                      'Click "Download Setup Files" above.\n'
                      'Two files will save to your Downloads folder: '
                      'install_bridge_service.ps1 and cash_drawer_bridge.py.',
                ),
                _Step(
                  n: '2',
                  text:
                      'Right-click install_bridge_service.ps1 → "Run with PowerShell".\n'
                      'It auto-installs Python dependencies and registers the bridge as a '
                      'Windows startup task. Done — no further steps ever needed!',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade800,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Only needs to be done once. To remove later, download and run uninstall_bridge_service.ps1.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Script
        _ScriptCard(port: int.tryParse(bridgePortController.text) ?? 8765),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: Colors.amber.shade700,
            child: Text(
              n,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  final int port;
  const _ScriptCard({required this.port});

  String get _script =>
      '''#!/usr/bin/env python3
"""
cash_drawer_bridge.py
Receives HTTP requests from Goldfish POS and opens the cash drawer by
sending an ESC/POS kick command to the USB receipt printer via Windows.

Requirements:
  pip install pywin32

Usage:
  python cash_drawer_bridge.py
"""

import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = $port          # Must match the Bridge Port in POS Cash Drawer settings
PRINTER_NAME = ""     # Leave blank for Windows default printer
                      # Or set e.g.: PRINTER_NAME = "EPSON TM-T20III"

# ESC/POS kick command — opens drawer on port 0 with ~50 ms pulse
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])


def open_drawer():
    try:
        import win32print
        printer = PRINTER_NAME or win32print.GetDefaultPrinter()
        handle = win32print.OpenPrinter(printer)
        try:
            job = win32print.StartDocPrinter(handle, 1, ("Cash Drawer", None, "RAW"))
            try:
                win32print.StartPagePrinter(handle)
                win32print.WritePrinter(handle, KICK_COMMAND)
                win32print.EndPagePrinter(handle)
            finally:
                win32print.EndDocPrinter(handle)
        finally:
            win32print.ClosePrinter(handle)
        return True, "ok"
    except Exception as e:
        return False, str(e)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(fmt % args)

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    def do_POST(self):
        if self.path == "/open-drawer":
            ok, msg = open_drawer()
            body = json.dumps({"ok": ok, "message": msg}).encode()
            self.send_response(200 if ok else 500)
            self._cors_headers()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print("  Cash drawer", "opened" if ok else f"error: {msg}")
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), Handler)
    print(f"Cash drawer bridge listening on http://localhost:{port}/")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\\nStopped.")
        sys.exit(0)
''';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'cash_drawer_bridge.py',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Script'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _script));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Script copied to clipboard.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _script,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
