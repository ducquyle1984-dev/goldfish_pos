import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// Screen for viewing and checking out a pending transaction.
class TransactionCheckoutScreen extends StatefulWidget {
  final Transaction transaction;

  const TransactionCheckoutScreen({super.key, required this.transaction});

  @override
  State<TransactionCheckoutScreen> createState() =>
      _TransactionCheckoutScreenState();
}

class _TransactionCheckoutScreenState extends State<TransactionCheckoutScreen> {
  final _repo = PosRepository();
  late Transaction _transaction;

  // Payment fields
  final _paymentAmountController = TextEditingController();
  String? _selectedPaymentMethodId;
  String? _selectedPaymentMethodName;

  // Reward points
  final _rewardPointsCtrl = TextEditingController();
  Customer? _customer;
  RewardSettings _rewardSettings = const RewardSettings();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
    _loadCustomerAndSettings();
  }

  Future<void> _loadCustomerAndSettings() async {
    final futures = await Future.wait([
      _repo.getRewardSettings(),
      if (_transaction.customerId != null)
        _repo.getCustomer(_transaction.customerId!),
    ]);
    if (!mounted) return;
    setState(() {
      _rewardSettings = futures[0] as RewardSettings;
      if (_transaction.customerId != null && futures.length > 1) {
        _customer = futures[1] as Customer?;
      }
    });
  }

  @override
  void dispose() {
    _paymentAmountController.dispose();
    _rewardPointsCtrl.dispose();
    super.dispose();
  }

  // Group items by employee for display
  Map<String, List<TransactionItem>> get _itemsByEmployee {
    final map = <String, List<TransactionItem>>{};
    for (final item in _transaction.items) {
      map.putIfAbsent(item.employeeName, () => []).add(item);
    }
    return map;
  }

  Future<void> _addPayment() async {
    final amount = double.tryParse(_paymentAmountController.text);
    if (amount == null || amount <= 0) {
      _showError('Please enter a valid payment amount.');
      return;
    }
    if (_selectedPaymentMethodId == null) {
      _showError('Please select a payment method.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payment = Payment(
        paymentMethodId: _selectedPaymentMethodId!,
        paymentMethodName: _selectedPaymentMethodName!,
        amountPaid: amount,
        paymentDate: DateTime.now(),
      );

      await _repo.addPaymentToTransaction(_transaction.id, payment);

      // Reload transaction to get updated state
      final updated = await _repo.getTransaction(_transaction.id);
      if (updated != null) {
        setState(() => _transaction = updated);
      }

      // If fully paid, mark as paid (and award reward points)
      final wasFullyPaid = _transaction.isFullyPaid;
      if (wasFullyPaid) {
        await _markAsPaid();
      }

      _paymentAmountController.clear();
      setState(() => _selectedPaymentMethodId = null);

      if (!wasFullyPaid && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment added successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to add payment: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// Apply reward points as a payment (1 point = \$1).
  Future<void> _applyRewardPoints() async {
    final customer = _customer;
    if (customer == null) return;

    final points = double.tryParse(_rewardPointsCtrl.text);
    if (points == null || points <= 0) {
      _showError('Enter a valid number of points.');
      return;
    }
    final balance = _transaction.balanceRemaining;
    final maxRedeemable = points
        .clamp(0.0, customer.rewardPoints)
        .clamp(0.0, balance);
    if (maxRedeemable <= 0) {
      _showError('No points available to redeem.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Deduct points from customer immediately
      await _repo.adjustCustomerPoints(customer.id, -maxRedeemable);

      // Record as a payment
      final payment = Payment(
        paymentMethodId: 'reward_points',
        paymentMethodName: 'Reward Points',
        amountPaid: maxRedeemable,
        paymentDate: DateTime.now(),
      );
      await _repo.addPaymentToTransaction(_transaction.id, payment);

      // Reload transaction and customer
      final results = await Future.wait([
        _repo.getTransaction(_transaction.id),
        _repo.getCustomer(customer.id),
      ]);
      if (mounted) {
        setState(() {
          if (results[0] != null) _transaction = results[0] as Transaction;
          _customer = results[1] as Customer?;
        });
      }

      // If fully paid, mark as paid and award new points
      final wasFullyPaid = _transaction.isFullyPaid;
      if (wasFullyPaid) await _markAsPaid();

      _rewardPointsCtrl.clear();
      if (!wasFullyPaid && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${maxRedeemable.toStringAsFixed(0)} point(s) redeemed (\$${maxRedeemable.toStringAsFixed(2)} off).',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to redeem points: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _markAsPaid() async {
    final updated = await _repo.getTransaction(_transaction.id);
    if (updated == null) return;

    final paid = Transaction(
      id: updated.id,
      items: updated.items,
      customerId: updated.customerId,
      customerName: updated.customerName,
      discounts: updated.discounts,
      payments: updated.payments,
      status: TransactionStatus.paid,
      isVoided: updated.isVoided,
      subtotal: updated.subtotal,
      totalDiscount: updated.totalDiscount,
      taxAmount: updated.taxAmount,
      totalAmount: updated.totalAmount,
      createdAt: updated.createdAt,
      updatedAt: DateTime.now(),
    );
    await _repo.updateTransaction(paid);

    // Award reward points: only count cash/card payments (not reward point payments)
    if (_customer != null && _rewardSettings.enabled) {
      final cashPaid = updated.payments
          .where((p) => p.paymentMethodId != 'reward_points')
          .fold<double>(0, (s, p) => s + p.amountPaid);
      final pointsEarned = _rewardSettings.pointsEarned(cashPaid);
      if (pointsEarned > 0) {
        await _repo.adjustCustomerPoints(
          _customer!.id,
          pointsEarned.toDouble(),
        );
        if (mounted) {
          _showSuccess(
            'Transaction paid! ${_customer!.name} earned $pointsEarned reward point(s).',
          );
        }
        // Refresh local customer and update transaction state
        final refreshed = await _repo.getCustomer(_customer!.id);
        if (mounted) {
          setState(() {
            _transaction = paid;
            _customer = refreshed;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() => _transaction = paid);
      _showSuccess('Transaction marked as paid!');
    }
  }

  Future<void> _voidTransaction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Transaction'),
        content: const Text(
          'Are you sure you want to void this transaction? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.voidTransaction(_transaction.id);
      if (mounted) {
        _showSuccess('Transaction voided.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Failed to void transaction: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = _transaction.status == TransactionStatus.paid;
    final isVoided = _transaction.isVoided;
    final balance = _transaction.balanceRemaining;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _transaction.customerName != null
              ? 'Transaction – ${_transaction.customerName}'
              : 'Transaction',
        ),
        actions: [
          if (!isPaid && !isVoided)
            TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              label: const Text('Void', style: TextStyle(color: Colors.red)),
              onPressed: _isSaving ? null : _voidTransaction,
            ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left column – Services & employees
                  Expanded(flex: 3, child: _buildServicesPanel()),
                  const SizedBox(width: 24),
                  // Right column – Summary & payment
                  Expanded(
                    flex: 2,
                    child: _buildSummaryPanel(balance, isPaid, isVoided),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildServicesPanel() {
    final byEmployee = _itemsByEmployee;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status chip
        _buildStatusChip(),
        const SizedBox(height: 16),

        // Customer
        if (_transaction.customerName != null) ...[
          _buildSectionHeader(Icons.person_outline, 'Customer'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(_transaction.customerName!),
              subtitle: _customer != null
                  ? Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_customer!.rewardPoints.toStringAsFixed(0)} reward points',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Services by employee
        _buildSectionHeader(Icons.spa_outlined, 'Services'),
        const SizedBox(height: 8),
        ...byEmployee.entries.map((entry) {
          final employeeName = entry.key;
          final items = entry.value;
          final employeeTotal = items.fold<double>(0, (s, i) => s + i.subtotal);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        employeeName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '\$${employeeTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item.itemName}'
                              '${item.quantity > 1 ? ' ×${item.quantity}' : ''}',
                            ),
                          ),
                          Text('\$${item.subtotal.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        // Discounts
        if (_transaction.discounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildSectionHeader(Icons.discount_outlined, 'Discounts'),
          const SizedBox(height: 8),
          ..._transaction.discounts.map(
            (d) => ListTile(
              dense: true,
              leading: const Icon(Icons.sell_outlined, size: 18),
              title: Text(d.description),
              trailing: Text(
                d.type == DiscountType.percentage
                    ? '-${d.amount.toStringAsFixed(0)}%'
                    : '-\$${d.amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.green),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryPanel(double balance, bool isPaid, bool isVoided) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Totals card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(Icons.receipt_long_outlined, 'Summary'),
                const SizedBox(height: 16),
                _buildTotalRow('Subtotal', _transaction.subtotal),
                if (_transaction.totalDiscount > 0)
                  _buildTotalRow(
                    'Discount',
                    -_transaction.totalDiscount,
                    color: Colors.green,
                  ),
                if (_transaction.taxAmount > 0)
                  _buildTotalRow('Tax', _transaction.taxAmount),
                const Divider(),
                _buildTotalRow(
                  'Total',
                  _transaction.totalAmount,
                  bold: true,
                  fontSize: 18,
                ),
                if (_transaction.payments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._transaction.payments.map(
                    (p) => _buildTotalRow(
                      'Paid (${p.paymentMethodName})',
                      p.amountPaid,
                      color: p.paymentMethodId == 'reward_points'
                          ? Colors.amber.shade700
                          : Colors.blue,
                    ),
                  ),
                  const Divider(),
                  _buildTotalRow(
                    'Balance Due',
                    balance,
                    bold: true,
                    color: balance > 0 ? Colors.red : Colors.green,
                    fontSize: 18,
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Payment section
        if (!isPaid && !isVoided) ...[
          // Reward points redemption (only shown when customer has points)
          if (_customer != null &&
              _rewardSettings.enabled &&
              _customer!.rewardPoints > 0 &&
              balance > 0) ...[
            _buildSectionHeader(Icons.star_outlined, 'Reward Points'),
            const SizedBox(height: 8),
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_customer!.rewardPoints.toStringAsFixed(0)} points available',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '1 pt = \$1.00',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rewardPointsCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: false,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Points to redeem',
                              prefixIcon: const Icon(Icons.star_border),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: TextButton(
                                onPressed: () {
                                  final max = _customer!.rewardPoints.clamp(
                                    0.0,
                                    balance,
                                  );
                                  _rewardPointsCtrl.text = max.toStringAsFixed(
                                    0,
                                  );
                                },
                                child: const Text('Max'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                          ),
                          onPressed: _isSaving ? null : _applyRewardPoints,
                          child: const Text('Redeem'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildSectionHeader(Icons.payment_outlined, 'Add Payment'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Payment method dropdown
                  StreamBuilder(
                    stream: _repo.getPaymentMethods(),
                    builder: (context, snapshot) {
                      final methods = snapshot.data ?? [];
                      return DropdownButtonFormField<String>(
                        value: _selectedPaymentMethodId,
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          border: OutlineInputBorder(),
                        ),
                        items: methods
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(m.merchantName),
                                onTap: () =>
                                    _selectedPaymentMethodName = m.merchantName,
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedPaymentMethodId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _paymentAmountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '\$',
                      border: const OutlineInputBorder(),
                      suffixIcon: TextButton(
                        onPressed: () => _paymentAmountController.text = balance
                            .toStringAsFixed(2),
                        child: const Text('Exact'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Apply Payment'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _addPayment,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (isPaid)
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text(
                'Paid',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('This transaction has been fully paid.'),
            ),
          ),

        if (isVoided)
          Card(
            color: Colors.red.shade50,
            child: const ListTile(
              leading: Icon(Icons.cancel, color: Colors.red),
              title: Text(
                'Voided',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text('This transaction has been voided.'),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusChip() {
    Color color;
    String label;
    switch (_transaction.status) {
      case TransactionStatus.pending:
        color = Colors.orange;
        label = 'Pending';
        break;
      case TransactionStatus.completed:
        color = Colors.blue;
        label = 'Completed';
        break;
      case TransactionStatus.paid:
        color = Colors.green;
        label = 'Paid';
        break;
      case TransactionStatus.voided:
        color = Colors.red;
        label = 'Voided';
        break;
    }
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    bool bold = false,
    Color? color,
    double fontSize = 14,
  }) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
      fontSize: fontSize,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}',
            style: style,
          ),
        ],
      ),
    );
  }
}
