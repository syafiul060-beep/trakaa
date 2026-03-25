import 'package:cloud_functions/cloud_functions.dart';

/// Terbitkan token bukti online (Cloud Function) sebelum PDF struk.
class PublicReceiptProofService {
  PublicReceiptProofService._();

  static Future<({String verifyUrl, String token, bool reused})> issueProof(
    String orderId,
  ) async {
    final trimmed = orderId.trim();
    if (trimmed.isEmpty) {
      throw PublicReceiptProofException('orderId kosong.');
    }
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('issuePublicReceiptProof');
      final result = await callable.call<Map<String, dynamic>>({
        'orderId': trimmed,
      });
      final data = result.data;
      final verifyUrl = data['verifyUrl'] as String?;
      final token = data['token'] as String?;
      if (verifyUrl == null ||
          verifyUrl.isEmpty ||
          token == null ||
          token.isEmpty) {
        throw PublicReceiptProofException('Data bukti tidak lengkap.');
      }
      final reused = data['reused'] == true;
      return (verifyUrl: verifyUrl, token: token, reused: reused);
    } on FirebaseFunctionsException catch (e) {
      throw PublicReceiptProofException(e.message ?? e.code);
    }
  }
}

class PublicReceiptProofException implements Exception {
  PublicReceiptProofException(this.message);
  final String message;

  @override
  String toString() => message;
}
