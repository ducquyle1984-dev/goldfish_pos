import 'package:flutter/material.dart';

import '../models/business_settings_model.dart';
import '../models/cash_drawer_settings_model.dart';
import '../models/transaction_model.dart';
import '../repositories/pos_repository.dart';
import '../services/receipt_service.dart';

/// Dialog shown after a transaction is fully paid.
///
/// Left panel: scrollable receipt preview.
/// Right panel: print-copy selector (Customer / Merchant / Technician / None)
///              and a Print button.
class ReceiptPrintDialog extends StatefulWidget {
  const ReceiptPrintDialog({super.key, required this.transaction});

  final Transaction transaction;

  @override
  State<ReceiptPrintDialog> createState() => _ReceiptPrintDialogState();
}

class _ReceiptPrintDialogState extends State<ReceiptPrintDialog> {
  final _repo = PosRepository();
  final _receiptSvc = ReceiptService();

  BusinessSettings _biz = const BusinessSettings();
  CashDrawerSettings _drawer = const CashDrawerSettings();

  bool _loading = true;
  bool _printing = false;
  ReceiptCopy _selectedCopy = ReceiptCopy.customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repo.getBusinessSettings(),
      _repo.getCashDrawerSettings(),
    ]);
    if (!mounted) return;
    setState(() {
      _biz = results[0] as BusinessSettings;
      _drawer = results[1] as CashDrawerSettings;
      _loading = false;
    });
  }

  /// Returns a deduplicated list of technician names in the transaction.
  List<String> get _technicians {
    final seen = <String>{};
    return widget.transaction.items
        .map((i) => i.employeeName)
        .where((n) => seen.add(n))
        .toList();
  }

  String _previewText() {
    if (_loading) return 'Loading…';
    return _receiptSvc.buildPreviewText(
      tx: widget.transaction,
      biz: _biz,
      copy: _selectedCopy,
      technicianName:
          _selectedCopy == ReceiptCopy.technician && _technicians.isNotEmpty
          ? _technicians.first
          : null,
    );
  }

  Future<void> _print() async {
    if (_selectedCopy == ReceiptCopy.none) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _printing = true);

    try {
      String? error;

      if (_selectedCopy == ReceiptCopy.technician) {
        // Print one receipt per technician
        for (final tech in _technicians) {
          final lines = _receiptSvc.buildLines(
            tx: widget.transaction,
            biz: _biz,
            copy: ReceiptCopy.technician,
            technicianName: tech,
          );
          error = await _receiptSvc.printViaSettings(
            settings: _drawer,
            lines: lines,
          );
          if (error != null) break;
        }
      } else if (_selectedCopy == ReceiptCopy.both) {
        // Print customer copy then merchant copy
        for (final copy in [ReceiptCopy.customer, ReceiptCopy.merchant]) {
          final lines = _receiptSvc.buildLines(
            tx: widget.transaction,
            biz: _biz,
            copy: copy,
          );
          error = await _receiptSvc.printViaSettings(
            settings: _drawer,
            lines: lines,
          );
          if (error != null) break;
        }
      } else {
        final lines = _receiptSvc.buildLines(
          tx: widget.transaction,
          biz: _biz,
          copy: _selectedCopy,
        );
        error = await _receiptSvc.printViaSettings(
          settings: _drawer,
          lines: lines,
        );
      }

      if (!mounted) return;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        final label = _selectedCopy == ReceiptCopy.technician
            ? '${_technicians.length} technician receipt(s)'
            : _selectedCopy == ReceiptCopy.both
                ? 'customer & merchant receipts'
                : '${_selectedCopy.name} receipt';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent $label to printer.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Title bar ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'Receipt – Print Options',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close without printing',
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Preview panel ──────────────────────────────
                        Expanded(
                          flex: 3,
                          child: Container(
                            color: theme.colorScheme.surfaceContainerLowest,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    6,
                                  ),
                                  child: Text(
                                    'Preview',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: SelectableText(
                                        _previewText(),
                                        style: const TextStyle(
                                          fontFamily: 'Courier New',
                                          fontSize: 14,
                                          height: 1.5,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),

                        const VerticalDivider(width: 1),

                        // ── Options panel ──────────────────────────────
                        SizedBox(
                          width: 220,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Print For',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Radio options
                                ..._buildRadioOptions(theme),

                                const Spacer(),

                                // Bridge mode note
                                if (!_drawer.enabled ||
                                    _drawer.connectionMode !=
                                        CashDrawerConnectionMode.localBridge)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      _drawer.enabled
                                          ? 'Receipt printing requires Local Bridge mode.\n'
                                                'Change in Admin → Cash Drawer.'
                                          : 'Cash drawer is disabled.\n'
                                                'Enable it in Admin → Cash Drawer to print.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.orange),
                                    ),
                                  ),

                                // Print button
                                FilledButton.icon(
                                  icon: _printing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          _selectedCopy == ReceiptCopy.none
                                              ? Icons.close
                                              : Icons.print,
                                        ),
                                  label: Text(
                                    _printing
                                        ? 'Printing…'
                                        : _selectedCopy == ReceiptCopy.none
                                        ? 'Close'
                                        : 'Print',
                                  ),
                                  onPressed: _printing ? null : _print,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRadioOptions(ThemeData theme) {
    final options = <_CopyOption>[
      _CopyOption(
        value: ReceiptCopy.customer,
        label: 'Customer',
        icon: Icons.person_outline,
        subtitle: 'Customer copy',
      ),
      _CopyOption(
        value: ReceiptCopy.merchant,
        label: 'Merchant',
        icon: Icons.store_outlined,
        subtitle: 'Merchant record',
      ),
      _CopyOption(
        value: ReceiptCopy.both,
        label: 'Both',
        icon: Icons.copy_all_outlined,
        subtitle: 'Customer & merchant copies',
      ),
      _CopyOption(
        value: ReceiptCopy.technician,
        label: 'Technician',
        icon: Icons.badge_outlined,
        subtitle: _technicians.length > 1
            ? '${_technicians.length} copies'
            : 'One copy',
      ),
      _CopyOption(
        value: ReceiptCopy.none,
        label: 'None',
        icon: Icons.not_interested_outlined,
        subtitle: 'Do not print',
      ),
    ];

    return options
        .map(
          (opt) => InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _selectedCopy = opt.value),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _selectedCopy == opt.value
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                border: Border.all(
                  color: _selectedCopy == opt.value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    opt.icon,
                    size: 20,
                    color: _selectedCopy == opt.value
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: _selectedCopy == opt.value
                                ? FontWeight.bold
                                : null,
                            color: _selectedCopy == opt.value
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        Text(
                          opt.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedCopy == opt.value)
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }
}

class _CopyOption {
  const _CopyOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.subtitle,
  });
  final ReceiptCopy value;
  final String label;
  final IconData icon;
  final String subtitle;
}
