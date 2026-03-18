import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Generator nomor rute perjalanan unik (format RUTE-YYYYMMDD-XXXXXX).
/// Memanggil Cloud Function generateRouteJourneyNumber (counter hanya ditulis oleh server).
class RouteJourneyNumberService {
  static final List<String> _hari = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  static const _maxRetries = 3;
  static const _retryDelay = Duration(seconds: 2);

  /// Generate nomor rute perjalanan unik. Format: RUTE-YYYYMMDD-000001, ...
  static Future<String> generateRouteJourneyNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Sesi tidak valid. Silakan login ulang.',
      );
    }

    Future<Map<String, dynamic>> call() => FirebaseFunctions.instance
        .httpsCallable('generateRouteJourneyNumber')
        .call<Map<String, dynamic>>()
        .then((r) => r.data);

    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await user.getIdToken(true);
        final data = await call();
        final routeJourneyNumber = data['routeJourneyNumber'] as String?;
        if (routeJourneyNumber == null || routeJourneyNumber.isEmpty) {
          throw Exception('generateRouteJourneyNumber: invalid response');
        }
        return routeJourneyNumber;
      } on FirebaseFunctionsException catch (e) {
        if (e.code == 'unauthenticated' && attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay);
          continue;
        }
        rethrow;
      } catch (e) {
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelay);
          continue;
        }
        rethrow;
      }
    }

    throw FirebaseFunctionsException(
      code: 'unauthenticated',
      message: 'Sesi tidak valid. Silakan login ulang.',
    );
  }

  /// Nama hari dari tanggal (untuk ditampilkan bersama nomor rute).
  static String getDayName(DateTime date) {
    return _hari[date.weekday % 7];
  }
}
