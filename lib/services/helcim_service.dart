import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// HELCIM ISV CONFIGURATION
// Replace these placeholder values with your actual credentials once you
// receive them from Helcim after completing the ISV onboarding process.
// See: https://devdocs.helcim.com/docs/isv-overview
// ─────────────────────────────────────────────────────────────────────────────

/// Your ISV (Independent Software Vendor) API token issued by Helcim.
/// This is used to authenticate on behalf of sub-merchants.
const String kHelcimIsvApiToken = 'YOUR_ISV_API_TOKEN';

/// Your ISV account GUID registered with Helcim.
const String kHelcimIsvAccountGuid = 'YOUR_ISV_ACCOUNT_GUID';

// ─────────────────────────────────────────────────────────────────────────────
// HELCIM API BASE URL
// Use 'https://api.helcimdev.com/v2' for sandbox testing.
// Switch to 'https://api.helcim.com/v2' for production.
// ─────────────────────────────────────────────────────────────────────────────
const String kHelcimBaseUrl = 'https://api.helcimdev.com/v2'; // sandbox
// const String kHelcimBaseUrl = 'https://api.helcim.com/v2'; // production

/// Result returned from any Helcim payment operation.
class HelcimPaymentResult {
  final bool success;
  final String? transactionId;
  final String? approvalCode;
  final String? cardToken;
  final double? amount;
  final String? currency;
  final String? cardType;
  final String? lastFour;
  final String? responseMessage;
  final String? errorMessage;
  final Map<String, dynamic>? raw;

  const HelcimPaymentResult({
    required this.success,
    this.transactionId,
    this.approvalCode,
    this.cardToken,
    this.amount,
    this.currency,
    this.cardType,
    this.lastFour,
    this.responseMessage,
    this.errorMessage,
    this.raw,
  });

  @override
  String toString() => success
      ? 'HelcimPaymentResult(success, txId=$transactionId, approval=$approvalCode)'
      : 'HelcimPaymentResult(failed: $errorMessage)';
}

/// Result returned when initializing a HelcimPay hosted checkout session.
class HelcimPaySessionResult {
  final bool success;
  final String? checkoutToken;
  final String? secretToken;
  final String? errorMessage;

  const HelcimPaySessionResult({
    required this.success,
    this.checkoutToken,
    this.secretToken,
    this.errorMessage,
  });
}

/// Service for integrating with the Helcim Payment API.
///
/// Usage (per-merchant / ISV sub-merchant model):
///   final helcim = HelcimService(
///     apiToken: paymentMethod.processorApiKey,         // merchant API token
///     accountGuid: paymentMethod.additionalConfig?['accountGuid'] ?? '',
///     terminalId: paymentMethod.additionalConfig?['terminalId'],
///   );
///
/// For ISV processing on behalf of a sub-merchant, set [accountGuid] to
/// the sub-merchant's account GUID. Helcim routes the funds accordingly.
///
/// API Docs: https://devdocs.helcim.com/reference
class HelcimService {
  /// The API token for this merchant account. Obtained from the Helcim
  /// dashboard (Settings → API Access) or provisioned via the ISV API.
  final String apiToken;

  /// The account GUID for the merchant. Required for ISV sub-merchant routing.
  final String accountGuid;

  /// Optional terminal / card-reader ID associated with this merchant account.
  final String? terminalId;

  /// Optional ISV API token. If provided, the ISV token is used for platform-
  /// level calls (e.g. provisioning sub-merchants). Defaults to [kHelcimIsvApiToken].
  final String? isvApiToken;

