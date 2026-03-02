import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum AppointmentStatus {
  pendingConfirmation,
  confirmed,
  cancelled,
  completed,
  noShow,
}

enum AppointmentSource { staff, online }

class Appointment {
  final String id;
  final String customerName;
  final String customerPhone;
  final String serviceName;
  final DateTime scheduledAt;
  final int durationMinutes;
  final AppointmentStatus status;
  final AppointmentSource source;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Appointment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.serviceName,
    required this.scheduledAt,
    this.durationMinutes = 60,
    this.status = AppointmentStatus.confirmed,
    this.source = AppointmentSource.staff,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  DateTime get endsAt => scheduledAt.add(Duration(minutes: durationMinutes));

  /// Minutes until the appointment starts (negative if past).
  int get minutesUntil => scheduledAt.difference(DateTime.now()).inMinutes;

  /// Color-coded urgency for the appointment tile on the home screen.
  Color get urgencyColor {
    final mins = minutesUntil;
    if (status == AppointmentStatus.cancelled) return Colors.grey;
    if (status == AppointmentStatus.completed) return Colors.green.shade300;
    if (mins < 0) return Colors.grey.shade400; // past
    if (mins <= 15) return Colors.red.shade600; // arriving soon
    if (mins <= 30) return Colors.orange.shade600; // coming up
    if (mins <= 60) return Colors.amber.shade600; // within the hour
    return Colors.teal.shade600; // later in the day
  }

  Color get statusColor {
    return switch (status) {
      AppointmentStatus.pendingConfirmation => Colors.orange,
      AppointmentStatus.confirmed => Colors.teal,
      AppointmentStatus.cancelled => Colors.grey,
      AppointmentStatus.completed => Colors.green,
      AppointmentStatus.noShow => Colors.red,
    };
  }

  String get statusLabel {
    return switch (status) {
      AppointmentStatus.pendingConfirmation => 'Pending',
      AppointmentStatus.confirmed => 'Confirmed',
      AppointmentStatus.cancelled => 'Cancelled',
      AppointmentStatus.completed => 'Completed',
      AppointmentStatus.noShow => 'No Show',
    };
  }

  Appointment copyWith({
    String? id,
    String? customerName,
    String? customerPhone,
    String? serviceName,
    DateTime? scheduledAt,
    int? durationMinutes,
    AppointmentStatus? status,
    AppointmentSource? source,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Appointment(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      serviceName: serviceName ?? this.serviceName,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      status: status ?? this.status,
      source: source ?? this.source,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Appointment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Appointment(
      id: doc.id,
      customerName: d['customerName'] ?? '',
      customerPhone: d['customerPhone'] ?? '',
      serviceName: d['serviceName'] ?? '',
      scheduledAt: (d['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      durationMinutes: (d['durationMinutes'] ?? 60) as int,
      status: AppointmentStatus.values.firstWhere(
        (s) => s.name == d['status'],
        orElse: () => AppointmentStatus.confirmed,
      ),
      source: AppointmentSource.values.firstWhere(
        (s) => s.name == d['source'],
        orElse: () => AppointmentSource.staff,
      ),
      notes: d['notes'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'customerName': customerName,
      'customerPhone': customerPhone,
      'serviceName': serviceName,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'durationMinutes': durationMinutes,
      'status': status.name,
      'source': source.name,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
