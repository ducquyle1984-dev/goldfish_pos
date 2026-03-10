import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/business_settings_model.dart';
import 'package:goldfish_pos/providers/touchscreen_provider.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:provider/provider.dart';

/// Admin screen for configuring the salon's business info (name, address,
/// phone) which appears at the top of every printed receipt.
class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _repo = PosRepository();

  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxLabelCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController();

  bool _touchscreenEnabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _taxLabelCtrl.dispose();
    _taxRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.getBusinessSettings();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = s.salonName;
        _addrCtrl.text = s.address;
        _phoneCtrl.text = s.phone;
        _taxLabelCtrl.text = s.taxLabel;
        _taxRateCtrl.text = s.taxRate > 0 ? s.taxRate.toStringAsFixed(2) : '';
        _touchscreenEnabled = s.touchscreenEnabled;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Salon name cannot be empty.');
      return;
    }

    final taxRate = double.tryParse(_taxRateCtrl.text) ?? 0.0;
    final settings = BusinessSettings(
      salonName: name,
      address: _addrCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      taxLabel: _taxLabelCtrl.text.trim().isNotEmpty
          ? _taxLabelCtrl.text.trim()
          : 'Tax',
      taxRate: taxRate,
      touchscreenEnabled: _touchscreenEnabled,
    );

    setState(() => _saving = true);
    try {
      await _repo.saveBusinessSettings(settings);
      if (mounted) {
        context.read<TouchscreenProvider>().setEnabled(_touchscreenEnabled);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business settings saved.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save', style: TextStyle(fontSize: 16)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── info banner ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'This information is printed at the top of every receipt. '
                          'Keep it accurate so customers can contact you.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Salon name ───────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Salon Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Salon Name *',
                            hintText: 'e.g. Goldfish Nail Salon',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.storefront_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addrCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            hintText: 'e.g. 123 Main Street\nHouston, TX 77001',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Icon(Icons.location_on_outlined),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'e.g. (713) 555-1234',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Tax settings ─────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tax Display',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Controls how the tax line is labelled on printed receipts.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _taxLabelCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Tax Label',
                                  hintText: 'Tax / VAT / GST',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _taxRateCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Default Rate (%)',
                                  hintText: 'e.g. 8.25',
                                  border: OutlineInputBorder(),
                                  suffixText: '%',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Note: The tax rate here is for display reference only. '
                          'Actual tax per transaction is set when creating each transaction.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Touchscreen mode ─────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Input Options',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enable if this POS terminal has a touchscreen. '
                          'PIN-entry dialogs will show an on-screen number pad.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _touchscreenEnabled,
                          onChanged: (v) =>
                              setState(() => _touchscreenEnabled = v),
                          title: const Text('Touchscreen Mode'),
                          subtitle: const Text(
                            'Show on-screen numpad for PIN entry',
                          ),
                          secondary: const Icon(Icons.touch_app_outlined),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Save button ──────────────────────────────────────────
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 15),
                  ),
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
