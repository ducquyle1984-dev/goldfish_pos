import 'package:cloud_firestore/cloud_firestore.dart';

/// Business / salon information displayed on receipts and in the booking portal.
/// Stored in Firestore at `settings/business`.
class BusinessSettings {
  /// Name of the salon shown at the top of every receipt.
  final String salonName;

  /// Street address of the salon (may be multi-line with \n).
  final String address;

  /// Public phone number shown on receipts.
  final String phone;

  /// Label for tax line on receipt, e.g. "Tax", "VAT", "GST".
  final String taxLabel;

  /// Default tax rate as a percentage (e.g. 8.5 = 8.5%).
  /// Stored here for reference; actual taxAmount is set per-transaction.
  final double taxRate;

  /// Whether this device is a touchscreen POS terminal.
  /// When true, PIN entry dialogs show an on-screen number pad.
  final bool touchscreenEnabled;

  const BusinessSettings({
    this.salonName = 'Goldfish Salon',
    this.address = '',
    this.phone = '',
    this.taxLabel = 'Tax',
    this.taxRate = 0.0,
    this.touchscreenEnabled = false,
  });

  factory BusinessSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BusinessSettings(
      salonName: data['salonName'] as String? ?? 'Goldfish Salon',
      address: data['address'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      taxLabel: data['taxLabel'] as String? ?? 'Tax',
      taxRate: (data['taxRate'] ?? 0).toDouble(),
      touchscreenEnabled: data['touchscreenEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'salonName': salonName,
    'address': address,
    'phone': phone,
    'taxLabel': taxLabel,
    'taxRate': taxRate,
    'touchscreenEnabled': touchscreenEnabled,
  };

  BusinessSettings copyWith({
    String? salonName,
    String? address,
    String? phone,
    String? taxLabel,
    double? taxRate,
    bool? touchscreenEnabled,
  }) => BusinessSettings(
    salonName: salonName ?? this.salonName,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    taxLabel: taxLabel ?? this.taxLabel,
    taxRate: taxRate ?? this.taxRate,
    touchscreenEnabled: touchscreenEnabled ?? this.touchscreenEnabled,
  );
}
