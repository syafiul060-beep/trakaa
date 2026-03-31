import '../config/driver_iap_catalog.dart';

/// Tarif navigasi premium: tier jarak (travel jauh) × pengali jenis rute, lalu snap ke SKU Play.
///
/// Firestore `app_config/settings` (opsional):
/// - [driverNavPremiumDistancePricingEnabled]: `false` = hanya tarif per-scope lama.
/// - [driverNavPremiumTierMaxKm]: daftar batas atas km per pita (naik), mis. [75,200,450,900,1500,1e9].
/// - [driverNavPremiumTierBaseFeesRupiah]: biaya dasar per pita (sama panjang dengan tier max km).
/// - [driverNavPremiumScopeMultBpsDalam] / …Antar / …Nasional: basis poin (100 = 1.00).
/// - [driverNavPremiumSnapFeesRupiah]: nominal IAP yang diizinkan (snap terdekat).
class DriverNavPremiumPricing {
  DriverNavPremiumPricing._();

  static const int minFeeRupiah = 9000;
  static const int maxFeeRupiah = 150000;

  /// Batas kepercayaan jarak dari klien (anti input ngawur).
  static const double maxTrustedDistanceMeters = 2500000;

  static const List<double> _defaultTierMaxKm = [
    75,
    200,
    450,
    900,
    1500,
    1e9,
  ];

  static const List<int> _defaultTierBaseFees = [
    10000,
    18000,
    28000,
    42000,
    55000,
    68000,
  ];

  /// Snap ke SKU yang sama dengan kontribusi driver ([kDriverDuesAmounts]) — satu set nominal Play.
  static List<int> get _defaultSnapFees => List<int>.from(kDriverDuesAmounts);

