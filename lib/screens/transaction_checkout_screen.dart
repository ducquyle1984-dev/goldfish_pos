import 'package:flutter/material.dart';
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

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
  }

  @override
  void dispose() {
    _paymentAmountController.dispose();
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

      // If fully paid, mark as paid
      if (_transaction.isFullyPaid) {
        await _markAsPaid();
      }

      _paymentAmountController.clear();
      setState(() => _selectedPaymentMethodId = null);

      if (mounted) {
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
                      color: Colors.blue,
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
