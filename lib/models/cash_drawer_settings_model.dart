import 'package:cloud_firestore/cloud_firestore.dart';

/// How the POS communicates with the cash drawer.
enum CashDrawerConnectionMode {
  /// Send ESC/POS kick over a raw TCP socket to a **network-connected** printer.
  /// Not available on web.
  tcpNetwork,

  /// Send an HTTP request to a small bridge script running on **localhost**.
  /// Works from both web and native apps; the bridge forwards the command to
  /// any USB (or network) printer visible to the host PC.
  localBridge,
}

/// Stores the cash-drawer configuration in Firestore (`settings/cashDrawer`).
class CashDrawerSettings {
  /// Whether the cash drawer integration is enabled.
  final bool enabled;

  /// How the POS reaches the printer/drawer.
  final CashDrawerConnectionMode connectionMode;

  // ── TCP Network mode ──────────────────────────────────────────────────────
  /// Hostname or IP of the network printer (TCP mode only).
  final String host;

  /// TCP port (default 9100 for ESC/POS printers).
  final int port;

  // ── Local Bridge mode ─────────────────────────────────────────────────────
  /// Port that the bridge script listens on (default 8765).
  final int bridgePort;

  /// Windows printer name as shown in Control Panel → Devices and Printers.
  /// Leave blank to use the Windows default printer.
  final String printerName;

  /// Automatically open the drawer when a cash payment is processed.
  final bool openOnCashPayment;

  const CashDrawerSettings({
    this.enabled = false,
    this.connectionMode = CashDrawerConnectionMode.localBridge,
    this.host = '',
    this.port = 9100,
    this.bridgePort = 8765,
    this.printerName = '',
    this.openOnCashPayment = true,
  });

  CashDrawerSettings copyWith({
    bool? enabled,
    CashDrawerConnectionMode? connectionMode,
    String? host,
    int? port,
    int? bridgePort,
    String? printerName,
    bool? openOnCashPayment,
  }) {
    return CashDrawerSettings(
      enabled: enabled ?? this.enabled,
      connectionMode: connectionMode ?? this.connectionMode,
      host: host ?? this.host,
      port: port ?? this.port,
      bridgePort: bridgePort ?? this.bridgePort,
      printerName: printerName ?? this.printerName,
      openOnCashPayment: openOnCashPayment ?? this.openOnCashPayment,
    );
  }

  static CashDrawerConnectionMode _parseMode(String? v) {
    if (v == 'tcpNetwork') return CashDrawerConnectionMode.tcpNetwork;
    return CashDrawerConnectionMode.localBridge;
  }

  factory CashDrawerSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CashDrawerSettings(
      enabled: data['enabled'] as bool? ?? false,
      connectionMode: _parseMode(data['connectionMode'] as String?),
      host: data['host'] as String? ?? '',
      port: (data['port'] as num?)?.toInt() ?? 9100,
      bridgePort: (data['bridgePort'] as num?)?.toInt() ?? 8765,
      printerName: data['printerName'] as String? ?? '',
      openOnCashPayment: data['openOnCashPayment'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'enabled': enabled,
    'connectionMode': connectionMode == CashDrawerConnectionMode.tcpNetwork
        ? 'tcpNetwork'
        : 'localBridge',
    'host': host,
    'port': port,
    'bridgePort': bridgePort,
    'printerName': printerName,
    'openOnCashPayment': openOnCashPayment,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
