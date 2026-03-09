import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/business_settings_model.dart';
import '../models/cash_drawer_settings_model.dart';
import '../models/customer_model.dart';
import '../models/transaction_model.dart';

/// Which variant of the receipt to print.
enum ReceiptCopy { customer, merchant, technician, none }

/// Service responsible for formatting and printing receipts via the
/// local bridge helper app (`cash_drawer_bridge.py`).
///
/// The bridge runs on `http://127.0.0.1:<PORT>` and accepts
/// `POST /print` with a JSON body describing the receipt lines.
class ReceiptService {
  static const int _lineWidth = 42; // chars for an 80mm thermal printer

  // ── Formatting helpers ───────────────────────────────────────────────────

  /// Pads [left] and [right] to fill exactly [_lineWidth] chars.
  static String _twoCol(String left, String right, {int width = _lineWidth}) {
    final spaces = width - left.length - right.length;
    if (spaces <= 0) return '$left $right';
    return '$left${' ' * spaces}$right';
  }

  static Map<String, dynamic> _line(
    String text, {
    String align = 'left',
    bool bold = false,
    int size = 1,
  }) => {'text': text, 'align': align, 'bold': bold, 'size': size};

  static Map<String, dynamic> _blank() => {'text': '', 'align': 'left'};
  static Map<String, dynamic> _sep() => {'separator': true};
  static Map<String, dynamic> _cut() => {'cut': true};

  // ── Receipt building ─────────────────────────────────────────────────────

  /// Builds the ESC/POS line list for [copy] type.
  ///
  /// [technicianName] is only relevant when [copy] == [ReceiptCopy.technician].
  /// Pass `null` (or omit) to print a combined copy with all technicians.
  List<Map<String, dynamic>> buildLines({
    required Transaction tx,
    required BusinessSettings biz,
    required ReceiptCopy copy,
    String? technicianName,
    Customer? customer,
  }) {
    final lines = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final dateFmt = DateFormat('MMM dd, yyyy');
    final timeFmt = DateFormat('hh:mm a');

    // ── Salon header ─────────────────────────────────────────────────────
    lines.add(_line(biz.salonName, align: 'center', bold: true, size: 2));
    for (final addrLine in biz.address.split('\n')) {
      if (addrLine.trim().isNotEmpty) {
        lines.add(_line(addrLine.trim(), align: 'center'));
      }
    }
    if (biz.phone.isNotEmpty) {
      lines.add(_line('Tel: ${biz.phone}', align: 'center'));
    }
    lines.add(_blank());

    // ── Copy label ───────────────────────────────────────────────────────
    switch (copy) {
      case ReceiptCopy.customer:
        lines.add(_line('CUSTOMER COPY', align: 'center', bold: true));
      case ReceiptCopy.merchant:
        lines.add(_line('** MERCHANT COPY **', align: 'center', bold: true));
      case ReceiptCopy.technician:
        lines.add(_line('** TECHNICIAN COPY **', align: 'center', bold: true));
        if (technicianName != null && technicianName.isNotEmpty) {
          lines.add(_line(technicianName, align: 'center'));
        }
      case ReceiptCopy.none:
        break;
    }

    lines.add(_sep());

    // ── Transaction meta ─────────────────────────────────────────────────
    final receiptNum = tx.dailyNumber > 0
        ? '#${tx.dailyNumber.toString().padLeft(4, '0')}'
        : tx.id.substring(0, tx.id.length.clamp(0, 8));
    lines.add(_line('Receipt #:  $receiptNum'));
    lines.add(
      _line('Printed:    ${timeFmt.format(now)} ${dateFmt.format(now)}'),
    );
    lines.add(
      _line(
        'TX #:       ${tx.id.length > 10 ? tx.id.substring(0, 10) : tx.id}',
      ),
    );

    final custName = tx.customerName ?? customer?.name ?? '';
    if (custName.isNotEmpty) {
      lines.add(_line('Customer:   $custName'));
    }
    lines.add(_line('Date:       ${dateFmt.format(tx.createdAt)}'));

    lines.add(_sep());

    // ── Services by technician ───────────────────────────────────────────
    final byEmployee = <String, List<TransactionItem>>{};
    for (final item in tx.items) {
      byEmployee.putIfAbsent(item.employeeName, () => []).add(item);
    }

    if (copy == ReceiptCopy.technician && technicianName != null) {
      // Only this technician's items
      final items = byEmployee[technicianName] ?? [];
      for (final item in items) {
        final price = '\$${item.subtotal.toStringAsFixed(2)}';
        final maxName = _lineWidth - price.length - 2;
        final name = item.itemName.length > maxName
            ? item.itemName.substring(0, maxName)
            : item.itemName;
        lines.add(_line('  ${name.padRight(maxName)}$price'));
        if (item.quantity > 1) {
          lines.add(
            _line(
              '    x${item.quantity} @ \$${item.itemPrice.toStringAsFixed(2)}',
            ),
          );
        }
      }
    } else {
      // All technicians
      for (final entry in byEmployee.entries) {
        lines.add(_line('${entry.key}:', bold: true));
        for (final item in entry.value) {
          final price = '\$${item.subtotal.toStringAsFixed(2)}';
          final maxName = _lineWidth - price.length - 4;
          final name = item.itemName.length > maxName
              ? item.itemName.substring(0, maxName)
              : item.itemName;
          lines.add(_line('  ${name.padRight(maxName)}$price'));
          if (item.quantity > 1) {
            lines.add(
              _line(
                '    x${item.quantity} @ \$${item.itemPrice.toStringAsFixed(2)}',
              ),
            );
          }
        }
        lines.add(_blank());
      }
    }

    lines.add(_sep());

    // ── Totals ───────────────────────────────────────────────────────────
    lines.add(
      _line(_twoCol('Subtotal:', '\$${tx.subtotal.toStringAsFixed(2)}')),
    );
    if (tx.totalDiscount > 0) {
      lines.add(
        _line(
          _twoCol('Discount:', '-\$${tx.totalDiscount.toStringAsFixed(2)}'),
        ),
      );
    }
    if (tx.taxAmount > 0) {
      final taxLabel = '${biz.taxLabel}:';
      lines.add(
        _line(_twoCol(taxLabel, '\$${tx.taxAmount.toStringAsFixed(2)}')),
      );
    }

    // Gratuity = totalPaid − totalAmount (if meaningful)
    final gratuity = tx.totalPaid - tx.totalAmount;
    if (gratuity > 0.005) {
      lines.add(
        _line(
          _twoCol('Gratuity:', '\$${gratuity.toStringAsFixed(2)}'),
          bold: true,
        ),
      );
    }
    lines.add(
      _line(
        _twoCol('TOTAL:', '\$${tx.totalAmount.toStringAsFixed(2)}'),
        bold: true,
      ),
    );
    lines.add(_sep());

    // ── Payments ─────────────────────────────────────────────────────────
    for (final p in tx.payments) {
      lines.add(
        _line(
          _twoCol(
            '  ${p.paymentMethodName}:',
            '\$${p.amountPaid.toStringAsFixed(2)}',
          ),
        ),
      );
    }
    lines.add(_sep());

    // ── Customer / merchant signature block ──────────────────────────────
    if (copy == ReceiptCopy.customer || copy == ReceiptCopy.merchant) {
      lines.add(_blank());
      lines.add(_line('I agree to pay the listed amount,'));
      lines.add(_line('acknowledge receipt of the products'));
      lines.add(_line('and services provided today, and'));
      lines.add(_line('confirm that they were delivered to'));
      lines.add(_line('my full satisfaction.'));
      lines.add(_blank());
    }

    // ── Technician subtotal ──────────────────────────────────────────────
    if (copy == ReceiptCopy.technician && technicianName != null) {
      final items = byEmployee[technicianName] ?? [];
      final techSubtotal = items.fold<double>(0.0, (s, i) => s + i.subtotal);
      lines.add(_blank());
      lines.add(
        _line(
          _twoCol('Tech Subtotal:', '\$${techSubtotal.toStringAsFixed(2)}'),
          bold: true,
        ),
      );
      lines.add(_blank());
    }

    lines.add(_line('Thank you for visiting us!', align: 'center', bold: true));
    lines.add(_blank());
    lines.add(_blank());
    lines.add(_blank());
    lines.add(_cut());

    return lines;
  }

