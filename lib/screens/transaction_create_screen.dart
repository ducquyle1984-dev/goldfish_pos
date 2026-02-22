import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

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
  PaymentMethodInfo? _checkoutProcessor;
  final _tenderCtrl = TextEditingController();
  final _otherNoteCtrl = TextEditingController();

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
        Navigator.of(context).pop();
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
                  label: Text(m.name, style: const TextStyle(fontSize: 12)),
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

          // Amount row
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
              final willComplete = tender > 0 && tender >= remaining - 0.01;
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
        ],
      ),
    );
  }

  Future<void> _addPaymentAndSave(_ScreenData data) async {
    final remaining = _balanceDue.clamp(0.0, double.infinity);
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
      pmId = _checkoutProcessor?.id ?? 'credit_card';
      pmName = _checkoutProcessor?.name ?? 'Credit Card';
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

    // Save – status is auto-determined by balance
    await _saveTransaction(asPending: false);
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

  Future<Employee?> _pickEmployee(
    BuildContext context,
    List<Employee> employees,
    Employee current,
  ) {
    return showDialog<Employee>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Assign Employee'),
        children: employees
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e),
                child: Row(
                  children: [
                    if (e.id == current.id)
                      const Icon(Icons.check, size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(e.name),
                  ],
                ),
              ),
            )
            .toList(),
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
    final paymentMethods = (results[4] as List)
        .cast<PaymentMethod>()
        .map((m) => PaymentMethodInfo(id: m.id, name: m.merchantName))
        .toList();

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
  final List<PaymentMethodInfo> paymentMethods;

  _ScreenData({
    required this.items,
    required this.categories,
    required this.employees,
    required this.customers,
    required this.paymentMethods,
  });
}

enum _CheckoutTab { cash, creditCard, other }

class PaymentMethodInfo {
  final String id;
  final String name;
  PaymentMethodInfo({required this.id, required this.name});
}

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
    final result = await showDialog<Customer?>(
      context: context,
      builder: (ctx) => _CustomerSearchDialog(customers: widget.customers),
    );
    // result == null means dialog was dismissed without selection
    // result == _CustomerSearchDialog.kClearSentinel means clear
    if (result == _CustomerSearchDialog.kClearSentinel) {
      widget.onChanged(null);
    } else if (result != null) {
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
          (c.phone?.toLowerCase().contains(q) ?? false);
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
                          subtitle: c.phone != null ? Text(c.phone!) : null,
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
