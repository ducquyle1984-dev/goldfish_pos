import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class ItemManagementScreen extends StatefulWidget {
  const ItemManagementScreen({super.key});

  @override
  State<ItemManagementScreen> createState() => _ItemManagementScreenState();
}

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  final _repository = PosRepository();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedCategoryId;
  ItemType _selectedType = ItemType.service;
  bool _isCustomPrice = false;
  int? _durationMinutes;
  Item? _editingItem;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _descriptionController.clear();
    _priceController.clear();
    _selectedCategoryId = null;
    _selectedType = ItemType.service;
    _isCustomPrice = false;
    _durationMinutes = null;
    _editingItem = null;
  }

  Future<void> _saveItem() async {
    if (_nameController.text.isEmpty ||
        _selectedCategoryId == null ||
        _priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, Category, and Price are required')),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final item = Item(
        id: _editingItem?.id ?? '',
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        categoryId: _selectedCategoryId!,
        type: _selectedType,
        price: double.parse(_priceController.text),
        isActive: true,
        isCustomPrice: _isCustomPrice,
        durationMinutes: _selectedType == ItemType.service
            ? _durationMinutes
            : null,
        createdAt: _editingItem?.createdAt ?? now,
        updatedAt: now,
      );

      if (_editingItem != null) {
        await _repository.updateItem(item);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item updated successfully')),
        );
      } else {
        await _repository.createItem(item);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item created successfully')),
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

  void _editItem(Item item) {
    _editingItem = item;
    _nameController.text = item.name;
    _descriptionController.text = item.description ?? '';
    _priceController.text = item.price.toString();
    _selectedCategoryId = item.categoryId;
    _selectedType = item.type;
    _isCustomPrice = item.isCustomPrice;
    _durationMinutes = item.durationMinutes;
  }

  Future<void> _deleteItem(String itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this item?'),
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
        await _repository.deleteItem(itemId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item deleted successfully')),
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
      appBar: AppBar(title: const Text('Item Management'), elevation: 0),
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
                      _editingItem == null ? 'Add New Item' : 'Edit Item',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        hintText: 'Enter item name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Enter item description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price *',
                        hintText: 'Enter price',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Category Dropdown
                    StreamBuilder<List<ItemCategory>>(
                      stream: _repository.getItemCategories(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const TextField(
                            decoration: InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            enabled: false,
                          );
                        }

                        final categories = snapshot.data!;
                        return DropdownButtonFormField<String>(
                          value: _selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          items: categories
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat.id,
                                  child: Text(cat.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedCategoryId = value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // Type Selector
                    SegmentedButton<ItemType>(
                      segments: const [
                        ButtonSegment(
                          value: ItemType.service,
                          label: Text('Service'),
                        ),
                        ButtonSegment(
                          value: ItemType.product,
                          label: Text('Product'),
                        ),
                      ],
                      selected: {_selectedType},
                      onSelectionChanged: (Set<ItemType> newSelection) {
                        setState(() => _selectedType = newSelection.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _isCustomPrice,
                          onChanged: (val) {
                            setState(() {
                              _isCustomPrice = val ?? false;
                            });
                          },
                        ),
                        const Text('Custom Price'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_selectedType == ItemType.service)
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Duration (minutes)',
                          hintText: 'Enter duration in minutes',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          setState(() {
                            _durationMinutes = int.tryParse(val);
                          });
                        },
                        controller: TextEditingController(
                          text: _durationMinutes?.toString() ?? '',
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saveItem,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Item'),
                        ),
                        const SizedBox(width: 8),
                        if (_editingItem != null)
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
            // Items List Section
            Text('Items', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            StreamBuilder<List<Item>>(
              stream: _repository.getItems(),
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
                        'No items yet',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }

                final items = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                          '\$${item.price.toStringAsFixed(2)} • ${item.type.name}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                _editItem(item);
                                setState(() {});
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteItem(item.id),
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
