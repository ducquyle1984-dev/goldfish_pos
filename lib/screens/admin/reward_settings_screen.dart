import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// Admin screen for configuring the customer reward points program.
class RewardSettingsScreen extends StatefulWidget {
  const RewardSettingsScreen({super.key});

  @override
  State<RewardSettingsScreen> createState() => _RewardSettingsScreenState();
}

class _RewardSettingsScreenState extends State<RewardSettingsScreen> {
  final _repo = PosRepository();
  final _dollarsCtrl = TextEditingController();
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dollarsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _repo.getRewardSettings();
      setState(() {
        _enabled = settings.enabled;
        _dollarsCtrl.text = settings.dollarsPerPoint.toStringAsFixed(0);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final dollars = double.tryParse(_dollarsCtrl.text);
    if (dollars == null || dollars <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid dollar amount greater than 0.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.updateRewardSettings(
        RewardSettings(dollarsPerPoint: dollars, enabled: _enabled),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reward settings saved.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reward Points Program')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable toggle
                  Card(
                    child: SwitchListTile(
                      title: const Text(
                        'Enable Reward Program',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'When enabled, customers earn points on every transaction.',
                      ),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      secondary: Icon(
                        Icons.star,
                        color: _enabled ? Colors.amber : Colors.grey,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Earn rate
                  Text(
                    'Earn Rate',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set how many dollars a customer must spend to earn 1 reward point. '
                    '1 point = \$1 off their service.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dollarsCtrl,
                    enabled: _enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Dollars spent per 1 point',
                      prefixText: '\$',
                      hintText: '100',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. 100 → spend \$100 = earn 1 point',
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Preview
                  if (_enabled) ...[
                    Builder(
                      builder: (context) {
                        final dollars = double.tryParse(_dollarsCtrl.text) ?? 0;
                        if (dollars <= 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            border: Border.all(color: Colors.amber.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.amber.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Spend \$${dollars.toStringAsFixed(0)} → earn 1 point  •  '
                                  '1 point = \$1.00 off',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save Settings'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
