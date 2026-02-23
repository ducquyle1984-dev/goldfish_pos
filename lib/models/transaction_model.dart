import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus { pending, completed, paid, voided }

enum DiscountType { fixed, percentage }

class Discount {
  final String id;
  final String description;
  final DiscountType type; // fixed amount or percentage
  final double amount;

  Discount({
    required this.id,
    required this.description,
    required this.type,
    required this.amount,
  });

  factory Discount.fromJson(Map<String, dynamic> json) {
    return Discount(
      id: json['id'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] == 'percentage'
          ? DiscountType.percentage
          : DiscountType.fixed,
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'type': type == DiscountType.percentage ? 'percentage' : 'fixed',
    'amount': amount,
  };
}

class TransactionItem {
  final String id;
  final String itemId;
  final String itemName;
  final String employeeId;
  final String employeeName;
  final double itemPrice;
  final int quantity;
  final double subtotal; // itemPrice * quantity

  TransactionItem({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.employeeId,
    required this.employeeName,
    required this.itemPrice,
    required this.quantity,
    required this.subtotal,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'] ?? '',
      itemId: json['itemId'] ?? '',
      itemName: json['itemName'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      itemPrice: (json['itemPrice'] ?? 0).toDouble(),
      quantity: json['quantity'] ?? 1,
      subtotal: (json['subtotal'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'itemName': itemName,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'itemPrice': itemPrice,
    'quantity': quantity,
    'subtotal': subtotal,
  };
}

class Payment {
  final String paymentMethodId;
  final String paymentMethodName;
  final double amountPaid;
  final DateTime paymentDate;

  Payment({
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.amountPaid,
    required this.paymentDate,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate() {
      final raw = json['paymentDate'];
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) {
        try {
          return DateTime.parse(raw);
        } catch (_) {}
      }
      return DateTime.now();
    }

    return Payment(
      paymentMethodId: json['paymentMethodId'] ?? '',
      paymentMethodName: json['paymentMethodName'] ?? '',
      amountPaid: (json['amountPaid'] ?? 0).toDouble(),
      paymentDate: parseDate(),
    );
  }

  Map<String, dynamic> toJson() => {
    'paymentMethodId': paymentMethodId,
    'paymentMethodName': paymentMethodName,
    'amountPaid': amountPaid,
    'paymentDate': Timestamp.fromDate(paymentDate),
  };
}

class Transaction {
  final String id;
  final int dailyNumber; // Sequential #1, #2... per day; 0 = unassigned
  final List<TransactionItem> items;
  final String? customerId; // Optional customer for reward points
  final String? customerName;
  final List<Discount> discounts; // Can have multiple discounts
  final List<Payment> payments; // Can have multiple payments
  final TransactionStatus status; // pending, completed, paid, voided
  final bool isVoided;
  final double subtotal; // Sum of all items
  final double totalDiscount; // Sum of all discounts
  final double taxAmount; // Can be calculated from subtotal
  final double totalAmount; // subtotal - discount + tax
  final DateTime createdAt;
  final DateTime updatedAt;

  Transaction({
    required this.id,
    this.dailyNumber = 0,
    required this.items,
    this.customerId,
    this.customerName,
    this.discounts = const [],
    this.payments = const [],
    this.status = TransactionStatus.pending,
    this.isVoided = false,
    required this.subtotal,
    this.totalDiscount = 0.0,
    this.taxAmount = 0.0,
    required this.totalAmount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() ?? {}) as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      dailyNumber: (data['dailyNumber'] ?? 0) as int,
      items:
          (data['items'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TransactionItem.fromJson)
              .toList() ??
          [],
      customerId: data['customerId'],
      customerName: data['customerName'],
      discounts:
          (data['discounts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Discount.fromJson)
              .toList() ??
          [],
      payments:
          (data['payments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Payment.fromJson)
              .toList() ??
          [],
      status: _parseTransactionStatus(data['status']),
      isVoided: data['isVoided'] ?? false,
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      totalDiscount: (data['totalDiscount'] ?? 0).toDouble(),
      taxAmount: (data['taxAmount'] ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] ?? '',
      dailyNumber: (json['dailyNumber'] ?? 0) as int,
      items:
          (json['items'] as List<dynamic>?)
              ?.map(
                (item) =>
                    TransactionItem.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          [],
      customerId: json['customerId'],
      customerName: json['customerName'],
      discounts:
          (json['discounts'] as List<dynamic>?)
              ?.map(
                (discount) =>
                    Discount.fromJson(discount as Map<String, dynamic>),
              )
              .toList() ??
          [],
      payments:
          (json['payments'] as List<dynamic>?)
              ?.map(
                (payment) => Payment.fromJson(payment as Map<String, dynamic>),
              )
              .toList() ??
          [],
      status: _parseTransactionStatus(json['status']),
      isVoided: json['isVoided'] ?? false,
      subtotal: (json['subtotal'] ?? 0).toDouble(),
      totalDiscount: (json['totalDiscount'] ?? 0).toDouble(),
      taxAmount: (json['taxAmount'] ?? 0).toDouble(),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
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

  static TransactionStatus _parseTransactionStatus(String? status) {
    switch (status) {
      case 'completed':
        return TransactionStatus.completed;
      case 'paid':
        return TransactionStatus.paid;
      case 'voided':
        return TransactionStatus.voided;
      default:
        return TransactionStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'dailyNumber': dailyNumber,
    'items': items.map((item) => item.toJson()).toList(),
    'customerId': customerId,
    'customerName': customerName,
    'discounts': discounts.map((discount) => discount.toJson()).toList(),
    'payments': payments.map((payment) => payment.toJson()).toList(),
    'status': _transactionStatusToString(status),
    'isVoided': isVoided,
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'taxAmount': taxAmount,
    'totalAmount': totalAmount,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toFirestore() => {
    'dailyNumber': dailyNumber,
    'items': items.map((item) => item.toJson()).toList(),
    'customerId': customerId,
    'customerName': customerName,
    'discounts': discounts.map((discount) => discount.toJson()).toList(),
    'payments': payments.map((payment) => payment.toJson()).toList(),
    'status': _transactionStatusToString(status),
    'isVoided': isVoided,
    'subtotal': subtotal,
    'totalDiscount': totalDiscount,
    'taxAmount': taxAmount,
    'totalAmount': totalAmount,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  static String _transactionStatusToString(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.pending:
        return 'pending';
      case TransactionStatus.completed:
        return 'completed';
      case TransactionStatus.paid:
        return 'paid';
      case TransactionStatus.voided:
        return 'voided';
    }
  }

  // Helper method to get total amount paid
  double get totalPaid =>
      payments.fold(0, (sum, payment) => sum + payment.amountPaid);

  // Helper method to get remaining balance
  double get balanceRemaining => totalAmount - totalPaid;

  // Helper method to check if transaction is fully paid
  bool get isFullyPaid => balanceRemaining <= 0;

  // Helper method to get all employees involved in this transaction
  List<String> get employeeIds =>
      items.map((item) => item.employeeId).toSet().toList();
}
