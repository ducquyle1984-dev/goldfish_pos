import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentProcessorType { stripe, square, paypal, helcim, custom }

class PaymentMethod {
  final String id;
  final String merchantName; // Name of the merchant account
  final PaymentProcessorType processorType; // Type of payment processor
  final String processorApiKey; // API key (should be encrypted in production)
  final String?
  processorSecretKey; // Secret key (should be encrypted in production)
  final double? transactionCommission; // Commission % for each transaction
  final String? webhookUrl; // Webhook URL for payment notifications
  final Map<String, dynamic>? additionalConfig; // Any additional configuration
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentMethod({
    required this.id,
    required this.merchantName,
    required this.processorType,
    required this.processorApiKey,
    this.processorSecretKey,
    this.transactionCommission = 0.0,
    this.webhookUrl,
    this.additionalConfig,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentMethod.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentMethod(
      id: doc.id,
      merchantName: data['merchantName'] ?? '',
      processorType: _parseProcessorType(data['processorType']),
      processorApiKey: data['processorApiKey'] ?? '',
      processorSecretKey: data['processorSecretKey'],
      transactionCommission: (data['transactionCommission'] ?? 0).toDouble(),
      webhookUrl: data['webhookUrl'],
      additionalConfig: data['additionalConfig'] as Map<String, dynamic>?,
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] ?? '',
      merchantName: json['merchantName'] ?? '',
      processorType: _parseProcessorType(json['processorType']),
      processorApiKey: json['processorApiKey'] ?? '',
      processorSecretKey: json['processorSecretKey'],
      transactionCommission: (json['transactionCommission'] ?? 0).toDouble(),
      webhookUrl: json['webhookUrl'],
      additionalConfig: json['additionalConfig'] as Map<String, dynamic>?,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(
              json['createdAt'] as String? ?? DateTime.now().toString(),
            ),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : DateTime.parse(
              json['updatedAt'] as String? ?? DateTime.now().toString(),
            ),
    );
  }

  static PaymentProcessorType _parseProcessorType(String? type) {
    switch (type) {
      case 'stripe':
        return PaymentProcessorType.stripe;
      case 'square':
        return PaymentProcessorType.square;
      case 'paypal':
        return PaymentProcessorType.paypal;
      case 'helcim':
        return PaymentProcessorType.helcim;
      default:
        return PaymentProcessorType.custom;
    }
  }

  static String _processorTypeToString(PaymentProcessorType type) {
    switch (type) {
      case PaymentProcessorType.stripe:
        return 'stripe';
      case PaymentProcessorType.square:
        return 'square';
      case PaymentProcessorType.paypal:
        return 'paypal';
      case PaymentProcessorType.helcim:
        return 'helcim';
      case PaymentProcessorType.custom:
        return 'custom';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'merchantName': merchantName,
    'processorType': _processorTypeToString(processorType),
    'processorApiKey': processorApiKey,
    'processorSecretKey': processorSecretKey,
    'transactionCommission': transactionCommission,
    'webhookUrl': webhookUrl,
    'additionalConfig': additionalConfig,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toFirestore() => {
    'merchantName': merchantName,
    'processorType': _processorTypeToString(processorType),
    'processorApiKey': processorApiKey,
    'processorSecretKey': processorSecretKey,
    'transactionCommission': transactionCommission,
    'webhookUrl': webhookUrl,
    'additionalConfig': additionalConfig,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