  /// Tarif lama: hanya [scope] + field Firestore tier tunggal (tanpa jarak).
  static int legacyScopeOnlyRupiah(String? scopeName, Map<String, dynamic>? d) {
    const min = 3000;
    int readPositive(String key) {
      final v = d?[key];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n >= min) return n;
      }
      return 0;
    }

    int legacy() {
      final v = d?['driverNavPremiumFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n >= min) return n;
      }
      return 0;
    }

    int forScope(String? scope) {
      switch (scope) {
        case 'dalamProvinsi':
          final x = readPositive('driverNavPremiumFeeDalamProvinsiRupiah');
          if (x > 0) return x;
          final l = legacy();
          if (l > 0) return l;
          return 50000;
        case 'antarProvinsi':
          final x = readPositive('driverNavPremiumFeeAntarProvinsiRupiah');
          if (x > 0) return x;
          final l = legacy();
          if (l > 0) return l;
          return 75000;
        case 'dalamNegara':
          final x = readPositive('driverNavPremiumFeeNasionalRupiah');
          if (x > 0) return x;
          final l = legacy();
          if (l > 0) return l;
          return 100000;
        default:
          final l = legacy();
          if (l > 0) return l;
          return 100000;
      }
    }

    return forScope(scopeName);
  }

  /// Satu angka final untuk IAP `traka_driver_nav_premium_<rupiah>`.
  static int computeRupiah({
    required String? scope,
    required double? distanceMeters,
    required Map<String, dynamic>? settings,
  }) {
    final enabled = settings?['driverNavPremiumDistancePricingEnabled'];
    final useDist = enabled != false &&
        distanceMeters != null &&
        distanceMeters > 0 &&
        distanceMeters <= maxTrustedDistanceMeters;

    if (!useDist) {
      return legacyScopeOnlyRupiah(scope, settings);
    }

    final km = distanceMeters / 1000.0;
    var maxKms = _parseTierMaxKm(settings);
    var bases = _parseTierBases(settings, maxKms.length);
    if (bases.length != maxKms.length) {
      maxKms = List<double>.from(_defaultTierMaxKm);
      bases = List<int>.from(_defaultTierBaseFees);
    }
    final snap = _parseSnapFees(settings);
    final base = _baseFeeForKm(km, maxKms, bases);
    final multBps = _scopeMultiplierBps(scope, settings);
    var rawInt = (base * multBps / 100.0).round();
    if (rawInt < minFeeRupiah) rawInt = minFeeRupiah;
    if (rawInt > maxFeeRupiah) rawInt = maxFeeRupiah;
    return _snapToNearest(rawInt, snap);
  }

  static List<double> _parseTierMaxKm(Map<String, dynamic>? d) {
    final raw = d?['driverNavPremiumTierMaxKm'];
    if (raw is! List || raw.length < 2) {
      return List<double>.from(_defaultTierMaxKm);
    }
    final out = <double>[];
    for (final e in raw) {
      final n = (e is num) ? e.toDouble() : double.tryParse(e.toString());
      if (n != null && n > 0) out.add(n);
    }
    if (out.length < 2) return List<double>.from(_defaultTierMaxKm);
    for (var i = 1; i < out.length; i++) {
      if (out[i] <= out[i - 1]) {
        return List<double>.from(_defaultTierMaxKm);
      }
    }
    return out;
  }

  static List<int> _parseTierBases(Map<String, dynamic>? d, int len) {
    final raw = d?['driverNavPremiumTierBaseFeesRupiah'];
    if (raw is! List || raw.length != len) {
      return len == _defaultTierMaxKm.length
          ? List<int>.from(_defaultTierBaseFees)
          : <int>[];
    }
    final out = <int>[];
    for (final e in raw) {
      final n = (e is num) ? e.toInt() : int.tryParse(e.toString());
      if (n == null || n < minFeeRupiah) {
        return len == _defaultTierMaxKm.length
            ? List<int>.from(_defaultTierBaseFees)
            : <int>[];
      }
      out.add(n);
    }
    return out;
  }

  static List<int> _parseSnapFees(Map<String, dynamic>? d) {
    final raw = d?['driverNavPremiumSnapFeesRupiah'];
    if (raw is! List || raw.isEmpty) {
      return List<int>.from(_defaultSnapFees);
    }
    final out = <int>[];
    for (final e in raw) {
      final n = (e is num) ? e.toInt() : int.tryParse(e.toString());
      if (n != null && n >= minFeeRupiah && n <= maxFeeRupiah) out.add(n);
    }
    out.sort();
    if (out.isEmpty) return List<int>.from(_defaultSnapFees);
    return out;
  }

  static int _scopeMultiplierBps(String? scope, Map<String, dynamic>? d) {
    int readBps(String key, int fallback) {
      final v = d?[key];
      if (v == null) return fallback;
      final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
      if (n == null || n < 50 || n > 300) return fallback;
      return n;
    }

    switch (scope) {
      case 'dalamProvinsi':
        return readBps('driverNavPremiumScopeMultBpsDalam', 100);
      case 'antarProvinsi':
        return readBps('driverNavPremiumScopeMultBpsAntar', 108);
      case 'dalamNegara':
      default:
        return readBps('driverNavPremiumScopeMultBpsNasional', 116);
    }
  }

  static int _baseFeeForKm(double km, List<double> maxKms, List<int> bases) {
    for (var i = 0; i < maxKms.length && i < bases.length; i++) {
      if (km <= maxKms[i]) return bases[i];
    }
    return bases.isNotEmpty ? bases.last : _defaultTierBaseFees.last;
  }

  static int _snapToNearest(int raw, List<int> allowed) {
    if (allowed.isEmpty) {
      var x = (raw / 1000).round() * 1000;
      if (x < minFeeRupiah) x = minFeeRupiah;
      if (x > maxFeeRupiah) x = maxFeeRupiah;
      return x;
    }
    var best = allowed.first;
    var bestDiff = (raw - best).abs();
    for (final a in allowed) {
      final d = (raw - a).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = a;
      }
    }
    if (best < minFeeRupiah) return minFeeRupiah;
    if (best > maxFeeRupiah) return maxFeeRupiah;
    return best;
  }
}
