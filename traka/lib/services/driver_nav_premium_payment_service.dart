import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_constants.dart';

/// Verifikasi pembayaran navigasi premium driver (consumable per rute).
class DriverNavPremiumPaymentService {
  static Future<Map<String, dynamic>> verifyPayment({
    required String purchaseToken,
    String? productId,
    String? routeJourneyNumber,
    String? navPremiumScope,
    int? routeDistanceMeters,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyDriverNavPremiumPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'packageName': AppConstants.packageName,
      if (productId != null) 'productId': productId,
      if (routeJourneyNumber != null && routeJourneyNumber.isNotEmpty)
        'routeJourneyNumber': routeJourneyNumber,
      if (navPremiumScope != null && navPremiumScope.isNotEmpty)
        'navPremiumScope': navPremiumScope,
      if (routeDistanceMeters != null && routeDistanceMeters > 0)
        'routeDistanceMeters': routeDistanceMeters,
    });
    return result.data;
  }
}
