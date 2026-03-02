import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/booking_settings_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

class BookingSettingsScreen extends StatefulWidget {
  const BookingSettingsScreen({super.key});

  @override
  State<BookingSettingsScreen> createState() => _BookingSettingsScreenState();
}

class _BookingSettingsScreenState extends State<BookingSettingsScreen> {
  final _repo = PosRepository();
  BookingSettings? _settings;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _repo.getBookingSettings();
    if (mounted)
      setState(() {
        _settings = s;
        _loading = false;
      });
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await _repo.saveBookingSettings(_settings!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking settings saved.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _toggleDay(int day) {
    if (_settings == null) return;
    final days = List<int>.from(_settings!.enabledWeekdays);
    if (days.contains(day)) {
      days.remove(day);
    } else {
      days.add(day);
      days.sort();
    }
    setState(() => _settings = _settings!.copyWith(enabledWeekdays: days));
  }

  Future<void> _addBlackoutDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null || _settings == null) return;
    final d = DateTime(picked.year, picked.month, picked.day);
    final existing = List<DateTime>.from(_settings!.blackoutDates);
    if (!existing.any((e) => e.isAtSameMomentAs(d))) {
      existing.add(d);
      existing.sort();
      setState(() => _settings = _settings!.copyWith(blackoutDates: existing));
    }
  }

  void _removeBlackoutDate(DateTime date) {
    if (_settings == null) return;
    final existing = List<DateTime>.from(_settings!.blackoutDates)
      ..removeWhere(
        (d) =>
            d.year == date.year && d.month == date.month && d.day == date.day,
      );
    setState(() => _settings = _settings!.copyWith(blackoutDates: existing));
  }

  Future<void> _pickHour(int weekday, bool isOpen) async {
    if (_settings == null) return;
    final current =
        _settings!.businessHours[weekday] ??
        const DayHours(open: '09:00', close: '18:00');
    TimeOfDay parseTime(String hhmm) {
      final p = hhmm.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }

    final initial = parseTime(isOpen ? current.open : current.close);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final fmt =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final updated = isOpen
        ? DayHours(open: fmt, close: current.close)
        : DayHours(open: current.open, close: fmt);
    final hours = Map<int, DayHours>.from(_settings!.businessHours)
      ..[weekday] = updated;
    setState(() => _settings = _settings!.copyWith(businessHours: hours));
  }

  Future<void> _manageServices() async {
    if (_settings == null) return;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _ServiceListEditor(services: _settings!.onlineServices),
    );
    if (result != null) {
      setState(() => _settings = _settings!.copyWith(onlineServices: result));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: _saving ? null : _save,
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Online Booking Toggle ─────────────────────────────────────────
        _SectionHeader(title: 'Online Booking', icon: Icons.public),
        Card(
          child: SwitchListTile(
            title: const Text('Enable Online Booking Portal'),
            subtitle: const Text(
              'Customers can book from the website when this is on.',
            ),
            value: s.onlineBookingEnabled,
            activeThumbColor: Colors.teal,
            onChanged: (v) =>
                setState(() => _settings = s.copyWith(onlineBookingEnabled: v)),
          ),
        ),
        const SizedBox(height: 24),

        // ── Enabled Weekdays ──────────────────────────────────────────────
        _SectionHeader(title: 'Open Days', icon: Icons.date_range),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final day = i + 1;
                final enabled = s.enabledWeekdays.contains(day);
                return FilterChip(
                  label: Text(Weekday.shortName(day)),
                  selected: enabled,
                  selectedColor: Colors.teal.shade100,
                  checkmarkColor: Colors.teal.shade800,
                  onSelected: (_) => _toggleDay(day),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Business Hours ────────────────────────────────────────────────
        _SectionHeader(title: 'Business Hours', icon: Icons.access_time),
        Card(
          child: Column(
            children: [
              ...List.generate(7, (i) {
                final day = i + 1;
                final isEnabled = s.enabledWeekdays.contains(day);
                final hours =
                    s.businessHours[day] ??
                    const DayHours(open: '09:00', close: '18:00');
                return Column(
                  children: [
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 32,
                        child: Text(
                          Weekday.shortName(day),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isEnabled
                                ? Colors.black87
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          _TimeButton(
                            label: hours.open,
                            enabled: isEnabled,
                            onTap: () => _pickHour(day, true),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('–'),
                          ),
                          _TimeButton(
                            label: hours.close,
                            enabled: isEnabled,
                            onTap: () => _pickHour(day, false),
                          ),
                        ],
                      ),
                      trailing: !isEnabled
                          ? Text(
                              'Closed',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Booking Window / Advance Notice ───────────────────────────────
        _SectionHeader(title: 'Booking Rules', icon: Icons.rule),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Booking Window (days in advance)'),
                subtitle: Text(
                  'Customers can book up to ${s.bookingWindowDays} days ahead.',
                ),
                trailing: SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<int>(
                    initialValue: s.bookingWindowDays,
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: [7, 14, 30, 60, 90]
                        .map(
                          (d) =>
                              DropdownMenuItem(value: d, child: Text('$d d')),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () => _settings = s.copyWith(bookingWindowDays: v ?? 30),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Minimum Advance Notice'),
                subtitle: Text(
                  'Online bookings must be at least ${s.minAdvanceHours}h in advance.',
                ),
                trailing: SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<int>(
                    initialValue: s.minAdvanceHours,
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: [1, 2, 4, 8, 24]
                        .map(
                          (h) =>
                              DropdownMenuItem(value: h, child: Text('${h}h')),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () => _settings = s.copyWith(minAdvanceHours: v ?? 2),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Time Slot Duration'),
                subtitle: Text(
                  'Default appointment slot is ${s.slotDurationMinutes} min.',
                ),
                trailing: SizedBox(
                  width: 90,
                  child: DropdownButtonFormField<int>(
                    initialValue: s.slotDurationMinutes,
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: [15, 30, 45, 60, 90, 120]
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text('$m min')),
                        )
                        .toList(),
                    onChanged: (v) => setState(
                      () =>
                          _settings = s.copyWith(slotDurationMinutes: v ?? 60),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Services ──────────────────────────────────────────────────────
        _SectionHeader(title: 'Online Services', icon: Icons.spa),
        Card(
          child: Column(
            children: [
              ...s.onlineServices.map(
                (svc) => Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.circle,
                        size: 8,
                        color: Colors.teal,
                      ),
                      title: Text(svc),
                    ),
                    const Divider(height: 1),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.teal),
                title: const Text(
                  'Edit Services List',
                  style: TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _manageServices,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Blackout Dates ────────────────────────────────────────────────
        _SectionHeader(title: 'Blackout Dates', icon: Icons.event_busy),
        Card(
          child: Column(
            children: [
              if (s.blackoutDates.isEmpty)
                const ListTile(
                  title: Text(
                    'No blackout dates',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ...s.blackoutDates.map((date) {
                final label =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.block,
                        size: 16,
                        color: Colors.red,
                      ),
                      title: Text(label),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        color: Colors.red,
                        onPressed: () => _removeBlackoutDate(date),
                        tooltip: 'Remove',
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),
              ListTile(
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.teal,
                ),
                title: const Text(
                  'Add Blackout Date',
                  style: TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _addBlackoutDate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.teal),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? Colors.teal.shade200 : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(6),
          color: enabled ? Colors.teal.shade50 : Colors.grey.shade50,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: enabled ? Colors.teal.shade800 : Colors.grey.shade400,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service list editor dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceListEditor extends StatefulWidget {
  final List<String> services;
  const _ServiceListEditor({required this.services});

  @override
  State<_ServiceListEditor> createState() => _ServiceListEditorState();
}

class _ServiceListEditorState extends State<_ServiceListEditor> {
  late List<String> _services;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _services = List<String>.from(widget.services);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final v = _ctrl.text.trim();
    if (v.isEmpty || _services.contains(v)) return;
    setState(() => _services.add(v));
    _ctrl.clear();
  }

  void _remove(String s) => setState(() => _services.remove(s));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Online Services'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Add service…',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                  style: IconButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _services.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_services[i]),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: Colors.red,
                    onPressed: () => _remove(_services[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _services),
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
