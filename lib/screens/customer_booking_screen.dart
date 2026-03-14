import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:goldfish_pos/models/appointment_model.dart';
import 'package:goldfish_pos/models/booking_settings_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';
import 'package:intl/intl.dart';

/// Customer-facing self-booking page, accessible at /book on the web build.
class CustomerBookingScreen extends StatefulWidget {
  const CustomerBookingScreen({super.key});

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

class _CustomerBookingScreenState extends State<CustomerBookingScreen> {
  final _repo = PosRepository();

  // Steps: 0=date, 1=time, 2=details, 3=confirmation
  int _step = 0;
  BookingSettings? _settings;
  bool _loadingSettings = true;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _selectedService;
  final _notesCtrl = TextEditingController();
  List<Employee> _employees = [];
  String? _requestedTechnicianId;
  bool _submitting = false;
  Appointment? _bookedAppt;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // Rebuild when text changes so the submit button reacts
    _nameCtrl.addListener(() => setState(() {}));
    _phoneCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadSettings() async {
    final s = await _repo.getBookingSettings();
    final employees = await _repo.getEmployees().first;
    if (mounted) {
      setState(() {
        _settings = s;
        _loadingSettings = false;
        if (s.onlineServices.isNotEmpty) {
          _selectedService = s.onlineServices.first;
        }
        _employees = employees.where((e) => e.isActive).toList();
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

  // ── Date helpers ─────────────────────────────────────────────────────────

  List<DateTime> _availableDates() {
    if (_settings == null) return [];
    final dates = <DateTime>[];
    final today = DateTime.now();
    for (var i = 0; i < _settings!.bookingWindowDays; i++) {
      final d = today.add(Duration(days: i));
      final norm = DateTime(d.year, d.month, d.day);
      if (_settings!.isDateAvailable(norm)) dates.add(norm);
    }
    return dates;
  }

  // ── Time-slot helpers ────────────────────────────────────────────────────

  List<TimeOfDay> _slotsForDate(DateTime date) {
    if (_settings == null) return [];
    final hours =
        _settings!.businessHours[date.weekday] ??
        const DayHours(open: '09:00', close: '18:00');
    final open = hours.toDateTime(date);
    final close = hours.closeDateTime(date);
    final slots = <TimeOfDay>[];
    var current = open;
    while (current.isBefore(close)) {
      slots.add(TimeOfDay(hour: current.hour, minute: current.minute));
      current = current.add(Duration(minutes: _settings!.slotDurationMinutes));
    }
    // Filter out slots too soon (minAdvanceHours)
    final minTime = DateTime.now().add(
      Duration(hours: _settings!.minAdvanceHours),
    );
    return slots.where((t) {
      final dt = DateTime(date.year, date.month, date.day, t.hour, t.minute);
      return dt.isAfter(minTime);
    }).toList();
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_selectedDate == null || _selectedTime == null) return;
    setState(() => _submitting = true);
    final now = DateTime.now();
    final scheduledAt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    final appt = Appointment(
      id: '',
      customerName: _nameCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim(),
      serviceName: _selectedService ?? '',
      scheduledAt: scheduledAt,
      durationMinutes: _settings?.slotDurationMinutes ?? 60,
      status: AppointmentStatus.pendingConfirmation,
      source: AppointmentSource.online,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      requestedTechnicianId: _requestedTechnicianId,
      requestedTechnicianName: _requestedTechnicianId == null
          ? null
          : _employees.firstWhere((e) => e.id == _requestedTechnicianId).name,
      createdAt: now,
      updatedAt: now,
    );
    try {
      final id = await _repo.createAppointment(appt);
      if (mounted) {
        setState(() {
          _bookedAppt = appt.copyWith(id: id);
          _step = 3;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 640;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Book an Appointment'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loadingSettings
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : (_settings?.onlineBookingEnabled == false)
          ? _buildClosed()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: EdgeInsets.all(isNarrow ? 12 : 32),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStepIndicator(),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: _buildCurrentStep(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildClosed() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Online Booking is Currently Unavailable',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Please call us to book an appointment.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final labels = ['Date', 'Time', 'Your Info', 'Confirmed'];
    return Container(
      color: Colors.teal,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(height: 1, color: Colors.white.withOpacity(0.4)),
            );
          }
          final stepIdx = i ~/ 2;
          final done = stepIdx < _step;
          final active = stepIdx == _step;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done || active
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
                child: done
                    ? Icon(Icons.check, size: 14, color: Colors.teal.shade700)
                    : Text(
                        '${stepIdx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: active ? Colors.teal.shade800 : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[stepIdx],
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(active ? 1 : 0.65),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    return switch (_step) {
      0 => _buildDateStep(),
      1 => _buildTimeStep(),
      2 => _buildDetailsStep(),
      _ => _buildConfirmation(),
    };
  }

  // Step 0 – Date
  Widget _buildDateStep() {
    final dates = _availableDates();
    if (dates.isEmpty) {
      return Column(
        children: [
          const Icon(Icons.event_busy, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No dates available for online booking.'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Date',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: dates.map((date) {
            final isSelected =
                _selectedDate != null && _selectedDate!.isAtSameMomentAs(date);
            return ChoiceChip(
              label: Column(
                children: [
                  Text(
                    DateFormat.E().format(date),
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    DateFormat.MMMd().format(date),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              selectedColor: Colors.teal.shade100,
              onSelected: (_) {
                setState(() {
                  _selectedDate = date;
                  _selectedTime = null; // reset time
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selectedDate == null
                ? null
                : () => setState(() => _step = 1),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Next: Choose Time'),
          ),
        ),
      ],
    );
  }

  // Step 1 – Time
  Widget _buildTimeStep() {
    final slots = _slotsForDate(_selectedDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              onPressed: () => setState(() => _step = 0),
            ),
          ],
        ),
        Text(
          'Select a Time — ${DateFormat.MMMMEEEEd().format(_selectedDate!)}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (slots.isEmpty)
          const Text('No available time slots for this date.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((t) {
              final label = t.format(context);
              final isSelected = _selectedTime == t;
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                selectedColor: Colors.teal.shade100,
                onSelected: (_) => setState(() => _selectedTime = t),
              );
            }).toList(),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selectedTime == null
                ? null
                : () => setState(() => _step = 2),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Next: Your Info'),
          ),
        ),
      ],
    );
  }

  // Step 2 – Details
  Widget _buildDetailsStep() {
    final services = _settings?.onlineServices ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              onPressed: () => setState(() => _step = 1),
            ),
          ],
        ),
        Text(
          'Your Information',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Summary chip
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.event, color: Colors.teal, size: 18),
              const SizedBox(width: 8),
              Text(
                '${DateFormat.MMMMd().format(_selectedDate!)} at ${_selectedTime!.format(context)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your Name *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Phone Number *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        if (services.isNotEmpty)
          DropdownButtonFormField<String>(
            value: services.contains(_selectedService)
                ? _selectedService
                : services.first,
            decoration: const InputDecoration(
              labelText: 'Service *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.spa_outlined),
            ),
            items: services
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _selectedService = v),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
        const SizedBox(height: 12),
        if (_employees.isNotEmpty)
          DropdownButtonFormField<String?>(
            value: _requestedTechnicianId,
            decoration: const InputDecoration(
              labelText: 'Requested Technician (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_pin_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No Preference'),
              ),
              ..._employees.map(
                (e) =>
                    DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
              ),
            ],
            onChanged: (v) => setState(() => _requestedTechnicianId = v),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed:
                (_nameCtrl.text.isNotEmpty &&
                    _phoneCtrl.text.isNotEmpty &&
                    !_submitting)
                ? _submit
                : null,
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Request Appointment'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your appointment will be confirmed by our team shortly.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Step 3 – Confirmation
  Widget _buildConfirmation() {
    final appt = _bookedAppt;
    if (appt == null) return const SizedBox();
    return Column(
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.check_circle, size: 72, color: Colors.teal),
        const SizedBox(height: 16),
        Text(
          'Request Received!',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'We\'ve received your booking request. Our team will confirm it shortly — please check your phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ConfirmRow(Icons.person_outline, appt.customerName),
              const SizedBox(height: 6),
              _ConfirmRow(Icons.phone_outlined, appt.customerPhone),
              const SizedBox(height: 6),
              _ConfirmRow(Icons.spa_outlined, appt.serviceName),
              const SizedBox(height: 6),
              _ConfirmRow(
                Icons.event,
                DateFormat.MMMMEEEEd().format(appt.scheduledAt),
              ),
              const SizedBox(height: 6),
              _ConfirmRow(
                Icons.access_time,
                DateFormat.jm().format(appt.scheduledAt),
              ),
              if (appt.requestedTechnicianName != null) ...[
                const SizedBox(height: 6),
                _ConfirmRow(
                  Icons.person_pin_outlined,
                  'Requested: ${appt.requestedTechnicianName}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () {
            setState(() {
              _step = 0;
              _selectedDate = null;
              _selectedTime = null;
              _nameCtrl.clear();
              _phoneCtrl.clear();
              _notesCtrl.clear();
              _requestedTechnicianId = null;
              _bookedAppt = null;
            });
          },
          child: const Text('Book Another Appointment'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ConfirmRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.teal),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}
