import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

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

                // Show current reward points for existing customers
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
