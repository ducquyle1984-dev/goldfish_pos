import 'package:cloud_firestore/cloud_firestore.dart';

/// Day-of-week constants matching Dart's DateTime.weekday (1=Mon … 7=Sun).
class Weekday {
  static const monday = 1;
  static const tuesday = 2;
  static const wednesday = 3;
  static const thursday = 4;
  static const friday = 5;
  static const saturday = 6;
  static const sunday = 7;

  static String name(int day) => const {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  }[day]!;

  static String shortName(int day) => const {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  }[day]!;
}

/// Per-day open/close times, stored as "HH:mm" strings.
class DayHours {
  final String open; // e.g. "09:00"
  final String close; // e.g. "18:00"

  const DayHours({required this.open, required this.close});

  factory DayHours.fromMap(Map<String, dynamic> m) =>
      DayHours(open: m['open'] ?? '09:00', close: m['close'] ?? '18:00');

  Map<String, dynamic> toMap() => {'open': open, 'close': close};

  /// Parses "HH:mm" into a today-based [DateTime].
  DateTime toDateTime(DateTime date) {
    final parts = open.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  DateTime closeDateTime(DateTime date) {
    final parts = close.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }
}

class BookingSettings {
  /// Weekdays on which online booking is allowed (Dart weekday 1–7).
  final List<int> enabledWeekdays;

  /// Dates that are blocked from any booking (normalized to midnight).
  final List<DateTime> blackoutDates;

  /// Whether the customer-facing online booking portal is active.
  final bool onlineBookingEnabled;

  /// How many calendar days in advance a customer may book online.
  final int bookingWindowDays;

  /// Minimum advance notice (hours) required for online bookings.
  final int minAdvanceHours;

  /// Default time-slot increment in minutes (e.g. 30 or 60).
  final int slotDurationMinutes;

  /// Business hours per weekday.  Key = Dart weekday (1–7).
  final Map<int, DayHours> businessHours;

  /// Services the customer can choose from when booking online.
  final List<String> onlineServices;

  const BookingSettings({
    required this.enabledWeekdays,
    required this.blackoutDates,
    this.onlineBookingEnabled = true,
    this.bookingWindowDays = 30,
    this.minAdvanceHours = 1,
    this.slotDurationMinutes = 60,
    required this.businessHours,
    required this.onlineServices,
  });

  static BookingSettings get defaults {
    const defaultHours = DayHours(open: '09:00', close: '18:00');
    return BookingSettings(
      enabledWeekdays: [1, 2, 3, 4, 5, 6], // Mon–Sat
      blackoutDates: [],
      onlineBookingEnabled: true,
      bookingWindowDays: 30,
      minAdvanceHours: 2,
      slotDurationMinutes: 60,
      businessHours: {
        1: defaultHours,
        2: defaultHours,
        3: defaultHours,
        4: defaultHours,
        5: defaultHours,
        6: defaultHours,
        7: const DayHours(open: '10:00', close: '16:00'),
      },
      onlineServices: ['Manicure', 'Pedicure', 'Gel Nails', 'Dip Powder'],
    );
  }

  bool isDateAvailable(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (!enabledWeekdays.contains(date.weekday)) return false;
    if (blackoutDates.any(
      (b) => b.year == d.year && b.month == d.month && b.day == d.day,
    )) {
      return false;
    }
    return true;
  }

  factory BookingSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BookingSettings(
      enabledWeekdays:
          (data['enabledWeekdays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [1, 2, 3, 4, 5, 6],
      blackoutDates:
          (data['blackoutDates'] as List<dynamic>?)
              ?.map((e) => (e as Timestamp).toDate())
              .map((dt) => DateTime(dt.year, dt.month, dt.day))
              .toList() ??
          [],
      onlineBookingEnabled: data['onlineBookingEnabled'] ?? true,
      bookingWindowDays: (data['bookingWindowDays'] as num? ?? 30).toInt(),
      minAdvanceHours: (data['minAdvanceHours'] as num? ?? 2).toInt(),
      slotDurationMinutes: (data['slotDurationMinutes'] as num? ?? 60).toInt(),
      businessHours:
          (data['businessHours'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(
              int.parse(k),
              DayHours.fromMap(v as Map<String, dynamic>),
            ),
          ) ??
          {},
      onlineServices:
          (data['onlineServices'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabledWeekdays': enabledWeekdays,
      'blackoutDates': blackoutDates.map((d) => Timestamp.fromDate(d)).toList(),
      'onlineBookingEnabled': onlineBookingEnabled,
      'bookingWindowDays': bookingWindowDays,
      'minAdvanceHours': minAdvanceHours,
      'slotDurationMinutes': slotDurationMinutes,
      'businessHours': businessHours.map(
        (k, v) => MapEntry(k.toString(), v.toMap()),
      ),
      'onlineServices': onlineServices,
    };
  }

  BookingSettings copyWith({
    List<int>? enabledWeekdays,
    List<DateTime>? blackoutDates,
    bool? onlineBookingEnabled,
    int? bookingWindowDays,
    int? minAdvanceHours,
    int? slotDurationMinutes,
    Map<int, DayHours>? businessHours,
    List<String>? onlineServices,
  }) {
    return BookingSettings(
      enabledWeekdays: enabledWeekdays ?? this.enabledWeekdays,
      blackoutDates: blackoutDates ?? this.blackoutDates,
      onlineBookingEnabled: onlineBookingEnabled ?? this.onlineBookingEnabled,
      bookingWindowDays: bookingWindowDays ?? this.bookingWindowDays,
      minAdvanceHours: minAdvanceHours ?? this.minAdvanceHours,
      slotDurationMinutes: slotDurationMinutes ?? this.slotDurationMinutes,
      businessHours: businessHours ?? this.businessHours,
      onlineServices: onlineServices ?? this.onlineServices,
    );
  }
}
