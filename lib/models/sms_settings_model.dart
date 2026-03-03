import 'package:cloud_firestore/cloud_firestore.dart';

/// Contains all Twilio + SMS configuration stored in Firestore.
class SmsSettings {
  /// Whether the SMS feature is enabled at all.
  final bool enabled;

  /// Twilio Account SID.
  final String accountSid;

  /// Twilio Auth Token.
  final String authToken;

  /// The Twilio "From" number in E.164 format, e.g. +15551234567.
  final String fromNumber;

  /// Template for the thank-you SMS sent after a positive survey response.
  /// Supported placeholders:
  ///   {name}       – customer's name
  ///   {reviewLink} – Google Review URL (omitted when blank)
  final String positiveTemplate;

  /// Template for the thank-you SMS sent after a negative survey response.
  /// Supported placeholders:
  ///   {name} – customer's name
  final String negativeTemplate;

  /// Google Review page URL included in the positive-response SMS.
  /// Leave blank to omit.
  final String googleReviewUrl;

  const SmsSettings({
    this.enabled = false,
    this.accountSid = '',
    this.authToken = '',
    this.fromNumber = '',
    this.positiveTemplate =
        'Hi {name}, thank you for visiting us today! 😊 We\'d love to hear your feedback — please leave us a Google review: {reviewLink}',
    this.negativeTemplate =
        'Hi {name}, thank you for visiting us today. We\'re sorry your experience wasn\'t perfect — your feedback helps us improve.',
    this.googleReviewUrl = '',
  });

  factory SmsSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SmsSettings(
      enabled: data['enabled'] as bool? ?? false,
      accountSid: data['accountSid'] as String? ?? '',
      authToken: data['authToken'] as String? ?? '',
      fromNumber: data['fromNumber'] as String? ?? '',
      positiveTemplate:
          data['positiveTemplate'] as String? ??
          'Hi {name}, thank you for visiting us today! 😊 We\'d love to hear your feedback — please leave us a Google review: {reviewLink}',
      negativeTemplate:
          data['negativeTemplate'] as String? ??
          'Hi {name}, thank you for visiting us today. We\'re sorry your experience wasn\'t perfect — your feedback helps us improve.',
      googleReviewUrl: data['googleReviewUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'enabled': enabled,
    'accountSid': accountSid,
    'authToken': authToken,
    'fromNumber': fromNumber,
    'positiveTemplate': positiveTemplate,
    'negativeTemplate': negativeTemplate,
    'googleReviewUrl': googleReviewUrl,
  };

  /// Resolve the positive message for a given customer name.
  String buildPositiveMessage(String customerName) {
    return positiveTemplate
        .replaceAll('{name}', customerName)
        .replaceAll('{reviewLink}', googleReviewUrl);
  }

  /// Resolve the negative message for a given customer name.
  String buildNegativeMessage(String customerName) {
    return negativeTemplate.replaceAll('{name}', customerName);
  }

  SmsSettings copyWith({
    bool? enabled,
    String? accountSid,
    String? authToken,
    String? fromNumber,
    String? positiveTemplate,
    String? negativeTemplate,
    String? googleReviewUrl,
  }) {
    return SmsSettings(
      enabled: enabled ?? this.enabled,
      accountSid: accountSid ?? this.accountSid,
      authToken: authToken ?? this.authToken,
      fromNumber: fromNumber ?? this.fromNumber,
      positiveTemplate: positiveTemplate ?? this.positiveTemplate,
      negativeTemplate: negativeTemplate ?? this.negativeTemplate,
      googleReviewUrl: googleReviewUrl ?? this.googleReviewUrl,
    );
  }
}
