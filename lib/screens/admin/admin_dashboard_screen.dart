import 'package:flutter/material.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/screens/admin/booking_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/business_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/cash_drawer_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/customer_feedback_screen.dart';
import 'package:goldfish_pos/screens/admin/customer_management_screen.dart';
import 'package:goldfish_pos/screens/admin/employee_management_screen.dart';
import 'package:goldfish_pos/screens/admin/item_management_screen.dart';
import 'package:goldfish_pos/screens/admin/payment_method_management_screen.dart';
import 'package:goldfish_pos/screens/admin/item_category_management_screen.dart';
import 'package:goldfish_pos/screens/admin/reward_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/sms_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/system_admin_dashboard_screen.dart';
import 'package:goldfish_pos/screens/admin/import_management_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  // ── System Admin PIN gate ─────────────────────────────────────────────────
  Future<void> _openSystemAdmin(BuildContext context) async {
    final repo = PosRepository();
    String? error;
    final pinCtrl = TextEditingController();

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text('System Admin Access'),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the System Admin PIN to continue.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: error,
                  ),
                  onSubmitted: (_) async {
                    final correct = await repo.getSysAdminPin();
                    if (pinCtrl.text.trim() == correct) {
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() => error = 'Incorrect PIN.');
                      pinCtrl.clear();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final correct = await repo.getSysAdminPin();
                if (pinCtrl.text.trim() == correct) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setDialogState(() => error = 'Incorrect PIN.');
                  pinCtrl.clear();
                }
              },
              child: const Text('Enter'),
            ),
          ],
        ),
      ),
    );
    pinCtrl.dispose();

    if (granted == true && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SystemAdminDashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Administration',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your business settings and data',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            // Admin Options Grid
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _AdminCard(
                  title: 'Business Info',
                  icon: Icons.storefront_outlined,
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BusinessSettingsScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Employees',
                  icon: Icons.people,
                  color: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmployeeManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Items',
                  icon: Icons.shopping_bag,
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ItemManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Payment Methods',
                  icon: Icons.payment,
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const PaymentMethodManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Item Categories',
                  icon: Icons.category,
                  color: Colors.purple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const ItemCategoryManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Customers',
                  icon: Icons.people,
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomerManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Reward Points',
                  icon: Icons.star,
                  color: Colors.amber,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RewardSettingsScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Cash Drawer',
                  icon: Icons.point_of_sale,
                  color: Colors.brown,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CashDrawerSettingsScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Booking',
                  icon: Icons.calendar_month,
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BookingSettingsScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Import Data',
                  icon: Icons.upload_file,
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ImportManagementScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'SMS Settings',
                  icon: Icons.sms,
                  color: Colors.cyan,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SmsSettingsScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'Feedback',
                  icon: Icons.feedback,
                  color: Colors.red,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomerFeedbackScreen(),
                    ),
                  ),
                ),
                _AdminCard(
                  title: 'System Admin',
                  icon: Icons.admin_panel_settings,
                  color: Colors.deepOrange,
                  onTap: () => _openSystemAdmin(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AdminCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
