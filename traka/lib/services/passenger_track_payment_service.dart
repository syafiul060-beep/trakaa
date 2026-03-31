import 'package:cloud_functions/cloud_functions.dart';

/// Service untuk verifikasi pembayaran Lacak Driver (Rp 3000) penumpang via Google Play.
class PassengerTrackPaymentService {
  /// Panggil Cloud Function untuk verifikasi pembayaran dan update order.
  static Future<Map<String, dynamic>> verifyPassengerTrackPayment({
    required String purchaseToken,
    required String orderId,
    String? productId,
    String? packageName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyPassengerTrackPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'orderId': orderId,
      'productId':? productId,
      'packageName':? packageName,
    });
    return result.data;
  }
}
