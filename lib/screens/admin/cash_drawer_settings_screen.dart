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
  // ── Python bridge (uses only standard library — no pip / no pywin32) ──────
  // Raw Dart string: backslashes are literal, $ is not interpolated.
  const bridgeScript = r'''
#!/usr/bin/env python3
"""
cash_drawer_bridge.py  —  Goldfish POS Cash Drawer Bridge
==========================================================
Uses ONLY Python standard library (ctypes + subprocess).
NO pip install needed. Works on any Python 3.6+.

Log: %APPDATA%\GoldfishPOS\bridge.log
"""
import sys, json, os, socket, logging, ctypes, ctypes.wintypes as wt, subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

PREFERRED_PORT = 8765
PRINTER_NAME   = ""   # blank = Windows default printer
KICK_COMMAND   = bytes([0x1B, 0x70, 0x00, 0x19, 0xFA])
_CREATE_NO_WND = 0x08000000


def _find_free_port(preferred):
    for p in [preferred] + [x for x in range(8765, 8780) if x != preferred]:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', p)); return p
        except OSError:
            pass
    return preferred


_app_dir  = os.path.join(os.environ.get('APPDATA', os.path.dirname(os.path.abspath(__file__))), 'GoldfishPOS')
_log_path = os.path.join(_app_dir, 'bridge.log')
os.makedirs(_app_dir, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s  %(levelname)-7s  %(message)s',
    handlers=[
        logging.FileHandler(_log_path, encoding='utf-8'),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger('bridge')

PORT = _find_free_port(PREFERRED_PORT)
if PORT != PREFERRED_PORT:
    log.warning('Port %d in use; using %d instead.', PREFERRED_PORT, PORT)

_winspool = ctypes.WinDLL('winspool.drv', use_last_error=True)


class _DocInfo1(ctypes.Structure):
    _fields_ = [('pDocName', wt.LPCWSTR), ('pOutputFile', wt.LPCWSTR), ('pDatatype', wt.LPCWSTR)]


def _get_default_printer():
    size = wt.DWORD(0)
    _winspool.GetDefaultPrinterW(None, ctypes.byref(size))
    if size.value == 0:
        raise RuntimeError('No default printer set. Go to Windows Settings -> Printers & scanners.')
    buf = ctypes.create_unicode_buffer(size.value)
    if not _winspool.GetDefaultPrinterW(buf, ctypes.byref(size)):
        raise RuntimeError(f'GetDefaultPrinterW failed (error {ctypes.get_last_error()})')
    return buf.value


def _send_raw(printer_name, data):
    handle = wt.HANDLE()
    if not _winspool.OpenPrinterW(printer_name, ctypes.byref(handle), None):
        raise RuntimeError(
            f'OpenPrinter("{printer_name}") failed — error {ctypes.get_last_error()}. '
            f'Is the printer installed and the name spelled correctly?'
        )
    try:
        doc = _DocInfo1(pDocName='GoldfishPOS', pOutputFile=None, pDatatype='RAW')
        job = _winspool.StartDocPrinterW(handle, 1, ctypes.byref(doc))
        if job == 0:
            raise RuntimeError(f'StartDocPrinter failed — error {ctypes.get_last_error()}')
        try:
            _winspool.StartPagePrinter(handle)
            buf = (ctypes.c_char * len(data))(*data)
            written = wt.DWORD(0)
            _winspool.WritePrinter(handle, buf, wt.DWORD(len(data)), ctypes.byref(written))
            _winspool.EndPagePrinter(handle)
        finally:
            _winspool.EndDocPrinter(handle)
    finally:
        _winspool.ClosePrinter(handle)


def open_drawer():
    try:
        printer = PRINTER_NAME or _get_default_printer()
        log.info('Opening drawer — printer: %s', printer)
        _send_raw(printer, KICK_COMMAND)
        log.info('Drawer opened OK.')
        return True, 'ok'
    except Exception as e:
        log.error('open_drawer: %s', e)
        return False, str(e)


def get_printers():
    try:
        r = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command',
             'Get-Printer | Select-Object -ExpandProperty Name'],
            capture_output=True, text=True, timeout=10, creationflags=_CREATE_NO_WND,
        )
        return [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    except Exception as e:
        log.error('get_printers: %s', e)
        return []


def print_receipt(data):
    try:
        printer_name = data.get('printer') or PRINTER_NAME or _get_default_printer()
        ESC = 0x1B; GS = 0x1D; LF = bytes([0x0A])
        INIT  = bytes([ESC, 0x40]);  LEFT  = bytes([ESC, 0x61, 0x00])
        CTR   = bytes([ESC, 0x61, 0x01]); RIGHT = bytes([ESC, 0x61, 0x02])
        BON   = bytes([ESC, 0x45, 0x01]); BOFF  = bytes([ESC, 0x45, 0x00])
        SZ1   = bytes([GS, 0x21, 0x00]);  SZ2   = bytes([GS, 0x21, 0x11])
        CUT   = bytes([GS, 0x56, 0x41, 0x00])
        SEP   = ('-' * 42).encode('ascii') + LF
        out   = bytearray(INIT)
        for line in data.get('lines', []):
            if line.get('cut'):       out += CUT; continue
            if line.get('separator'): out += LEFT + SZ1 + BOFF + SEP; continue
            a = line.get('align', 'left')
            out += CTR if a == 'center' else (RIGHT if a == 'right' else LEFT)
            out += SZ2 if line.get('size', 1) >= 2 else SZ1
            out += BON if line.get('bold') else BOFF
            out += line.get('text', '').encode('utf-8', errors='replace') + LF
        out += LEFT + SZ1 + BOFF
        _send_raw(printer_name, bytes(out))
        log.info('Receipt printed OK on %s', printer_name)
        return True, 'ok'
    except Exception as e:
        log.error('print_receipt: %s', e)
        return False, str(e)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *a): log.debug(fmt, *a)
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()
    def _json(self, code, body_dict):
        body = json.dumps(body_dict).encode()
        self.send_response(code); self._cors()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if self.path == '/status':
            self._json(200, {'ok': True, 'service': 'Goldfish POS Cash Drawer Bridge', 'port': PORT, 'log': _log_path})
        elif self.path == '/printers':
            self._json(200, {'ok': True, 'printers': get_printers()})
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path == '/open-drawer':
            ok, msg = open_drawer()
            self._json(200 if ok else 500, {'ok': ok, 'message': msg})
        elif self.path == '/print':
            length = int(self.headers.get('Content-Length', 0))
            try: data = json.loads(self.rfile.read(length))
            except Exception: self.send_response(400); self.end_headers(); return
            ok, msg = print_receipt(data)
            self._json(200 if ok else 500, {'ok': ok, 'message': msg})
        else:
            self.send_response(404); self.end_headers()


if __name__ == '__main__':
    log.info('=' * 55)
    log.info('Goldfish POS Cash Drawer Bridge  (ctypes — no pip needed)')
    log.info('Port : %d  |  Log : %s', PORT, _log_path)
    log.info('=' * 55)
    try:
        HTTPServer(('127.0.0.1', PORT), _Handler).serve_forever()
    except OSError as e:
        log.critical('Cannot bind port %d: %s', PORT, e); sys.exit(1)
    except KeyboardInterrupt:
        log.info('Stopped.'); sys.exit(0)
    except Exception as e:
        log.critical('Fatal: %s', e, exc_info=True); sys.exit(1)
''';

  // ── PowerShell installer (simplified — no pip, no pywin32) ───────────────
  final installer =
      """
#Requires -Version 5.1
<#
  Goldfish POS — Cash Drawer Bridge Installer
  No pip install needed. Requires Python 3.6+ from python.org.
  Safe to re-run — updates the existing setup.
#>
\$ErrorActionPreference = 'Stop'

# ── Elevate to Administrator (UAC prompt) ─────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '  Requesting administrator rights...' -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"\$PSCommandPath`"" -Wait
    exit
}

\$TaskName     = 'GoldfishPOS_CashDrawerBridge'
\$AppDir       = "\$env:APPDATA\\GoldfishPOS"
\$ScriptSrc    = Join-Path \$PSScriptRoot 'cash_drawer_bridge.py'
\$ScriptDest   = Join-Path \$AppDir 'cash_drawer_bridge.py'
\$LauncherDest = Join-Path \$AppDir 'run_bridge.bat'
\$LogDest      = Join-Path \$AppDir 'bridge.log'

function Write-Step { param(\$m) Write-Host "  >> \$m" -ForegroundColor Cyan }
function Write-Ok   { param(\$m) Write-Host "  OK  \$m" -ForegroundColor Green }
function Write-Warn { param(\$m) Write-Host "  !!  \$m" -ForegroundColor Yellow }
function Write-Err  { param(\$m) Write-Host "\`n  ERROR: \$m\`n" -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   Goldfish POS  Cash Drawer Bridge Installer     ' -ForegroundColor Cyan
Write-Host '   No pip install needed (standard library only)  ' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ''

# ── 1. Find Python ────────────────────────────────────────────────────────────
Write-Step 'Looking for Python 3...'
\$pythonExe = \$null
try { \$pythonExe = (Get-Command python.exe -ErrorAction Stop).Source } catch {}
if (-not \$pythonExe) {
    foreach (\$g in @(
        "\$env:LOCALAPPDATA\\Programs\\Python\\Python3*\\python.exe",
        'C:\\Python3*\\python.exe',
        'C:\\Program Files\\Python3*\\python.exe',
        'C:\\Program Files (x86)\\Python3*\\python.exe'
    )) {
        \$hit = Get-Item \$g -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if (\$hit) { \$pythonExe = \$hit.FullName; break }
    }
}
if (-not \$pythonExe) {
    Write-Err 'Python 3 not found.`nInstall from https://python.org  (check "Add Python to PATH")  then re-run.'
}
# Reject Microsoft Store Python — it is a stub shell that cannot run scripts reliably
if (\$pythonExe -like '*WindowsApps*') {
    Write-Err "Found Microsoft Store Python at:\`n  \$pythonExe\`n\`nThis version is NOT compatible.\`nPlease install Python from https://python.org (check Add to PATH), then re-run."
}
\$pyVer = & \$pythonExe --version 2>&1
Write-Ok "Python: \$pythonExe  (\$pyVer)"

# ── 2. Verify standard library modules ───────────────────────────────────────
Write-Step 'Verifying required modules (standard library only)...'
\$check = & \$pythonExe -c "import ctypes, ctypes.wintypes, subprocess, socket, json, logging; print('ok')" 2>&1
if ("\$check".Trim() -ne 'ok') {
    Write-Err "Standard library check failed:\`n\$check\`n\`nTry a fresh Python install from https://python.org"
}
Write-Ok 'All modules present — no pip install needed.'

# ── 3. Install files ──────────────────────────────────────────────────────────
Write-Step "Installing to: \$AppDir"
if (-not (Test-Path \$ScriptSrc)) {
    Write-Err "cash_drawer_bridge.py not found next to this installer.\`nMake sure both files are in the same folder."
}
New-Item -ItemType Directory -Force -Path \$AppDir | Out-Null
Copy-Item \$ScriptSrc \$ScriptDest -Force
Write-Ok "Script copied to: \$ScriptDest"

# Launcher .bat — redirects stdout+stderr to bridge.log
\$bat = "@echo off\`r\`n\`"\$pythonExe\`" \`"\$ScriptDest\`" >> \`"\$LogDest\`" 2>&1\`r\`n"
[System.IO.File]::WriteAllText(\$LauncherDest, \$bat, [System.Text.Encoding]::ASCII)
Write-Ok "Launcher: \$LauncherDest"

# ── 4. Register Windows startup task ─────────────────────────────────────────
Write-Step 'Registering Windows startup task...'
Unregister-ScheduledTask -TaskName \$TaskName -Confirm:\$false -ErrorAction SilentlyContinue | Out-Null
\$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"\$LauncherDest`""
\$trigger   = New-ScheduledTaskTrigger -AtLogOn -User \$env:USERNAME
\$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 10 \`
              -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
\$principal = New-ScheduledTaskPrincipal -UserId "\$env:USERDOMAIN\\\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName \$TaskName -Action \$action -Trigger \$trigger \`
    -Settings \$settings -Principal \$principal -Force | Out-Null
Write-Ok "Task '\$TaskName' registered (runs at every logon)."

# ── 5. Kill old instance + start fresh ───────────────────────────────────────
Write-Step 'Starting the bridge...'
Get-CimInstance Win32_Process -Filter "Name LIKE 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { \$_.CommandLine -like '*cash_drawer_bridge*' } |
    ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
if (Test-Path \$LogDest) { Clear-Content \$LogDest }
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"\$LauncherDest`"" -WindowStyle Hidden
Start-Sleep -Seconds 4

# ── 6. Verify ─────────────────────────────────────────────────────────────────
Write-Step 'Checking http://127.0.0.1:$port/status ...'
\$ok = \$false
for (\$i = 0; \$i -lt 5; \$i++) {
    try {
        \$r = Invoke-WebRequest -Uri 'http://127.0.0.1:$port/status' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if (\$r.StatusCode -eq 200) { \$ok = \$true; break }
    } catch {}
    Write-Host "    attempt \$(\$i+1)/5 — waiting..."
    Start-Sleep -Seconds 2
}

Write-Host ''
if (\$ok) {
    Write-Host '==================================================' -ForegroundColor Green
    Write-Host '  SUCCESS!  Bridge is running.                    ' -ForegroundColor Green
    Write-Host '  Go back to the POS app and click Refresh.       ' -ForegroundColor Green
    Write-Host '==================================================' -ForegroundColor Green
} else {
    Write-Warn 'Bridge did not respond. Last log output:'
    Write-Host ''
    if (Test-Path \$LogDest) {
        \$lines = Get-Content \$LogDest
        if (\$lines) { \$lines | Select-Object -Last 30 | ForEach-Object { Write-Host "    \$_" }
        } else { Write-Host '    (log file is empty — Python may have crashed before writing anything)' }
    } else {
        Write-Host '    No log file found.'
        Write-Host "    Launcher: \$LauncherDest"
        Write-Host "    Python:   \$pythonExe"
    }
    Write-Host ''
    Write-Warn 'Run  run_bridge_debug.bat  (from the Download folder) to see the error live.'
}
Write-Host ''
Read-Host 'Press Enter to close'
""";

  final debugBat = '''@echo off
echo Goldfish POS Cash Drawer Bridge - Debug Mode
echo =============================================
echo Errors will be shown here. Press Ctrl+C to stop.
echo.
set PYFILE=%APPDATA%\\GoldfishPOS\\cash_drawer_bridge.py
if not exist "%PYFILE%" (
    if exist "%~dp0cash_drawer_bridge.py" (
        echo Using cash_drawer_bridge.py from this folder.
        echo.
        set PYFILE=%~dp0cash_drawer_bridge.py
    ) else (
        echo ERROR: cash_drawer_bridge.py not found.
        echo.
        echo Run install_bridge_service.ps1 first, or place
        echo cash_drawer_bridge.py in the same folder as this bat.
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

  downloadTextFile('cash_drawer_bridge.py', bridgeScript);
  downloadTextFile('install_bridge_service.ps1', installer);
  downloadTextFile('run_bridge_debug.bat', debugBat);
  downloadTextFile('run_installer.bat', runInstallerBat);
}
