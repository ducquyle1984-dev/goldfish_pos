import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/cash_drawer_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/services/cash_drawer_service.dart';
import 'package:goldfish_pos/utils/file_downloader.dart';
import 'package:goldfish_pos/utils/url_opener.dart';
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
  String? _bridgeError; // last error from status check
  bool _checkingBridge = false;
  bool _selectingPrinter = false;

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
    setState(() {
      _checkingBridge = true;
      _bridgeError = null;
    });

    final preferred = _settings.bridgePort;
    int? foundPort;

    // 1. Try the configured port first with a normal timeout.
    try {
      final res = await http
          .get(Uri.parse('http://127.0.0.1:$preferred/status'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) foundPort = preferred;
    } catch (_) {}

    // 2. Not found — scan the well-known range in parallel (fast, ~800 ms).
    if (foundPort == null) {
      final candidates = List.generate(
        10,
        (i) => 8765 + i,
      ).where((p) => p != preferred);
      final results = await Future.wait(
        candidates.map((port) async {
          try {
            final res = await http
                .get(Uri.parse('http://127.0.0.1:$port/status'))
                .timeout(const Duration(milliseconds: 800));
            if (res.statusCode == 200) return port;
          } catch (_) {}
          return null;
        }),
      );
      foundPort = results.whereType<int>().firstOrNull;
    }

    if (!mounted) return;

    // 3. Auto-save if found on a different port.
    if (foundPort != null && foundPort != preferred) {
      final updated = _settings.copyWith(bridgePort: foundPort);
      setState(() => _settings = updated);
      _printerNameController.text = updated.printerName;
      await _repo.saveCashDrawerSettings(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bridge found on port $foundPort — '
              'settings updated automatically.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _bridgeOnline = foundPort != null;
        _bridgeError = foundPort == null
            ? 'Bridge not found on port $preferred or nearby ports (8765–8774).'
            : null;
        _checkingBridge = false;
      });
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
            content: Text(
              'Open command sent to printer. '
              'If the drawer did not open, check that the cash drawer cable is plugged into the receipt printer.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
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

  Future<void> _selectPrinter() async {
    if (!mounted) return;
    setState(() => _selectingPrinter = true);
    try {
      final res = await http
          .get(Uri.parse('http://127.0.0.1:${_settings.bridgePort}/printers'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final printers = (data['printers'] as List<dynamic>)
            .map((e) => e.toString())
            .toList();
        if (printers.isEmpty) {
          _showError(
            'No printers found on this computer.\n'
            'Make sure at least one printer is installed in Windows Settings.',
          );
          return;
        }
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => _PrinterPickerDialog(
            printers: printers,
            current: _printerNameController.text.trim(),
          ),
        );
        if (picked != null && mounted) {
          setState(() => _printerNameController.text = picked);
        }
      } else {
        _showError(
          'The bridge responded but could not list printers.\n'
          'Reinstall the bridge from this page to get the latest version.',
        );
      }
    } catch (_) {
      _showError(
        'Cannot reach the bridge.\n'
        'Click the refresh icon (↻) first to confirm it is online.',
      );
    } finally {
      if (mounted) setState(() => _selectingPrinter = false);
    }
  }

  /// Returns widgets shown inside the Helper App card when the bridge is offline.
  List<Widget> _offlineTroubleshoot(BuildContext context) {
    final statusUrl = 'http://127.0.0.1:${_settings.bridgePort}/status';
    return [
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade700,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Helper app not detected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_bridgeError != null) ...[
              Text(
                'Error: $_bridgeError',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
            ],

            // Step 1: verify in browser
            const Text(
              'Step 1 — Verify the helper app is running:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    statusUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.blue,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Open', style: TextStyle(fontSize: 12)),
                  onPressed: () => openUrl(statusUrl),
                ),
              ],
            ),
            const Text(
              'Click "Open" — if you see  {"ok": true}  the helper app IS running.\n'
              'If you get "site can\'t be reached" it is not running.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),

            // Step 2: if running but still offline here
            const Text(
              'Step 2 — If you see {"ok": true} but the status still shows Offline:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your browser may be blocking the automatic check. '
              'This is fine — the open-drawer command will still work. '
              'Just click "Test — Open Drawer Now" to confirm.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),

            // Step 3: debug tool
            const Text(
              'Step 3 — If the page doesn\'t load, run the debug tool:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Double-click  run_bridge_debug.bat  (from the Download).\n'
              'A black window will open showing the exact error.\n\n'
              'Common errors:\n'
              '  "No module named win32print" → re-run install_bridge_service.ps1 as Administrator\n'
              '  "Address already in use" → another instance is already running (good!)\n'
              '  "No default printer" → set a default printer in Windows Settings first',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    ];
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
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
              title: const Text(
                'Enable Cash Drawer',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Opens the cash drawer automatically or on demand.',
              ),
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
                  'Drawer opens automatically when a cash transaction is completed.',
                ),
                value: _settings.openOnCashPayment,
                onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(openOnCashPayment: v),
                ),
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
                    const Text(
                      'Receipt Printer Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
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
                        hintText:
                            'e.g.  EPSON TM-T20III  (leave blank for default)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.print_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _selectingPrinter
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.list_alt_outlined, size: 18),
                        label: Text(
                          _selectingPrinter
                              ? 'Loading printers\u2026'
                              : 'Select Printer from List',
                        ),
                        onPressed: (_selectingPrinter || _bridgeOnline != true)
                            ? null
                            : _selectPrinter,
                      ),
                    ),
                    if (_bridgeOnline != true)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Bridge must be online to list printers.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
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
                        const Text(
                          'Helper App',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        _BridgeStatusBadge(
                          online: _bridgeOnline,
                          checking: _checkingBridge,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Refresh status',
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _checkingBridge
                              ? null
                              : _checkBridgeStatus,
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
                        label: const Text(
                          'Download Installer',
                          style: TextStyle(fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                          'Click "Download Installer" — files will download to your Downloads folder.',
                    ),
                    _InstallStep(
                      number: '2',
                      text:
                          'Double-click  run_installer.bat  to run the setup.\n'
                          'It installs everything automatically and confirms the helper app is running.',
                    ),
                    _InstallStep(
                      number: '3',
                      text:
                          'Click the refresh icon (↻) above. If still Offline, '
                          'double-click  run_bridge_debug.bat  to see the exact error.',
                    ),

                    // ── Offline troubleshooter ──────────────────────────
                    if (_bridgeOnline == false)
                      ..._offlineTroubleshoot(context),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text('Checking…', style: TextStyle(fontSize: 13)),
        ],
      );
    }
    if (online == null) {
      return const Text(
        '—',
        style: TextStyle(color: Colors.grey, fontSize: 13),
      );
    }
    final color = online! ? Colors.green : Colors.red;
    final label = online! ? 'Online' : 'Offline';
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
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
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Printer picker dialog ────────────────────────────────────────────────────

