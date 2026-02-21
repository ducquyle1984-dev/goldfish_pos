import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final _repository = PosRepository();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _commissionController = TextEditingController();
  Employee? _editingEmployee;

  int _selectedColorValue = 0xFF1565C0; // default deep blue

  static const List<({String label, int value})> _palette = [
    (label: 'Deep Blue', value: 0xFF1565C0),
    (label: 'Deep Purple', value: 0xFF6A1B9A),
    (label: 'Teal', value: 0xFF00695C),
    (label: 'Deep Orange', value: 0xFFE65100),
    (label: 'Deep Red', value: 0xFFC62828),
    (label: 'Green', value: 0xFF2E7D32),
    (label: 'Indigo', value: 0xFF4527A0),
    (label: 'Cyan', value: 0xFF00838F),
    (label: 'Pink', value: 0xFFAD1457),
    (label: 'Light Green', value: 0xFF558B2F),
    (label: 'Navy', value: 0xFF283593),
    (label: 'Brown', value: 0xFF4E342E),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _addressController.clear();
    _commissionController.clear();
    _editingEmployee = null;
    _selectedColorValue = 0xFF1565C0;
  }

  Future<void> _saveEmployee() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    try {
      final now = DateTime.now();
      final employee = Employee(
        id: _editingEmployee?.id ?? '',
        name: _nameController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        address: _addressController.text.isEmpty
            ? null
            : _addressController.text,
        commissionPercentage:
            double.tryParse(_commissionController.text) ?? 0.0,
        isActive: true,
        colorValue: _selectedColorValue,
        createdAt: _editingEmployee?.createdAt ?? now,
        updatedAt: now,
      );

      if (_editingEmployee != null) {
        await _repository.updateEmployee(employee);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee updated successfully')),
        );
      } else {
        await _repository.createEmployee(employee);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee created successfully')),
        );
      }

      _clearForm();
      FocusScope.of(context).unfocus();
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _editEmployee(Employee employee) {
    _editingEmployee = employee;
    _nameController.text = employee.name;
    _emailController.text = employee.email ?? '';
    _phoneController.text = employee.phone ?? '';
    _addressController.text = employee.address ?? '';
    _commissionController.text = employee.commissionPercentage.toString();
    _selectedColorValue = employee.colorValue;
  }

  Future<void> _deleteEmployee(String employeeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this employee?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repository.deleteEmployee(employeeId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employee Management'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Form Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingEmployee == null
                          ? 'Add New Employee'
                          : 'Edit Employee',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        hintText: 'Enter employee name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Enter email address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: 'Enter phone number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        hintText: 'Enter address',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commissionController,
                      decoration: const InputDecoration(
                        labelText: 'Commission Percentage',
                        hintText: 'Enter commission %',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Color picker
                    Text(
                      'Tile Color',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _palette.map((entry) {
                        final selected = _selectedColorValue == entry.value;
                        return Tooltip(
                          message: entry.label,
                          child: GestureDetector(
                            onTap: () => setState(
                              () => _selectedColorValue = entry.value,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(entry.value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: Color(
                                            entry.value,
                                          ).withOpacity(0.6),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 18,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saveEmployee,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Employee'),
                        ),
                        const SizedBox(width: 8),
                        if (_editingEmployee != null)
                          TextButton.icon(
                            onPressed: () {
                              _clearForm();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('Cancel'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Employee List Section
            Text('Employees', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StreamBuilder<List<Employee>>(
              stream: _repository.getEmployees(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: TextStyle(color: Colors.red.shade600),
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'No employees yet',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }

                final employees = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: employee.tileColor,
                          child: Text(
                            employee.name.isNotEmpty
                                ? employee.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(employee.name),
                        subtitle: Text(
                          'Commission: ${employee.commissionPercentage}%',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                _editEmployee(employee);
                                setState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteEmployee(employee.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
