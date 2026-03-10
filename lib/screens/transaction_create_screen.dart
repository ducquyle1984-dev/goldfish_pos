import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/gift_card_model.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/models/customer_feedback_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/models/sms_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/services/cash_drawer_service.dart';
import 'package:goldfish_pos/services/helcim_service.dart';
import 'package:goldfish_pos/services/sms_service.dart';
import 'package:goldfish_pos/widgets/customer_check_in_dialog.dart';
import 'package:goldfish_pos/widgets/receipt_print_dialog.dart';

// ---------------------------------------------------------------------------
// Local draft line‑item (not the Firestore model)
// ---------------------------------------------------------------------------
class _LineItem {
  final String id; // uuid-ish
  final Item item;
  Employee employee;
  int quantity;
  double unitPrice; // allows custom price override

  _LineItem({
    required this.id,
    required this.item,
    required this.employee,
    this.quantity = 1,
    required this.unitPrice,
  });

  double get subtotal => unitPrice * quantity;

  TransactionItem toTransactionItem() => TransactionItem(
    id: id,
    itemId: item.id,
    itemName: item.name,
    employeeId: employee.id,
    employeeName: employee.name,
    itemPrice: unitPrice,
    quantity: quantity,
    subtotal: subtotal,
  );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class TransactionCreateScreen extends StatefulWidget {
  final Employee defaultEmployee;
  final Transaction? existingTransaction;

  const TransactionCreateScreen({
    super.key,
    required this.defaultEmployee,
    this.existingTransaction,
  });

  @override
  State<TransactionCreateScreen> createState() =>
      _TransactionCreateScreenState();
}

class _TransactionCreateScreenState extends State<TransactionCreateScreen> {
  final _repo = PosRepository();

  // Draft order state
  final List<_LineItem> _lineItems = [];
  final List<Discount> _discounts = [];
  final List<Payment> _payments = [];
  Customer? _selectedCustomer;

  // Active technician – new services are assigned to this employee
  late Employee _activeEmployee;

  // Inline payment entry
  _CheckoutTab _checkoutTab = _CheckoutTab.cash;
  PaymentMethod? _checkoutProcessor; // full object for Helcim routing
  final _tenderCtrl = TextEditingController();
  final _otherNoteCtrl = TextEditingController();

  // Gift card payment state
  final _giftCardIdCtrl = TextEditingController();
  final _giftCardAmountCtrl = TextEditingController();
  GiftCard? _lookedUpGiftCard;
  bool _isLookingUpCard = false;

  // Reward points
  final _rewardPointsCtrl = TextEditingController();
  RewardSettings _rewardSettings = const RewardSettings();

  // SMS toggle – staff can suppress the survey for a specific transaction
  bool _sendSmsThisTransaction = true;

  // Item browser
  String? _selectedCategoryId;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  bool _isSaving = false;

  // Tracks the Firestore document ID after the first save so subsequent
  // partial payments update the same document instead of creating a new one.
  String? _savedTransactionId;

  late Future<_ScreenData> _screenDataFuture;

  @override
  void initState() {
    super.initState();
    _activeEmployee = widget.defaultEmployee;
    _savedTransactionId = widget.existingTransaction?.id;
    _screenDataFuture = _loadAndPopulate();
  }

  /// Loads reference data then pre-populates the draft order when resuming
  /// an existing pending transaction.
  Future<_ScreenData> _loadAndPopulate() async {
    final data = await _loadScreenData();
    // Load reward settings in the background (non-blocking)
    _repo
        .getRewardSettings()
        .then((s) {
          if (mounted) setState(() => _rewardSettings = s);
        })
        .catchError((_) {});
    final tx = widget.existingTransaction;
    if (tx != null) {
      _discounts.addAll(tx.discounts);
      _payments.addAll(tx.payments);

      // Restore customer
      if (tx.customerId != null) {
        final matches = data.customers.where((c) => c.id == tx.customerId);
        if (matches.isNotEmpty) _selectedCustomer = matches.first;
      }

      // Rebuild line items by matching IDs against loaded items/employees
      for (final ti in tx.items) {
        final itemMatches = data.items.where((i) => i.id == ti.itemId);
        final empMatches = data.employees.where((e) => e.id == ti.employeeId);
        if (itemMatches.isEmpty || empMatches.isEmpty) continue;
        _lineItems.add(
          _LineItem(
            id: ti.id,
            item: itemMatches.first,
            employee: empMatches.first,
            quantity: ti.quantity,
            unitPrice: ti.itemPrice,
          ),
        );
      }
    }
    return data;
  }

  // ── Computed totals ──────────────────────────────────────────────────────
  double get _subtotal => _lineItems.fold(0, (s, l) => s + l.subtotal);

  double get _totalDiscount => _discounts.fold(0, (s, d) {
    if (d.type == DiscountType.percentage) {
      return s + (_subtotal * d.amount / 100);
    }
    return s + d.amount;
  });

  double get _totalAmount =>
      (_subtotal - _totalDiscount).clamp(0, double.infinity);

  double get _totalPaid => _payments.fold(0, (s, p) => s + p.amountPaid);

  double get _balanceDue => _totalAmount - _totalPaid;

  // ── Unique id helper ─────────────────────────────────────────────────────
  String _uid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  // ── Item actions ─────────────────────────────────────────────────────────
  void _addItemDirectly(Item item, List<Employee> employees) {
    // Require a real employee to be selected before a quick-add.
    if (_activeEmployee.id.isEmpty) {
      _snack('Please select a technician first.', error: true);
      return;
    }
    setState(() {
      _lineItems.add(
        _LineItem(
          id: _uid(),
          item: item,
          employee: _activeEmployee,
          quantity: 1,
          unitPrice: item.price,
        ),
      );
    });
  }

