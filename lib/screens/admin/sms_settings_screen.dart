import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/sms_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  final _repo = PosRepository();
  bool _isLoading = true;
  bool _isSaving = false;

  // Form fields
  bool _enabled = false;
  final _positiveMsgCtrl = TextEditingController();
  final _negativeMsgCtrl = TextEditingController();
  final _reviewUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.getSmsSettings();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled;
        _positiveMsgCtrl.text = s.positiveTemplate;
        _negativeMsgCtrl.text = s.negativeTemplate;
        _reviewUrlCtrl.text = s.googleReviewUrl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Failed to load SMS settings: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final settings = SmsSettings(
        enabled: _enabled,
        positiveTemplate: _positiveMsgCtrl.text.trim(),
        negativeTemplate: _negativeMsgCtrl.text.trim(),
        googleReviewUrl: _reviewUrlCtrl.text.trim(),
      );
      await _repo.saveSmsPublicSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS settings saved.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _positiveMsgCtrl.dispose();
    _negativeMsgCtrl.dispose();
    _reviewUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS / Text Message Settings'),
        elevation: 0,
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Enable toggle ──────────────────────────────────────
                  Card(
                    child: SwitchListTile(
                      title: const Text(
                        'Enable SMS Thank-You Messages',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Send an SMS to customers after they pay, prompting them to rate their experience.',
                      ),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Twilio note (System Admin) ─────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: Colors.blueGrey.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Twilio API credentials (Account SID, Auth Token, From Number) '
                            'are managed by System Admin. Ask your System Administrator '
                            'to configure them under Admin → System Admin.',
                            style: TextStyle(
                              color: Colors.blueGrey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Message templates ──────────────────────────────────
                  _sectionHeader('Message Templates'),
                  const SizedBox(height: 4),
                  _hint(
                    'Use {name} for the customer\'s name and {reviewLink} for the Google Review URL '
                    '(positive template only).',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _positiveMsgCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Positive Response Template',
                      helperText: 'Sent when the customer rates positively.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _negativeMsgCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Negative Response Template',
                      helperText:
                          'Sent when the customer rates negatively (feedback is also stored internally).',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Google Review URL ──────────────────────────────────
                  _sectionHeader('Google Review Link'),
                  const SizedBox(height: 4),
                  _hint(
                    'Go to your Google Business Profile → "Get more reviews" to copy your review link.',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _reviewUrlCtrl,
                    label: 'Google Review URL',
                    hint: 'https://g.page/r/...',
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _hint(String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
