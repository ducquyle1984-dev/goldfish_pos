import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:goldfish_pos/models/gift_card_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class GiftCardManagementScreen extends StatefulWidget {
  const GiftCardManagementScreen({super.key});

  @override
  State<GiftCardManagementScreen> createState() =>
      _GiftCardManagementScreenState();
}

class _GiftCardManagementScreenState extends State<GiftCardManagementScreen> {
  final _repo = PosRepository();
  final _fmt = NumberFormat.currency(symbol: '\$');
  final _dateFmt = DateFormat('MM/dd/yyyy');

  // Filter
  String _filter = 'all'; // 'all' | 'active' | 'inactive' | 'expired'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Cards'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.add_card),
              label: const Text('Issue New Card'),
              onPressed: () => _showIssueDialog(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'All'),
                  const SizedBox(width: 8),
                  _filterChip('active', 'Active'),
                  const SizedBox(width: 8),
                  _filterChip('inactive', 'Inactive'),
                  const SizedBox(width: 8),
                  _filterChip('expired', 'Expired'),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<GiftCard>>(
              stream: _repo.streamGiftCards(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data!;
                final cards = _applyFilter(all);

                if (cards.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.card_giftcard,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          all.isEmpty
                              ? 'No gift cards yet.\nTap "Issue New Card" to get started.'
                              : 'No cards match the current filter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _GiftCardTile(
                    card: cards[index],
                    fmt: _fmt,
                    dateFmt: _dateFmt,
                    onTap: () => _showDetailSheet(context, cards[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  List<GiftCard> _applyFilter(List<GiftCard> cards) {
    switch (_filter) {
      case 'active':
        return cards.where((c) => c.isActive && !c.isExpired).toList();
      case 'inactive':
        return cards.where((c) => !c.isActive).toList();
      case 'expired':
        return cards.where((c) => c.isExpired).toList();
      default:
        return cards;
    }
  }

  // ── Issue new card dialog ─────────────────────────────────────────────────

  Future<void> _showIssueDialog(BuildContext context) async {
    final cardIdCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? expiresAt;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_card, color: Colors.teal),
              SizedBox(width: 8),
              Text('Issue New Gift Card'),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  TextField(
                    controller: cardIdCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Card ID *',
                      hintText: 'e.g. GC-001234',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.credit_card),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Initial Balance *',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Expiration date picker
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiresAt == null
                              ? 'No expiration date'
                              : 'Expires: ${DateFormat('MM/dd/yyyy').format(expiresAt!)}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          expiresAt == null ? 'Set Expiry' : 'Change',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            firstDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 10),
                            ),
                          );
                          if (picked != null) {
                            setDlg(() => expiresAt = picked);
                          }
                        },
                      ),
                      if (expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          tooltip: 'Remove expiry',
                          onPressed: () => setDlg(() => expiresAt = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'e.g. customer name, occasion',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final cardId = cardIdCtrl.text.trim();
                final amount = double.tryParse(amountCtrl.text.trim());

                if (cardId.isEmpty) {
                  setDlg(() => error = 'Please enter a Card ID.');
                  return;
                }
                if (amount == null || amount <= 0) {
                  setDlg(() => error = 'Please enter a valid initial balance.');
                  return;
                }

                // Check for duplicate card ID
                try {
                  final existing = await _repo.getGiftCardByCardId(cardId);
                  if (existing != null) {
                    setDlg(
                      () => error =
                          'A gift card with ID "$cardId" already exists. '
                          'Use "Reload" instead to add balance.',
                    );
                    return;
                  }
                } catch (_) {
                  // ignore lookup error; proceed
                }

                final now = DateTime.now();
                final card = GiftCard(
                  id: '',
                  cardId: cardId,
                  balance: amount,
                  loadedAmount: amount,
                  issuedAt: now,
                  expiresAt: expiresAt,
                  isActive: true,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                  history: [
                    GiftCardEntry(
                      type: GiftCardEntryType.issued,
                      amount: amount,
                      date: now,
                      note: 'Initial issue',
                    ),
                  ],
                  updatedAt: now,
                );

                try {
                  await _repo.createGiftCard(card);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Gift card $cardId issued (\$${amount.toStringAsFixed(2)}).',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  setDlg(() => error = 'Failed to issue card: $e');
                }
              },
              child: const Text('Issue Card'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card detail bottom sheet ──────────────────────────────────────────────

  Future<void> _showDetailSheet(BuildContext context, GiftCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _GiftCardDetailSheet(
        card: card,
        repo: _repo,
        fmt: _fmt,
        dateFmt: _dateFmt,
      ),
    );
  }
}

// ── Gift card list tile ────────────────────────────────────────────────────

class _GiftCardTile extends StatelessWidget {
  final GiftCard card;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final VoidCallback onTap;

  const _GiftCardTile({
    required this.card,
    required this.fmt,
    required this.dateFmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (!card.isActive) {
      statusColor = Colors.grey;
      statusLabel = 'Inactive';
      statusIcon = Icons.block;
    } else if (card.isExpired) {
      statusColor = Colors.orange;
      statusLabel = 'Expired';
      statusIcon = Icons.schedule;
    } else if (card.balance <= 0) {
      statusColor = Colors.red;
      statusLabel = 'Empty';
      statusIcon = Icons.money_off;
    } else {
      statusColor = Colors.green;
      statusLabel = 'Active';
      statusIcon = Icons.check_circle_outline;
    }

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.15),
          child: Icon(Icons.card_giftcard, color: statusColor),
        ),
        title: Row(
          children: [
            Text(
              card.cardId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 10, color: statusColor),
                  const SizedBox(width: 3),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Text(
          card.expiresAt != null
              ? 'Expires ${dateFmt.format(card.expiresAt!)}'
              : 'No expiration',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmt.format(card.balance),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: card.balance > 0 ? Colors.teal.shade700 : Colors.grey,
              ),
            ),
            Text(
              'balance',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gift card detail bottom sheet ─────────────────────────────────────────

class _GiftCardDetailSheet extends StatefulWidget {
  final GiftCard card;
  final PosRepository repo;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _GiftCardDetailSheet({
    required this.card,
    required this.repo,
    required this.fmt,
    required this.dateFmt,
  });

  @override
  State<_GiftCardDetailSheet> createState() => _GiftCardDetailSheetState();
}

class _GiftCardDetailSheetState extends State<_GiftCardDetailSheet> {
  late GiftCard _card;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Column(
        children: [
          // handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                        Icons.card_giftcard,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _card.cardId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            'Issued ${widget.dateFmt.format(_card.issuedAt)}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    // Active/Inactive toggle
                    _card.isActive
                        ? OutlinedButton.icon(
                            icon: const Icon(
                              Icons.block,
                              size: 16,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'Deactivate',
                              style: TextStyle(color: Colors.red),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                            ),
                            onPressed: _busy ? null : _toggleActive,
                          )
                        : FilledButton.icon(
                            icon: const Icon(Icons.check_circle, size: 16),
                            label: const Text('Reactivate'),
                            onPressed: _busy ? null : _toggleActive,
                          ),
                  ],
                ),

                const SizedBox(height: 20),

                // Balance card
                Card(
                  color: colorScheme.primaryContainer.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Balance',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                widget.fmt.format(_card.balance),
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: _card.balance > 0
                                      ? colorScheme.primary
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Reload'),
                          onPressed: _busy ? null : _showReloadDialog,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Details
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow(
                          Icons.event_available,
                          'Status',
                          _card.isActive
                              ? (_card.isExpired ? 'Expired' : 'Active')
                              : 'Inactive',
                          color: _card.isActive && !_card.isExpired
                              ? Colors.green
                              : Colors.red,
                        ),
                        _detailRow(
                          Icons.calendar_today,
                          'Expiration',
                          _card.expiresAt != null
                              ? widget.dateFmt.format(_card.expiresAt!)
                              : 'None',
                        ),
                        _detailRow(
                          Icons.attach_money,
                          'Last Load Amount',
                          widget.fmt.format(_card.loadedAmount),
                        ),
                        if (_card.notes != null)
                          _detailRow(
                            Icons.note_outlined,
                            'Notes',
                            _card.notes!,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Transaction history
                Text(
                  'History',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),

                if (_card.history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No history yet.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                else
                  ..._card.history.reversed.map((entry) {
                    final isPositive = entry.amount >= 0;
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isPositive
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        child: Icon(
                          entry.type == GiftCardEntryType.redeemed
                              ? Icons.remove
                              : entry.type == GiftCardEntryType.reloaded
                              ? Icons.refresh
                              : Icons.add,
                          size: 14,
                          color: isPositive
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                      title: Text(
                        _entryLabel(entry.type),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${widget.dateFmt.format(entry.date)}'
                        '${entry.note != null ? ' · ${entry.note}' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      trailing: Text(
                        '${isPositive ? '+' : ''}'
                        '${widget.fmt.format(entry.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPositive
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _entryLabel(GiftCardEntryType type) {
    switch (type) {
      case GiftCardEntryType.issued:
        return 'Issued';
      case GiftCardEntryType.reloaded:
        return 'Reloaded';
      case GiftCardEntryType.redeemed:
        return 'Redeemed';
    }
  }

  Future<void> _toggleActive() async {
    setState(() => _busy = true);
    try {
      if (_card.isActive) {
        await widget.repo.deactivateGiftCard(_card.id);
      } else {
        await widget.repo.reactivateGiftCard(_card.id);
      }
      // Refresh from Firestore
      final updated = await widget.repo.getGiftCardByCardId(_card.cardId);
      if (mounted && updated != null) {
        setState(() => _card = updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showReloadDialog() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.refresh, color: Colors.teal),
              const SizedBox(width: 8),
              Text('Reload Card ${_card.cardId}'),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                Text(
                  'Current balance: ${widget.fmt.format(_card.balance)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Amount to Add *',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) {
                  setDlg(() => error = 'Please enter a valid amount.');
                  return;
                }

                try {
                  await widget.repo.reloadGiftCard(
                    _card.id,
                    amount,
                    note: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  );
                  // Refresh card
                  final updated = await widget.repo.getGiftCardByCardId(
                    _card.cardId,
                  );
                  if (mounted && updated != null) {
                    setState(() => _card = updated);
                  }
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          '\$${amount.toStringAsFixed(2)} added to ${_card.cardId}.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  setDlg(() => error = 'Failed to reload: $e');
                }
              },
              child: const Text('Add Balance'),
            ),
          ],
        ),
      ),
    );
  }
}
