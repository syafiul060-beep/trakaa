import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ID produk consumable Google Play — harus sama dengan SKU di Play Console.
String driverNavPremiumProductId(int amountRupiah) =>
    'traka_driver_nav_premium_$amountRupiah';

/// Penanda hutang navigasi premium (rute selesai, belum bayar).
/// Hutang tercermin di `users` (untuk gabung verifikasi kontribusi) + prefs (offline UI).
class DriverNavPremiumService {
  DriverNavPremiumService._();

  static bool? _phoneExemptCached;
  static DateTime? _phoneExemptCachedAt;

  /// Apakah nomor HP profil user ada di [driverNavPremiumExemptPhones] (app_config/settings).
  /// Hasil di-cache singkat untuk mengurangi panggilan Cloud Function.
  static Future<bool> fetchPhoneExempt({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _phoneExemptCached != null &&
        _phoneExemptCachedAt != null &&
        DateTime.now().difference(_phoneExemptCachedAt!) <
            const Duration(minutes: 5)) {
      return _phoneExemptCached!;
    }
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkDriverNavPremiumPhoneExempt');
      final res = await callable.call<Map<String, dynamic>>({});
      final exempt = res.data['exempt'] == true;
      _phoneExemptCached = exempt;
      _phoneExemptCachedAt = DateTime.now();
      return exempt;
    } catch (_) {
      return _phoneExemptCached ?? false;
    }
  }

  static void clearPhoneExemptCache() {
    _phoneExemptCached = null;
    _phoneExemptCachedAt = null;
  }

  static const _kOwed = 'driver_nav_premium_owed';
  static const _kOwedJourney = 'driver_nav_premium_owed_journey';
  static const _kOwedScope = 'driver_nav_premium_owed_scope';
  static const _kOwedDistanceM = 'driver_nav_premium_owed_distance_m';

  static Future<bool> hasOwedPayment() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kOwed) ?? false;
  }

  static Future<String?> owedRouteJourneyNumber() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kOwedJourney);
  }

  /// [navPremiumScope]: `dalamProvinsi` | `antarProvinsi` | `dalamNegara` (nama enum RouteType).
  /// [routeDistanceMeters]: jarak rute Directions saat hutang terjadi (untuk tarif jarak).
  /// [feeRupiahSnapshot]: tampilan total; server verifikasi ulang dari scope + jarak.
  static Future<void> setOwed({
    required String routeJourneyNumber,
    String? navPremiumScope,
    int? routeDistanceMeters,
    required int feeRupiahSnapshot,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOwed, true);
    await p.setString(_kOwedJourney, routeJourneyNumber);
    if (navPremiumScope != null && navPremiumScope.isNotEmpty) {
      await p.setString(_kOwedScope, navPremiumScope);
    } else {
      await p.remove(_kOwedScope);
    }
    if (routeDistanceMeters != null && routeDistanceMeters > 0) {
      await p.setInt(_kOwedDistanceM, routeDistanceMeters);
    } else {
      await p.remove(_kOwedDistanceM);
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final data = <String, dynamic>{
          'driverNavPremiumOwedJourney': routeJourneyNumber,
          'driverNavPremiumOwedScope': navPremiumScope ?? 'dalamNegara',
          'driverNavPremiumOwedFeeRupiah': feeRupiahSnapshot,
        };
        if (routeDistanceMeters != null && routeDistanceMeters > 0) {
          data['driverNavPremiumOwedDistanceM'] = routeDistanceMeters;
        } else {
          data['driverNavPremiumOwedDistanceM'] = FieldValue.delete();
        }
        await FirebaseFirestore.instance.collection('users').doc(uid).update(data);
      } catch (_) {}
    }
  }

  static Future<String?> owedNavPremiumScope() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kOwedScope);
  }

  static Future<int?> owedRouteDistanceMeters() async {
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey(_kOwedDistanceM)) return null;
    final v = p.getInt(_kOwedDistanceM);
    if (v == null || v <= 0) return null;
    return v;
  }

  static Future<void> clearOwed() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kOwed);
    await p.remove(_kOwedJourney);
    await p.remove(_kOwedScope);
    await p.remove(_kOwedDistanceM);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'driverNavPremiumOwedJourney': FieldValue.delete(),
          'driverNavPremiumOwedScope': FieldValue.delete(),
          'driverNavPremiumOwedDistanceM': FieldValue.delete(),
          'driverNavPremiumOwedFeeRupiah': FieldValue.delete(),
        });
      } catch (_) {}
    }
  }
}
