import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_feedback_model.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/models/sms_settings_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/services/cash_drawer_service.dart';
import 'package:goldfish_pos/services/helcim_service.dart';
import 'package:goldfish_pos/services/sms_service.dart';

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
  final _cashDrawer = CashDrawerService();
  late Transaction _transaction;

  // Payment fields
  final _paymentAmountController = TextEditingController();
  String? _selectedPaymentMethodId;
  String? _selectedPaymentMethodName;
  PaymentMethod?
  _selectedPaymentMethod; // full object for processor-specific logic
  List<PaymentMethod> _paymentMethods = [];

  // Reward points
  final _rewardPointsCtrl = TextEditingController();
  Customer? _customer;
  RewardSettings _rewardSettings = const RewardSettings();

  /// Per-transaction SMS opt-out. Defaults to true (send SMS). Staff can
  /// flip this off before checkout to suppress the post-payment survey.
  bool _sendSmsThisTransaction = true;

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

    // Route to Helcim-specific flow
    if (_selectedPaymentMethod?.processorType == PaymentProcessorType.helcim) {
      await _processHelcimPayment(amount);
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

      // Capture before clearing selection — setState triggers a rebuild
      // which can lose the reference if the StreamBuilder re-emits.
      final paidWithMethod = _selectedPaymentMethod;

      _paymentAmountController.clear();
      setState(() {
        _selectedPaymentMethodId = null;
        _selectedPaymentMethod = null;
        _selectedPaymentMethodName = null;
      });

      // Open cash drawer if this is a cash payment.
      // Check isCash flag first; fall back to name matching in case the flag
      // was not set on the Firestore payment method.
      final isCashPayment =
          paidWithMethod?.isCash == true ||
          (paidWithMethod?.merchantName.toLowerCase().contains('cash') == true);
      if (isCashPayment) {
        _openDrawerIfCash();
      }

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

  // ─────────────────────────────────────────────────────────────────────────
  // HELCIM PAYMENT FLOW
  // ─────────────────────────────────────────────────────────────────────────

  /// Handles payment via Helcim — shows a dialog so the cashier can either:
  ///   • Initiate a HelcimPay hosted checkout session (online / card-not-present)
  ///   • Confirm a physical terminal payment and enter the Helcim transaction ID
  Future<void> _processHelcimPayment(double amount) async {
    final method = _selectedPaymentMethod!;
    final config = method.additionalConfig ?? {};
    final accountGuid = config['accountGuid']?.toString() ?? '';
    final terminalId = config['terminalId']?.toString();
    final apiToken = method.processorApiKey;

    if (accountGuid.isEmpty || apiToken.isEmpty) {
      _showError(
        'Helcim is not fully configured. '
        'Please add the Account GUID and API Token in Payment Processor Settings.',
      );
      return;
    }

    final helcim = HelcimService(
      apiToken: apiToken,
      accountGuid: accountGuid,
      terminalId: terminalId,
    );

    // Show dialog offering terminal confirm or HelcimPay hosted session
    final result = await showDialog<_HelcimPaymentDialogResult?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HelcimPaymentDialog(
        amount: amount,
        helcim: helcim,
        merchantName: method.merchantName,
      ),
    );

    if (result == null || !result.confirmed) return; // user cancelled

    setState(() => _isSaving = true);
    try {
      final payment = Payment(
        paymentMethodId: _selectedPaymentMethodId!,
        paymentMethodName: _selectedPaymentMethodName!,
        amountPaid: amount,
        paymentDate: DateTime.now(),
        // Store the Helcim transaction reference in the notes via a custom field
        // when PaymentModel is extended. For now we embed it in the name.
      );

      await _repo.addPaymentToTransaction(_transaction.id, payment);

      final updated = await _repo.getTransaction(_transaction.id);
      if (updated != null) setState(() => _transaction = updated);

      final wasFullyPaid = _transaction.isFullyPaid;
      if (wasFullyPaid) await _markAsPaid();

      _paymentAmountController.clear();
      setState(() => _selectedPaymentMethodId = null);

      if (!wasFullyPaid && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.helcimTransactionId != null
                  ? 'Helcim payment recorded (Ref: ${result.helcimTransactionId}).'
                  : 'Helcim payment recorded.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to record Helcim payment: \$e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        // Show post-payment survey
        if (mounted) await _showPostPaymentSurvey(paid);
        return;
      }
    }

    if (mounted) {
      setState(() => _transaction = paid);
      _showSuccess('Transaction marked as paid!');
      await _showPostPaymentSurvey(paid);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // POST-PAYMENT SURVEY + SMS FLOW
  // ─────────────────────────────────────────────────────────────────────────

  /// Called after a transaction is fully paid.
  /// If SMS is enabled and the customer has a phone number, shows a survey
  /// dialog. Positive → send thank-you SMS with optional Google Review link.
  /// Negative → collect feedback, store it in Firestore, send a consolation SMS.
  Future<void> _showPostPaymentSurvey(Transaction paidTransaction) async {
    if (!mounted) return;

    // Load SMS settings
    SmsSettings smsSettings;
    try {
      smsSettings = await _repo.getSmsSettings();
    } catch (_) {
      return; // silently skip if we can't load settings
    }

    if (!smsSettings.enabled) return;

    // Respect customer-level opt-out
    if (_customer?.smsOptOut == true) return;

    // Respect per-transaction opt-out
    if (!_sendSmsThisTransaction) return;

    // Determine customer name and phone
    final customer = _customer;
    final customerName =
        customer?.name ?? paidTransaction.customerName ?? 'Valued Customer';
    final customerPhone = customer?.phone ?? '';

    // Ask for survey rating
    if (!mounted) return;
    final rating = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SurveyRatingDialog(customerName: customerName),
    );

    if (rating == null) return; // dismissed

    if (rating) {
      // ── POSITIVE ──────────────────────────────────────────────────────
      await _handlePositiveFeedback(
        paidTransaction: paidTransaction,
        smsSettings: smsSettings,
        customerName: customerName,
        customerPhone: customerPhone,
        customer: customer,
      );
    } else {
      // ── NEGATIVE ──────────────────────────────────────────────────────
      await _handleNegativeFeedback(
        paidTransaction: paidTransaction,
        smsSettings: smsSettings,
        customerName: customerName,
        customerPhone: customerPhone,
        customer: customer,
      );
    }
  }

  /// Positive path: preview the thank-you + review SMS and optionally send it.
  Future<void> _handlePositiveFeedback({
    required Transaction paidTransaction,
    required SmsSettings smsSettings,
    required String customerName,
    required String customerPhone,
    Customer? customer,
  }) async {
    if (!mounted) return;

    final composedMessage = smsSettings.buildPositiveMessage(customerName);

    // Show SMS preview / send dialog
    final result = await showDialog<_SmsPreviewResult?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SmsPreviewDialog(
        title: 'Send Thank-You SMS',
        subtitle:
            'The customer left a positive rating. Review and send the message below.',
        initialMessage: composedMessage,
        phoneNumber: customerPhone,
        positiveIcon: true,
      ),
    );

    if (result == null || !result.shouldSend || customerPhone.isEmpty) return;

    final smsService = SmsService(
      accountSid: smsSettings.accountSid,
      authToken: smsSettings.authToken,
      fromNumber: smsSettings.fromNumber,
    );

    final sendResult = await smsService.send(
      toNumber: customerPhone,
      body: result.message,
    );

    if (mounted) {
      final isSuccess = sendResult == SmsSendResult.success;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SmsService.resultMessage(sendResult)),
          backgroundColor: isSuccess ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  /// Negative path: collect feedback text, store in Firestore, optionally send SMS.
  Future<void> _handleNegativeFeedback({
    required Transaction paidTransaction,
    required SmsSettings smsSettings,
    required String customerName,
    required String customerPhone,
    Customer? customer,
  }) async {
    if (!mounted) return;

    // Collect feedback text
    final feedbackResult = await showDialog<_NegativeFeedbackResult?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NegativeFeedbackDialog(
        customerName: customerName,
        negativeMessage: smsSettings.buildNegativeMessage(customerName),
        customerPhone: customerPhone,
      ),
    );

    if (feedbackResult == null) return;

    bool smsSent = false;

    // Optionally send negative SMS
    if (feedbackResult.sendSms && customerPhone.isNotEmpty) {
      final smsService = SmsService(
        accountSid: smsSettings.accountSid,
        authToken: smsSettings.authToken,
        fromNumber: smsSettings.fromNumber,
      );

      final sendResult = await smsService.send(
        toNumber: customerPhone,
        body: feedbackResult.smsMessage,
      );

      smsSent = sendResult == SmsSendResult.success;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SmsService.resultMessage(sendResult)),
            backgroundColor: smsSent ? Colors.green : Colors.orange,
          ),
        );
      }
    }

    // Always store the feedback in Firestore
    if (feedbackResult.feedbackText.trim().isNotEmpty) {
      try {
        await _repo.saveCustomerFeedback(
          CustomerFeedback(
            id: '',
            transactionId: paidTransaction.id,
            customerId: customer?.id,
            customerName: customerName,
            customerPhone: customerPhone,
            feedbackText: feedbackResult.feedbackText.trim(),
            smsSent: smsSent,
            createdAt: DateTime.now(),
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Feedback saved. Thank you for helping us improve!',
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          _showError('Could not save feedback: $e');
        }
      }
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

  /// Fires the cash drawer open command in the background (non-blocking).
  /// Shows a brief error snack if the connection fails.
  void _openDrawerIfCash() {
    _cashDrawer.openDrawerOnCashPayment().then((result) {
      if (!mounted) return;
      switch (result) {
        case CashDrawerResult.success:
        case CashDrawerResult.disabled:
          break; // silent — either opened or drawer integration is off
        case CashDrawerResult.notConfigured:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cash drawer is not configured. '
                'Go to Setup → Admin → Cash Drawer.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        case CashDrawerResult.connectionFailed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open cash drawer — check the network connection.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        case CashDrawerResult.bridgeNotRunning:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cash drawer bridge is not running.\n'
                'Re-run install_bridge_service.ps1, then check '
                '%AppData%\\GoldfishPOS\\bridge.log',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
            ),
          );
        case CashDrawerResult.webNotSupported:
          break; // silent — bridge mode works on web
      }
    });
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
                      // Keep cached list for lookup
                      if (methods.isNotEmpty) _paymentMethods = methods;
                      return DropdownButtonFormField<String>(
                        value: _selectedPaymentMethodId,
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          border: OutlineInputBorder(),
                        ),
                        items: _paymentMethods
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.id,
                                child: Row(
                                  children: [
                                    if (m.processorType ==
                                        PaymentProcessorType.helcim)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(
                                          Icons.credit_card,
                                          size: 16,
                                        ),
                                      ),
                                    Text(m.merchantName),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          final found = _paymentMethods
                              .where((m) => m.id == val)
                              .firstOrNull;
                          setState(() {
                            _selectedPaymentMethodId = val;
                            _selectedPaymentMethodName = found?.merchantName;
                            _selectedPaymentMethod = found;
                          });
                        },
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
          const SizedBox(height: 12),

          // ── Per-transaction SMS toggle ────────────────────────────────
          Card(
            child: SwitchListTile(
              secondary: Icon(
                _sendSmsThisTransaction
                    ? Icons.sms_outlined
                    : Icons.sms_failed_outlined,
                color: _sendSmsThisTransaction ? Colors.teal : Colors.grey,
              ),
              title: const Text('Send thank-you SMS after payment'),
              subtitle: Text(
                _customer?.smsOptOut == true
                    ? 'Customer is opted out of SMS — will not be sent.'
                    : _sendSmsThisTransaction
                    ? 'An SMS survey will be sent after checkout.'
                    : 'SMS survey suppressed for this transaction.',
              ),
              value: _sendSmsThisTransaction && _customer?.smsOptOut != true,
              onChanged: _customer?.smsOptOut == true
                  ? null // greyed-out when customer is opted out
                  : (v) => setState(() => _sendSmsThisTransaction = v),
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
// ─────────────────────────────────────────────────────────────────────────────
// HELCIM PAYMENT DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _HelcimPaymentDialogResult {
  final bool confirmed;
  final String? helcimTransactionId;

  const _HelcimPaymentDialogResult({
    required this.confirmed,
    this.helcimTransactionId,
  });
}

/// Dialog shown when the cashier selects Helcim as the payment method.
/// Offers two options:
///   1. Initiate a HelcimPay hosted checkout session (returns a checkout token
///      which can be opened in a browser / WebView for card-not-present).
///   2. Confirm a card-present terminal payment and record the Helcim
///      transaction reference ID issued by the physical terminal.
class _HelcimPaymentDialog extends StatefulWidget {
  final double amount;
  final HelcimService helcim;
  final String merchantName;

  const _HelcimPaymentDialog({
    required this.amount,
    required this.helcim,
    required this.merchantName,
  });

  @override
  State<_HelcimPaymentDialog> createState() => _HelcimPaymentDialogState();
}

class _HelcimPaymentDialogState extends State<_HelcimPaymentDialog> {
  final _txIdController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;
  String? _checkoutToken;

  @override
  void dispose() {
    _txIdController.dispose();
    super.dispose();
  }

  /// Initializes a HelcimPay hosted session and shows the checkout token.
  /// The cashier can open this token URL in a browser or WebView.
  Future<void> _initHelcimPaySession() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final amountCents = (widget.amount * 100).round();
    final result = await widget.helcim.initializeHelcimPaySession(
      amountInCents: amountCents,
    );

    if (!mounted) return;
    if (result.success) {
      setState(() {
        _isProcessing = false;
        _checkoutToken = result.checkoutToken;
      });
    } else {
      setState(() {
        _isProcessing = false;
        _errorMessage =
            result.errorMessage ?? 'Failed to initialize HelcimPay.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.credit_card, size: 20),
          const SizedBox(width: 8),
          Text('Helcim — \$${widget.amount.toStringAsFixed(2)}'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Merchant: ${widget.merchantName}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),

              // ── Option A: Physical Terminal ──────────────────────────────
              const Text(
                'Option A — Card Terminal',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Process the payment on your Helcim card reader / terminal, '
                'then enter the Helcim Transaction ID shown on the receipt.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _txIdController,
                decoration: const InputDecoration(
                  labelText: 'Helcim Transaction ID (from terminal)',
                  hintText: 'e.g. 12345678',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // ── Option B: HelcimPay Hosted Checkout ──────────────────────
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Option B — HelcimPay Hosted Checkout',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Generate a secure HelcimPay checkout session. Open the returned '
                'token URL in a browser or WebView for the customer to enter card details.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 18),
                  label: const Text('Initialize HelcimPay Session'),
                  onPressed: _isProcessing ? null : _initHelcimPaySession,
                ),
              ),

              // Status / error messages
              if (_isProcessing) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Contacting Helcim…'),
                  ],
                ),
              ],
              if (_checkoutToken != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Checkout token ready:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _checkoutToken!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'After the customer completes payment, enter the Helcim '
                        'Transaction ID in the field above and tap Confirm.',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _HelcimPaymentDialogResult(confirmed: false),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Confirm Payment'),
          onPressed: _isProcessing
              ? null
              : () => Navigator.pop(
                  context,
                  _HelcimPaymentDialogResult(
                    confirmed: true,
                    helcimTransactionId: _txIdController.text.trim().isEmpty
                        ? null
                        : _txIdController.text.trim(),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMS / Survey dialog widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a thumbs-up / thumbs-down rating prompt.
/// Returns true for positive, false for negative, null if dismissed.
class _SurveyRatingDialog extends StatelessWidget {
  final String customerName;
  const _SurveyRatingDialog({required this.customerName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How was their experience?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ask $customerName to rate their visit today.',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RatingButton(
                icon: Icons.thumb_up_rounded,
                label: 'Great!',
                color: Colors.green,
                onTap: () => Navigator.pop(context, true),
              ),
              _RatingButton(
                icon: Icons.thumb_down_rounded,
                label: 'Not great',
                color: Colors.red,
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RatingButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SMS preview dialog ───────────────────────────────────────────────────────

class _SmsPreviewResult {
  final bool shouldSend;
  final String message;
  const _SmsPreviewResult({required this.shouldSend, required this.message});
}

class _SmsPreviewDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String initialMessage;
  final String phoneNumber;
  final bool positiveIcon;

  const _SmsPreviewDialog({
    required this.title,
    required this.subtitle,
    required this.initialMessage,
    required this.phoneNumber,
    this.positiveIcon = true,
  });

  @override
  State<_SmsPreviewDialog> createState() => _SmsPreviewDialogState();
}

class _SmsPreviewDialogState extends State<_SmsPreviewDialog> {
  late final TextEditingController _msgCtrl;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.positiveIcon ? Icons.star_rounded : Icons.message_rounded,
            color: widget.positiveIcon ? Colors.amber : Colors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (widget.phoneNumber.isNotEmpty) ...[
              Text(
                'To: ${widget.phoneNumber}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _msgCtrl,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (widget.phoneNumber.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'No phone number on file — SMS cannot be sent. The message is shown for reference.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _SmsPreviewResult(shouldSend: false, message: ''),
          ),
          child: const Text('Skip'),
        ),
        if (widget.phoneNumber.isNotEmpty)
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send SMS'),
            onPressed: () => Navigator.pop(
              context,
              _SmsPreviewResult(shouldSend: true, message: _msgCtrl.text),
            ),
          ),
      ],
    );
  }
}

// ─── Negative feedback dialog ─────────────────────────────────────────────────

class _NegativeFeedbackResult {
  final String feedbackText;
  final bool sendSms;
  final String smsMessage;
  const _NegativeFeedbackResult({
    required this.feedbackText,
    required this.sendSms,
    required this.smsMessage,
  });
}

class _NegativeFeedbackDialog extends StatefulWidget {
  final String customerName;
  final String negativeMessage;
  final String customerPhone;

  const _NegativeFeedbackDialog({
    required this.customerName,
    required this.negativeMessage,
    required this.customerPhone,
  });

  @override
  State<_NegativeFeedbackDialog> createState() =>
      _NegativeFeedbackDialogState();
}

class _NegativeFeedbackDialogState extends State<_NegativeFeedbackDialog> {
  late final TextEditingController _feedbackCtrl;
  late final TextEditingController _msgCtrl;
  bool _sendSms = true;

  @override
  void initState() {
    super.initState();
    _feedbackCtrl = TextEditingController();
    _msgCtrl = TextEditingController(text: widget.negativeMessage);
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sentiment_dissatisfied, color: Colors.red),
          SizedBox(width: 8),
          Text('Capture Feedback'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'re sorry ${widget.customerName}\'s experience wasn\'t perfect. '
              'Please note their feedback so we can improve.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feedbackCtrl,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Customer Feedback',
                hintText: 'What could we have done better?',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // SMS section
            if (widget.customerPhone.isNotEmpty) ...[
              CheckboxListTile(
                value: _sendSms,
                onChanged: (v) => setState(() => _sendSms = v ?? false),
                title: const Text('Send a thank-you SMS'),
                subtitle: Text('To: ${widget.customerPhone}'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_sendSms) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _msgCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'SMS Message',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ] else
              const Text(
                'No phone number on file — SMS will not be sent.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _NegativeFeedbackResult(
              feedbackText: _feedbackCtrl.text,
              sendSms: _sendSms && widget.customerPhone.isNotEmpty,
              smsMessage: _msgCtrl.text,
            ),
          ),
          child: const Text('Save Feedback'),
        ),
      ],
    );
  }
}
