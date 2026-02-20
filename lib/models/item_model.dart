import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemType { service, product }

class Item {
  final String id;
  final String name;
  final String? description;
  final String categoryId;
  final ItemType type; // service or product
  final double price;
  final bool isActive;
  final bool isCustomPrice;
  final int? durationMinutes; // Only for services
  final DateTime createdAt;
  final DateTime updatedAt;

  Item({
    required this.id,
    required this.name,
    this.description,
    required this.categoryId,
    required this.type,
    required this.price,
    this.isActive = true,
    this.isCustomPrice = false,
    this.durationMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Item.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Item(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      categoryId: data['categoryId'] ?? '',
      type: data['type'] == 'product' ? ItemType.product : ItemType.service,
      price: (data['price'] ?? 0).toDouble(),
      isActive: data['isActive'] ?? true,
      isCustomPrice: data['isCustomPrice'] ?? false,
      durationMinutes: data['durationMinutes'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      categoryId: json['categoryId'] ?? '',
      type: json['type'] == 'product' ? ItemType.product : ItemType.service,
      price: (json['price'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? true,
      isCustomPrice: json['isCustomPrice'] ?? false,
      durationMinutes: json['durationMinutes'],
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
    'description': description,
    'categoryId': categoryId,
    'type': type == ItemType.product ? 'product' : 'service',
    'price': price,
    'isActive': isActive,
    'isCustomPrice': isCustomPrice,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'description': description,
    'categoryId': categoryId,
    'type': type == ItemType.product ? 'product' : 'service',
    'price': price,
    'isActive': isActive,
    'isCustomPrice': isCustomPrice,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };
}
