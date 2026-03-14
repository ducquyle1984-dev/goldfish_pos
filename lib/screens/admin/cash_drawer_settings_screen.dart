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
              'A PowerShell window will open showing the real-time log.\n\n'
              'Common errors:\n'
              '  "Access is denied" → re-run run_installer.bat as Administrator\n'
              '  "port already in use" → another instance is already running\n'
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
  // ── PowerShell bridge (no Python, no pip — uses only built-in Windows PowerShell) ──
  // Dart raw string: $ and backslashes are literal (not interpolated).
  const bridgeScript = r'''
#Requires -Version 5.1
<#
.SYNOPSIS
    Goldfish POS Cash Drawer Bridge  —  PowerShell edition
    HTTP server on http://127.0.0.1:8765/ — no Python, no pip.
    Windows PowerShell 5.1 is pre-installed on every Windows 10/11 PC.
#>

param(
    [int]   $Port        = 8765,
    [string]$PrinterName = ''
)

$KickCommand = [byte[]](0x1B, 0x70, 0x00, 0x19, 0xFA)

$AppDir  = Join-Path $env:APPDATA 'GoldfishPOS'
$null    = New-Item -ItemType Directory -Force -Path $AppDir
$LogFile = Join-Path $AppDir 'bridge.log'

function Write-Log {
    param([string]$Level, [string]$Msg)
    $entry = '{0}  {1,-7}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    Write-Host $entry
}

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WinSpool {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DOC_INFO_1 { public string pDocName; public string pOutputFile; public string pDatatype; }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pDefault);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern int StartDocPrinter(IntPtr hPrinter, int Level, ref DOC_INFO_1 info);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr hPrinter, byte[] pBuf, int cbBuf, out int pcWritten);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern int EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool GetDefaultPrinter(StringBuilder pszBuffer, ref int pcchBuffer);

    public static string GetDefaultPrinterName() {
        int size = 256; var buf = new StringBuilder(size);
        if (!GetDefaultPrinter(buf, ref size))
            throw new Exception("No default printer configured. Set one in Windows Settings -> Printers & scanners.");
        return buf.ToString();
    }
    public static void SendRaw(string printerName, byte[] data) {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero))
            throw new Exception(string.Format("OpenPrinter(\"{0}\") failed — error {1}. Is the printer installed?", printerName, Marshal.GetLastWin32Error()));
        try {
            var doc = new DOC_INFO_1 { pDocName = "GoldfishPOS", pDatatype = "RAW" };
            int job = StartDocPrinter(hPrinter, 1, ref doc);
            if (job == 0) throw new Exception("StartDocPrinter failed: " + Marshal.GetLastWin32Error());
            try { StartPagePrinter(hPrinter); int w; WritePrinter(hPrinter, data, data.Length, out w); EndPagePrinter(hPrinter); }
            finally { EndDocPrinter(hPrinter); }
        } finally { ClosePrinter(hPrinter); }
    }
}
'@ -ErrorAction Stop

function Get-PrinterNameToUse {
    if ($PrinterName) { return $PrinterName }
    return [WinSpool]::GetDefaultPrinterName()
}

function Invoke-OpenDrawer {
    try {
        $name = Get-PrinterNameToUse
        Write-Log 'INFO' "Opening drawer via printer: $name"
        [WinSpool]::SendRaw($name, $KickCommand)
        Write-Log 'INFO' 'Drawer opened OK.'
        return @{ ok = $true; message = 'ok' }
    } catch {
        $msg = $_.Exception.Message
        Write-Log 'ERROR' "open_drawer: $msg"
        return @{ ok = $false; message = $msg }
    }
}

function Get-PrinterList {
    try { return @{ ok = $true; printers = @(Get-Printer | Select-Object -ExpandProperty Name) } }
    catch { Write-Log 'ERROR' "get_printers: $($_.Exception.Message)"; return @{ ok = $true; printers = @() } }
}

function Invoke-PrintReceipt {
    param($Data)
    try {
        $printerName = if ($Data.printer) { "$($Data.printer)" } else { Get-PrinterNameToUse }
        [byte]$ESC = 0x1B; [byte]$GS = 0x1D; [byte]$LF = 0x0A
        $INIT = [byte[]]($ESC,0x40); $LEFT=[byte[]]($ESC,0x61,0x00); $CTR=[byte[]]($ESC,0x61,0x01); $RIGHT=[byte[]]($ESC,0x61,0x02)
        $BON=[byte[]]($ESC,0x45,0x01); $BOFF=[byte[]]($ESC,0x45,0x00)
        $SZ1=[byte[]]($GS,0x21,0x00); $SZ2=[byte[]]($GS,0x21,0x11)
        $CUT=[byte[]]($GS,0x56,0x41,0x00)
        $SEP=[System.Text.Encoding]::ASCII.GetBytes(('-'*42))
        $out=[System.Collections.Generic.List[byte]]::new(); $out.AddRange($INIT)
        foreach ($ln in @($Data.lines)) {
            if ($ln.cut)       { $out.AddRange($CUT); continue }
            if ($ln.separator) { $out.AddRange($LEFT); $out.AddRange($SZ1); $out.AddRange($BOFF); $out.AddRange($SEP); $out.Add($LF); continue }
            switch ("$($ln.align)") { 'center'{$out.AddRange($CTR)} 'right'{$out.AddRange($RIGHT)} default{$out.AddRange($LEFT)} }
            if (($ln.size -as [int]) -ge 2) { $out.AddRange($SZ2) } else { $out.AddRange($SZ1) }
            if ($ln.bold -eq $true) { $out.AddRange($BON) } else { $out.AddRange($BOFF) }
            $out.AddRange([System.Text.Encoding]::UTF8.GetBytes(if ($ln.text) { "$($ln.text)" } else { '' }))
            $out.Add($LF)
        }
        $out.AddRange($LEFT); $out.AddRange($SZ1); $out.AddRange($BOFF)
        [WinSpool]::SendRaw($printerName, $out.ToArray())
        Write-Log 'INFO' "Receipt printed OK on $printerName"
        return @{ ok = $true; message = 'ok' }
    } catch {
        $msg = $_.Exception.Message; Write-Log 'ERROR' "print_receipt: $msg"
        return @{ ok = $false; message = $msg }
    }
}

function Send-JsonResponse {
    param($Context, [int]$StatusCode, $Body)
    $json = ConvertTo-Json $Body -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $res = $Context.Response
    $res.StatusCode = $StatusCode; $res.ContentType = 'application/json'; $res.ContentLength64 = $bytes.LongLength
    $res.Headers.Add('Access-Control-Allow-Origin','*')
    $res.Headers.Add('Access-Control-Allow-Methods','GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers','Content-Type')
    $res.OutputStream.Write($bytes,0,$bytes.Length); $res.OutputStream.Close()
}

Write-Log 'INFO' ('='*55)
Write-Log 'INFO' 'Goldfish POS Cash Drawer Bridge  (PowerShell — no Python needed)'
Write-Log 'INFO' "Port : $Port  |  Log : $LogFile"
Write-Log 'INFO' ('='*55)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
    $listener.Start()
    Write-Log 'INFO' "Listening on http://127.0.0.1:$Port/"
} catch {
    Write-Log 'ERROR' "Cannot start listener on port $Port`: $($_.Exception.Message)"
    Write-Log 'ERROR' 'Re-run run_installer.bat as Administrator to fix the URL reservation.'
    exit 1
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext(); $req = $ctx.Request
        $method = $req.HttpMethod; $path = $req.Url.AbsolutePath
        if ($method -eq 'OPTIONS') {
            $ctx.Response.StatusCode = 204
            $ctx.Response.Headers.Add('Access-Control-Allow-Origin','*')
            $ctx.Response.Headers.Add('Access-Control-Allow-Methods','GET, POST, OPTIONS')
            $ctx.Response.Headers.Add('Access-Control-Allow-Headers','Content-Type')
            $ctx.Response.OutputStream.Close(); continue
        }
        if     ($method -eq 'GET'  -and $path -eq '/status')       { Send-JsonResponse $ctx 200 @{ ok=$true; service='Goldfish POS Cash Drawer Bridge'; port=$Port; log=$LogFile } }
        elseif ($method -eq 'GET'  -and $path -eq '/printers')     { Send-JsonResponse $ctx 200 (Get-PrinterList) }
        elseif ($method -eq 'POST' -and $path -eq '/open-drawer')  { $r=Invoke-OpenDrawer; Send-JsonResponse $ctx (if($r.ok){200}else{500}) $r }
        elseif ($method -eq 'POST' -and $path -eq '/print') {
            try {
                $data = ([System.IO.StreamReader]::new($req.InputStream,[System.Text.Encoding]::UTF8)).ReadToEnd() | ConvertFrom-Json
                $r = Invoke-PrintReceipt $data; Send-JsonResponse $ctx (if($r.ok){200}else{500}) $r
            } catch { $ctx.Response.StatusCode=400; $ctx.Response.OutputStream.Close() }
        }
        else { $ctx.Response.StatusCode=404; $ctx.Response.OutputStream.Close() }
    }
} catch { Write-Log 'ERROR' "Fatal: $($_.Exception.Message)"
} finally { $listener.Stop(); Write-Log 'INFO' 'Bridge stopped.' }
''';

  // ── PowerShell installer (no Python lookup at all) ────────────────────────
  const installer = r'''
#Requires -Version 5.1
<#
  Goldfish POS — Cash Drawer Bridge Installer
  No Python needed. Uses built-in Windows PowerShell only.
  Safe to re-run — updates the existing setup automatically.
#>

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$TaskName   = 'GoldfishPOS_CashDrawerBridge'
$AppDir     = "$env:APPDATA\GoldfishPOS"
$BridgeName = 'cash_drawer_bridge.ps1'
$BridgeSrc  = Join-Path $PSScriptRoot $BridgeName
$BridgeDest = Join-Path $AppDir $BridgeName
$LogDest    = Join-Path $AppDir 'bridge.log'

function Write-Step { param($m) Write-Host "  >> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  !!  $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "`n  ERROR: $m`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host '  Goldfish POS  Cash Drawer Bridge Installer     ' -ForegroundColor Cyan
Write-Host '  No Python needed  (PowerShell built-in only)   ' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ''

# 1. Copy bridge
Write-Step "Installing bridge to: $AppDir"
if (-not (Test-Path $BridgeSrc)) {
    Write-Err "$BridgeName not found next to this installer.`nMake sure both files are in the same folder."
}
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item $BridgeSrc $BridgeDest -Force
Write-Ok "Bridge: $BridgeDest"

# 2. Reserve HTTP namespace (allows non-admin bridge to use HttpListener)
Write-Step 'Reserving HTTP namespace for port 8765...'
netsh http delete urlacl url='http://127.0.0.1:8765/' 2>&1 | Out-Null
$r = netsh http add urlacl url='http://127.0.0.1:8765/' user="$env:USERDOMAIN\$env:USERNAME" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Warn "URL reservation skipped (non-critical): $r" }
else { Write-Ok "HTTP namespace reserved for $env:USERNAME" }

# 3. Register startup task
Write-Step 'Registering Windows startup task...'
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
$action    = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BridgeDest`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Ok "Task '$TaskName' registered (runs at every logon)."

# 4. Kill old bridge + start fresh
Write-Step 'Starting the bridge...'
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
if (Test-Path $LogDest) { Clear-Content $LogDest }
Start-Process -FilePath 'PowerShell.exe' -ArgumentList "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BridgeDest`"" -WindowStyle Hidden
Start-Sleep -Seconds 5

# 5. Verify
Write-Step 'Verifying bridge at http://127.0.0.1:8765/status ...'
$ok = $false
for ($i = 0; $i -lt 5; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8765/status' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { $ok = $true; break }
    } catch {}
    Write-Host "    attempt $($i+1)/5 — waiting..."
    Start-Sleep -Seconds 2
}

Write-Host ''
if ($ok) {
    Write-Host '=================================================' -ForegroundColor Green
    Write-Host '  SUCCESS!  Bridge is running.                   ' -ForegroundColor Green
    Write-Host '  Go back to the POS app and click Refresh.      ' -ForegroundColor Green
    Write-Host '=================================================' -ForegroundColor Green
} else {
    Write-Warn 'Bridge did not respond. Log output:'
    if (Test-Path $LogDest) {
        $ls = Get-Content $LogDest
        if ($ls) { $ls | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" } }
        else { Write-Host '    (log is empty — bridge may have crashed at startup)' }
    } else { Write-Host "    No log found at: $LogDest" }
    Write-Host ''
    Write-Warn 'Run  run_bridge_debug.bat  to see the error in real time.'
    Write-Warn 'Common fix: re-run this installer as Administrator.'
}
Write-Host ''
Read-Host 'Press Enter to close'
''';

  const debugBat = '''@echo off
echo Goldfish POS Cash Drawer Bridge - Debug Mode
echo =============================================
echo Errors will be shown here. Press Ctrl+C to stop.
echo.
set PSFILE=%APPDATA%\\GoldfishPOS\\cash_drawer_bridge.ps1
if not exist "%PSFILE%" (
    if exist "%~dp0cash_drawer_bridge.ps1" (
        set PSFILE=%~dp0cash_drawer_bridge.ps1
    ) else (
        echo ERROR: cash_drawer_bridge.ps1 not found.
        echo Run the installer first, or place cash_drawer_bridge.ps1 here.
        pause
        exit /b 1
    )
)
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
echo.
echo Bridge stopped. Press any key to close.
pause >nul
''';

  const runInstallerBat =
      '@echo off\r\n'
      'echo Goldfish POS Cash Drawer Bridge Installer\r\n'
      'echo ==========================================\r\n'
      'PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_bridge_service.ps1"\r\n'
      'if %ERRORLEVEL% NEQ 0 pause\r\n';

  downloadTextFile('cash_drawer_bridge.ps1', bridgeScript);
  downloadTextFile('install_bridge_service.ps1', installer);
  downloadTextFile('run_bridge_debug.bat', debugBat);
  downloadTextFile('run_installer.bat', runInstallerBat);
}
