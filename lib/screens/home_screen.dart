import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/screens/admin/admin_dashboard_screen.dart';
import 'package:goldfish_pos/screens/transaction_create_screen.dart';

/// Main dashboard screen with role-based navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final user = FirebaseAuth.instance.currentUser;
  final _repo = PosRepository();

  // For now, we'll assume the user role based on email domain or a custom claim
  // In production, fetch this from Firestore
  bool get isAdmin => user?.email?.contains('admin') ?? false;

  List<NavigationRailDestination> get _sideMenu => [
    const NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: Text('Home'),
    ),
    const NavigationRailDestination(
      icon: Icon(Icons.calendar_today_outlined),
      selectedIcon: Icon(Icons.calendar_today),
      label: Text('Booking'),
    ),
    const NavigationRailDestination(
      icon: Icon(Icons.admin_panel_settings_outlined),
      selectedIcon: Icon(Icons.admin_panel_settings),
      label: Text('Admin'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final menuItems = _sideMenu;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goldfish POS'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                user?.email ?? 'User',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isMobile)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: menuItems,
              extended: true,
              backgroundColor: Colors.grey.shade100,
            ),
          Expanded(child: _buildPage(_selectedIndex, isAdmin)),
        ],
      ),
      drawer: isMobile
          ? Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(color: Colors.blue.shade700),
                    child: const Text(
                      'Menu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...List.generate(
                    menuItems.length,
                    (index) => ListTile(
                      title: menuItems[index].label,
                      leading: _selectedIndex == index
                          ? menuItems[index].selectedIcon
                          : menuItems[index].icon,
                      selected: _selectedIndex == index,
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Sign Out'),
                    leading: const Icon(Icons.logout),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildPage(int index, bool isAdmin) {
    switch (index) {
      case 0:
        return _buildDashboard();
      case 1:
        return _buildPlaceholder('Booking');
      case 2:
        return const AdminDashboardScreen();
      default:
        return _buildDashboard();
    }
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pending Transactions
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Pending Transactions',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                'Tap to reopen and check out',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPendingTransactions(),

          const SizedBox(height: 32),

          // Active Employees
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Active Employees',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                'Tap to start a new transaction',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildEmployeeGrid(),
        ],
      ),
    );
  }

  Widget _buildPendingTransactions() {
    return StreamBuilder<List<Transaction>>(
      stream: _repo.getTransactionsByStatus('pending'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        final pending = snapshot.data ?? [];
        if (pending.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  color: Colors.grey.shade400,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'No pending transactions',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }
        return Column(
          children: pending.map((tx) => _buildPendingCard(tx)).toList(),
        );
      },
    );
  }

  Widget _buildPendingCard(Transaction tx) {
    final employees = tx.items.map((i) => i.employeeName).toSet().join(', ');
    final serviceNames = tx.items.map((i) => i.itemName).toList();
    final servicesSummary = serviceNames.length <= 3
        ? serviceNames.join(', ')
        : '${serviceNames.take(3).join(', ')} +${serviceNames.length - 3} more';
    final createdTime = _formatTime(tx.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Build a minimal Employee from the first item so the create screen
          // knows which employee to default new items to.
          final firstItem = tx.items.isNotEmpty ? tx.items.first : null;
          final resumeEmployee = firstItem != null
              ? Employee(
                  id: firstItem.employeeId,
                  name: firstItem.employeeName,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                )
              : Employee(
                  id: '',
                  name: 'Unknown',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionCreateScreen(
                defaultEmployee: resumeEmployee,
                existingTransaction: tx,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Orange pending indicator bar
              Container(
                width: 4,
                height: 56,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade400,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (tx.customerName != null) ...[
                          const Icon(Icons.person_outline, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            tx.customerName!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          createdTime,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      servicesSummary,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            employees,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action buttons
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                tooltip: 'Void & close',
                onPressed: () => _closePendingTransaction(tx),
              ),
            ],
          ),
        ),
      ), // InkWell
    );
  }

  Future<void> _closePendingTransaction(Transaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Transaction'),
        content: const Text(
          'Are you sure you want to close and void this pending transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close & Void'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.voidTransaction(tx.id);
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}';
  }

  Widget _buildEmployeeGrid() {
    return StreamBuilder<List<Employee>>(
      stream: _repo.getEmployees(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading employees: ${snapshot.error}'),
          );
        }
        final employees = (snapshot.data ?? [])
            .where((e) => e.isActive)
            .toList();
        if (employees.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(48.0),
              child: Text('No active employees found.'),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final cols = (constraints.maxWidth / 140).floor().clamp(2, 8);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: employees.length,
              itemBuilder: (context, index) {
                final employee = employees[index];
                return _buildEmployeeTile(employee, employee.tileColor);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmployeeTile(Employee employee, Color color) {
    final isLight = color.computeLuminance() > 0.35;
    final textColor = isLight ? Colors.grey.shade800 : Colors.white;
    final overlayColor = isLight
        ? Colors.black.withOpacity(0.12)
        : Colors.white.withOpacity(0.25);

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _startTransaction(employee),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth;
            final avatarRadius = (size * 0.28).clamp(16.0, 36.0);
            final fontSizeName = (size * 0.13).clamp(10.0, 18.0);
            final fontSizeInitial = avatarRadius * 0.75;
            return Padding(
              padding: EdgeInsets.all(size * 0.08),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: overlayColor,
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: fontSizeInitial,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  SizedBox(height: size * 0.06),
                  Text(
                    employee.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSizeName,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _startTransaction(Employee employee) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionCreateScreen(defaultEmployee: employee),
      ),
    );
  }

  Widget _buildPlaceholder(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('$title', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Coming soon...', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
