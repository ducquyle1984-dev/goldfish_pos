import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:intl/intl.dart';

/// Screen for viewing, creating, and editing customers.
class CustomerManagementScreen extends StatelessWidget {
  const CustomerManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = PosRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Customer'),
        onPressed: () => _openForm(context, repo, null),
      ),
      body: StreamBuilder<List<Customer>>(
        stream: repo.getCustomers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final customers = snapshot.data ?? [];
          if (customers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No customers yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final c = customers[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                    ),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📞 ${c.phone}'),
                      Text(
                        '🎂 ${c.birthDateDisplay}  •  ⭐ ${c.rewardPoints.toStringAsFixed(0)} pts',
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.history_outlined),
                        tooltip: 'View History',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                _CustomerHistoryScreen(customer: c, repo: repo),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openForm(context, repo, c),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _confirmDelete(context, repo, c),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, PosRepository repo, Customer? customer) {
    showDialog(
      context: context,
      builder: (_) => _CustomerFormDialog(repo: repo, customer: customer),
    );
  }

  void _confirmDelete(
    BuildContext context,
    PosRepository repo,
    Customer customer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Delete ${customer.name}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.deleteCustomer(customer.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Customer history screen  (2 tabs: Transactions | Rewards)
// ---------------------------------------------------------------------------
class _CustomerHistoryScreen extends StatefulWidget {
  final Customer customer;
  final PosRepository repo;

  const _CustomerHistoryScreen({required this.customer, required this.repo});

  @override
  State<_CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<_CustomerHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  RewardSettings _rewardSettings = const RewardSettings();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    widget.repo.getRewardSettings().then((s) {
      if (mounted) setState(() => _rewardSettings = s);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Transactions'),
            Tab(icon: Icon(Icons.star_outline), text: 'Rewards'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _TransactionHistoryTab(
            customer: widget.customer,
            repo: widget.repo,
            rewardSettings: _rewardSettings,
          ),
          _RewardsTab(
            customer: widget.customer,
            repo: widget.repo,
            rewardSettings: _rewardSettings,
          ),
        ],
      ),
    );
  }
}

// ── Transactions tab ─────────────────────────────────────────────────────────
class _TransactionHistoryTab extends StatelessWidget {
  final Customer customer;
  final PosRepository repo;
  final RewardSettings rewardSettings;

  const _TransactionHistoryTab({
    required this.customer,
    required this.repo,
    required this.rewardSettings,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');
    final timeFmt = DateFormat('h:mm a');

    return StreamBuilder<List<Transaction>>(
      stream: repo.getTransactionsByCustomer(customer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final txns = snapshot.data ?? [];
        if (txns.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No transactions found.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // Summary bar
        final total = txns
            .where((t) => !t.isVoided)
            .fold<double>(0, (s, t) => s + t.totalAmount);
        final visits = txns.where((t) => !t.isVoided).length;

        return Column(
          children: [
            Container(
              color: Theme.of(context).primaryColor.withAlpha(20),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _summaryChip(Icons.receipt_outlined, '$visits visits'),
                  _summaryChip(
                    Icons.attach_money,
                    '\$${total.toStringAsFixed(2)} total spent',
                  ),
                  _summaryChip(
                    Icons.star,
                    '${customer.rewardPoints.toStringAsFixed(0)} pts balance',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: txns.length,
                itemBuilder: (context, i) {
                  final tx = txns[i];
                  final voided =
                      tx.isVoided || tx.status == TransactionStatus.voided;
                  final receiptNum = tx.dailyNumber > 0
                      ? '#${tx.dailyNumber.toString().padLeft(4, '0')}'
                      : tx.id.substring(0, tx.id.length.clamp(0, 8));

                  // Points earned / redeemed on this transaction
                  final cashPaid = tx.payments
                      .where((p) => p.paymentMethodId != 'reward_points')
                      .fold<double>(0, (s, p) => s + p.amountPaid);
                  final pointsEarned = voided
                      ? 0
                      : rewardSettings.pointsEarned(cashPaid);
                  final pointsRedeemed = tx.payments
                      .where((p) => p.paymentMethodId == 'reward_points')
                      .fold<double>(0, (s, p) => s + p.amountPaid);

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    elevation: voided ? 0 : 1,
                    color: voided ? Colors.grey.shade100 : null,
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: voided
                            ? Colors.grey.shade300
                            : Theme.of(context).primaryColor.withAlpha(30),
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 20,
                          color: voided
                              ? Colors.grey
                              : Theme.of(context).primaryColor,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            receiptNum,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: voided ? Colors.grey : null,
                              decoration: voided
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (voided)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'VOIDED',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '\$${tx.totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${dateFmt.format(tx.createdAt)}  ${timeFmt.format(tx.createdAt)}'
                        '${pointsEarned > 0 ? "  •  +$pointsEarned pts" : ""}'
                        '${pointsRedeemed > 0 ? "  •  -${pointsRedeemed.toStringAsFixed(0)} pts redeemed" : ""}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(),
                              // Services
                              if (tx.items.isNotEmpty) ...[
                                const Text(
                                  'Services',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...tx.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${item.itemName}  ×${item.quantity}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '\$${item.subtotal.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '(${item.employeeName})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              // Discounts
                              if (tx.discounts.isNotEmpty) ...[
                                const Text(
                                  'Discounts',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...tx.discounts.map(
                                  (d) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            d.description,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          d.type == DiscountType.percentage
                                              ? '-${d.amount.toStringAsFixed(0)}%'
                                              : '-\$${d.amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              // Totals row
                              Row(
                                children: [
                                  const Spacer(),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (tx.totalDiscount > 0)
                                        Text(
                                          'Discount: -\$${tx.totalDiscount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      if (tx.taxAmount > 0)
                                        Text(
                                          'Tax: \$${tx.taxAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      Text(
                                        'Total: \$${tx.totalAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // Payments
                              if (tx.payments.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Divider(),
                                const Text(
                                  'Payments',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...tx.payments.map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      children: [
                                        Icon(
                                          p.paymentMethodId == 'reward_points'
                                              ? Icons.star_outline
                                              : Icons.payment_outlined,
                                          size: 14,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            p.paymentMethodName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '\$${p.amountPaid.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              // Points earned badge
                              if (pointsEarned > 0 || pointsRedeemed > 0) ...[
                                const SizedBox(height: 8),
                                const Divider(),
                                Row(
                                  children: [
                                    if (pointsEarned > 0)
                                      Chip(
                                        avatar: const Icon(
                                          Icons.star,
                                          size: 14,
                                          color: Colors.amber,
                                        ),
                                        label: Text(
                                          '+$pointsEarned pts earned',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        backgroundColor: Colors.amber.shade50,
                                        padding: EdgeInsets.zero,
                                      ),
                                    if (pointsEarned > 0 && pointsRedeemed > 0)
                                      const SizedBox(width: 8),
                                    if (pointsRedeemed > 0)
                                      Chip(
                                        avatar: const Icon(
                                          Icons.star_half_outlined,
                                          size: 14,
                                          color: Colors.orange,
                                        ),
                                        label: Text(
                                          '-${pointsRedeemed.toStringAsFixed(0)} pts redeemed',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        backgroundColor: Colors.orange.shade50,
                                        padding: EdgeInsets.zero,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
        ),
      ],
    );
  }
}

// ── Rewards tab ──────────────────────────────────────────────────────────────
class _RewardsTab extends StatelessWidget {
  final Customer customer;
  final PosRepository repo;
  final RewardSettings rewardSettings;

  const _RewardsTab({
    required this.customer,
    required this.repo,
    required this.rewardSettings,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy  h:mm a');

    return StreamBuilder<List<Transaction>>(
      stream: repo.getTransactionsByCustomer(customer.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final txns = (snapshot.data ?? [])
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Build point events from transactions
        final events = <_PointEvent>[];
        for (final tx in txns) {
          final voided = tx.isVoided || tx.status == TransactionStatus.voided;
          final receiptNum = tx.dailyNumber > 0
              ? '#${tx.dailyNumber.toString().padLeft(4, '0')}'
              : tx.id.substring(0, tx.id.length.clamp(0, 8));

          if (!voided) {
            final cashPaid = tx.payments
                .where((p) => p.paymentMethodId != 'reward_points')
                .fold<double>(0, (s, p) => s + p.amountPaid);
            final earned = rewardSettings.pointsEarned(cashPaid);
            if (earned > 0) {
              events.add(
                _PointEvent(
                  date: tx.createdAt,
                  txLabel: receiptNum,
                  delta: earned.toDouble(),
                  description:
                      'Earned from \$${cashPaid.toStringAsFixed(2)} paid',
                ),
              );
            }
          }

          final redeemed = tx.payments
              .where((p) => p.paymentMethodId == 'reward_points')
              .fold<double>(0, (s, p) => s + p.amountPaid);
          if (redeemed > 0) {
            events.add(
              _PointEvent(
                date: tx.createdAt,
                txLabel: receiptNum,
                delta: -redeemed,
                description: 'Redeemed (\$${redeemed.toStringAsFixed(2)} off)',
              ),
            );
          }
        }

        // Sort events newest-first for display; compute running balance
        // Build running balance oldest→newest, then reverse for display
        double running = 0;
        for (final e in events) {
          running += e.delta;
          e.runningBalance = running;
        }
        final displayEvents = events.reversed.toList();

        return Column(
          children: [
            // Balance card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade300, Colors.amber.shade600],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 40),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Balance',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '${customer.rewardPoints.toStringAsFixed(0)} points',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (rewardSettings.dollarsPerPoint > 0)
                        Text(
                          '≈ \$${customer.rewardPoints.toStringAsFixed(0)} in rewards',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            if (displayEvents.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No reward point activity yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: displayEvents.length,
                  itemBuilder: (context, i) {
                    final e = displayEvents[i];
                    final isEarn = e.delta > 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isEarn
                            ? Colors.amber.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          isEarn ? Icons.add : Icons.remove,
                          color: isEarn
                              ? Colors.amber.shade800
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            isEarn
                                ? '+${e.delta.toStringAsFixed(0)} pts'
                                : '${e.delta.toStringAsFixed(0)} pts',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isEarn
                                  ? Colors.amber.shade800
                                  : Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            e.txLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.description,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            dateFmt.format(e.date),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        'Balance:\n${e.runningBalance.toStringAsFixed(0)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PointEvent {
  final DateTime date;
  final String txLabel;
  final double delta;
  final String description;
  double runningBalance = 0;

  _PointEvent({
    required this.date,
    required this.txLabel,
    required this.delta,
    required this.description,
  });
}

// ---------------------------------------------------------------------------
// Customer form dialog (create / edit)
// ---------------------------------------------------------------------------
class _CustomerFormDialog extends StatefulWidget {
  final PosRepository repo;
  final Customer? customer;

  const _CustomerFormDialog({required this.repo, this.customer});

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;

  int _birthMonth = 1;
  int _birthDay = 1;
  bool _smsOptOut = false;
  bool _saving = false;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _birthMonth = c?.birthMonth ?? 1;
    _birthDay = c?.birthDay ?? 1;
    _smsOptOut = c?.smsOptOut ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  int _daysInMonth(int month) {
    const days = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      if (widget.customer == null) {
        // Create
        final newCustomer = Customer(
          id: '',
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          birthMonth: _birthMonth,
          birthDay: _birthDay,
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          smsOptOut: _smsOptOut,
          createdAt: now,
          updatedAt: now,
        );
        await widget.repo.createCustomer(newCustomer);
      } else {
        // Update
        final updated = widget.customer!.copyWith(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          birthMonth: _birthMonth,
          birthDay: _birthDay,
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          smsOptOut: _smsOptOut,
          updatedAt: now,
        );
        await widget.repo.updateCustomer(updated);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customer != null;
    final maxDay = _daysInMonth(_birthMonth);
    if (_birthDay > maxDay) _birthDay = maxDay;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Customer' : 'New Customer'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 14),

                // Phone
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Phone number is required'
                      : null,
                ),
                const SizedBox(height: 14),

                // Birthday (month + day)
                Text(
                  'Birthday *',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Month
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: _birthMonth,
                        decoration: const InputDecoration(
                          labelText: 'Month',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(_months[i]),
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          _birthMonth = v!;
                          final max = _daysInMonth(_birthMonth);
                          if (_birthDay > max) _birthDay = max;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Day
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        value: _birthDay,
                        decoration: const InputDecoration(
                          labelText: 'Day',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: List.generate(
                          _daysInMonth(_birthMonth),
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}'),
                          ),
                        ),
                        onChanged: (v) => setState(() => _birthDay = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Email (optional)
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),

                // SMS opt-out
                SwitchListTile(
                  value: _smsOptOut,
                  onChanged: (v) => setState(() => _smsOptOut = v),
                  title: const Text('Opt out of SMS messages'),
                  subtitle: const Text(
                    'No thank-you SMS will be sent to this customer after checkout.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    _smsOptOut ? Icons.sms_failed_outlined : Icons.sms_outlined,
                    color: _smsOptOut ? Colors.red : Colors.grey,
                  ),
                ),
                if (isEdit) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Reward Points: ${widget.customer!.rewardPoints.toStringAsFixed(0)} pts',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
