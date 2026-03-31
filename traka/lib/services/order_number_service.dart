import 'package:cloud_functions/cloud_functions.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// Generator nomor pesanan unik (format TRK-YYYYMMDD-XXXXXX).
/// Memanggil Cloud Function generateOrderNumber (counter hanya ditulis oleh server).
class OrderNumberService {
  @visibleForTesting
  static Future<String> Function()? generateOrderNumberOverride;

  /// Generate nomor pesanan unik. Format: TRK-YYYYMMDD-000001, TRK-YYYYMMDD-000002, ...
  static Future<String> generateOrderNumber() async {
    final override = generateOrderNumberOverride;
    if (override != null) return override();
    final result = await FirebaseFunctions.instance
        .httpsCallable('generateOrderNumber')
        .call<Map<String, dynamic>>();
    final orderNumber = result.data['orderNumber'] as String?;
    if (orderNumber == null || orderNumber.isEmpty) {
      throw Exception('generateOrderNumber: invalid response');
    }
    return orderNumber;
  }
}
