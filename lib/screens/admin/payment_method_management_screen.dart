import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class PaymentMethodManagementScreen extends StatefulWidget {
  const PaymentMethodManagementScreen({super.key});

  @override
  State<PaymentMethodManagementScreen> createState() =>
      _PaymentMethodManagementScreenState();
}

class _PaymentMethodManagementScreenState
    extends State<PaymentMethodManagementScreen> {
  final _repository = PosRepository();
  final _merchantNameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _commissionController = TextEditingController();
  final _webhookUrlController = TextEditingController();
  PaymentProcessorType _selectedProcessor = PaymentProcessorType.stripe;
  PaymentMethod? _editingMethod;

  @override
  void dispose() {
    _merchantNameController.dispose();
    _apiKeyController.dispose();
    _secretKeyController.dispose();
    _commissionController.dispose();
    _webhookUrlController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _merchantNameController.clear();
    _apiKeyController.clear();
    _secretKeyController.clear();
    _commissionController.clear();
    _webhookUrlController.clear();
    _selectedProcessor = PaymentProcessorType.stripe;
    _editingMethod = null;
  }

  Future<void> _savePaymentMethod() async {
    if (_merchantNameController.text.isEmpty ||
        _apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merchant Name and API Key are required')),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final paymentMethod = PaymentMethod(
        id: _editingMethod?.id ?? '',
        merchantName: _merchantNameController.text,
        processorType: _selectedProcessor,
        processorApiKey: _apiKeyController.text,
        processorSecretKey: _secretKeyController.text.isEmpty
            ? null
            : _secretKeyController.text,
        transactionCommission:
            double.tryParse(_commissionController.text) ?? 0.0,
        webhookUrl: _webhookUrlController.text.isEmpty
            ? null
            : _webhookUrlController.text,
        isActive: true,
        createdAt: _editingMethod?.createdAt ?? now,
        updatedAt: now,
      );

      if (_editingMethod != null) {
        await _repository.updatePaymentMethod(paymentMethod);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment method updated successfully')),
        );
      } else {
        await _repository.createPaymentMethod(paymentMethod);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment method created successfully')),
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

  void _editPaymentMethod(PaymentMethod method) {
    _editingMethod = method;
    _merchantNameController.text = method.merchantName;
    _apiKeyController.text = method.processorApiKey;
    _secretKeyController.text = method.processorSecretKey ?? '';
    _commissionController.text =
        method.transactionCommission?.toString() ?? '0';
    _webhookUrlController.text = method.webhookUrl ?? '';
    _selectedProcessor = method.processorType;
  }

  Future<void> _deletePaymentMethod(String methodId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text(
          'Are you sure you want to delete this payment method?',
        ),
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
        await _repository.deletePaymentMethod(methodId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment method deleted successfully')),
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
      appBar: AppBar(
        title: const Text('Payment Processor Setup'),
        elevation: 0,
      ),
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
                      _editingMethod == null
                          ? 'Add Payment Processor'
                          : 'Edit Payment Processor',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _merchantNameController,
                      decoration: const InputDecoration(
                        labelText: 'Merchant Account Name *',
                        hintText: 'e.g., My Store Stripe Account',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentProcessorType>(
                      value: _selectedProcessor,
                      decoration: const InputDecoration(
                        labelText: 'Payment Processor *',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: PaymentProcessorType.stripe,
                          child: const Text('Stripe'),
                        ),
                        DropdownMenuItem(
                          value: PaymentProcessorType.square,
                          child: const Text('Square'),
                        ),
                        DropdownMenuItem(
                          value: PaymentProcessorType.paypal,
                          child: const Text('PayPal'),
                        ),
                        DropdownMenuItem(
                          value: PaymentProcessorType.custom,
                          child: const Text('Custom'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedProcessor = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key *',
                        hintText: 'Enter your API key',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _secretKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Secret Key',
                        hintText: 'Enter your secret key (if applicable)',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commissionController,
                      decoration: const InputDecoration(
                        labelText: 'Transaction Commission %',
                        hintText: 'Enter commission percentage',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webhookUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Webhook URL',
                        hintText: 'Enter webhook URL for payment notifications',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _savePaymentMethod,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Processor'),
                        ),
                        const SizedBox(width: 8),
                        if (_editingMethod != null)
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
            // Payment Methods List Section
            Text(
              'Configured Payment Processors',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<PaymentMethod>>(
              stream: _repository.getPaymentMethods(),
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
                        'No payment processors configured yet',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }

                final paymentMethods = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: paymentMethods.length,
                  itemBuilder: (context, index) {
                    final method = paymentMethods[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(method.merchantName),
                        subtitle: Text(
                          method.processorType.toString().split('.').last,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Processor: ${method.processorType.toString().split('.').last}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Commission: ${method.transactionCommission}%',
                                ),
                                if (method.webhookUrl != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Webhook: ${method.webhookUrl}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        _editPaymentMethod(method);
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _deletePaymentMethod(method.id),
                                      icon: const Icon(Icons.delete),
                                      label: const Text('Delete'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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