  /// Builds a plain-text preview of the receipt (for on-screen display).
  String buildPreviewText({
    required Transaction tx,
    required BusinessSettings biz,
    required ReceiptCopy copy,
    String? technicianName,
  }) {
    final lines = buildLines(
      tx: tx,
      biz: biz,
      copy: copy,
      technicianName: technicianName,
    );

    final buf = StringBuffer();
    for (final line in lines) {
      if (line['cut'] == true) {
        buf.writeln('- - - - - - - - - - - - - - - -');
        continue;
      }
      if (line['separator'] == true) {
        buf.writeln('-' * _lineWidth);
        continue;
      }
      final text = line['text'] as String? ?? '';
      final align = line['align'] as String? ?? 'left';
      if (align == 'center') {
        final pad = ((_lineWidth - text.length) / 2).floor();
        buf.writeln('${' ' * pad.clamp(0, _lineWidth)}$text');
      } else {
        buf.writeln(text);
      }
    }
    return buf.toString();
  }

  // ── Sending to bridge ────────────────────────────────────────────────────

  /// Sends a `POST /print` to the local bridge running on [settings].
  ///
  /// Returns `null` on success, or an error string on failure.
  Future<String?> printViaSettings({
    required CashDrawerSettings settings,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (!settings.enabled) return null; // silently skip if disabled
    if (settings.connectionMode != CashDrawerConnectionMode.localBridge) {
      return 'Receipt printing only supported in Local Bridge mode.';
    }

    final body = json.encode({'printer': settings.printerName, 'lines': lines});

    // Try the configured port first, then scan nearby ports in case the
    // bridge auto-selected a different port on this PC.
    final portsToTry = [
      settings.bridgePort,
      ...List.generate(
        10,
        (i) => 8765 + i,
      ).where((p) => p != settings.bridgePort),
    ];

    for (final port in portsToTry) {
      try {
        final response = await http
            .post(
              Uri.parse('http://127.0.0.1:$port/print'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(Duration(seconds: port == settings.bridgePort ? 8 : 1));

        if (response.statusCode == 200) return null; // success
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        return decoded['message']?.toString() ??
            'Bridge returned ${response.statusCode}';
      } catch (_) {
        // Port not responding — try next.
      }
    }

    return 'Could not reach the bridge helper on port '
        '${settings.bridgePort} or nearby ports.\n'
        'Go to Admin → Cash Drawer and tap Refresh (↻) '
        'to auto-detect the correct port.';
  }
}
