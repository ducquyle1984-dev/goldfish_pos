import 'package:cloud_firestore/cloud_firestore.dart';

/// Reward program configuration stored at settings/rewardProgram in Firestore.
class RewardSettings {
  /// How many dollars a customer must spend to earn 1 point. Default: $100.
  final double dollarsPerPoint;

  /// Whether the reward program is enabled at all.
  final bool enabled;

  /// Whether services count toward earning points.
  final bool earnOnServices;

  /// Whether products count toward earning points.
  final bool earnOnProducts;

  /// Whether gift card purchases count toward earning points.
  final bool earnOnGiftCardPurchases;

  const RewardSettings({
    this.dollarsPerPoint = 100.0,
    this.enabled = true,
    this.earnOnServices = true,
    this.earnOnProducts = true,
    this.earnOnGiftCardPurchases = false,
  });

  /// Points earned for a given spend amount.
  int pointsEarned(double amountSpent) {
    if (!enabled || dollarsPerPoint <= 0) return 0;
    return (amountSpent / dollarsPerPoint).floor();
  }

  factory RewardSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return RewardSettings(
      dollarsPerPoint: (data['dollarsPerPoint'] as num? ?? 100).toDouble(),
      enabled: data['enabled'] ?? true,
      earnOnServices: data['earnOnServices'] ?? true,
      earnOnProducts: data['earnOnProducts'] ?? true,
      earnOnGiftCardPurchases: data['earnOnGiftCardPurchases'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'dollarsPerPoint': dollarsPerPoint,
    'enabled': enabled,
    'earnOnServices': earnOnServices,
    'earnOnProducts': earnOnProducts,
    'earnOnGiftCardPurchases': earnOnGiftCardPurchases,
    'updatedAt': Timestamp.now(),
  };

  RewardSettings copyWith({
    double? dollarsPerPoint,
    bool? enabled,
    bool? earnOnServices,
    bool? earnOnProducts,
    bool? earnOnGiftCardPurchases,
  }) {
    return RewardSettings(
      dollarsPerPoint: dollarsPerPoint ?? this.dollarsPerPoint,
      enabled: enabled ?? this.enabled,
      earnOnServices: earnOnServices ?? this.earnOnServices,
      earnOnProducts: earnOnProducts ?? this.earnOnProducts,
      earnOnGiftCardPurchases:
          earnOnGiftCardPurchases ?? this.earnOnGiftCardPurchases,
    );
  }
}
