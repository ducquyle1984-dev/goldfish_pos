import 'dart:async';

import 'package:flutter/material.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enum for the different "views" inside the kiosk flow
// ─────────────────────────────────────────────────────────────────────────────
enum _KioskView { phoneEntry, loading, welcomeBack, registration, success }

// ─────────────────────────────────────────────────────────────────────────────
// Root widget – stateful, self-contained kiosk flow
// ─────────────────────────────────────────────────────────────────────────────
class KioskCheckInScreen extends StatefulWidget {
  const KioskCheckInScreen({super.key});

  @override
  State<KioskCheckInScreen> createState() => _KioskCheckInScreenState();
}

class _KioskCheckInScreenState extends State<KioskCheckInScreen> {
  final _repo = PosRepository();

  // ── state ─────────────────────────────────────────────────────────────────
  _KioskView _view = _KioskView.phoneEntry;
  String _digits = ''; // raw 10 digits, no dashes
  Customer? _foundCustomer; // set after successful lookup or registration

  // Registration form
  final _nameCtrl = TextEditingController();
  int _birthMonth = 1; // 1-12
  int _birthDay = 1; // 1-31

  // Auto-reset timer after success
  Timer? _resetTimer;
  int _countdown = 6; // seconds remaining on success screen

  @override
  void dispose() {
    _nameCtrl.dispose();
    _resetTimer?.cancel();
    super.dispose();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Format raw digits into (XXX) XXX-XXXX for display.
  String get _formattedPhone {
    if (_digits.isEmpty) return '';
    final d = _digits.padRight(10, '_');
    final area = d.substring(0, 3);
    final mid = d.substring(3, 6);
    final last = d.substring(6, 10);
    return '($area) $mid-$last';
  }

  void _onDigit(String digit) {
    if (_digits.length >= 10) return;
    setState(() => _digits += digit);
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  void _reset() {
    _resetTimer?.cancel();
    setState(() {
      _digits = '';
      _nameCtrl.clear();
      _birthMonth = 1;
      _birthDay = 1;
      _foundCustomer = null;
      _countdown = 6;
      _view = _KioskView.phoneEntry;
    });
  }

  void _startResetCountdown() {
    _countdown = 6;
    _resetTimer?.cancel();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        _reset();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  // ── look up customer by phone ─────────────────────────────────────────────
  Future<void> _submitPhone() async {
    if (_digits.length != 10) return;

    setState(() => _view = _KioskView.loading);
    try {
      final customer = await _repo.getCustomerByPhone(_digits);
      if (!mounted) return;

      if (customer != null) {
        // Existing customer → create pending transaction
        await _createPendingTransaction(customer);
        setState(() {
          _foundCustomer = customer;
          _view = _KioskView.welcomeBack;
        });
        _startResetCountdown();
      } else {
        // New customer → registration
        setState(() => _view = _KioskView.registration);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _view = _KioskView.phoneEntry);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── create pending transaction (same logic as POS) ────────────────────────
  Future<void> _createPendingTransaction(Customer customer) async {
    final now = DateTime.now();
    final tx = Transaction(
      id: '',
      items: const [],
      customerId: customer.id,
      customerName: customer.name,
      status: TransactionStatus.pending,
      subtotal: 0,
      totalAmount: 0,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.createTransaction(tx);
  }

  // ── register new customer ─────────────────────────────────────────────────
  Future<void> _registerCustomer() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _view = _KioskView.loading);
    try {
      final now = DateTime.now();
      final customer = Customer(
        id: '',
        name: name,
        phone: _digits,
        birthMonth: _birthMonth,
        birthDay: _birthDay,
        createdAt: now,
        updatedAt: now,
      );
      final id = await _repo.createCustomer(customer);
      final created = await _repo.getCustomer(id);
      if (!mounted) return;

      if (created != null) {
        await _createPendingTransaction(created);
        setState(() {
          _foundCustomer = created;
          _view = _KioskView.success;
        });
        _startResetCountdown();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _view = _KioskView.registration);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _buildCurrentView(),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_view) {
      case _KioskView.phoneEntry:
        return _PhoneEntryView(
          key: const ValueKey('phone'),
          formattedPhone: _formattedPhone,
          digitCount: _digits.length,
          onDigit: _onDigit,
          onDelete: _onDelete,
          onSubmit: _digits.length == 10 ? _submitPhone : null,
        );
      case _KioskView.loading:
        return const _LoadingView(key: ValueKey('loading'));
      case _KioskView.welcomeBack:
        return _SuccessView(
          key: const ValueKey('welcome'),
          customer: _foundCustomer!,
          isNew: false,
          countdown: _countdown,
          onDone: _reset,
        );
      case _KioskView.registration:
        return _RegistrationView(
          key: const ValueKey('registration'),
          phone: _formattedPhone,
          nameCtrl: _nameCtrl,
          birthMonth: _birthMonth,
          birthDay: _birthDay,
          onMonthChanged: (m) => setState(() => _birthMonth = m),
          onDayChanged: (d) => setState(() => _birthDay = d),
          onSubmit: _registerCustomer,
          onBack: _reset,
        );
      case _KioskView.success:
        return _SuccessView(
          key: const ValueKey('success'),
          customer: _foundCustomer!,
          isNew: true,
          countdown: _countdown,
          onDone: _reset,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone Entry View
// ─────────────────────────────────────────────────────────────────────────────
class _PhoneEntryView extends StatelessWidget {
  const _PhoneEntryView({
    super.key,
    required this.formattedPhone,
    required this.digitCount,
    required this.onDigit,
    required this.onDelete,
    required this.onSubmit,
  });

  final String formattedPhone;
  final int digitCount;
  final void Function(String) onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Logo / Brand ─────────────────────────────────────────────
              const Icon(
                Icons.storefront_rounded,
                color: Colors.tealAccent,
                size: 48,
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter your phone number to check in.',
                style: TextStyle(color: Colors.white60, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // ── Phone display ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.tealAccent.withAlpha(130)),
                ),
                child: Text(
                  digitCount == 0
                      ? '(___) ___-____'
                      : formattedPhone.replaceAll('_', '·'),
                  style: TextStyle(
                    color: digitCount == 0 ? Colors.white38 : Colors.white,
                    fontSize: 34,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // ── Numpad ───────────────────────────────────────────────────
              _NumPad(onDigit: onDigit, onDelete: onDelete),
              const SizedBox(height: 28),

              // ── Submit button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 62,
                child: FilledButton(
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white30,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('Check In'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numpad widget
// ─────────────────────────────────────────────────────────────────────────────
class _NumPad extends StatelessWidget {
  const _NumPad({required this.onDigit, required this.onDelete});

  final void Function(String) onDigit;
  final VoidCallback onDelete;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row
                .map((d) => _DialKey(label: d, onTap: () => onDigit(d)))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        // Bottom row: blank | 0 | delete
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 90 + 12), // blank space
            _DialKey(label: '0', onTap: () => onDigit('0')),
            _DialKey(icon: Icons.backspace_outlined, onTap: onDelete),
          ],
        ),
      ],
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.tealAccent.withAlpha(60),
          child: SizedBox(
            width: 90,
            height: 72,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Icon(icon, color: Colors.white70, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading View
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.tealAccent),
          SizedBox(height: 24),
          Text(
            'Looking you up…',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Success / Welcome-back View
// ─────────────────────────────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  const _SuccessView({
    super.key,
    required this.customer,
    required this.isNew,
    required this.countdown,
    required this.onDone,
  });

  final Customer customer;
  final bool isNew;
  final int countdown;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.tealAccent.withAlpha(30),
                  border: Border.all(color: Colors.tealAccent, width: 2),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.tealAccent,
                  size: 56,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                isNew ? 'Welcome to our loyalty program!' : 'Welcome back!',
                style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                customer.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (!isNew)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${customer.rewardPoints.toStringAsFixed(0)} reward points',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'You\'re all checked in!\nA staff member will be right with you.',
                style: const TextStyle(color: Colors.white60, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: 200,
                height: 52,
                child: OutlinedButton(
                  onPressed: onDone,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Done ($countdown)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration View
// ─────────────────────────────────────────────────────────────────────────────
class _RegistrationView extends StatelessWidget {
  const _RegistrationView({
    super.key,
    required this.phone,
    required this.nameCtrl,
    required this.birthMonth,
    required this.birthDay,
    required this.onMonthChanged,
    required this.onDayChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final String phone;
  final TextEditingController nameCtrl;
  final int birthMonth;
  final int birthDay;
  final void Function(int) onMonthChanged;
  final void Function(int) onDayChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  int _daysInMonth(int month) {
    const days = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month];
  }

  @override
  Widget build(BuildContext context) {
    final maxDay = _daysInMonth(birthMonth);
    final effectiveDay = birthDay.clamp(1, maxDay);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white70,
                    ),
                    onPressed: onBack,
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'New Customer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: Text(
                  'Phone: $phone',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
              const SizedBox(height: 28),

              // ── Name ──────────────────────────────────────────────────────
              _FieldLabel('Your Name'),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                cursorColor: Colors.tealAccent,
                decoration: InputDecoration(
                  hintText: 'First & Last Name',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withAlpha(20),
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: Colors.tealAccent,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.tealAccent,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Birthday ──────────────────────────────────────────────────
              _FieldLabel('Birthday (Month & Day)'),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Month wheel
                  Expanded(
                    flex: 3,
                    child: _WheelPicker(
                      items: _months,
                      selectedIndex: birthMonth - 1,
                      onChanged: (i) => onMonthChanged(i + 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Day wheel
                  Expanded(
                    flex: 2,
                    child: _WheelPicker(
                      items: List.generate(maxDay, (i) => '${i + 1}'),
                      selectedIndex: effectiveDay - 1,
                      onChanged: (i) => onDayChanged(i + 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Submit ────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 62,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: nameCtrl,
                  builder: (_, val, __) {
                    final enabled = val.text.trim().isNotEmpty;
                    return FilledButton(
                      onPressed: enabled ? onSubmit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.tealAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white30,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Register & Check In'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Touch-friendly scroll-wheel picker
// ─────────────────────────────────────────────────────────────────────────────
class _WheelPicker extends StatefulWidget {
  const _WheelPicker({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> items;
  final int selectedIndex;
  final void Function(int) onChanged;

  @override
  State<_WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<_WheelPicker> {
  late FixedExtentScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = FixedExtentScrollController(initialItem: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(_WheelPicker old) {
    super.didUpdateWidget(old);
    // When the list shrinks (e.g. month changes and day is out of range),
    // clamp the controller to the new valid range.
    if (widget.selectedIndex != _ctrl.selectedItem && _ctrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ctrl.jumpToItem(
            widget.selectedIndex.clamp(0, widget.items.length - 1),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Selection highlight strip
          Center(
            child: IgnorePointer(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: Colors.tealAccent.withAlpha(100),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _ctrl,
            itemExtent: 44,
            diameterRatio: 1.8,
            squeeze: 1.0,
            perspective: 0.003,
            onSelectedItemChanged: widget.onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.items.length,
              builder: (context, index) {
                final isSelected = index == widget.selectedIndex;
                return Center(
                  child: Text(
                    widget.items[index],
                    style: TextStyle(
                      color: isSelected ? Colors.tealAccent : Colors.white54,
                      fontSize: isSelected ? 18 : 15,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
