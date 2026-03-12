import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single salon that has been onboarded as a paying client.
/// Stored in your master Firebase under `clients/{id}`.
class ClientRecord {
  final String? id;

  // ── Business Info ──────────────────────────────────────────────────────────
  final String salonName;
  final String ownerName;
  final String ownerEmail;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String zip;

  // ── Technical Config ───────────────────────────────────────────────────────
  /// The URL-safe slug, e.g. "city-nails". Used for subdomain + project ID.
  final String slug;

  /// Firebase project ID, e.g. "gnp-city-nails". Max 30 chars.
  final String firebaseProjectId;

  /// Base domain, e.g. "goldfishpos.com".
  final String baseDomain;

  // ── Credentials (stored for your reference — remind client to change) ──────
  final String adminEmail;

  /// Plaintext temp password. In production consider encrypting or removing
  /// this after the client logs in for the first time.
  final String tempPassword;

  // ── Plan & Metadata ────────────────────────────────────────────────────────
  final String plan;
  final String notes;
  final DateTime onboardedAt;

  /// 'pending' → script not yet run, 'active' → live, 'suspended' → paused.
  final String status;

  ClientRecord({
    this.id,
    required this.salonName,
    required this.ownerName,
    required this.ownerEmail,
    required this.phone,
    this.address = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    required this.slug,
    required this.firebaseProjectId,
    this.baseDomain = 'goldfishpos.com',
    required this.adminEmail,
    required this.tempPassword,
    this.plan = 'Starter',
    this.notes = '',
    required this.onboardedAt,
    this.status = 'pending',
  });

  String get fullUrl => 'https://$slug.$baseDomain';
  String get fallbackUrl => 'https://$firebaseProjectId.web.app';

  Map<String, dynamic> toFirestore() => {
    'salonName': salonName,
    'ownerName': ownerName,
    'ownerEmail': ownerEmail,
    'phone': phone,
    'address': address,
    'city': city,
    'state': state,
    'zip': zip,
    'slug': slug,
    'firebaseProjectId': firebaseProjectId,
    'baseDomain': baseDomain,
    'adminEmail': adminEmail,
    'tempPassword': tempPassword,
    'plan': plan,
    'notes': notes,
    'onboardedAt': Timestamp.fromDate(onboardedAt),
    'status': status,
  };

  ClientRecord copyWith({String? status, String? notes}) => ClientRecord(
    id: id,
    salonName: salonName,
    ownerName: ownerName,
    ownerEmail: ownerEmail,
    phone: phone,
    address: address,
    city: city,
    state: state,
    zip: zip,
    slug: slug,
    firebaseProjectId: firebaseProjectId,
    baseDomain: baseDomain,
    adminEmail: adminEmail,
    tempPassword: tempPassword,
    plan: plan,
    notes: notes ?? this.notes,
    onboardedAt: onboardedAt,
    status: status ?? this.status,
  );

  factory ClientRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ClientRecord(
      id: doc.id,
      salonName: d['salonName'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? '',
      ownerEmail: d['ownerEmail'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      address: d['address'] as String? ?? '',
      city: d['city'] as String? ?? '',
      state: d['state'] as String? ?? '',
      zip: d['zip'] as String? ?? '',
      slug: d['slug'] as String? ?? '',
      firebaseProjectId: d['firebaseProjectId'] as String? ?? '',
      baseDomain: d['baseDomain'] as String? ?? 'goldfishpos.com',
      adminEmail: d['adminEmail'] as String? ?? '',
      tempPassword: d['tempPassword'] as String? ?? '',
      plan: d['plan'] as String? ?? 'Starter',
      notes: d['notes'] as String? ?? '',
      onboardedAt: (d['onboardedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: d['status'] as String? ?? 'pending',
    );
  }
}
