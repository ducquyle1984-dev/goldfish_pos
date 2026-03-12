import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:goldfish_pos/models/client_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/screens/admin/client_onboarding_screen.dart';

/// Displays all onboarded clients, their status, and quick access to their
/// deployment scripts. Accessible from the System Admin dashboard.
class ClientManagerScreen extends StatelessWidget {
  const ClientManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = PosRepository();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Manager'),
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClientOnboardingScreen()),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Onboard New Client'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<List<ClientRecord>>(
        stream: repo.streamClients(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error loading clients: ${snap.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          final clients = snap.data ?? [];
          if (clients.isEmpty) {
            return _EmptyState(
              onAdd: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ClientOnboardingScreen(),
                ),
              ),
            );
          }
          return Column(
            children: [
              _StatBar(clients: clients),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) =>
                      _ClientTile(client: clients[i], repo: repo),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Stat summary bar ─────────────────────────────────────────────────────────

class _StatBar extends StatelessWidget {
  const _StatBar({required this.clients});
  final List<ClientRecord> clients;

  @override
  Widget build(BuildContext context) {
    final total = clients.length;
    final active = clients.where((c) => c.status == 'active').length;
    final pending = clients.where((c) => c.status == 'pending').length;
    final suspended = clients.where((c) => c.status == 'suspended').length;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Row(
        children: [
          _Stat('Total Clients', '$total', Colors.grey.shade700),
          const SizedBox(width: 32),
          _Stat('Active', '$active', Colors.green.shade700),
          const SizedBox(width: 32),
          _Stat('Pending Deploy', '$pending', Colors.orange.shade700),
          const SizedBox(width: 32),
          _Stat('Suspended', '$suspended', Colors.red.shade700),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ─── Individual client card ───────────────────────────────────────────────────

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.repo});
  final ClientRecord client;
  final PosRepository repo;

  Color get _statusColor => switch (client.status) {
    'active' => Colors.green,
    'suspended' => Colors.red,
    _ => Colors.orange,
  };

  IconData get _statusIcon => switch (client.status) {
    'active' => Icons.check_circle_outline,
    'suspended' => Icons.block_outlined,
    _ => Icons.hourglass_empty_outlined,
  };

  String get _statusLabel => switch (client.status) {
    'active' => 'Active',
    'suspended' => 'Suspended',
    _ => 'Pending Deploy',
  };

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, yyyy').format(client.onboardedAt);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Colour avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  client.salonName.isNotEmpty
                      ? client.salonName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.salonName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${client.ownerName}  ·  ${client.ownerEmail}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.fullUrl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Plan chip
              Chip(
                label: Text(client.plan, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),

              // Status chip
              Chip(
                avatar: Icon(_statusIcon, size: 14, color: _statusColor),
                label: Text(
                  _statusLabel,
                  style: TextStyle(fontSize: 11, color: _statusColor),
                ),
                backgroundColor: _statusColor.withValues(alpha: 0.1),
                side: BorderSide(color: _statusColor.withValues(alpha: 0.3)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),

              // Date
              Text(
                date,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ── Detail bottom sheet ───────────────────────────────────────────────────

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ClientDetailSheet(client: client, repo: repo),
    );
  }
}

// ─── Detail bottom sheet ──────────────────────────────────────────────────────

class _ClientDetailSheet extends StatefulWidget {
  const _ClientDetailSheet({required this.client, required this.repo});
  final ClientRecord client;
  final PosRepository repo;

  @override
  State<_ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends State<_ClientDetailSheet> {
  late String _status;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _status = widget.client.status;
  }

  Future<void> _setStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      await widget.repo.updateClientStatus(widget.client.id!, newStatus);
      if (mounted) setState(() => _status = newStatus);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final date = DateFormat('MMM d, yyyy  h:mm a').format(client.onboardedAt);
    final scriptText = _buildScript(client);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.salonName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Onboarded $date',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),

          // Scrollable content
          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // Status & actions row
                Row(
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _status,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending Deploy'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'suspended',
                          child: Text('Suspended'),
                        ),
                      ],
                      onChanged: _updating
                          ? null
                          : (v) {
                              if (v != null && v != _status) _setStatus(v);
                            },
                    ),
                    if (_updating)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Details grid
                _DetailCard(
                  title: 'Business',
                  rows: [
                    ('Owner', client.ownerName),
                    ('Email', client.ownerEmail),
                    ('Phone', client.phone),
                    if (client.address.isNotEmpty)
                      (
                        'Address',
                        [
                          client.address,
                          [
                            client.city,
                            client.state,
                            client.zip,
                          ].where((s) => s.isNotEmpty).join(', '),
                        ].where((s) => s.isNotEmpty).join(', '),
                      ),
                    ('Plan', client.plan),
                  ],
                ),
                const SizedBox(height: 10),
                _DetailCard(
                  title: 'Technical',
                  rows: [
                    ('Firebase ID', client.firebaseProjectId),
                    ('Custom URL', client.fullUrl),
                    ('Fallback URL', client.fallbackUrl),
                    ('Admin Email', client.adminEmail),
                  ],
                ),
                if (client.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Notes',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            client.notes,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Script
                Row(
                  children: [
                    const Text(
                      'Deployment Script',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: scriptText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Script copied to clipboard!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scriptText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFD4D4D4),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildScript(ClientRecord c) =>
      '# Goldfish POS — Re-deploy Script for ${c.salonName}\n'
      '\$PROJECT_ID = "${c.firebaseProjectId}"\n'
      '\$SALON_NAME = "${c.salonName}"\n\n'
      '\$originalConfig = Get-Content lib\\firebase_options.dart -Raw\n'
      'flutterfire configure --project=\$PROJECT_ID --platforms=web --yes\n'
      'flutter build web --release\n'
      'firebase deploy --only hosting --project \$PROJECT_ID\n'
      'Set-Content lib\\firebase_options.dart \$originalConfig\n'
      'Write-Host "Deployed ${c.salonName} to ${c.fullUrl}"';
}

// ─── Detail card helper ───────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        r.$1,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(r.$2, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_mall_directory_outlined,
            size: 72,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No clients yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Onboard your first nail salon client to get started.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Onboard First Client'),
          ),
        ],
      ),
    );
  }
}
