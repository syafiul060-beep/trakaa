import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service untuk cek daftar pengguna yang mendapat pembebasan/izin khusus.
/// Dibaca dari Firestore app_config agar admin bisa mengatur tanpa ubah program.
class ExemptionService {
  static const _collection = 'app_config';

  /// Penumpang/pengirim/penerima dalam daftar ini tidak perlu bayar Lacak Driver & Lacak Barang.
  static const _docLacakExempt = 'lacak_exempt_users';

  /// Pengguna dalam daftar ini diizinkan pakai fake GPS/lokasi palsu (untuk testing/demo).
  static const _docFakeGpsAllowed = 'fake_gps_allowed_users';

  static List<String>? _lacakExemptCache;
  static List<String>? _fakeGpsAllowedCache;
  static DateTime? _lacakExemptCacheTime;
  static DateTime? _fakeGpsAllowedCacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  static Future<List<String>> _getUserUids(String docId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(docId)
          .get();
      final data = doc.data();
      final uids = data?['userUids'];
      if (uids is List) {
        return uids
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Cek apakah user bebas bayar Lacak Driver & Lacak Barang.
  static Future<bool> isLacakExempt(String? uid) async {
    if (uid == null || uid.isEmpty) return false;
    if (_lacakExemptCache != null &&
        _lacakExemptCacheTime != null &&
        DateTime.now().difference(_lacakExemptCacheTime!) < _cacheDuration) {
      return _lacakExemptCache!.contains(uid);
    }
    _lacakExemptCache = await _getUserUids(_docLacakExempt);
    _lacakExemptCacheTime = DateTime.now();
    return _lacakExemptCache!.contains(uid);
  }

  /// Cek apakah user diizinkan pakai fake GPS.
  static Future<bool> isFakeGpsAllowed(String? uid) async {
    if (uid == null || uid.isEmpty) return false;
    if (_fakeGpsAllowedCache != null &&
        _fakeGpsAllowedCacheTime != null &&
        DateTime.now().difference(_fakeGpsAllowedCacheTime!) < _cacheDuration) {
      return _fakeGpsAllowedCache!.contains(uid);
    }
    _fakeGpsAllowedCache = await _getUserUids(_docFakeGpsAllowed);
    _fakeGpsAllowedCacheTime = DateTime.now();
    return _fakeGpsAllowedCache!.contains(uid);
  }

  /// Cek untuk user saat ini (dari Firebase Auth).
  static Future<bool> isCurrentUserLacakExempt() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return isLacakExempt(uid);
  }

  static Future<bool> isCurrentUserFakeGpsAllowed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return isFakeGpsAllowed(uid);
  }
}
