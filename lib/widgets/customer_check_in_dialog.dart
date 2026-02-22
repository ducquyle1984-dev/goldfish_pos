import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// A dialog that lets staff find an existing customer or quickly register a
/// new one. Returns the selected [Customer], or null if dismissed.
///
/// Usage:
/// ```dart
/// final customer = await showCustomerCheckIn(context);
/// ```
Future<Customer?> showCustomerCheckIn(BuildContext context) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => const _CustomerCheckInDialog(),
  );
}

class _CustomerCheckInDialog extends StatefulWidget {
  const _CustomerCheckInDialog();

  @override
  State<_CustomerCheckInDialog> createState() => _CustomerCheckInDialogState();
}

class _CustomerCheckInDialogState extends State<_CustomerCheckInDialog> {
  final _repo = PosRepository();
  final _searchCtrl = TextEditingController();
  String _query = '';

  // New-customer form state
  bool _showNewForm = false;
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  int _birthMonth = 1;
  int _birthDay = 1;
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
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  int _daysInMonth(int month) {
    const days = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month];
  }

  Future<void> _createAndSelect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final customer = Customer(
        id: '',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        birthMonth: _birthMonth,
        birthDay: _birthDay,
        createdAt: now,
        updatedAt: now,
      );
      final id = await _repo.createCustomer(customer);
      // Fetch the created doc so we have the real ID
      final created = await _repo.getCustomer(id);
      if (mounted && created != null) {
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create customer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.person_search_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Customer Check-in',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _showNewForm
                  ? _buildNewCustomerForm()
                  : _buildSearchView(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search existing customers ─────────────────────────────────────────────
  Widget _buildSearchView() {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
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
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // New customer button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('New Customer'),
              onPressed: () {
                // Pre-fill name from search if it looks like a name
                if (_query.isNotEmpty && !RegExp(r'^\d').hasMatch(_query)) {
                  _nameCtrl.text = _query;
                } else if (_query.isNotEmpty &&
                    RegExp(r'^\d').hasMatch(_query)) {
                  _phoneCtrl.text = _query;
                }
                setState(() => _showNewForm = true);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
          const Divider(height: 1),

          // Customer list (streamed)
          Flexible(
            child: StreamBuilder<List<Customer>>(
              stream: _repo.getCustomers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final all = snapshot.data ?? [];
                final q = _query.toLowerCase().trim();
                final filtered = q.isEmpty
                    ? all
                    : all.where((c) {
                        return c.name.toLowerCase().contains(q) ||
                            c.phone.toLowerCase().contains(q);
                      }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          q.isEmpty
                              ? 'No customers yet.'
                              : 'No customers matching "$_query".',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (ctx, i) {
                    final c = filtered[i];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        ),
                      ),
                      title: Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Row(
                        children: [
                          Text(c.phone),
                          const SizedBox(width: 10),
                          const Icon(Icons.cake_outlined, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            c.birthDateDisplay,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.star, size: 12, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(
                            '${c.rewardPoints.toStringAsFixed(0)} pts',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick new-customer form ───────────────────────────────────────────────
  Widget _buildNewCustomerForm() {
    final maxDay = _daysInMonth(_birthMonth);
    if (_birthDay > maxDay) _birthDay = maxDay;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_add_outlined, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'New Customer',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _showNewForm = false),
                  child: const Text('Back to search'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Name
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),

            // Phone
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone *',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
            ),
            const SizedBox(height: 14),

            // Birthday
            Text(
              'Birthday * (month & day only)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
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
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Check In & Create',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _createAndSelect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
