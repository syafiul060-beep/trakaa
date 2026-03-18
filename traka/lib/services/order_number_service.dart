import 'package:cloud_functions/cloud_functions.dart';

/// Generator nomor pesanan unik (format TRK-YYYYMMDD-XXXXXX).
/// Memanggil Cloud Function generateOrderNumber (counter hanya ditulis oleh server).
class OrderNumberService {
  /// Generate nomor pesanan unik. Format: TRK-YYYYMMDD-000001, TRK-YYYYMMDD-000002, ...
  static Future<String> generateOrderNumber() async {
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
