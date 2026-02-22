import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Employee {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final double commissionPercentage; // Percentage for calculating commission
  final bool isActive;

  /// Tile color stored as an ARGB integer (e.g. 0xFF1565C0).
  /// Defaults to deep blue when not set.
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  Employee({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.commissionPercentage = 0.0,
    this.isActive = true,
    this.colorValue = 0xFF90CAF9,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the tile color as a Flutter [Color].
  Color get tileColor => Color(colorValue);

  factory Employee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Employee(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'],
      phone: data['phone'],
      address: data['address'],
      commissionPercentage: (data['commissionPercentage'] ?? 0).toDouble(),
      isActive: data['isActive'] ?? true,
      colorValue: (data['colorValue'] as int?) ?? 0xFF90CAF9,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      phone: json['phone'],
      address: json['address'],
      commissionPercentage: (json['commissionPercentage'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? true,
      colorValue: (json['colorValue'] as int?) ?? 0xFF90CAF9,
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
    'email': email,
    'phone': phone,
    'address': address,
    'commissionPercentage': commissionPercentage,
    'isActive': isActive,
    'colorValue': colorValue,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'email': email,
    'phone': phone,
    'address': address,
    'commissionPercentage': commissionPercentage,
    'isActive': isActive,
    'colorValue': colorValue,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
