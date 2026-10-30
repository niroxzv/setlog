import 'dart:convert';

import 'package:http/http.dart' as http;

// Talks to the NETS QR sandbox — the same OPENAPIPAAS endpoints covered in
// class, pointed at SetLog Premium instead of a registration fee.
//
// Three calls make up one transaction:
//   requestQR()    asks NETS for a QR image and a retrieval reference
//   webhookStream() streams live events (server-sent events) while the user pays
//   checkPayment() asks for the final outcome, used when the stream tells us
//                  the code was scanned and as a fallback when it times out
//
// This is a sandbox project, so the credentials below are test values and no
// real money moves. They are safe to keep in source; a production integration
// would hold the key server-side and never ship it in the app at all.
class NetsService {
  NetsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base =
      'https://sandbox.nets.openapipaas.com/api/v1/common/payments';
  // Sandbox credentials are passed at build time with --dart-define, never stored in source.
  static const String _apiKey =
      String.fromEnvironment('NETS_API_KEY', defaultValue: '');
  static const String _projectId =
      String.fromEnvironment('NETS_PROJECT_ID', defaultValue: '');
  static const String _txnId =
      'sandbox_nets|m|8ff8e5b6-d43e-4786-8ac5-7accf8c5bd9b';

  // NETS signals success with response code "00"; anything else is a failure.
  static const String successCode = '00';

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'api-key': _apiKey,
        'project-id': _projectId,
      };

  // Asks NETS to open a transaction for [amount] and hand back a QR to show.
  Future<NetsQrRequest> requestQr(double amount) async {
    final http.Response res = await _client
        .post(
          Uri.parse('$_base/nets-qr/request'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'txn_id': _txnId,
            'amt_in_dollars': amount,
            'notify_mobile': 0,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw NetsException('NETS returned ${res.statusCode} requesting a QR.');
    }

    final Map<String, dynamic>? data = _unwrap(res.body);
    final String? qr = data?['qr_code'] as String?;
    final String? ref = data?['txn_retrieval_ref'] as String?;

    // Returning an empty map here (as the lab version does) only defers the
    // crash to base64Decode(null), so the failure is raised where it happens.
    if (qr == null || ref == null) {
      throw NetsException('NETS did not return a QR code.');
    }

    return NetsQrRequest(qrImage: base64Decode(qr), txnRef: ref); //locally decode the base64 QR code into bytes for display
  }

  // Server-sent events for one transaction. Each chunk is raw SSE text; the
  // controller watches it for the "QR code scanned" event.
  Stream<String> webhookStream(String txnRef) async* {
    final http.Request req = http.Request(
      'GET',
      Uri.parse('$_base/nets/webhook?txn_retrieval_ref=$txnRef'),
    )..headers.addAll(<String, String>{
        'Accept': 'text/event-stream',
        'Connection': 'keep-alive',
        ..._headers,
      });

    final http.StreamedResponse res = await _client.send(req);
    if (res.statusCode != 200) return;

    yield* res.stream.transform(utf8.decoder);
  }

  // The authoritative outcome. Called once the stream reports a scan, and
  // again if the QR expires without one.
  Future<NetsPaymentResult> checkPayment(String txnRef) async {
    final http.Response res = await _client
        .post(
          Uri.parse('$_base/nets-qr/query'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'txn_retrieval_ref': txnRef,
            'frontend_timeout_status': 1,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw NetsException('NETS returned ${res.statusCode} checking payment.');
    }

    final Map<String, dynamic>? data = _unwrap(res.body);
    return NetsPaymentResult(
      responseCode: data?['response_code'] as String? ?? '99',
      message: data?['message'] as String?,
    );
  }

  // Both endpoints nest the payload under result -> data.
  Map<String, dynamic>? _unwrap(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final Object? result = decoded['result'];
    if (result is! Map<String, dynamic>) return null;
    return result['data'] as Map<String, dynamic>?;
  }
}

// A freshly opened transaction: the QR to display and the reference that
// identifies it for the rest of the flow.
class NetsQrRequest {
  const NetsQrRequest({required this.qrImage, required this.txnRef});

  final List<int> qrImage;
  final String txnRef;
}

class NetsPaymentResult {
  const NetsPaymentResult({required this.responseCode, this.message});

  final String responseCode;
  final String? message;

  bool get isPaid => responseCode == NetsService.successCode;
}

class NetsException implements Exception {
  const NetsException(this.message);
  final String message;

  @override
  String toString() => message;
}
