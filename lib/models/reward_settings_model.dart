import 'package:cloud_firestore/cloud_firestore.dart';

/// Reward program configuration stored at settings/rewardProgram in Firestore.
class RewardSettings {
  /// How many dollars a customer must spend to earn 1 point. Default: $100.
  final double dollarsPerPoint;

  /// Whether the reward program is enabled at all.
  final bool enabled;

  const RewardSettings({this.dollarsPerPoint = 100.0, this.enabled = true});

  /// Points earned for a given spend amount.
  int pointsEarned(double amountSpent) {
    if (!enabled || dollarsPerPoint <= 0) return 0;
    return (amountSpent / dollarsPerPoint).floor();
  }

  factory RewardSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return RewardSettings(
      dollarsPerPoint: (data['dollarsPerPoint'] ?? 100).toDouble(),
      enabled: data['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'dollarsPerPoint': dollarsPerPoint,
    'enabled': enabled,
    'updatedAt': Timestamp.now(),
  };

  RewardSettings copyWith({double? dollarsPerPoint, bool? enabled}) {
    return RewardSettings(
      dollarsPerPoint: dollarsPerPoint ?? this.dollarsPerPoint,
      enabled: enabled ?? this.enabled,
    );
  }
}
