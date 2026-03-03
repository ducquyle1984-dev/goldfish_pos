import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a piece of negative feedback collected after checkout.
class CustomerFeedback {
  final String id;

  /// Firestore ID of the transaction that triggered the feedback.
  final String transactionId;

  /// Firestore ID of the customer (null for walk-in customers).
  final String? customerId;

  /// Display name of the customer at the time of the transaction.
  final String customerName;

  /// The phone number used for the outgoing SMS (or empty if not sent).
  final String customerPhone;

  /// Free-form feedback text entered by the customer or staff.
  final String feedbackText;

  /// Whether an SMS was successfully sent to the customer.
  final bool smsSent;

  final DateTime createdAt;

  CustomerFeedback({
    required this.id,
    required this.transactionId,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.feedbackText,
    required this.smsSent,
    required this.createdAt,
  });

  factory CustomerFeedback.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CustomerFeedback(
      id: doc.id,
      transactionId: data['transactionId'] as String? ?? '',
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String? ?? '',
      customerPhone: data['customerPhone'] as String? ?? '',
      feedbackText: data['feedbackText'] as String? ?? '',
      smsSent: data['smsSent'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'transactionId': transactionId,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'feedbackText': feedbackText,
    'smsSent': smsSent,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