  HelcimService({
    required this.apiToken,
    required this.accountGuid,
    this.terminalId,
    this.isvApiToken,
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'api-token': apiToken,
    'account-guid': accountGuid,
  };

  Uri _uri(String path) => Uri.parse('$kHelcimBaseUrl$path');

  /// Parses a Helcim API response body into a [HelcimPaymentResult].
  HelcimPaymentResult _parsePaymentResponse(
    http.Response response, {
    required double amount,
  }) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;

    if (!isSuccess) {
      final errors = body['errors'] as List<dynamic>?;
      final message = errors?.isNotEmpty == true
          ? errors!.first.toString()
          : body['message']?.toString() ?? 'Unknown Helcim error';
      return HelcimPaymentResult(
        success: false,
        errorMessage: message,
        raw: body,
      );
    }

    final txData = (body['data'] as Map<String, dynamic>?) ?? body;
    return HelcimPaymentResult(
      success: true,
      transactionId:
          txData['transactionId']?.toString() ?? txData['id']?.toString(),
      approvalCode: txData['approvalCode']?.toString(),
      cardToken: txData['cardToken']?.toString(),
      amount: (txData['amount'] as num?)?.toDouble() ?? amount,
      currency: txData['currency']?.toString() ?? 'CAD',
      cardType: txData['cardType']?.toString(),
      lastFour: txData['lastFour']?.toString() ?? txData['last4']?.toString(),
      responseMessage: txData['responseMessage']?.toString(),
      raw: body,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HELCIM PAY (HOSTED CHECKOUT)
  // Use this to generate a secure, tokenized checkout session URL / token
  // that can be displayed in a WebView or redirected to in a browser.
  // See: https://devdocs.helcim.com/docs/helcim-pay-overview
  // ───────────────────────────────────────────────────────────────────────────

  /// Initializes a HelcimPay hosted checkout session.
  ///
  /// [amountInCents] — e.g. 1999 for \$19.99 CAD
  /// [currency]      — ISO 4217 currency code (default: 'CAD')
  /// [invoiceNumber] — Optional merchant invoice / order number
  /// [customerCode]  — Optional Helcim customer code
  ///
  /// Returns a [HelcimPaySessionResult] containing the [checkoutToken] that
  /// you embed with HelcimPay.js, or open directly in a WebView.
  Future<HelcimPaySessionResult> initializeHelcimPaySession({
    required int amountInCents,
    String currency = 'CAD',
    String? invoiceNumber,
    String? customerCode,
    bool hasConvenienceFee = false,
  }) async {
    final payload = {
      'paymentType': 'purchase',
      'amount': amountInCents,
      'currency': currency,
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      if (customerCode != null) 'customerCode': customerCode,
      if (hasConvenienceFee) 'hasConvenienceFee': true,
    };

    try {
      final response = await http.post(
        _uri('/helcim-pay/initialize'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return HelcimPaySessionResult(
          success: true,
          checkoutToken: body['checkoutToken']?.toString(),
          secretToken: body['secretToken']?.toString(),
        );
      } else {
        return HelcimPaySessionResult(
          success: false,
          errorMessage:
              body['errors']?.toString() ?? body['message']?.toString(),
        );
      }
    } catch (e) {
      return HelcimPaySessionResult(success: false, errorMessage: e.toString());
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CARD-NOT-PRESENT (Direct API)
  // IMPORTANT: Passing raw card numbers directly requires PCI-DSS SAQ D
  // compliance. Prefer HelcimPay.js tokenization or a certified terminal.
  // ───────────────────────────────────────────────────────────────────────────

  /// Process a card purchase (card-not-present, using a saved card token).
  ///
  /// [cardToken]      — Tokenized card from a previous HelcimPay session.
  /// [amount]         — Charge amount in dollars (e.g. 19.99).
  /// [currency]       — ISO 4217 (default: 'CAD').
  /// [invoiceNumber]  — Optional invoice reference for your records.
  /// [customerCode]   — Optional Helcim customer code.
  /// [ipAddress]      — Customer IP address (recommended for fraud prevention).
  Future<HelcimPaymentResult> purchaseWithToken({
    required String cardToken,
    required double amount,
    String currency = 'CAD',
    String? invoiceNumber,
    String? customerCode,
    String? ipAddress,
  }) async {
    final payload = {
      'cardToken': cardToken,
      'amount': amount,
      'currency': currency,
      if (terminalId != null) 'terminalId': terminalId,
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      if (customerCode != null) 'customerCode': customerCode,
      if (ipAddress != null) 'ipAddress': ipAddress,
    };

    try {
      final response = await http.post(
        _uri('/payment/purchase'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      return _parsePaymentResponse(response, amount: amount);
    } catch (e) {
      return HelcimPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // REFUND
  // ───────────────────────────────────────────────────────────────────────────

  /// Refund a previously captured transaction.
  ///
  /// [originalTransactionId] — The Helcim transaction ID to refund.
  /// [amount]                — Amount to refund (can be partial).
  /// [currency]              — ISO 4217 (default: 'CAD').
  Future<HelcimPaymentResult> refund({
    required String originalTransactionId,
    required double amount,
    String currency = 'CAD',
  }) async {
    final payload = {
      'originalTransactionId': originalTransactionId,
      'amount': amount,
      'currency': currency,
    };

    try {
      final response = await http.post(
        _uri('/payment/refund'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      return _parsePaymentResponse(response, amount: amount);
    } catch (e) {
      return HelcimPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // VOID
  // ───────────────────────────────────────────────────────────────────────────

  /// Void a transaction that has not yet been settled/batched.
  ///
  /// [transactionId] — The Helcim transaction ID to void.
  /// [amount]        — The original transaction amount.
  Future<HelcimPaymentResult> voidTransaction({
    required String transactionId,
    required double amount,
  }) async {
    final payload = {'transactionId': transactionId, 'amount': amount};

    try {
      final response = await http.post(
        _uri('/payment/void'),
        headers: _headers,
        body: jsonEncode(payload),
      );
      return _parsePaymentResponse(response, amount: amount);
    } catch (e) {
      return HelcimPaymentResult(success: false, errorMessage: e.toString());
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // GET TRANSACTION
  // ───────────────────────────────────────────────────────────────────────────

  /// Look up a previously processed transaction by its Helcim transaction ID.
  Future<Map<String, dynamic>?> getTransaction(String transactionId) async {
    try {
      final response = await http.get(
        _uri('/payment/$transactionId'),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ISV — SUB-MERCHANT PROVISIONING
  // These calls use the ISV-level API token (kHelcimIsvApiToken) rather than
  // a per-merchant token. Implement once you have ISV credentials from Helcim.
  // See: https://devdocs.helcim.com/docs/isv-sub-merchant-provisioning
  // ───────────────────────────────────────────────────────────────────────────

  /// Creates (onboards) a new sub-merchant under your ISV account.
  ///
  /// [businessName]  — Legal business name of the sub-merchant.
  /// [contactEmail]  — Primary contact email.
  /// [contactPhone]  — Primary contact phone.
  /// Additional KYB (Know Your Business) fields may be required by Helcim.
  /// Returns the provisioned account GUID if successful.
  Future<String?> provisionSubMerchant({
    required String businessName,
    required String contactEmail,
    required String contactPhone,
    Map<String, dynamic>? additionalFields,
  }) async {
    // TODO: Replace kHelcimIsvApiToken with actual ISV credentials.
    final headers = {
      'Content-Type': 'application/json',
      'api-token': isvApiToken ?? kHelcimIsvApiToken,
      'account-guid': kHelcimIsvAccountGuid,
    };

    final payload = {
      'businessName': businessName,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
      ...?additionalFields,
    };

    try {
      final response = await http.post(
        _uri('/accounts'), // endpoint may vary — confirm with Helcim ISV docs
        headers: headers,
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['accountGuid']?.toString() ?? body['id']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