class _PrinterPickerDialog extends StatelessWidget {
  final List<String> printers;
  final String current;

  const _PrinterPickerDialog({required this.printers, required this.current});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Printer'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 440,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: printers.length,
          itemBuilder: (context, i) {
            final name = printers[i];
            final selected = name == current;
            return ListTile(
              leading: Icon(
                Icons.print_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: Text(name),
              trailing: selected
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, name),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear (Use Default Printer)'),
        ),
      ],
    );
  }
}

// ── Download helper ───────────────────────────────────────────────────────────

void _downloadInstaller(int port) {
  final installer =
      """
#Requires -Version 5.1
\$ErrorActionPreference = 'Continue'
\$TaskName   = 'GoldfishPOS_CashDrawerBridge'
\$AppDir     = "\$env:APPDATA\\GoldfishPOS"
\$Port       = $port
\$ScriptDest = Join-Path \$AppDir 'cash_drawer_bridge.py'
\$LauncherDest = Join-Path \$AppDir 'run_bridge.bat'
\$LogDest    = Join-Path \$AppDir 'bridge.log'

function Write-Step { param(\$msg) Write-Host "  >> \$msg" -ForegroundColor Cyan }
function Write-Ok   { param(\$msg) Write-Host "  OK  \$msg" -ForegroundColor Green }
function Write-Err  { param(\$msg) Write-Host "\`n  ERROR: \$msg\`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }
function Write-Warn { param(\$msg) Write-Host "  !!  \$msg" -ForegroundColor Yellow }

Write-Host ''
Write-Host '  Goldfish POS - Cash Drawer Setup' -ForegroundColor Cyan
Write-Host ''

# 1. Find Python
Write-Step 'Looking for Python 3...'
\$pythonExe = \$null
try { \$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}
if (-not \$pythonExe) {
    foreach (\$g in @("\$env:LOCALAPPDATA\\Programs\\Python\\Python3*\\python.exe","C:\\Python3*\\python.exe","C:\\Program Files\\Python3*\\python.exe")) {
        \$hit = Get-Item \$g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if (\$hit) { \$pythonExe = \$hit.FullName; break }
    }
}
if (-not \$pythonExe) { Write-Err 'Python 3 not found. Install from https://python.org  (check "Add to PATH")  then re-run.' }
Write-Ok "Python: \$pythonExe"

# 2. Install pywin32
Write-Step 'Installing pywin32...'
\$pipExe = Join-Path (Split-Path \$pythonExe) 'Scripts\\pip.exe'
if (-not (Test-Path \$pipExe)) { \$pipExe = 'pip' }
\$pipOut = & \$pipExe install --upgrade pywin32 2>&1
\$pipOut | ForEach-Object { Write-Host "    \$_" }
if (\$LASTEXITCODE -ne 0) { Write-Err "pip failed (exit \$LASTEXITCODE). Try running as Administrator." }
Write-Ok 'pywin32 installed.'

# 3. pywin32 post-install  (registers DLLs - critical step)
Write-Step 'Registering pywin32 DLLs...'
\$postInstall = Join-Path (Split-Path \$pythonExe) 'Scripts\\pywin32_postinstall.py'
if (Test-Path \$postInstall) {
    \$out = & \$pythonExe \$postInstall -install 2>&1
    Write-Host (\$out | Out-String)
} else {
    Write-Warn 'pywin32_postinstall.py not found - trying alternate method'
    \$out = & \$pythonExe -c "import pywin32_bootstrap" 2>&1
}

\$check = & \$pythonExe -c "import win32print; print('ok')" 2>&1
if ("\$check".Trim() -ne 'ok') {
    Write-Err "win32print still cannot be imported: \$check\`n\`nTry running this installer as Administrator (right-click -> Run as Administrator)."
}
Write-Ok 'pywin32 verified.'

# 4. Install files (bridge script is embedded - no external file needed)
Write-Step "Installing to \$AppDir..."
New-Item -ItemType Directory -Force -Path \$AppDir | Out-Null
\$bridgeScript = @'
#!/usr/bin/env python3
# Goldfish POS Cash Drawer Bridge
# Log: %APPDATA%\\GoldfishPOS\\bridge.log
import sys, json, os, logging, socket
from http.server import HTTPServer, BaseHTTPRequestHandler

PREFERRED_PORT = $port
PRINTER_NAME = ""
KICK_COMMAND = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])

def _find_free_port(preferred):
    for p in [preferred] + [x for x in range(8765, 8780) if x != preferred]:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', p))
                return p
        except OSError:
            continue
    return preferred

# Stdout-only logging: the launcher bat redirects stdout >> bridge.log
# Do NOT also open bridge.log here -- that causes PermissionError (two handles on same file)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    stream=sys.stdout,
)
log = logging.getLogger('bridge')

PORT = _find_free_port(PREFERRED_PORT)
if PORT != PREFERRED_PORT:
    log.warning('Port %d in use; using port %d instead', PREFERRED_PORT, PORT)


def open_drawer():
    try:
        import win32print
        printer = PRINTER_NAME or win32print.GetDefaultPrinter()
        log.info('Opening drawer - printer: %s', printer)
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


def print_receipt(data):
    try:
        import win32print
        ESC=0x1B; GS=0x1D
        INIT=bytes([ESC,0x40]); LEFT=bytes([ESC,0x61,0x00]); CTR=bytes([ESC,0x61,0x01])
        RIGHT=bytes([ESC,0x61,0x02]); BON=bytes([ESC,0x45,0x01]); BOFF=bytes([ESC,0x45,0x00])
        SZ1=bytes([GS,0x21,0x00]); SZ2=bytes([GS,0x21,0x11]); LF=b'\\n'
        CUT=bytes([GS,0x56,0x41,0x00]); SEP=('-'*42)
        printer = data.get('printer') or PRINTER_NAME or win32print.GetDefaultPrinter()
        out = bytearray(INIT)
        for line in data.get('lines', []):
            if line.get('cut'): out += CUT; continue
            if line.get('separator'): out += LEFT+SZ1+BOFF+SEP.encode('ascii')+LF; continue
            a = line.get('align','left')
            out += CTR if a=='center' else (RIGHT if a=='right' else LEFT)
            out += SZ2 if line.get('size',1)>=2 else SZ1
            out += BON if line.get('bold') else BOFF
            out += line.get('text','').encode('utf-8','replace')+LF
        out += LEFT+SZ1+BOFF
        h = win32print.OpenPrinter(printer)
        try:
            win32print.StartDocPrinter(h, 1, ('Receipt', None, 'RAW'))
            try:
                win32print.StartPagePrinter(h)
                win32print.WritePrinter(h, bytes(out))
                win32print.EndPagePrinter(h)
            finally:
                win32print.EndDocPrinter(h)
        finally:
            win32print.ClosePrinter(h)
        log.info('Receipt printed OK on %s', printer)
        return True, 'ok'
    except Exception as e:
        log.error('print_receipt: %s', e)
        return False, str(e)


def get_printers():
    try:
        import win32print
        flags = win32print.PRINTER_ENUM_LOCAL | win32print.PRINTER_ENUM_CONNECTIONS
        printers = win32print.EnumPrinters(flags, None, 2)
        return [p['pPrinterName'] for p in printers]
    except Exception as e:
        log.error('get_printers: %s', e)
        return []


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
        elif self.path == '/printers':
            names = get_printers()
            body = json.dumps({'ok': True, 'printers': names}).encode()
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
        elif self.path == '/print':
            length = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(length)
            try: data = json.loads(raw)
            except: self.send_response(400); self.end_headers(); return
            ok, msg = print_receipt(data)
            body = json.dumps({'ok': ok, 'message': msg}).encode()
            self.send_response(200 if ok else 500); self._cors()
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(404); self.end_headers()


if __name__ == '__main__':
    log.info('Cash Drawer Bridge starting - port %d', PORT)
    try:
        HTTPServer(('127.0.0.1', PORT), _H).serve_forever()
    except OSError as e:
        log.critical('Cannot bind port %d: %s', PORT, e); sys.exit(1)
    except KeyboardInterrupt:
        log.info('Stopped.'); sys.exit(0)
    except Exception as e:
        log.critical('Fatal: %s', e, exc_info=True); sys.exit(1)
'@
[System.IO.File]::WriteAllText(\$ScriptDest, \$bridgeScript, [System.Text.Encoding]::UTF8)

# Write a .bat launcher - more reliable than calling pythonw.exe directly from Task Scheduler
\$batContent = "@echo off\`r\`n\`"\$pythonExe\`" \`"\$ScriptDest\`" >> \`"\$LogDest\`" 2>&1"
[System.IO.File]::WriteAllText(\$LauncherDest, \$batContent, [System.Text.Encoding]::ASCII)
Write-Ok 'Files installed.'

# 5. Kill any existing bridge
Write-Step 'Stopping any existing bridge...'
Get-Process -Name 'python*' -ErrorAction SilentlyContinue | Where-Object {
    \$_.CommandLine -like '*cash_drawer_bridge*'
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# 6. Register startup task (runs the .bat launcher)
Write-Step 'Registering Windows startup task...'
Unregister-ScheduledTask -TaskName \$TaskName -Confirm:\$false -ErrorAction SilentlyContinue | Out-Null
\$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c \`"\$LauncherDest\`""
\$trigger   = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
\$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
\$principal = New-ScheduledTaskPrincipal -UserId "\$env:USERDOMAIN\\\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName \$TaskName -Action \$action -Trigger \$trigger -Settings \$settings -Principal \$principal -Force | Out-Null
Write-Ok 'Startup task registered.'

# 7. Start the bridge NOW via the launcher bat (handles stdout+stderr redirect correctly)
Write-Step 'Starting bridge...'
if (Test-Path \$LogDest) { Clear-Content \$LogDest }
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c \`"\$LauncherDest\`"" -WindowStyle Hidden
Start-Sleep -Seconds 5

# 8. Verify it actually responds
Write-Step "Testing http://127.0.0.1:\$Port/status ..."
\$ok = \$false
for (\$i = 0; \$i -lt 8; \$i++) {
    try {
        \$r = Invoke-WebRequest -Uri "http://127.0.0.1:\$Port/status" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if (\$r.StatusCode -eq 200) { \$ok = \$true; break }
    } catch {}
    Write-Host "    attempt \$(\$i+1)/8 - waiting..."
    Start-Sleep -Seconds 2
}

if (\$ok) {
    Write-Ok "Bridge is live at http://127.0.0.1:\$Port/status"
    Write-Host ''
    Write-Host '  SUCCESS! Go back to the POS app and click Refresh.' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Warn 'Bridge did not respond. Log output:'
    Write-Host ''
    if (Test-Path \$LogDest) {
        \$lines = Get-Content \$LogDest
        if (\$lines) { \$lines | Select-Object -Last 40 | ForEach-Object { Write-Host "    \$_" } }
        else { Write-Host '    (log file is empty - Python may have crashed before writing anything)' }
    } else {
        Write-Host '    (no log file - launcher bat may have failed to start)'
        Write-Host "    Launcher path: \$LauncherDest"
        Write-Host "    Python path:   \$pythonExe"
    }
    Write-Host ''
    Write-Warn 'To see the error live: double-click  run_bridge_debug.bat  in your Downloads folder.'
}

Write-Host ''
Read-Host 'Press Enter to close'
""";

  final debugBat = '''@echo off
echo Goldfish POS Cash Drawer Bridge - Debug Mode
echo =============================================
echo Any errors will be shown here. Press Ctrl+C to stop.
echo.
set PYFILE=%APPDATA%\\GoldfishPOS\\cash_drawer_bridge.py
if not exist "%PYFILE%" (
    if exist "%~dp0cash_drawer_bridge.py" (
        echo Note: Using cash_drawer_bridge.py from this folder.
        echo       Run install_bridge_service.ps1 for permanent setup.
        echo.
        set PYFILE=%~dp0cash_drawer_bridge.py
    ) else (
        echo ERROR: cash_drawer_bridge.py not found.
        echo.
        echo Either:
        echo   1. Run install_bridge_service.ps1 first  (recommended)
        echo   2. Place cash_drawer_bridge.py in the same folder as this bat
        echo.
        pause
        exit /b 1
    )
)
python "%PYFILE%"
echo.
echo Bridge stopped.
pause
''';

  final runInstallerBat =
      '@echo off\r\n'
      'echo Running Goldfish POS Cash Drawer Installer...\r\n'
      'PowerShell -ExecutionPolicy Bypass -File "%~dp0install_bridge_service.ps1"\r\n'
      'if %ERRORLEVEL% NEQ 0 pause\r\n';

  downloadTextFile('install_bridge_service.ps1', installer);
  downloadTextFile('run_bridge_debug.bat', debugBat);
  downloadTextFile('run_installer.bat', runInstallerBat);
}
