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
      'productId':? productId,
      'routeJourneyNumber':? (routeJourneyNumber != null &&
              routeJourneyNumber.isNotEmpty
          ? routeJourneyNumber
          : null),
      'navPremiumScope':? (navPremiumScope != null && navPremiumScope.isNotEmpty
          ? navPremiumScope
          : null),
      'routeDistanceMeters':? (routeDistanceMeters != null && routeDistanceMeters > 0
          ? routeDistanceMeters
          : null),
    });
    return result.data;
  }
}
