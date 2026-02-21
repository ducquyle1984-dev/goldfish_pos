import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/screens/admin/admin_dashboard_screen.dart';

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
          // Welcome Header
          Text(
            'Dashboard',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back, ${user?.displayName ?? user?.email ?? 'User'}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),

          // Active Employees
          Text(
            'Active Employees',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap an employee to start a new transaction',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          _buildEmployeeGrid(),
        ],
      ),
    );
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
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
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
  }

  Widget _buildEmployeeTile(Employee employee, Color color) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _startTransaction(employee),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withOpacity(0.25),
                child: Text(
                  employee.name.isNotEmpty
                      ? employee.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                employee.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'New Transaction',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startTransaction(Employee employee) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New Transaction'),
        content: Text(
          'Starting a new transaction for ${employee.name}.\n\n'
          'Transaction creation flow coming soon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Navigate to transaction creation screen with employee pre-selected
            },
            child: const Text('Continue'),
          ),
        ],
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