  Future<void> _showAddItemDialog(Item item, List<Employee> employees) async {
    // Match by ID so the dropdown value is the exact object from the list.
    Employee selectedEmployee = employees.firstWhere(
      (e) => e.id == widget.defaultEmployee.id,
      orElse: () =>
          employees.isNotEmpty ? employees.first : widget.defaultEmployee,
    );
    int qty = 1;
    double price = item.price;
    final priceCtrl = TextEditingController(text: price.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Add – ${item.name}'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Employee picker
                DropdownButtonFormField<Employee>(
                  value: selectedEmployee,
                  decoration: const InputDecoration(
                    labelText: 'Assigned to',
                    border: OutlineInputBorder(),
                  ),
                  items: employees
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (e) {
                    if (e != null) setS(() => selectedEmployee = e);
                  },
                ),
                const SizedBox(height: 12),
                // Quantity
                Row(
                  children: [
                    const Text('Quantity'),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: qty > 1 ? () => setS(() => qty--) : null,
                    ),
                    Text(
                      '$qty',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setS(() => qty++),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Price
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: item.isCustomPrice
                        ? 'Custom Price'
                        : 'Unit Price',
                    prefixText: '\$',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => price = double.tryParse(v) ?? price,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _lineItems.add(
                    _LineItem(
                      id: _uid(),
                      item: item,
                      employee: selectedEmployee,
                      quantity: qty,
                      unitPrice: double.tryParse(priceCtrl.text) ?? item.price,
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    priceCtrl.dispose();
  }

  Future<void> _showAddDiscountDialog() async {
    const presets = [5.0, 10.0, 15.0, 20.0, 25.0, 50.0];
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    DiscountType type = DiscountType.percentage; // default to %
    double? selectedPreset;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Discount'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Type toggle
                SegmentedButton<DiscountType>(
                  segments: const [
                    ButtonSegment(
                      value: DiscountType.percentage,
                      label: Text('Percent %'),
                      icon: Icon(Icons.percent, size: 15),
                    ),
                    ButtonSegment(
                      value: DiscountType.fixed,
                      label: Text('Fixed \$'),
                      icon: Icon(Icons.attach_money, size: 15),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setS(() {
                    type = s.first;
                    selectedPreset = null;
                    amtCtrl.clear();
                  }),
                ),
                const SizedBox(height: 14),

                // Quick-select preset chips (only for percentage)
                if (type == DiscountType.percentage) ...[
                  const Text(
                    'Quick select',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: presets.map((p) {
                      final isSelected = selectedPreset == p;
                      return ChoiceChip(
                        label: Text('${p.toInt()}%'),
                        selected: isSelected,
                        onSelected: (_) => setS(() {
                          selectedPreset = p;
                          amtCtrl.text = p.toStringAsFixed(0);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],

                // Custom amount field
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: type == DiscountType.percentage
                        ? 'Custom percentage (%)'
                        : 'Amount (\$)',
                    border: const OutlineInputBorder(),
                    suffixText: type == DiscountType.percentage ? '%' : '\$',
                  ),
                  onChanged: (_) => setS(() => selectedPreset = null),
                ),
                const SizedBox(height: 12),

                // Optional description
                TextField(
                  controller: descCtrl,
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
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amtCtrl.text);
                if (amt == null || amt <= 0) return;
                setState(() {
                  _discounts.add(
                    Discount(
                      id: _uid(),
                      description: descCtrl.text.isNotEmpty
                          ? descCtrl.text
                          : type == DiscountType.percentage
                          ? '${amt.toStringAsFixed(amt % 1 == 0 ? 0 : 1)}% off'
                          : '\$${amt.toStringAsFixed(2)} off',
                      type: type,
                      amount: amt,
                    ),
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    descCtrl.dispose();
    amtCtrl.dispose();
  }

  // ── Save ─────────────────────────────────────────────────────────────────
  Future<void> _saveTransaction({required bool asPending}) async {
    if (_lineItems.isEmpty) {
      _snack('Add at least one service or item.', error: true);
      return;
    }

    // Guard against any item that has no real employee assigned.
    final unassigned = _lineItems.where((l) => l.employee.id.isEmpty).toList();
    if (unassigned.isNotEmpty) {
      _snack(
        'Every item must have a technician assigned. '
        'Please remove or reassign: '
        '${unassigned.map((l) => l.item.name).join(', ')}',
        error: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      // Status is always driven by balance: paid if fully settled, else pending.
      // (asPending=true means the user explicitly hit Save with no payment intent)
      final status = !asPending && _balanceDue <= 0
          ? TransactionStatus.paid
          : TransactionStatus.pending;

      final tx = Transaction(
        id: _savedTransactionId ?? '',
        items: _lineItems.map((l) => l.toTransactionItem()).toList(),
        customerId: _selectedCustomer?.id,
        customerName: _selectedCustomer?.name,
        discounts: _discounts,
        payments: _payments,
        status: status,
        subtotal: _subtotal,
        totalDiscount: _totalDiscount,
        totalAmount: _totalAmount,
        createdAt: widget.existingTransaction?.createdAt ?? now,
        updatedAt: now,
      );

      if (_savedTransactionId != null && _savedTransactionId!.isNotEmpty) {
        await _repo.updateTransaction(tx);
      } else {
        final newId = await _repo.createTransaction(tx);
        if (mounted) setState(() => _savedTransactionId = newId);
      }

      if (!mounted) return;
      final isPaid = status == TransactionStatus.paid;
      if (isPaid) {
        _snack('Transaction completed.');
        // Show receipt print dialog before returning to the home screen
        if (mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ReceiptPrintDialog(transaction: tx),
          );
        }
        // Award reward points and show SMS survey
        if (mounted) await _handlePostPayment(tx);
        if (mounted) Navigator.of(context).pop();
      } else if (asPending) {
        _snack('Transaction saved.');
        Navigator.of(context).pop();
      } else {
        // Partial payment – stay on screen so additional payments can be added.
        final remaining = _balanceDue.clamp(0.0, double.infinity);
        _snack(
          'Payment recorded. Balance remaining: \$${remaining.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      if (mounted) _snack('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingTransaction != null
              ? 'Resume – ${widget.defaultEmployee.name}'
              : 'New Transaction – ${widget.defaultEmployee.name}',
        ),
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<_ScreenData>(
              future: _screenDataFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final data = snap.data!;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left – item browser
                    Expanded(flex: 3, child: _buildItemBrowser(data)),
                    const VerticalDivider(width: 1),
                    // Right – order summary
                    SizedBox(width: 340, child: _buildOrderSummary(data)),
                  ],
                );
              },
            ),
    );
  }

  // ── Item browser (left panel) ─────────────────────────────────────────────
  Widget _buildItemBrowser(_ScreenData data) {
    // Filter items
    final filtered = data.items.where((item) {
      if (!item.isActive) return false;
      if (_selectedCategoryId != null && item.categoryId != _selectedCategoryId)
        return false;
      if (_searchQuery.isNotEmpty &&
          !item.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Customer + search bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Customer picker
              Expanded(
                child: _CustomerSearchField(
                  customers: data.customers,
                  selected: _selectedCustomer,
                  onChanged: (c) => setState(() => _selectedCustomer = c),
                ),
              ),
              const SizedBox(width: 12),
              // Search
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search services…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ],
          ),
        ),

        // Technician selector
        Container(
          color: Colors.blue.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.badge_outlined, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Technician:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: data.employees.map((emp) {
                      final isActive = emp.id == _activeEmployee.id;
                      final empColor = Color(emp.colorValue);
                      final isDark = empColor.computeLuminance() < 0.35;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(emp.name),
                          selected: isActive,
                          onSelected: (_) =>
                              setState(() => _activeEmployee = emp),
                          selectedColor: empColor.withOpacity(0.85),
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? (isDark ? Colors.white : Colors.grey.shade800)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Category chips
        if (data.categories.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _selectedCategoryId == null,
                  onTap: () => setState(() => _selectedCategoryId = null),
                ),
                ...data.categories.map(
                  (c) => _CategoryChip(
                    label: c.name,
                    selected: _selectedCategoryId == c.id,
                    onTap: () => setState(() => _selectedCategoryId = c.id),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Item grid
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No items found.'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Target ~110px per tile; aim for 6 cols, min 2
                    final cols = (constraints.maxWidth / 110).floor().clamp(
                      2,
                      8,
                    );
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        return _ItemTile(
                          item: item,
                          onTap: () => _addItemDirectly(item, data.employees),
                          onLongPress: () =>
                              _showAddItemDialog(item, data.employees),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Grouped line items (by employee) ─────────────────────────────────────
  Widget _buildGroupedLineItems(_ScreenData data) {
    if (_lineItems.isEmpty) {
      return const Center(
        child: Text(
          'No items added yet.\nTap a service to add it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Employees in order of first appearance in the order
    final seen = <String>{};
    final orderedEmployees = <Employee>[];
    for (final l in _lineItems) {
      if (seen.add(l.employee.id)) {
        orderedEmployees.add(l.employee);
      }
    }

    final sections = <Widget>[];
    for (final emp in orderedEmployees) {
      final empItems = _lineItems
          .where((l) => l.employee.id == emp.id)
          .toList();
      final empSubtotal = empItems.fold<double>(0, (s, l) => s + l.subtotal);
      final empColor = Color(emp.colorValue);
      final isDark = empColor.computeLuminance() < 0.35;

      // Employee section header
      sections.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: empColor.withOpacity(0.15),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: empColor,
                child: Text(
                  emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  emp.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '\$${empSubtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );

      // Items for this employee
      for (final l in empItems) {
        sections.add(
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 0,
            ),
            title: Text(
              l.item.name + (l.quantity > 1 ? ' \u00d7${l.quantity}' : ''),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('\$${l.subtotal.toStringAsFixed(2)}'),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                  onPressed: () => setState(() => _lineItems.remove(l)),
                ),
              ],
            ),
          ),
        );
      }
      sections.add(const Divider(height: 1));
    }

    return ListView(padding: EdgeInsets.zero, children: sections);
  }

  // ── Order summary (right panel) ───────────────────────────────────────────
  Widget _buildOrderSummary(_ScreenData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.grey.shade100,
          child: const Text(
            'Order Summary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const Divider(height: 1),

        // Action buttons row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.discount_outlined,
                  label: 'Discount',
                  onTap: _showAddDiscountDialog,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.save_outlined,
                  label: 'Save',
                  onTap: _lineItems.isEmpty
                      ? null
                      : () => _saveTransaction(asPending: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.add_card,
                  label: 'Sell GC',
                  onTap: _showSellGiftCardDialog,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Line items list grouped by employee
        Expanded(child: _buildGroupedLineItems(data)),

        const Divider(height: 1),

        // Totals + discounts + payments
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalRow('Subtotal', _subtotal),
              if (_discounts.isNotEmpty) ...[
                ..._discounts.asMap().entries.map((e) {
                  final d = e.value;
                  final idx = e.key;
                  final label = d.type == DiscountType.percentage
                      ? '${d.description} (${d.amount.toStringAsFixed(0)}%)'
                      : d.description;
                  return _TotalRow(
                    label,
                    -_discountValue(d),
                    color: Colors.green,
                    trailing: GestureDetector(
                      onTap: () => setState(() => _discounts.removeAt(idx)),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.red,
                      ),
                    ),
                  );
                }),
              ],
              const Divider(height: 16),
              _TotalRow('Total', _totalAmount, bold: true, fontSize: 18),
              if (_payments.isNotEmpty) ...[
                const SizedBox(height: 4),
                ..._payments.asMap().entries.map((e) {
                  final p = e.value;
                  final idx = e.key;
                  return _TotalRow(
                    'Paid (${p.paymentMethodName})',
                    p.amountPaid,
                    color: Colors.blue,
                    trailing: GestureDetector(
                      onTap: () => setState(() => _payments.removeAt(idx)),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.red,
                      ),
                    ),
                  );
                }),
                _TotalRow(
                  'Balance Due',
                  _balanceDue,
                  bold: true,
                  color: _balanceDue > 0 ? Colors.red : Colors.green,
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),

        // ── Inline payment entry ──────────────────────────────────────────
        if (_lineItems.isNotEmpty) _buildPaymentEntry(data),
      ],
    );
  }

  double _discountValue(Discount d) {
    if (d.type == DiscountType.percentage) {
      return _subtotal * d.amount / 100;
    }
    return d.amount;
  }

  // ── Inline payment entry panel ────────────────────────────────────────────
  Widget _buildPaymentEntry(_ScreenData data) {
    final remaining = _balanceDue.clamp(0.0, double.infinity);
    final isFullyPaid = remaining < 0.01;

    if (isFullyPaid) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.green.shade50,
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              'Fully paid',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
      );
    }

    final tender = double.tryParse(_tenderCtrl.text) ?? 0.0;
    final cashChange = _checkoutTab == _CheckoutTab.cash
        ? (tender - remaining).clamp(0.0, double.infinity)
        : 0.0;

    // Reward points section (shown when a customer with points is attached)
    final canRedeemRewards =
        _selectedCustomer != null &&
        _rewardSettings.enabled &&
        _selectedCustomer!.rewardPoints > 0 &&
        remaining > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Reward Points redemption (only when customer has points) ─────
          if (canRedeemRewards) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber.shade700, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_selectedCustomer!.rewardPoints.toStringAsFixed(0)} pts available (1 pt = \$1.00)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rewardPointsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Points to redeem',
                            prefixIcon: const Icon(Icons.star_border, size: 16),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: TextButton(
                              onPressed: () {
                                final max = _selectedCustomer!.rewardPoints
                                    .clamp(0.0, remaining);
                                _rewardPointsCtrl.text = max.toStringAsFixed(0);
                              },
                              child: const Text('Max'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
          ],

          // Header row
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                'Add Payment',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                'Remaining: \$${remaining.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Method selector
          Row(
            children: [
              _payTabBtn(
                ctx: context,
                icon: Icons.payments_outlined,
                label: 'Cash',
                active: _checkoutTab == _CheckoutTab.cash,
                onTap: () => setState(() {
                  _checkoutTab = _CheckoutTab.cash;
                  _tenderCtrl.text = remaining.toStringAsFixed(2);
                }),
              ),
              const SizedBox(width: 6),
              _payTabBtn(
                ctx: context,
                icon: Icons.credit_card,
                label: 'Card',
                active: _checkoutTab == _CheckoutTab.creditCard,
                onTap: () => setState(() {
                  _checkoutTab = _CheckoutTab.creditCard;
                  _tenderCtrl.text = remaining.toStringAsFixed(2);
                }),
              ),
              const SizedBox(width: 6),
              _payTabBtn(
                ctx: context,
                icon: Icons.more_horiz,
                label: 'Other',
                active: _checkoutTab == _CheckoutTab.other,
                onTap: () => setState(() {
                  _checkoutTab = _CheckoutTab.other;
                  _tenderCtrl.text = remaining.toStringAsFixed(2);
                }),
              ),
              const SizedBox(width: 6),
              _payTabBtn(
                ctx: context,
                icon: Icons.card_giftcard,
                label: 'Gift Card',
                active: _checkoutTab == _CheckoutTab.giftCard,
                onTap: () => setState(() {
                  _checkoutTab = _CheckoutTab.giftCard;
                  _lookedUpGiftCard = null;
                  _giftCardIdCtrl.clear();
                  _giftCardAmountCtrl.text = remaining.toStringAsFixed(2);
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Credit card processor selector
          if (_checkoutTab == _CheckoutTab.creditCard &&
              data.paymentMethods.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: data.paymentMethods.map((m) {
                final sel = m.id == _checkoutProcessor?.id;
                return ChoiceChip(
                  label: Text(
                    m.merchantName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: sel,
                  onSelected: (_) => setState(() => _checkoutProcessor = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          if (_checkoutTab == _CheckoutTab.creditCard &&
              data.paymentMethods.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'No card processor configured. Go to Admin → Payment Methods to add one.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Gift Card lookup
          if (_checkoutTab == _CheckoutTab.giftCard) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _giftCardIdCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Gift Card ID',
                      hintText: 'e.g. GC-001234',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.credit_card, size: 18),
                    ),
                    onSubmitted: (_) => _lookUpGiftCard(remaining),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 14,
                    ),
                  ),
                  onPressed: _isLookingUpCard
                      ? null
                      : () => _lookUpGiftCard(remaining),
                  child: _isLookingUpCard
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Look Up'),
                ),
              ],
            ),
            if (_lookedUpGiftCard != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.teal,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Balance: \$${_lookedUpGiftCard!.balance.toStringAsFixed(2)}'
                        '${_lookedUpGiftCard!.expiresAt != null ? ' · Expires ${_lookedUpGiftCard!.expiresAt!.month}/${_lookedUpGiftCard!.expiresAt!.day}/${_lookedUpGiftCard!.expiresAt!.year}' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.teal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _giftCardAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount to Apply',
                        prefixText: '\$',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: TextButton(
                          onPressed: () {
                            final max = _lookedUpGiftCard!.balance.clamp(
                              0.0,
                              remaining,
                            );
                            _giftCardAmountCtrl.text = max.toStringAsFixed(2);
                          },
                          child: const Text('Max'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],

          // Other – note field
          if (_checkoutTab == _CheckoutTab.other) ...[
            TextField(
              controller: _otherNoteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. check, gift card…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Amount row (hidden for gift card — amount entered in the lookup UI)
          if (_checkoutTab != _CheckoutTab.giftCard)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tenderCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _checkoutTab == _CheckoutTab.cash
                          ? 'Amount Tendered'
                          : 'Amount',
                      prefixText: '\$',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_checkoutTab == _CheckoutTab.cash) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(
                      () => _tenderCtrl.text = remaining.toStringAsFixed(2),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                    ),
                    child: const Text('Exact', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),

          // Cash change display
          if (_checkoutTab == _CheckoutTab.cash && tender > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cashChange >= 0
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cashChange >= 0
                      ? Colors.green.shade200
                      : Colors.orange.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Change',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '\$${cashChange.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Payment action button – label adapts to whether this payment settles the balance
          Builder(
            builder: (context) {
              final gcAmt = _checkoutTab == _CheckoutTab.giftCard
                  ? (double.tryParse(_giftCardAmountCtrl.text) ?? 0.0)
                  : 0.0;
              final effectiveTender = _checkoutTab == _CheckoutTab.giftCard
                  ? gcAmt
                  : tender;
              final gcReady =
                  _checkoutTab != _CheckoutTab.giftCard ||
                  (_lookedUpGiftCard != null && gcAmt > 0);
              final willComplete =
                  gcReady && effectiveTender >= remaining - 0.01;
              return ElevatedButton.icon(
                icon: Icon(
                  willComplete
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  size: 18,
                ),
                label: Text(
                  willComplete
                      ? 'Complete Transaction'
                      : 'Apply Partial Payment',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: willComplete ? Colors.green : null,
                  foregroundColor: willComplete ? Colors.white : null,
                ),
                onPressed: _isSaving ? null : () => _addPaymentAndSave(data),
              );
            },
          ),

          // SMS toggle (only meaningful for transactions with a customer on file)
          if (_selectedCustomer != null) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                _sendSmsThisTransaction
                    ? Icons.sms_outlined
                    : Icons.sms_failed_outlined,
                size: 18,
                color: _sendSmsThisTransaction ? Colors.teal : Colors.grey,
              ),
              title: const Text(
                'Send thank-you SMS',
                style: TextStyle(fontSize: 12),
              ),
              value:
                  _sendSmsThisTransaction &&
                  _selectedCustomer?.smsOptOut != true,
              onChanged: _selectedCustomer?.smsOptOut == true
                  ? null
                  : (v) => setState(() => _sendSmsThisTransaction = v),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addPaymentAndSave(_ScreenData data) async {
    final remaining = _balanceDue.clamp(0.0, double.infinity);

    // ── Gift Card branch ────────────────────────────────────────────────────
    if (_checkoutTab == _CheckoutTab.giftCard) {
      final card = _lookedUpGiftCard;
      if (card == null) {
        _snack('Please look up a gift card first.', error: true);
        return;
      }
      final amt = double.tryParse(_giftCardAmountCtrl.text);
      if (amt == null || amt <= 0) {
        _snack('Enter a valid amount to apply.', error: true);
        return;
      }
      if (amt > card.balance + 0.001) {
        _snack(
          'Amount exceeds gift card balance (\$${card.balance.toStringAsFixed(2)}).',
          error: true,
        );
        return;
      }

      final paid = amt.clamp(0.0, remaining);

      // First save the transaction so we have an ID to pass to the deduction.
      await _saveTransaction(asPending: false);

      // Deduct from the gift card (best-effort — transaction already saved).
      try {
        await _repo.deductFromGiftCard(
          card.id,
          paid,
          transactionId: null, // no doc ID available synchronously; acceptable
          note: 'POS payment',
        );
      } catch (e) {
        _snack('Gift card deducted failed: $e', error: true);
      }

      setState(() {
        _payments.add(
          Payment(
            paymentMethodId: 'gift_card:${card.cardId}',
            paymentMethodName: 'Gift Card (${card.cardId})',
            amountPaid: paid,
            paymentDate: DateTime.now(),
          ),
        );
        _lookedUpGiftCard = null;
        _giftCardIdCtrl.clear();
        _giftCardAmountCtrl.clear();
      });
      return;
    }

    // ── Standard branch ─────────────────────────────────────────────────────
    final amt = double.tryParse(_tenderCtrl.text);
    if (amt == null || amt <= 0) {
      _snack('Enter a valid amount.', error: true);
      return;
    }

    final String pmId;
    final String pmName;
    if (_checkoutTab == _CheckoutTab.cash) {
      pmId = 'cash';
      pmName = 'Cash';
    } else if (_checkoutTab == _CheckoutTab.creditCard) {
      // Helcim — route to dedicated dialog
      final method = _checkoutProcessor;
      if (method != null &&
          method.processorType == PaymentProcessorType.helcim) {
        await _processHelcimPayment(amt, method);
        return;
      }
      pmId = _checkoutProcessor?.id ?? 'credit_card';
      pmName = _checkoutProcessor?.merchantName ?? 'Credit Card';
    } else {
      final note = _otherNoteCtrl.text.trim();
      pmId = 'other';
      pmName = note.isNotEmpty ? 'Other – $note' : 'Other';
    }

    // Record up to the remaining balance (change is given as physical cash)
    final paid = amt.clamp(0.0, remaining);

    setState(() {
      _payments.add(
        Payment(
          paymentMethodId: pmId,
          paymentMethodName: pmName,
          amountPaid: paid,
          paymentDate: DateTime.now(),
        ),
      );
      _tenderCtrl.clear();
      _otherNoteCtrl.clear();
    });

    // Open cash drawer immediately — before the receipt dialog so the
    // drawer is ready as the cashier collects payment.
    if (_checkoutTab == _CheckoutTab.cash ||
        _checkoutProcessor?.isCash == true) {
      CashDrawerService().openDrawerOnCashPayment();
    }

    // Save – status is auto-determined by balance
    await _saveTransaction(asPending: false);
  }

  // ── Reward points redemption ──────────────────────────────────────────────
  Future<void> _applyRewardPoints() async {
    final customer = _selectedCustomer;
    if (customer == null) return;

    final points = double.tryParse(_rewardPointsCtrl.text);
    if (points == null || points <= 0) {
      _snack('Enter a valid number of points.', error: true);
      return;
    }
    final balance = _balanceDue.clamp(0.0, double.infinity);
    final maxRedeemable = points
        .clamp(0.0, customer.rewardPoints)
        .clamp(0.0, balance);
    if (maxRedeemable <= 0) {
      _snack('No points available to redeem.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Deduct points from customer immediately; save tx first if needed
      await _saveTransaction(asPending: false);
      await _repo.adjustCustomerPoints(customer.id, -maxRedeemable);

      // Refresh customer
      final refreshed = await _repo.getCustomer(customer.id);
      setState(() {
        _payments.add(
          Payment(
            paymentMethodId: 'reward_points',
            paymentMethodName: 'Reward Points',
            amountPaid: maxRedeemable,
            paymentDate: DateTime.now(),
          ),
        );
        _selectedCustomer = refreshed ?? _selectedCustomer;
        _rewardPointsCtrl.clear();
      });

      _snack(
        '${maxRedeemable.toStringAsFixed(0)} points redeemed (\$${maxRedeemable.toStringAsFixed(2)} off).',
      );
    } catch (e) {
      _snack('Failed to redeem points: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Helcim payment flow ───────────────────────────────────────────────────
  Future<void> _processHelcimPayment(
    double amount,
    PaymentMethod method,
  ) async {
    final config = method.additionalConfig ?? {};
    final accountGuid = config['accountGuid']?.toString() ?? '';
    final terminalId = config['terminalId']?.toString();
    final apiToken = method.processorApiKey;

    if (accountGuid.isEmpty || apiToken.isEmpty) {
      _snack(
        'Helcim is not fully configured. Add Account GUID and API Token in Admin → Payment Methods.',
        error: true,
      );
      return;
    }

    final helcim = HelcimService(
      apiToken: apiToken,
      accountGuid: accountGuid,
      terminalId: terminalId,
    );

    if (!mounted) return;
    final result = await showDialog<_HelcimPaymentDialogResult?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HelcimPaymentDialog(
        amount: amount,
        helcim: helcim,
        merchantName: method.merchantName,
      ),
    );

    if (result == null || !result.confirmed) return;

    setState(() => _isSaving = true);
    try {
      final paid = amount.clamp(0.0, _balanceDue.clamp(0.0, double.infinity));
      setState(() {
        _payments.add(
          Payment(
            paymentMethodId: method.id,
            paymentMethodName: method.merchantName,
            amountPaid: paid,
            paymentDate: DateTime.now(),
          ),
        );
        _tenderCtrl.clear();
      });
      await _saveTransaction(asPending: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Post-payment: award points + SMS survey ───────────────────────────────
  Future<void> _handlePostPayment(Transaction tx) async {
    // Award reward points
    final customer = _selectedCustomer;
    if (customer != null && _rewardSettings.enabled) {
      final cashPaid = tx.payments
          .where(
            (p) =>
                p.paymentMethodId != 'reward_points' &&
                !p.paymentMethodId.startsWith('gift_card:'),
          )
          .fold<double>(0, (s, p) => s + p.amountPaid);
      final pointsEarned = _rewardSettings.pointsEarned(cashPaid);
      if (pointsEarned > 0) {
        try {
          await _repo.adjustCustomerPoints(
            customer.id,
            pointsEarned.toDouble(),
          );
          if (mounted) {
            _snack('${customer.name} earned $pointsEarned reward point(s)!');
          }
        } catch (_) {}
      }
    }

    // SMS survey
    await _showPostPaymentSurvey(tx);
  }

  Future<void> _showPostPaymentSurvey(Transaction tx) async {
    if (!mounted) return;

    SmsSettings smsSettings;
    try {
      smsSettings = await _repo.getSmsSettings();
    } catch (_) {
      return;
    }
    if (!smsSettings.enabled) return;

    final customer = _selectedCustomer;
    if (customer?.smsOptOut == true) return;
    if (!_sendSmsThisTransaction) return;

    final customerName = customer?.name ?? tx.customerName ?? 'Valued Customer';
    final customerPhone = customer?.phone ?? '';

    if (!mounted) return;
    final rating = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SurveyRatingDialog(customerName: customerName),
    );
    if (rating == null) return;

    if (rating) {
      await _handlePositiveFeedback(
        tx: tx,
        smsSettings: smsSettings,
        customerName: customerName,
        customerPhone: customerPhone,
        customer: customer,
      );
    } else {
      await _handleNegativeFeedback(
        tx: tx,
        smsSettings: smsSettings,
        customerName: customerName,
        customerPhone: customerPhone,
        customer: customer,
      );
    }
  }

  Future<void> _handlePositiveFeedback({
    required Transaction tx,
    required SmsSettings smsSettings,
    required String customerName,
    required String customerPhone,
    Customer? customer,
  }) async {
    if (!mounted) return;
    final msg = smsSettings.buildPositiveMessage(customerName);
    final result = await showDialog<_SmsPreviewResult?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SmsPreviewDialog(
        title: 'Send Thank-You SMS',
        subtitle:
            'The customer left a positive rating. Review and send the message below.',
        initialMessage: msg,
        phoneNumber: customerPhone,
        positiveIcon: true,
      ),
    );
    if (result == null || !result.shouldSend || customerPhone.isEmpty) return;

    final sms = SmsService(
      accountSid: smsSettings.accountSid,
      authToken: smsSettings.authToken,
      fromNumber: smsSettings.fromNumber,
    );
    final sendResult = await sms.send(
      toNumber: customerPhone,
      body: result.message,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SmsService.resultMessage(sendResult)),
          backgroundColor: sendResult == SmsSendResult.success
              ? Colors.green
              : Colors.orange,
        ),
      );
    }
  }

  Future<void> _handleNegativeFeedback({
    required Transaction tx,
    required SmsSettings smsSettings,
    required String customerName,
    required String customerPhone,
    Customer? customer,
  }) async {
    if (!mounted) return;
    final feedbackResult = await showDialog<_NegativeFeedbackResult?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NegativeFeedbackDialog(
        customerName: customerName,
        negativeMessage: smsSettings.buildNegativeMessage(customerName),
        customerPhone: customerPhone,
      ),
    );
    if (feedbackResult == null) return;

    bool smsSent = false;
    if (feedbackResult.sendSms && customerPhone.isNotEmpty) {
      final sms = SmsService(
        accountSid: smsSettings.accountSid,
        authToken: smsSettings.authToken,
        fromNumber: smsSettings.fromNumber,
      );
      final sendResult = await sms.send(
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

    if (feedbackResult.feedbackText.trim().isNotEmpty) {
      try {
        await _repo.saveCustomerFeedback(
          CustomerFeedback(
            id: '',
            transactionId: tx.id,
            customerId: customer?.id,
            customerName: customerName,
            customerPhone: customerPhone,
            feedbackText: feedbackResult.feedbackText.trim(),
            smsSent: smsSent,
            createdAt: DateTime.now(),
          ),
        );
      } catch (_) {}
    }
  }

  // ── Sell Gift Card dialog ─────────────────────────────────────────────────
  Future<void> _showSellGiftCardDialog() async {
    final cardIdCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? expiresAt;
    String? error;
    bool busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_card, color: Colors.teal),
              SizedBox(width: 8),
              Text('Sell a Gift Card'),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This will issue a new gift card and add its value to the current transaction bill.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
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
                    autofocus: true,
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
                      labelText: 'Card Value *',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                      helperText: 'Amount charged to customer & loaded on card',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiresAt == null
                              ? 'No expiration date'
                              : 'Expires: ${expiresAt!.month}/${expiresAt!.day}/${expiresAt!.year}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
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
                          if (picked != null) setDlg(() => expiresAt = picked);
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'e.g. customer name, occasion',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_shopping_cart, size: 18),
              label: Text(busy ? 'Adding...' : 'Issue & Add to Bill'),
              onPressed: busy
                  ? null
                  : () async {
                      final cardId = cardIdCtrl.text.trim();
                      final amount = double.tryParse(amountCtrl.text.trim());
                      if (cardId.isEmpty) {
                        setDlg(() => error = 'Please enter a Card ID.');
                        return;
                      }
                      if (amount == null || amount <= 0) {
                        setDlg(
                          () => error = 'Please enter a valid card value.',
                        );
                        return;
                      }
                      setDlg(() => busy = true);
                      try {
                        final existing = await _repo.getGiftCardByCardId(
                          cardId,
                        );
                        if (existing != null) {
                          setDlg(() {
                            busy = false;
                            error =
                                'Card "$cardId" already exists. Use "Reload" in Gift Card admin to add balance.';
                          });
                          return;
                        }
                        final now = DateTime.now();
                        // Ensure the transaction exists before adding the item
                        if (_savedTransactionId == null ||
                            _savedTransactionId!.isEmpty) {
                          await _saveTransaction(asPending: true);
                        }
                        if (_savedTransactionId == null ||
                            _savedTransactionId!.isEmpty) {
                          setDlg(() {
                            busy = false;
                            error = 'Could not save transaction.';
                          });
                          return;
                        }
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
                              transactionId: _savedTransactionId,
                              note: 'Sold at POS',
                            ),
                          ],
                          updatedAt: now,
                        );
                        await _repo.createGiftCard(card);
                        // Add gift card sale as a line item
                        final item = TransactionItem(
                          id: now.millisecondsSinceEpoch.toString(),
                          itemId: 'gift_card_sale',
                          itemName: 'Gift Card ($cardId)',
                          employeeId: '',
                          employeeName: 'Gift Card Sales',
                          itemPrice: amount,
                          quantity: 1,
                          subtotal: amount,
                        );
                        await _repo.addGiftCardSaleToTransaction(
                          _savedTransactionId!,
                          item,
                          amount,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Gift card $cardId (\$${amount.toStringAsFixed(2)}) issued and added to bill.',
                              ),
                              backgroundColor: Colors.teal,
                            ),
                          );
                        }
                        // Reload the transaction state
                        final updated = await _repo.getTransaction(
                          _savedTransactionId!,
                        );
                        if (mounted && updated != null) {
                          setState(() {
                            _lineItems.clear();
                            _discounts
                              ..clear()
                              ..addAll(updated.discounts);
                            _payments
                              ..clear()
                              ..addAll(updated.payments);
                          });
                        }
                      } catch (e) {
                        setDlg(() {
                          busy = false;
                          error = 'Failed: $e';
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );

    cardIdCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _lookUpGiftCard(double remaining) async {
    final cardId = _giftCardIdCtrl.text.trim();
    if (cardId.isEmpty) {
      _snack('Enter a gift card ID.', error: true);
      return;
    }
    setState(() => _isLookingUpCard = true);
    try {
      final card = await _repo.getGiftCardByCardId(cardId);
      if (card == null) {
        _snack('Gift card "$cardId" not found.', error: true);
        setState(() {
          _lookedUpGiftCard = null;
          _isLookingUpCard = false;
        });
        return;
      }
      if (!card.isActive) {
        _snack('This gift card is inactive.', error: true);
        setState(() {
          _lookedUpGiftCard = null;
          _isLookingUpCard = false;
        });
        return;
      }
      if (card.isExpired) {
        _snack('This gift card has expired.', error: true);
        setState(() {
          _lookedUpGiftCard = null;
          _isLookingUpCard = false;
        });
        return;
      }
      if (card.balance <= 0) {
        _snack('This gift card has no remaining balance.', error: true);
        setState(() {
          _lookedUpGiftCard = null;
          _isLookingUpCard = false;
        });
        return;
      }
      final maxApply = card.balance.clamp(0.0, remaining);
      setState(() {
        _lookedUpGiftCard = card;
        _isLookingUpCard = false;
        _giftCardAmountCtrl.text = maxApply.toStringAsFixed(2);
      });
    } catch (e) {
      _snack('Error: $e', error: true);
      setState(() => _isLookingUpCard = false);
    }
  }

  Widget _payTabBtn({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = Theme.of(ctx).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            border: Border.all(color: active ? color : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<_ScreenData> _loadScreenData() async {
    final results = await Future.wait([
      _repo.getItems().first,
      _repo.getItemCategories().first,
      _repo.getEmployees().first,
      _repo.getCustomers().first,
      _repo.getPaymentMethods().first,
    ]);

    final items = (results[0] as List).cast<Item>();
    final categories = (results[1] as List).cast<ItemCategory>();
    final employees = (results[2] as List).cast<Employee>();
    final customers = (results[3] as List).cast<Customer>();
    final paymentMethods = (results[4] as List).cast<PaymentMethod>();

    return _ScreenData(
      items: items,
      categories: categories,
      employees: employees.where((e) => e.isActive).toList(),
      customers: customers,
      paymentMethods: paymentMethods,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tenderCtrl.dispose();
    _otherNoteCtrl.dispose();
    _giftCardIdCtrl.dispose();
    _giftCardAmountCtrl.dispose();
    _rewardPointsCtrl.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Small data container
// ---------------------------------------------------------------------------
class _ScreenData {
  final List<Item> items;
  final List<ItemCategory> categories;
  final List<Employee> employees;
  final List<Customer> customers;
  final List<PaymentMethod> paymentMethods;

  _ScreenData({
    required this.items,
    required this.categories,
    required this.employees,
    required this.customers,
    required this.paymentMethods,
  });
}

enum _CheckoutTab { cash, creditCard, giftCard, other }

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------
class _ItemTile extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ItemTile({required this.item, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final pad = (w * 0.08).clamp(6.0, 12.0);
            final nameSize = (w * 0.11).clamp(10.0, 14.0);
            final priceSize = (w * 0.10).clamp(9.0, 13.0);
            final iconSize = (w * 0.12).clamp(12.0, 18.0);
            return Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: nameSize,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '\$${item.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: priceSize,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        item.type == ItemType.service
                            ? Icons.spa_outlined
                            : Icons.inventory_2_outlined,
                        size: iconSize,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
      ),
    );
  }
}

class _CustomerSearchField extends StatefulWidget {
  final List<Customer> customers;
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;

  const _CustomerSearchField({
    required this.customers,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends State<_CustomerSearchField> {
  Future<void> _openSearch() async {
    final result = await showCustomerCheckIn(context);
    if (result != null) {
      widget.onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.selected?.name ?? 'Walk-in / No customer';
    return GestureDetector(
      onTap: _openSearch,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Customer (optional)',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: widget.selected == null ? Colors.grey.shade600 : null,
                ),
              ),
            ),
            if (widget.selected != null)
              GestureDetector(
                onTap: () => widget.onChanged(null),
                child: const Icon(Icons.close, size: 16),
              )
            else
              const Icon(Icons.search, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchDialog extends StatefulWidget {
  /// Returned when the user explicitly clears the customer selection.
  static final kClearSentinel = Customer(
    id: '__clear__',
    name: '',
    phone: '',
    birthMonth: 1,
    birthDay: 1,
    isActive: true,
    rewardPoints: 0,
    createdAt: DateTime(0),
    updatedAt: DateTime(0),
  );

  final List<Customer> customers;
  const _CustomerSearchDialog({required this.customers});

  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return widget.customers;
    return widget.customers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          children: [
            // Title + search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Customer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _ctrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Walk-in option
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Walk-in / No customer'),
              onTap: () =>
                  Navigator.pop(context, _CustomerSearchDialog.kClearSentinel),
            ),
            const Divider(height: 1),
            // Results
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No customers found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (ctx, i) {
                        final c = _filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(c.name),
                          subtitle: c.phone.isNotEmpty ? Text(c.phone) : null,
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;
  final Color? color;
  final double fontSize;
  final Widget? trailing;

  const _TotalRow(
    this.label,
    this.amount, {
    this.bold = false,
    this.color,
    this.fontSize = 14,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
          Expanded(child: Text(label, style: style)),
          Text(
            '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}',
            style: style,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button used inside the order summary panel
// ---------------------------------------------------------------------------
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? Colors.white : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      elevation: enabled ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.35)
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade400,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HELCIM PAYMENT DIALOG
// =============================================================================

class _HelcimPaymentDialogResult {
  final bool confirmed;
  final String? helcimTransactionId;
  const _HelcimPaymentDialogResult({
    required this.confirmed,
    this.helcimTransactionId,
  });
}

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

// =============================================================================
// SURVEY + SMS DIALOGS
// =============================================================================

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
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.4)),
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
                'No phone number on file — SMS cannot be sent.',
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
              "We're sorry ${widget.customerName}'s experience wasn't perfect. "
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
