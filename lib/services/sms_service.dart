import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of an SMS send attempt.
enum SmsSendResult {
  success,
  invalidCredentials,
  invalidPhoneNumber,
  networkError,
  disabled,
  unknown,
}

/// Sends SMS messages via the Twilio REST API.
///
/// The [accountSid] and [authToken] match those in [SmsSettings].
class SmsService {
  final String accountSid;
  final String authToken;
  final String fromNumber;

  const SmsService({
    required this.accountSid,
    required this.authToken,
    required this.fromNumber,
  });

  /// Send [body] to [toNumber].
  /// [toNumber] should be in E.164 format, e.g. +15551234567.
  /// The method will attempt to normalise 10-digit US numbers automatically.
  Future<SmsSendResult> send({
    required String toNumber,
    required String body,
  }) async {
    final normalised = _normalise(toNumber);
    if (normalised == null) return SmsSendResult.invalidPhoneNumber;

    final url = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$accountSid:$authToken'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'To': normalised, 'From': fromNumber, 'Body': body},
      );

      if (response.statusCode == 201) return SmsSendResult.success;

      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final code = decoded?['code'] as int?;

      // Twilio error codes: 20003 = invalid credentials, 21211 = invalid To
      if (response.statusCode == 401 || code == 20003) {
        return SmsSendResult.invalidCredentials;
      }
      if (code == 21211 || code == 21614) {
        return SmsSendResult.invalidPhoneNumber;
      }
      return SmsSendResult.unknown;
    } catch (_) {
      return SmsSendResult.networkError;
    }
  }

  /// Attempt to coerce a raw phone string to E.164.
  /// Strips non-digit characters; prepends +1 for 10-digit US numbers.
  static String? _normalise(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('1') && digits.length == 11) return '+$digits';
    if (digits.length == 10) return '+1$digits';
    if (digits.length > 10) return '+$digits'; // assume country code present
    return null; // too short
  }

  /// Human-readable error message for a [SmsSendResult].
  static String resultMessage(SmsSendResult result) {
    switch (result) {
      case SmsSendResult.success:
        return 'SMS sent successfully.';
      case SmsSendResult.invalidCredentials:
        return 'SMS failed: invalid Twilio credentials. Check SMS settings.';
      case SmsSendResult.invalidPhoneNumber:
        return 'SMS failed: invalid phone number.';
      case SmsSendResult.networkError:
        return 'SMS failed: network error. Check internet connection.';
      case SmsSendResult.disabled:
        return 'SMS is disabled.';
      case SmsSendResult.unknown:
        return 'SMS failed: unknown error.';
    }
  }
}
