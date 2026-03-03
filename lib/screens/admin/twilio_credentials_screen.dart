import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/sms_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// System Admin only — configure Twilio API credentials used for sending SMS.
class TwilioCredentialsScreen extends StatefulWidget {
  const TwilioCredentialsScreen({super.key});

  @override
  State<TwilioCredentialsScreen> createState() =>
      _TwilioCredentialsScreenState();
}

class _TwilioCredentialsScreenState extends State<TwilioCredentialsScreen> {
  final _repo = PosRepository();
  bool _isLoading = true;
  bool _isSaving = false;

  final _sidCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  bool _showToken = false;

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
        _sidCtrl.text = s.accountSid;
        _tokenCtrl.text = s.authToken;
        _fromCtrl.text = s.fromNumber;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Failed to load credentials: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _repo.saveTwilioCredentials(
        accountSid: _sidCtrl.text.trim(),
        authToken: _tokenCtrl.text.trim(),
        fromNumber: _fromCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Twilio credentials saved.'),
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
    _sidCtrl.dispose();
    _tokenCtrl.dispose();
    _fromCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twilio Credentials'),
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
                  // Info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.indigo.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'These credentials are used to send SMS thank-you messages via Twilio. '
                            'Find them on your Twilio Console dashboard (console.twilio.com).',
                            style: TextStyle(
                              color: Colors.indigo.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _sectionHeader('Account SID'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _sidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Account SID',
                      hintText: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  _sectionHeader('Auth Token'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _tokenCtrl,
                    obscureText: !_showToken,
                    decoration: InputDecoration(
                      labelText: 'Auth Token',
                      hintText: '••••••••••••••••',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showToken ? Icons.visibility_off : Icons.visibility,
                        ),
                        tooltip: _showToken ? 'Hide' : 'Show',
                        onPressed: () =>
                            setState(() => _showToken = !_showToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  _sectionHeader('From Phone Number'),
                  const SizedBox(height: 4),
                  Text(
                    'Must be a Twilio-provisioned number in E.164 format.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _fromCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'From Number',
                      hintText: '+15551234567',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Credentials'),
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
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
