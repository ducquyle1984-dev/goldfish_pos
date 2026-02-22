import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String phone; // Required
  final int birthMonth; // 1–12, required (for birthday promotions)
  final int birthDay; // 1–31, required (for birthday promotions)
  final String? email;
  final String? address;
  final double rewardPoints; // Accumulated reward points
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.birthMonth,
    required this.birthDay,
    this.email,
    this.address,
    this.rewardPoints = 0.0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Display-friendly birthday string, e.g. "Mar 15".
  String get birthDateDisplay {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = (birthMonth >= 1 && birthMonth <= 12)
        ? months[birthMonth - 1]
        : '??';
    return '$m $birthDay';
  }

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Customer(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      birthMonth: (data['birthMonth'] ?? 1) as int,
      birthDay: (data['birthDay'] ?? 1) as int,
      email: data['email'],
      address: data['address'],
      rewardPoints: (data['rewardPoints'] ?? 0).toDouble(),
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      birthMonth: (json['birthMonth'] ?? 1) as int,
      birthDay: (json['birthDay'] ?? 1) as int,
      email: json['email'],
      address: json['address'],
      rewardPoints: (json['rewardPoints'] ?? 0).toDouble(),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'birthMonth': birthMonth,
    'birthDay': birthDay,
    'email': email,
    'address': address,
    'rewardPoints': rewardPoints,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'phone': phone,
    'birthMonth': birthMonth,
    'birthDay': birthDay,
    'email': email,
    'address': address,
    'rewardPoints': rewardPoints,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Customer copyWith({
    String? name,
    String? phone,
    int? birthMonth,
    int? birthDay,
    String? email,
    String? address,
    double? rewardPoints,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      birthMonth: birthMonth ?? this.birthMonth,
      birthDay: birthDay ?? this.birthDay,
      email: email ?? this.email,
      address: address ?? this.address,
      rewardPoints: rewardPoints ?? this.rewardPoints,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
