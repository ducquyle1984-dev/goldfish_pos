import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:goldfish_pos/models/cash_drawer_settings_model.dart';
import 'package:goldfish_pos/services/cash_drawer_platform.dart';
import 'package:http/http.dart' as http;

/// High-level service for cash drawer operations.
///
/// Supports two connection modes (set in Admin → Cash Drawer):
///
/// **Local Bridge** (recommended for USB printers / web app):
///   A small Python script runs on the POS PC and listens on localhost.
///   The app calls `http://localhost:<bridgePort>/open-drawer` and the bridge
///   forwards the ESC/POS kick command to the USB printer via the Windows
///   print spooler. Works from both the web browser and native builds.
///
/// **TCP Network**:
///   Sends an ESC/POS kick command directly over a raw TCP socket to a
///   network-connected printer. Not available on web.
class CashDrawerService {
  static const _docPath = 'settings/cashDrawer';

  final FirebaseFirestore _db;

  CashDrawerService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  // ── Settings ────────────────────────────────────────────────────────────

  Future<CashDrawerSettings> loadSettings() async {
    final doc = await _db.doc(_docPath).get();
    if (!doc.exists) return const CashDrawerSettings();
    return CashDrawerSettings.fromFirestore(doc);
  }

  Stream<CashDrawerSettings> watchSettings() {
    return _db
        .doc(_docPath)
        .snapshots()
        .map(
          (doc) => doc.exists
              ? CashDrawerSettings.fromFirestore(doc)
              : const CashDrawerSettings(),
        );
  }

  Future<void> saveSettings(CashDrawerSettings settings) async {
    await _db
        .doc(_docPath)
        .set(settings.toFirestore(), SetOptions(merge: true));
  }

  // ── Open drawer ─────────────────────────────────────────────────────────

  /// Attempt to open the cash drawer using the configured mode.
  Future<CashDrawerResult> openDrawer() async {
    final settings = await loadSettings();
    return _open(settings);
  }

  /// Open the drawer only if enabled AND [openOnCashPayment] is set.
  Future<CashDrawerResult> openDrawerOnCashPayment() async {
    final settings = await loadSettings();
    if (!settings.openOnCashPayment) return CashDrawerResult.disabled;
    return _open(settings);
  }

  Future<CashDrawerResult> _open(CashDrawerSettings settings) async {
    if (!settings.enabled) return CashDrawerResult.disabled;

    switch (settings.connectionMode) {
      case CashDrawerConnectionMode.localBridge:
        return _openViaBridge(settings.bridgePort);

      case CashDrawerConnectionMode.tcpNetwork:
        if (kIsWeb) return CashDrawerResult.webNotSupported;
        if (settings.host.isEmpty) return CashDrawerResult.notConfigured;
        final ok = await openCashDrawerNetwork(settings.host, settings.port);
        return ok
            ? CashDrawerResult.success
            : CashDrawerResult.connectionFailed;
    }
  }

  /// Send an open-drawer request to the local bridge script.
  Future<CashDrawerResult> _openViaBridge(int bridgePort) async {
    try {
      final uri = Uri.parse('http://localhost:$bridgePort/open-drawer');
      final response = await http.post(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) return CashDrawerResult.success;
      return CashDrawerResult.connectionFailed;
    } catch (_) {
      return CashDrawerResult.bridgeNotRunning;
    }
  }
}

/// Describes the outcome of an open-drawer call.
enum CashDrawerResult {
  /// The command was sent successfully.
  success,

  /// Cash drawer integration is disabled in settings.
  disabled,

  /// Host/IP has not been configured (TCP mode).
  notConfigured,

  /// Could not reach the printer (TCP mode).
  connectionFailed,

  /// TCP mode is not supported in the web version.
  webNotSupported,

  /// Local bridge mode: the bridge script is not running on this PC.
  bridgeNotRunning,
}
