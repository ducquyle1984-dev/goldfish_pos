import 'package:flutter/material.dart';
import 'package:goldfish_pos/providers/touchscreen_provider.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/screens/admin/cash_drawer_settings_screen.dart';
import 'package:goldfish_pos/screens/admin/client_manager_screen.dart';
import 'package:goldfish_pos/screens/admin/client_onboarding_screen.dart';
import 'package:goldfish_pos/screens/admin/payment_method_management_screen.dart';
import 'package:goldfish_pos/screens/admin/twilio_credentials_screen.dart';
import 'package:goldfish_pos/widgets/pin_numpad.dart';
import 'package:provider/provider.dart';

/// The System Admin area is PIN-gated and contains settings that must be
/// restricted from regular admins and receptionists (e.g. Twilio API keys).
class SystemAdminDashboardScreen extends StatelessWidget {
  const SystemAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Admin'),
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Warning banner ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.deepOrange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, color: Colors.deepOrange.shade700, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'System Admin — Restricted Access\n'
                      'Changes here affect core integrations. '
                      'Only authorised personnel should access this section.',
                      style: TextStyle(
                        color: Colors.deepOrange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Grid of admin cards ───────────────────────────────────────
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _SysAdminCard(
                  title: 'Payment Methods',
                  subtitle: 'Configure accepted payments',
                  icon: Icons.payment_outlined,
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentMethodManagementScreen(),
                    ),
                  ),
                ),
                _SysAdminCard(
                  title: 'Cash Drawer',
                  subtitle: 'Hardware & bridge settings',
                  icon: Icons.point_of_sale_outlined,
                  color: Colors.brown,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CashDrawerSettingsScreen(),
                    ),
                  ),
                ),
                _SysAdminCard(
                  title: 'Twilio Credentials',
                  subtitle: 'SMS API keys',
                  icon: Icons.message_outlined,
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TwilioCredentialsScreen(),
                    ),
                  ),
                ),
                _SysAdminCard(
                  title: 'Change Sys Admin PIN',
                  subtitle: 'System Admin access PIN',
                  icon: Icons.admin_panel_settings_outlined,
                  color: Colors.teal,
                  onTap: () => _showChangeSysAdminPinDialog(context),
                ),
                _SysAdminCard(
                  title: 'Change Admin PIN',
                  subtitle: 'Admin (Setup) access PIN',
                  icon: Icons.pin_outlined,
                  color: Colors.blueGrey,
                  onTap: () => _showChangeAdminPinDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── SaaS Client Management ────────────────────────────────────
            Text(
              'SaaS Client Management',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Onboard new nail salon clients and manage existing deployments.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _SysAdminCard(
                  title: 'Onboard New Client',
                  subtitle: 'Step-by-step setup wizard',
                  icon: Icons.add_business_outlined,
                  color: Colors.green.shade700,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ClientOnboardingScreen(),
                    ),
                  ),
                ),
                _SysAdminCard(
                  title: 'Client Manager',
                  subtitle: 'View all clients & scripts',
                  icon: Icons.store_mall_directory_outlined,
                  color: Colors.indigo.shade600,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ClientManagerScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showChangeSysAdminPinDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const _ChangeSysAdminPinDialog(),
    );
  }

  Future<void> _showChangeAdminPinDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => const _ChangeAdminPinDialog(),
    );
  }
}

// ─── Shared PIN change dialog ──────────────────────────────────────────────────

class _PinChangeDialog extends StatefulWidget {
  final String title;
  final Color color;
  final IconData icon;
  final Future<void> Function(String pin) onSave;
  final String successMessage;

  const _PinChangeDialog({
    required this.title,
    required this.color,
    required this.icon,
    required this.onSave,
    required this.successMessage,
  });

  @override
  State<_PinChangeDialog> createState() => _PinChangeDialogState();
}

class _PinChangeDialogState extends State<_PinChangeDialog> {
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  final _newPinFocus = FocusNode();
  final _confirmPinFocus = FocusNode();
  // Which controller the numpad should target (starts with newPin).
  late TextEditingController _activeCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _activeCtrl = _newPinCtrl;
    _newPinFocus.addListener(() {
      if (_newPinFocus.hasFocus) setState(() => _activeCtrl = _newPinCtrl);
    });
    _confirmPinFocus.addListener(() {
      if (_confirmPinFocus.hasFocus)
        setState(() => _activeCtrl = _confirmPinCtrl);
    });
  }

  @override
  void dispose() {
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _newPinFocus.dispose();
    _confirmPinFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _newPinCtrl.text.trim();
    final confirm = _confirmPinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'PIN must be at least 4 characters.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(pin);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.successMessage),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Failed to save PIN: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final touchscreen = context.read<TouchscreenProvider>().enabled;
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.icon, color: widget.color),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: SizedBox(
        width: touchscreen ? 260 : 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _newPinCtrl,
              focusNode: _newPinFocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: !touchscreen,
              readOnly: touchscreen,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPinCtrl,
              focusNode: _confirmPinFocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              readOnly: touchscreen,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (touchscreen) ...[
              const SizedBox(height: 16),
              // Tabs to switch which field the numpad targets
              Row(
                children: [
                  _FieldTab(
                    label: 'New PIN',
                    active: _activeCtrl == _newPinCtrl,
                    onTap: () => setState(() => _activeCtrl = _newPinCtrl),
                  ),
                  const SizedBox(width: 8),
                  _FieldTab(
                    label: 'Confirm PIN',
                    active: _activeCtrl == _confirmPinCtrl,
                    onTap: () => setState(() => _activeCtrl = _confirmPinCtrl),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PinNumpad(
                onDigit: (d) => setState(() => pinNumpadAppend(_activeCtrl, d)),
                onDelete: () => setState(() => pinNumpadDelete(_activeCtrl)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save PIN'),
        ),
      ],
    );
  }
}

// ─── Field-selector tab for numpad ────────────────────────────────────────────

class _FieldTab extends StatelessWidget {
  const _FieldTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? cs.onPrimary : cs.onSurface,
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sys Admin PIN dialog ─────────────────────────────────────────────────────

class _ChangeSysAdminPinDialog extends StatelessWidget {
  const _ChangeSysAdminPinDialog();

  @override
  Widget build(BuildContext context) {
    final repo = PosRepository();
    return _PinChangeDialog(
      title: 'Change Sys Admin PIN',
      color: Colors.teal,
      icon: Icons.admin_panel_settings_outlined,
      onSave: (pin) => repo.saveSysAdminPin(pin),
      successMessage: 'System Admin PIN updated.',
    );
  }
}

// ─── Admin PIN dialog ─────────────────────────────────────────────────────────

class _ChangeAdminPinDialog extends StatelessWidget {
  const _ChangeAdminPinDialog();

  @override
  Widget build(BuildContext context) {
    final repo = PosRepository();
    return _PinChangeDialog(
      title: 'Change Admin PIN',
      color: Colors.blueGrey,
      icon: Icons.pin_outlined,
      onSave: (pin) => repo.saveAdminPin(pin),
      successMessage: 'Admin PIN updated.',
    );
  }
}

// ─── Card widget ──────────────────────────────────────────────────────────────

class _SysAdminCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SysAdminCard({
    required this.title,
    required this.subtitle,
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
              colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
