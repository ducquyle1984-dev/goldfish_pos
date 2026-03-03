import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:goldfish_pos/models/appointment_model.dart';
import 'package:goldfish_pos/models/booking_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// Opens the quick booking dialog and returns the created [Appointment],
/// or null if cancelled / failed.
Future<Appointment?> showQuickBookDialog(
  BuildContext context, {
  DateTime? initialDate,
}) async {
  return showDialog<Appointment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuickBookDialog(initialDate: initialDate),
  );
}

class _QuickBookDialog extends StatefulWidget {
  final DateTime? initialDate;
  const _QuickBookDialog({this.initialDate});

  @override
  State<_QuickBookDialog> createState() => _QuickBookDialogState();
}

class _QuickBookDialogState extends State<_QuickBookDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _repo = PosRepository();

  BookingSettings? _settings;
  String? _selectedService;
  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 10, minute: 0);
  int _durationMinutes = 60;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _repo.getBookingSettings();
    if (mounted) {
      setState(() {
        _settings = s;
        // Default service to first in list
        if (s.onlineServices.isNotEmpty) {
          _selectedService = s.onlineServices.first;
        }
        _durationMinutes = s.slotDurationMinutes;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final scheduledAt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final appt = Appointment(
      id: '',
      customerName: _nameCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim(),
      serviceName: _selectedService ?? _nameCtrl.text.trim(),
      scheduledAt: scheduledAt,
      durationMinutes: _durationMinutes,
      status: AppointmentStatus.confirmed,
      source: AppointmentSource.staff,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: now,
      updatedAt: now,
    );

    try {
      final id = await _repo.createAppointment(appt);
      if (mounted) Navigator.pop(context, appt.copyWith(id: id));
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _settings?.onlineServices ?? [];
    final dateLabel =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final timeLabel = _selectedTime.format(context);

    final isBlackout =
        _settings != null &&
        !_settings!.isDateAvailable(_selectedDate) &&
        // distinguish blackout from closed weekday — show different messages
        _settings!.blackoutDates.any(
          (b) =>
              b.year == _selectedDate.year &&
              b.month == _selectedDate.month &&
              b.day == _selectedDate.day,
        );
    final isClosedDay =
        _settings != null &&
        !_settings!.enabledWeekdays.contains(_selectedDate.weekday) &&
        !isBlackout;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.calendar_month, color: Colors.teal),
          const SizedBox(width: 8),
          const Text('Book Appointment'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Blackout / closed-day warning ──────────────────────
                if (isBlackout) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_busy,
                          color: Colors.orange.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$dateLabel is a blackout date. You can still book as staff override.',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isClosedDay) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.store_outlined,
                          color: Colors.orange.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$dateLabel is outside normal business days. You can still book as staff override.',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name *',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Phone
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\s\-\+\(\)]'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Service
                if (services.isEmpty)
                  TextFormField(
                    initialValue: _selectedService,
                    decoration: const InputDecoration(
                      labelText: 'Service *',
                      prefixIcon: Icon(Icons.spa_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => _selectedService = v,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedService,
                    decoration: const InputDecoration(
                      labelText: 'Service *',
                      prefixIcon: Icon(Icons.spa_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: services
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedService = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                const SizedBox(height: 12),

                // Date & Time row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(dateLabel),
                        onPressed: _pickDate,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 12,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(timeLabel),
                        onPressed: _pickTime,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 12,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Duration
                Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text('Duration:'),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _durationMinutes,
                      underline: const SizedBox(),
                      items: [30, 45, 60, 90, 120]
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text('$m min'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _durationMinutes = v ?? 60),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Notes (optional)
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 16),
          label: const Text('Book'),
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
        ),
      ],
    );
  }
}
