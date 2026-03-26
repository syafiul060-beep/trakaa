import 'package:cloud_functions/cloud_functions.dart';

import '../utils/phone_utils.dart';

/// Service untuk cek kontak yang terdaftar sebagai driver (role=driver).
/// Dipakai untuk Oper Driver: pilih driver kedua dari kontak.
class DriverContactService {
  DriverContactService._();

  static String? normalizePhone(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return toE164OrNull(raw);
  }

  /// Cek maksimal 50 nomor ke backend. Mengembalikan map (kunci: nomor dinormalisasi) berisi
  /// `uid`, `displayName`, `photoUrl`, dan `email` untuk driver yang terdaftar.
  /// Hanya user dengan role=driver yang dikembalikan.
  static Future<Map<String, Map<String, dynamic>>> checkRegisteredDrivers(
    List<String> phoneNumbers,
  ) async {
    if (phoneNumbers.isEmpty) return {};
    final normalized = <String>[];
    final seen = <String>{};
    for (var i = 0; i < phoneNumbers.length && normalized.length < 50; i++) {
      final n = normalizePhone(phoneNumbers[i]);
      if (n != null && !seen.contains(n)) {
        seen.add(n);
        normalized.add(n);
      }
    }
    if (normalized.isEmpty) return {};
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkRegisteredDrivers');
      final result = await callable.call({'phoneNumbers': normalized});
      final data = result.data as Map<String, dynamic>?;
      final list = data?['registered'] as List<dynamic>? ?? [];
      final map = <String, Map<String, dynamic>>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>?;
        if (m == null) continue;
        final phone = m['phoneNumber'] as String?;
        if (phone == null) continue;
        map[phone] = {
          'uid': m['uid'],
          'displayName': m['displayName'],
          'photoUrl': m['photoUrl'],
          'email': m['email'],
          'vehicleJumlahPenumpang': m['vehicleJumlahPenumpang'],
        };
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
