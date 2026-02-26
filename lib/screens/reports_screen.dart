import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Reports Screen – Daily & Payroll reports with date-range filtering
// ---------------------------------------------------------------------------
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = PosRepository();
  late TabController _tab;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _loading = false;
  List<Transaction> _transactions = [];
  String? _error;

  // ── Customer data ─────────────────────────────────────────────────────────
  List<Customer> _customers = [];

  // ── Filter state ──────────────────────────────────────────────────────────
  List<ItemCategory> _categories = [];
  Map<String, String> _itemCategoryMap = {}; // itemId → categoryId
  Set<String> _selCategoryIds = {};
  Set<String> _selEmployeeIds = {};
  Set<TransactionStatus> _selStatuses = {};
  Set<String> _selPaymentMethods = {};

  // Active quick-date label (Today / Yesterday / etc.)
  String? _activeQuickLabel;

  // Whether to include voided transactions in the report
  bool _includeVoided = false;

  // Derived from loaded transactions
  List<String> get _allEmployeeNames {
    final names = <String>{};
    for (final tx in _transactions) {
      for (final item in tx.items) {
        names.add(item.employeeName);
      }
    }
    return names.toList()..sort();
  }

  Map<String, String> get _employeeNameToId {
    final map = <String, String>{};
    for (final tx in _transactions) {
      for (final item in tx.items) {
        map[item.employeeName] = item.employeeId;
      }
    }
    return map;
  }

  List<String> get _allPaymentMethodNames {
    final names = <String>{};
    for (final tx in _transactions) {
      for (final p in tx.payments) {
        names.add(p.paymentMethodName);
      }
    }
    return names.toList()..sort();
  }

  bool get _hasActiveFilters =>
      _selCategoryIds.isNotEmpty ||
      _selEmployeeIds.isNotEmpty ||
      _selStatuses.isNotEmpty ||
      _selPaymentMethods.isNotEmpty;

  List<Transaction> get _filteredTransactions {
    return _transactions.where((tx) {
      // Category filter: match if any item belongs to a selected category
      if (_selCategoryIds.isNotEmpty) {
        final hasCat = tx.items.any(
          (i) => _selCategoryIds.contains(_itemCategoryMap[i.itemId]),
        );
        if (!hasCat) return false;
      }
      // Employee filter
      if (_selEmployeeIds.isNotEmpty) {
        final hasEmp = tx.items.any(
          (i) => _selEmployeeIds.contains(i.employeeId),
        );
        if (!hasEmp) return false;
      }
      // Status filter
      if (_selStatuses.isNotEmpty && !_selStatuses.contains(tx.status)) {
        return false;
      }
      // Payment method filter
      if (_selPaymentMethods.isNotEmpty) {
        final hasPm = tx.payments.any(
          (p) => _selPaymentMethods.contains(p.paymentMethodName),
        );
        if (!hasPm) return false;
      }
      return true;
    }).toList();
  }

  static final _currency = NumberFormat.currency(symbol: '\$');
  static final _dateLabel = DateFormat('MMM d, yyyy');
  static final _timeLabel = DateFormat('h:mm a');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Loads transactions for the selected date range. Category/item data is
  /// fetched lazily the first time the filter sheet is opened.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final txns = await _repo.getTransactionsByDateRange(
        _startDate,
        _endDate,
        includeVoided: _includeVoided,
      );
      final customers = await _repo.getAllCustomers();
      if (mounted) {
        setState(() {
          _transactions = txns;
          _customers = customers;
        });
      }
    } catch (e, st) {
      debugPrint('ReportsScreen _load error: $e\n$st');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Eagerly loads categories + items when the filter sheet is first opened.
  /// Safe to call multiple times; skips if already loaded.
  Future<void> _ensureFilterDataLoaded() async {
    if (_categories.isNotEmpty || _itemCategoryMap.isNotEmpty) return;
    try {
      final cats = await _repo.getItemCategories().first;
      final items = await _repo.getItems().first;
      final catMap = <String, String>{};
      for (final item in items) {
        catMap[item.id] = item.categoryId;
      }
      if (mounted) {
        setState(() {
          _categories = cats;
          _itemCategoryMap = catMap;
        });
      }
    } catch (e, st) {
      debugPrint('ReportsScreen filter data error: $e\n$st');
    }
  }

  // ── Filter bottom sheet ──────────────────────────────────────────────────
  Future<void> _showFilterSheet() async {
    // Load categories/items on first open
    await _ensureFilterDataLoaded();
    var selCats = Set<String>.from(_selCategoryIds);
    var selEmps = Set<String>.from(_selEmployeeIds);
    var selStatuses = Set<TransactionStatus>.from(_selStatuses);
    var selPm = Set<String>.from(_selPaymentMethods);
    final empNameToId = _employeeNameToId;
    final empNames = _allEmployeeNames;
    final pmNames = _allPaymentMethodNames;
    final cats = _categories;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget section(String title, Widget child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              child,
              const Divider(),
            ],
          );

          Widget chips<T>({
            required List<T> items,
            required String Function(T) label,
            required bool Function(T) selected,
            required void Function(T) onTap,
          }) => Wrap(
            spacing: 6,
            runSpacing: 4,
            children: items.map((item) {
              final sel = selected(item);
              return FilterChip(
                label: Text(label(item), style: const TextStyle(fontSize: 12)),
                selected: sel,
                onSelected: (_) {
                  setS(() => onTap(item));
                },
                selectedColor: Colors.blue.shade100,
                checkmarkColor: Colors.blue.shade700,
                labelStyle: TextStyle(color: sel ? Colors.blue.shade800 : null),
              );
            }).toList(),
          );

          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Filter Transactions',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setS(() {
                            selCats = {};
                            selEmps = {};
                            selStatuses = {};
                            selPm = {};
                          });
                        },
                        child: const Text('Clear all'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Scrollable content
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: [
                      // Status
                      section(
                        'Status',
                        chips<TransactionStatus>(
                          items: [
                            TransactionStatus.paid,
                            TransactionStatus.pending,
                          ],
                          label: (s) =>
                              s == TransactionStatus.paid ? 'Paid' : 'Pending',
                          selected: (s) => selStatuses.contains(s),
                          onTap: (s) => selStatuses.contains(s)
                              ? selStatuses.remove(s)
                              : selStatuses.add(s),
                        ),
                      ),
                      // Categories
                      if (cats.isNotEmpty)
                        section(
                          'Service Category',
                          chips<ItemCategory>(
                            items: cats,
                            label: (c) => c.name,
                            selected: (c) => selCats.contains(c.id),
                            onTap: (c) => selCats.contains(c.id)
                                ? selCats.remove(c.id)
                                : selCats.add(c.id),
                          ),
                        ),
                      // Employees
                      if (empNames.isNotEmpty)
                        section(
                          'Technician',
                          chips<String>(
                            items: empNames,
                            label: (n) => n,
                            selected: (n) =>
                                selEmps.contains(empNameToId[n] ?? ''),
                            onTap: (n) {
                              final id = empNameToId[n] ?? '';
                              selEmps.contains(id)
                                  ? selEmps.remove(id)
                                  : selEmps.add(id);
                            },
                          ),
                        ),
                      // Payment methods
                      if (pmNames.isNotEmpty)
                        section(
                          'Payment Method',
                          chips<String>(
                            items: pmNames,
                            label: (n) => n,
                            selected: (n) => selPm.contains(n),
                            onTap: (n) => selPm.contains(n)
                                ? selPm.remove(n)
                                : selPm.add(n),
                          ),
                        ),
                    ],
                  ),
                ),
                // Apply button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _selCategoryIds = selCats;
                            _selEmployeeIds = selEmps;
                            _selStatuses = selStatuses;
                            _selPaymentMethods = selPm;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply Filters'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Date range picker ────────────────────────────────────────────────────
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: Colors.blue.shade700),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _activeQuickLabel = null; // custom range — deselect all chips
      });
      _load();
    }
  }

  void _setQuick(DateTime start, DateTime end, String label) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _activeQuickLabel = label;
    });
    _load();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sameDay =
        _startDate.year == _endDate.year &&
        _startDate.month == _endDate.month &&
        _startDate.day == _endDate.day;
    final rangeText = sameDay
        ? _dateLabel.format(_startDate)
        : '${_dateLabel.format(_startDate)} – ${_dateLabel.format(_endDate)}';

    return Column(
      children: [
        // ── Header bar ───────────────────────────────────────────────
        Container(
          color: Colors.blue.shade700,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + date range
              Row(
                children: [
                  const Icon(
                    Icons.bar_chart_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Reports',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Filter button
                  GestureDetector(
                    onTap: _showFilterSheet,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _hasActiveFilters
                            ? Colors.amber.shade600
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _hasActiveFilters
                              ? Colors.amber.shade300
                              : Colors.white.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_list,
                            size: 14,
                            color: _hasActiveFilters
                                ? Colors.white
                                : Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _hasActiveFilters
                                ? 'Filters (${_selCategoryIds.length + _selEmployeeIds.length + _selStatuses.length + _selPaymentMethods.length})'
                                : 'Filter',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Range display + picker
                  GestureDetector(
                    onTap: _pickRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            rangeText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Quick-range chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _QuickChip(
                      label: 'Today',
                      isSelected: _activeQuickLabel == 'Today',
                      onTap: () {
                        final d = DateTime.now();
                        _setQuick(d, d, 'Today');
                      },
                    ),
                    _QuickChip(
                      label: 'Yesterday',
                      isSelected: _activeQuickLabel == 'Yesterday',
                      onTap: () {
                        final d = DateTime.now().subtract(
                          const Duration(days: 1),
                        );
                        _setQuick(d, d, 'Yesterday');
                      },
                    ),
                    _QuickChip(
                      label: 'This Week',
                      isSelected: _activeQuickLabel == 'This Week',
                      onTap: () {
                        final now = DateTime.now();
                        final start = now.subtract(
                          Duration(days: now.weekday - 1),
                        );
                        _setQuick(start, now, 'This Week');
                      },
                    ),
                    _QuickChip(
                      label: 'This Month',
                      isSelected: _activeQuickLabel == 'This Month',
                      onTap: () {
                        final now = DateTime.now();
                        _setQuick(
                          DateTime(now.year, now.month, 1),
                          now,
                          'This Month',
                        );
                      },
                    ),
                    _QuickChip(
                      label: 'Last Month',
                      isSelected: _activeQuickLabel == 'Last Month',
                      onTap: () {
                        final now = DateTime.now();
                        final first = DateTime(now.year, now.month - 1, 1);
                        final last = DateTime(now.year, now.month, 0);
                        _setQuick(first, last, 'Last Month');
                      },
                    ),
                    const SizedBox(width: 8),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Colors.white24,
                    ),
                    const SizedBox(width: 8),
                    // Voided toggle
                    GestureDetector(
                      onTap: () {
                        setState(() => _includeVoided = !_includeVoided);
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _includeVoided
                              ? Colors.red.shade400
                              : Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _includeVoided
                                ? Colors.red.shade200
                                : Colors.white.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _includeVoided
                                  ? Icons.visibility
                                  : Icons.visibility_off_outlined,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Voided',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Daily Report'),
                  Tab(text: 'Payroll'),
                  Tab(text: 'Customers'),
                ],
              ),
            ],
          ),
        ),

        // ── Content ──────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : TabBarView(
                  controller: _tab,
                  children: [
                    _DailyReport(
                      transactions: _filteredTransactions,
                      currency: _currency,
                      timeLabel: _timeLabel,
                      dateLabel: _dateLabel,
                    ),
                    _PayrollReport(
                      transactions: _filteredTransactions,
                      currency: _currency,
                      dateLabel: _dateLabel,
                    ),
                    _CustomerReport(
                      transactions: _filteredTransactions,
                      customers: _customers,
                      startDate: _startDate,
                      endDate: _endDate,
                      currency: _currency,
                      dateLabel: _dateLabel,
                      timeLabel: _timeLabel,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ── Quick-range chip ─────────────────────────────────────────────────────────
class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  const _QuickChip({
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white38,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.blue.shade700 : Colors.white,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Daily Report Tab
// ===========================================================================
class _DailyReport extends StatelessWidget {
  final List<Transaction> transactions;
  final NumberFormat currency;
  final DateFormat timeLabel;
  final DateFormat dateLabel;

  const _DailyReport({
    required this.transactions,
    required this.currency,
    required this.timeLabel,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(
        child: Text(
          'No transactions found for this period.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Compute summary totals
    final totalRevenue = transactions.fold<double>(
      0,
      (s, t) => s + t.totalAmount,
    );
    final totalPaid = transactions.fold<double>(0, (s, t) => s + t.totalPaid);
    final totalDiscount = transactions.fold<double>(
      0,
      (s, t) => s + t.totalDiscount,
    );
    final paidCount = transactions
        .where((t) => t.status == TransactionStatus.paid)
        .length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Summary cards
        _SummaryRow(
          children: [
            _SummaryCard(
              label: 'Transactions',
              value: '${transactions.length}',
              icon: Icons.receipt_long_outlined,
              color: Colors.blue,
            ),
            _SummaryCard(
              label: 'Paid',
              value: '$paidCount',
              icon: Icons.check_circle_outline,
              color: Colors.green,
            ),
            _SummaryCard(
              label: 'Revenue',
              value: currency.format(totalRevenue),
              icon: Icons.attach_money,
              color: Colors.teal,
            ),
            _SummaryCard(
              label: 'Collected',
              value: currency.format(totalPaid),
              icon: Icons.payments_outlined,
              color: Colors.indigo,
            ),
            _SummaryCard(
              label: 'Discounts',
              value: currency.format(totalDiscount),
              icon: Icons.discount_outlined,
              color: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Transaction list
        Text(
          'All Transactions',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...transactions.map(
          (tx) => _TxRow(
            tx: tx,
            currency: currency,
            timeLabel: timeLabel,
            dateLabel: dateLabel,
          ),
        ),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  final Transaction tx;
  final NumberFormat currency;
  final DateFormat timeLabel;
  final DateFormat dateLabel;
  const _TxRow({
    required this.tx,
    required this.currency,
    required this.timeLabel,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isVoided = tx.status == TransactionStatus.voided;
    final isPaid = tx.status == TransactionStatus.paid;
    final statusColor = isVoided
        ? Colors.red.shade400
        : isPaid
        ? Colors.green.shade600
        : Colors.orange.shade600;
    final statusLabel = isVoided
        ? 'Voided'
        : isPaid
        ? 'Paid'
        : 'Pending';

    // Unique technicians in order of appearance
    final techs = tx.items.map((i) => i.employeeName).toSet().join(' · ');

    // Payment methods used
    final paymentMethods = tx.payments
        .map((p) => p.paymentMethodName)
        .toSet()
        .join(', ');

    return Opacity(
      opacity: isVoided ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status bar
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Main info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: customer + time
                        Row(
                          children: [
                            if (tx.dailyNumber > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Text(
                                  '#${tx.dailyNumber}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const Icon(
                              Icons.person_outline,
                              size: 13,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tx.customerName ?? 'Walk-in',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${dateLabel.format(tx.createdAt)}  ${timeLabel.format(tx.createdAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // Row 2: services (one per line if multiple)
                        ...tx.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.spa_outlined,
                                  size: 11,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    item.itemName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '×${item.quantity}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  currency.format(item.subtotal),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Row 3: technician(s) + payment method
                        Row(
                          children: [
                            if (techs.isNotEmpty) ...[
                              Icon(
                                Icons.badge_outlined,
                                size: 12,
                                color: Colors.blue.shade300,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  techs,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ] else
                              const Expanded(child: SizedBox()),
                            if (paymentMethods.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.payment_outlined,
                                size: 12,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                paymentMethods,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Right: total + status badge
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(tx.totalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: isVoided
                            ? TextDecoration.lineThrough
                            : null,
                        color: isVoided ? Colors.red.shade300 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Payroll Report Tab
// ===========================================================================
class _PayrollReport extends StatelessWidget {
  final List<Transaction> transactions;
  final NumberFormat currency;
  final DateFormat dateLabel;

  const _PayrollReport({
    required this.transactions,
    required this.currency,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(
        child: Text(
          'No transactions found for this period.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Build per-employee aggregate
    final Map<String, _EmployeeSummary> byEmployee = {};
    for (final tx in transactions) {
      for (final item in tx.items) {
        final key = item.employeeId;
        byEmployee.putIfAbsent(
          key,
          () => _EmployeeSummary(id: key, name: item.employeeName),
        );
        byEmployee[key]!.addItem(item);
      }
    }

    final employees = byEmployee.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    // Grand total
    final grandTotal = employees.fold<double>(0, (s, e) => s + e.totalRevenue);
    final grandServices = employees.fold<int>(0, (s, e) => s + e.serviceCount);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Summary cards
        _SummaryRow(
          children: [
            _SummaryCard(
              label: 'Employees',
              value: '${employees.length}',
              icon: Icons.badge_outlined,
              color: Colors.blue,
            ),
            _SummaryCard(
              label: 'Services',
              value: '$grandServices',
              icon: Icons.spa_outlined,
              color: Colors.purple,
            ),
            _SummaryCard(
              label: 'Total Revenue',
              value: currency.format(grandTotal),
              icon: Icons.attach_money,
              color: Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 20),

        Text(
          'By Technician',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        ...employees.map(
          (emp) => _EmployeeCard(
            summary: emp,
            currency: currency,
            grandTotal: grandTotal,
          ),
        ),
      ],
    );
  }
}

// Per-employee mutable aggregate built during report calculation
class _EmployeeSummary {
  final String id;
  final String name;
  int serviceCount = 0;
  double totalRevenue = 0;
  final Map<String, _ServiceLine> byService = {};

  _EmployeeSummary({required this.id, required this.name});

  void addItem(TransactionItem item) {
    serviceCount += item.quantity;
    totalRevenue += item.subtotal;
    byService.putIfAbsent(item.itemId, () => _ServiceLine(name: item.itemName));
    byService[item.itemId]!.quantity += item.quantity;
    byService[item.itemId]!.revenue += item.subtotal;
  }
}

class _ServiceLine {
  final String name;
  int quantity = 0;
  double revenue = 0;
  _ServiceLine({required this.name});
}

class _EmployeeCard extends StatefulWidget {
  final _EmployeeSummary summary;
  final NumberFormat currency;
  final double grandTotal;
  const _EmployeeCard({
    required this.summary,
    required this.currency,
    required this.grandTotal,
  });

  @override
  State<_EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends State<_EmployeeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final pct = widget.grandTotal > 0
        ? widget.summary.totalRevenue / widget.grandTotal
        : 0.0;
    final services = widget.summary.byService.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header row (always visible)
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      widget.summary.name.isNotEmpty
                          ? widget.summary.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.summary.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Progress bar for share of revenue
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 5,
                            backgroundColor: Colors.grey.shade200,
                            color: Colors.blue.shade400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.summary.serviceCount} service${widget.summary.serviceCount == 1 ? '' : 's'}  ·  ${(pct * 100).toStringAsFixed(1)}% of revenue',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.currency.format(widget.summary.totalRevenue),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.teal,
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey.shade400,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded service breakdown
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: services.map((svc) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fiber_manual_record,
                          size: 8,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            svc.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '×${svc.quantity}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          widget.currency.format(svc.revenue),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared layout helpers ────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final List<Widget> children;
  const _SummaryRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: children);
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Customer Report Tab
// ===========================================================================
class _CustomerReport extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Customer> customers;
  final DateTime startDate;
  final DateTime endDate;
  final NumberFormat currency;
  final DateFormat dateLabel;
  final DateFormat timeLabel;

  const _CustomerReport({
    required this.transactions,
    required this.customers,
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.dateLabel,
    required this.timeLabel,
  });

  @override
  State<_CustomerReport> createState() => _CustomerReportState();
}

class _CustomerReportState extends State<_CustomerReport> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build a map: customerId → Customer (for quick lookup)
    final customerMap = {for (final c in widget.customers) c.id: c};

    // Aggregate per-customer stats from transactions
    const walkInKey = '__walkin__';
    final Map<String, _CustSummary> byCustomer = {};

    for (final tx in widget.transactions) {
      final isWalkIn = tx.customerId == null || tx.customerId!.isEmpty;
      final id = isWalkIn ? walkInKey : tx.customerId!;

      byCustomer.putIfAbsent(id, () {
        if (isWalkIn) {
          return _CustSummary(
            id: walkInKey,
            name: 'Walk-in',
            phone: '',
            rewardPoints: 0,
            isNew: false,
            isWalkIn: true,
          );
        }
        final cust = customerMap[id];
        return _CustSummary(
          id: id,
          name: cust?.name ?? tx.customerName ?? 'Unknown',
          phone: cust?.phone ?? '',
          rewardPoints: cust?.rewardPoints ?? 0,
          isNew:
              cust != null &&
              !cust.createdAt.isBefore(
                DateTime(
                  widget.startDate.year,
                  widget.startDate.month,
                  widget.startDate.day,
                ),
              ) &&
              !cust.createdAt.isAfter(
                DateTime(
                  widget.endDate.year,
                  widget.endDate.month,
                  widget.endDate.day,
                  23,
                  59,
                  59,
                ),
              ),
        );
      });
      byCustomer[id]!.addTransaction(tx);
    }

    final walkInSummary = byCustomer[walkInKey];
    final walkInCount = walkInSummary?.visitCount ?? 0;

    // Sort: named customers by spend descending, walk-in always last
    final allCustomers = byCustomer.values.toList()
      ..sort((a, b) {
        if (a.isWalkIn) return 1;
        if (b.isWalkIn) return -1;
        return b.totalSpent.compareTo(a.totalSpent);
      });

    final newCount = allCustomers.where((c) => c.isNew).length;

    // Apply search filter
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? allCustomers
        : allCustomers
              .where(
                (c) => c.name.toLowerCase().contains(q) || c.phone.contains(q),
              )
              .toList();

    final totalRevenue = allCustomers.fold<double>(
      0,
      (s, c) => s + c.totalSpent,
    );

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name or phone…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),

        // Summary cards – hidden while searching but always in the tree so
        // Expanded below stays at a fixed position in the Column children list
        Offstage(
          offstage: q.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryCard(
                  label: 'Customers',
                  value: '${allCustomers.where((c) => !c.isWalkIn).length}',
                  icon: Icons.people_outline,
                  color: Colors.blue,
                ),
                _SummaryCard(
                  label: 'New in Period',
                  value: '$newCount',
                  icon: Icons.person_add_outlined,
                  color: Colors.green,
                ),
                _SummaryCard(
                  label: 'Walk-ins',
                  value: '$walkInCount',
                  icon: Icons.directions_walk,
                  color: Colors.orange,
                ),
                _SummaryCard(
                  label: 'Revenue',
                  value: widget.currency.format(totalRevenue),
                  icon: Icons.attach_money,
                  color: Colors.teal,
                ),
              ],
            ),
          ),
        ),

        // List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    q.isEmpty
                        ? 'No customer transactions in this period.'
                        : 'No customers match "$q".',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _CustomerCard(
                    summary: filtered[i],
                    currency: widget.currency,
                    dateLabel: widget.dateLabel,
                    timeLabel: widget.timeLabel,
                  ),
                ),
        ),
      ],
    );
  }
}

// Per-customer mutable aggregate
class _CustSummary {
  final String id;
  final String name;
  final String phone;
  final double rewardPoints;
  final bool isNew;
  final bool isWalkIn;
  int visitCount = 0;
  double totalSpent = 0;
  DateTime? lastVisit;
  final List<Transaction> transactions = [];

  _CustSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.rewardPoints,
    required this.isNew,
    this.isWalkIn = false,
  });

  void addTransaction(Transaction tx) {
    visitCount++;
    totalSpent += tx.totalAmount;
    if (lastVisit == null || tx.createdAt.isAfter(lastVisit!)) {
      lastVisit = tx.createdAt;
    }
    transactions.add(tx);
  }
}

class _CustomerCard extends StatefulWidget {
  final _CustSummary summary;
  final NumberFormat currency;
  final DateFormat dateLabel;
  final DateFormat timeLabel;

  const _CustomerCard({
    required this.summary,
    required this.currency,
    required this.dateLabel,
    required this.timeLabel,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final txs = s.transactions
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: s.isWalkIn
                        ? Colors.grey.shade200
                        : s.isNew
                        ? Colors.green.shade100
                        : Colors.blue.shade100,
                    child: s.isWalkIn
                        ? Icon(
                            Icons.directions_walk,
                            size: 20,
                            color: Colors.grey.shade600,
                          )
                        : Text(
                            s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: s.isNew
                                  ? Colors.green.shade800
                                  : Colors.blue.shade800,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Name + phone + new badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (s.isNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: Colors.green.shade300,
                                  ),
                                ),
                                child: Text(
                                  'NEW',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (s.phone.isNotEmpty)
                          Text(
                            s.phone,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Stats
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.currency.format(s.totalSpent),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.teal,
                        ),
                      ),
                      Text(
                        '${s.visitCount} visit${s.visitCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (s.rewardPoints > 0)
                        Text(
                          '${s.rewardPoints.toStringAsFixed(0)} pts',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Expanded transaction list
          if (_expanded) ...[
            const Divider(height: 1),
            ...txs.map(
              (tx) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (tx.dailyNumber > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Text(
                              '#${tx.dailyNumber}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        Text(
                          '${widget.dateLabel.format(tx.createdAt)}  ${widget.timeLabel.format(tx.createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.currency.format(tx.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: tx.status == TransactionStatus.paid
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: tx.status == TransactionStatus.paid
                                  ? Colors.green.shade300
                                  : Colors.orange.shade300,
                            ),
                          ),
                          child: Text(
                            tx.status == TransactionStatus.paid
                                ? 'Paid'
                                : 'Pending',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: tx.status == TransactionStatus.paid
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ...tx.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 1),
                        child: Row(
                          children: [
                            Icon(
                              Icons.spa_outlined,
                              size: 10,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.itemName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            Text(
                              '×${item.quantity}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.currency.format(item.subtotal),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (txs.last != tx) const Divider(height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
