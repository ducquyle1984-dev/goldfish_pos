import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/appointment_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:goldfish_pos/widgets/quick_book_dialog.dart';
import 'package:intl/intl.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _repo = PosRepository();
  DateTime _viewDate = DateTime.now();
  late Stream<List<Appointment>> _appointmentsStream;

  DateTime get _normalised =>
      DateTime(_viewDate.year, _viewDate.month, _viewDate.day);

  @override
  void initState() {
    super.initState();
    _appointmentsStream = _repo.getAppointmentsForDate(_normalised);
  }

  void _previousDay() {
    final newDate = DateTime(
      _viewDate.year,
      _viewDate.month,
      _viewDate.day,
    ).subtract(const Duration(days: 1));
    setState(() {
      _viewDate = newDate;
      _appointmentsStream = _repo.getAppointmentsForDate(newDate);
    });
  }

  void _nextDay() {
    final newDate = DateTime(
      _viewDate.year,
      _viewDate.month,
      _viewDate.day,
    ).add(const Duration(days: 1));
    setState(() {
      _viewDate = newDate;
      _appointmentsStream = _repo.getAppointmentsForDate(newDate);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _viewDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      final newDate = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _viewDate = newDate;
        _appointmentsStream = _repo.getAppointmentsForDate(newDate);
      });
    }
  }

  Future<void> _bookNew() async {
    final result = await showQuickBookDialog(context, initialDate: _viewDate);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Appointment booked for ${result.customerName} at ${DateFormat.jm().format(result.scheduledAt)}',
          ),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday =
        _normalised ==
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final headerLabel = isToday
        ? 'Today — ${DateFormat.MMMMd().format(_viewDate)}'
        : DateFormat.MMMMEEEEd().format(_viewDate);

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date navigator ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousDay,
                  tooltip: 'Previous day',
                ),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          size: 18,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          headerLabel,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextDay,
                  tooltip: 'Next day',
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Appointment'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: _bookNew,
                ),
              ],
            ),
          ),

          // ── Appointment list ─────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<Appointment>>(
              stream: _appointmentsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    snapshot.connectionState == ConnectionState.none) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  // Print full error so Firestore index URLs appear in debug console
                  debugPrint(
                    'BookingScreen stream error: ${snapshot.error}\n${snapshot.stackTrace}',
                  );
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Failed to load appointments',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            '${snapshot.error}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final appts = snapshot.data ?? [];

                if (appts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No appointments scheduled',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Book one'),
                          onPressed: _bookNew,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: appts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _AppointmentCard(appt: appts[i], repo: _repo),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual appointment card
// ─────────────────────────────────────────────────────────────────────────────

class _AppointmentCard extends StatelessWidget {
  final Appointment appt;
  final PosRepository repo;

  const _AppointmentCard({required this.appt, required this.repo});

  Future<void> _setStatus(
    BuildContext context,
    AppointmentStatus status,
  ) async {
    try {
      await repo.updateAppointmentStatus(appt.id, status);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Appointment'),
        content: const Text('Permanently delete this appointment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await repo.deleteAppointment(appt.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat.jm().format(appt.scheduledAt);
    final endLabel = DateFormat.jm().format(appt.endsAt);
    final isOnline = appt.source == AppointmentSource.online;
    final isPending = appt.status == AppointmentStatus.pendingConfirmation;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status stripe
            Container(width: 6, color: appt.statusColor),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Time
                        Text(
                          '$timeLabel – $endLabel',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Source chip
                        if (isOnline)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Text(
                              'Online',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        // Pending confirmation badge
                        if (isPending) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Text(
                              'Awaiting Confirmation',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],

                        const Spacer(),

                        // Status label
                        Text(
                          appt.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: appt.statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appt.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      appt.customerPhone,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.spa_outlined,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          appt.serviceName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${appt.durationMinutes} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    if (appt.notes != null && appt.notes!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        appt.notes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isPending) ...[
                    _ActionBtn(
                      icon: Icons.check_circle_outline,
                      label: 'Confirm',
                      color: Colors.teal,
                      onTap: () =>
                          _setStatus(context, AppointmentStatus.confirmed),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (appt.status == AppointmentStatus.confirmed) ...[
                    _ActionBtn(
                      icon: Icons.done_all,
                      label: 'Done',
                      color: Colors.green,
                      onTap: () =>
                          _setStatus(context, AppointmentStatus.completed),
                    ),
                    const SizedBox(height: 4),
                    _ActionBtn(
                      icon: Icons.person_off_outlined,
                      label: 'No Show',
                      color: Colors.orange,
                      onTap: () =>
                          _setStatus(context, AppointmentStatus.noShow),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (appt.status != AppointmentStatus.cancelled &&
                      appt.status != AppointmentStatus.completed) ...[
                    _ActionBtn(
                      icon: Icons.cancel_outlined,
                      label: 'Cancel',
                      color: Colors.red,
                      onTap: () =>
                          _setStatus(context, AppointmentStatus.cancelled),
                    ),
                    const SizedBox(height: 4),
                  ],
                  _ActionBtn(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: Colors.grey,
                    onTap: () => _delete(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
