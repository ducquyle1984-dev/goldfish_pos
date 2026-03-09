import 'package:cloud_firestore/cloud_firestore.dart';

enum GiftCardEntryType { issued, reloaded, redeemed }

/// A single ledger entry that records a change to a gift card's balance.
class GiftCardEntry {
  final GiftCardEntryType type;
  final double amount; // positive for issued/reloaded, negative for redeemed
  final DateTime date;
  final String? transactionId; // linked POS transaction ID (if any)
  final String? note;

  const GiftCardEntry({
    required this.type,
    required this.amount,
    required this.date,
    this.transactionId,
    this.note,
  });

  factory GiftCardEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate() {
      final raw = json['date'];
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    return GiftCardEntry(
      type: _parseType(json['type']),
      amount: (json['amount'] ?? 0).toDouble(),
      date: parseDate(),
      transactionId: json['transactionId'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'amount': amount,
    'date': Timestamp.fromDate(date),
    if (transactionId != null) 'transactionId': transactionId,
    if (note != null) 'note': note,
  };

  static GiftCardEntryType _parseType(dynamic value) {
    switch (value?.toString()) {
      case 'reloaded':
        return GiftCardEntryType.reloaded;
      case 'redeemed':
        return GiftCardEntryType.redeemed;
      default:
        return GiftCardEntryType.issued;
    }
  }
}

/// A physical or virtual gift card tracked in Firestore.
class GiftCard {
  final String id; // Firestore document ID
  final String cardId; // Physical card label (e.g., "GC-001234")
  final double balance; // Current remaining balance
  final double loadedAmount; // Amount loaded at most recent issue/reload
  final DateTime issuedAt;
  final DateTime? expiresAt; // null means no expiration
  final bool isActive;
  final String? notes;
  final List<GiftCardEntry> history;
  final DateTime updatedAt;

  const GiftCard({
    required this.id,
    required this.cardId,
    required this.balance,
    required this.loadedAmount,
    required this.issuedAt,
    this.expiresAt,
    this.isActive = true,
    this.notes,
    this.history = const [],
    required this.updatedAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isUsable => isActive && !isExpired && balance > 0;

  factory GiftCard.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime parseTs(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
      return DateTime.now();
    }

    return GiftCard(
      id: doc.id,
      cardId: data['cardId'] as String? ?? '',
      balance: (data['balance'] ?? 0).toDouble(),
      loadedAmount: (data['loadedAmount'] ?? 0).toDouble(),
      issuedAt: parseTs(data['issuedAt']),
      expiresAt: data['expiresAt'] != null ? parseTs(data['expiresAt']) : null,
      isActive: data['isActive'] as bool? ?? true,
      notes: data['notes'] as String?,
      history: (data['history'] as List<dynamic>? ?? [])
          .map((e) => GiftCardEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt: parseTs(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'cardId': cardId,
    'balance': balance,
    'loadedAmount': loadedAmount,
    'issuedAt': Timestamp.fromDate(issuedAt),
    'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'isActive': isActive,
    if (notes != null) 'notes': notes,
    'history': history.map((e) => e.toJson()).toList(),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
