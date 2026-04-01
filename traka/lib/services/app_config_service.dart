import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;

import 'driver_nav_premium_pricing.dart';
import '../utils/app_logger.dart' show logError;

/// Service untuk membaca konfigurasi aplikasi dari app_config/settings.
class AppConfigService {
  static const String _collection = 'app_config';

  /// Biaya Lacak Barang (Rp) berdasarkan tier provinsi.
  /// Tier: 1 = dalam provinsi (10000), 2 = beda provinsi (15000), 3 = lebih dari 1 provinsi (25000).
  static Future<int> getLacakBarangFeeRupiah(int tier) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final d = doc.data();
      if (tier == 1) {
        final v = d?['lacakBarangDalamProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 10000) return n;
        }
        return 10000;
      }
      if (tier == 2) {
        final v = d?['lacakBarangBedaProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 15000) return n;
        }
        return 15000;
      }
      if (tier == 3) {
        final v = d?['lacakBarangLebihDari1ProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 25000) return n;
        }
        return 25000;
      }
    } catch (e, st) {
      logError('AppConfigService.getLacakBarangFeeRupiah', e, st);
    }
    return tier == 1 ? 10000 : tier == 2 ? 15000 : 25000;
  }

  /// Range biaya Lacak Barang (min–max Rp) untuk tooltip. Tier 1 = min, tier 3 = max.
  static Future<String> getLacakBarangFeeRangeForTooltip() async {
    final min = await getLacakBarangFeeRupiah(1);
    final max = await getLacakBarangFeeRupiah(3);
    String fmt(int n) => n
        .toString()
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp ${fmt(min)} - Rp ${fmt(max)}';
  }

  /// Slot kapasitas per order kargo (1 kargo = X slot penumpang). Dokumen = 0.
  /// Default 1. Bisa dikonfigurasi di app_config/settings.kargoSlotPerOrder.
  static Future<double> getKargoSlotPerOrder() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['kargoSlotPerOrder'];
      if (v != null) {
        final n = (v is num) ? v.toDouble() : double.tryParse(v.toString());
        if (n != null && n >= 0) return n;
      }
    } catch (e, st) {
      logError('AppConfigService.getKargoSlotPerOrder', e, st);
    }
    return 1.0;
  }

  /// Tarif kontribusi kirim barang per km (Rp) berdasarkan tier provinsi.
  /// Tier 1 = dalam provinsi (15), 2 = beda provinsi (35), 3 = lebih dari 1 provinsi (50).
  static Future<int> getTarifBarangPerKm(int tier) async {
    return getTarifBarangPerKmWithCategory(tier, null);
  }

  /// Tarif kontribusi kirim barang per km (Rp) berdasarkan tier dan kategori barang.
  /// [barangCategory]: 'dokumen' | 'kargo' | null. Jika null atau 'kargo', pakai tarif kargo.
  /// Dokumen biasanya lebih murah (surat, amplop). Kargo untuk paket berat/dimensi besar.
  /// Field app_config: tarifBarangDokumenDalamProvinsiPerKm, tarifBarangDokumenBedaProvinsiPerKm,
  /// tarifBarangDokumenLebihDari1ProvinsiPerKm. Default dokumen: 10/25/35 Rp/km.
  static Future<int> getTarifBarangPerKmWithCategory(int tier, String? barangCategory) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final d = doc.data();
      final isDokumen = barangCategory == 'dokumen';

      if (isDokumen) {
        if (tier == 1) {
          final v = d?['tarifBarangDokumenDalamProvinsiPerKm'];
          if (v != null) {
            final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
            if (n != null && n >= 5) return n;
          }
          return 10;
        }
        if (tier == 2) {
          final v = d?['tarifBarangDokumenBedaProvinsiPerKm'];
          if (v != null) {
            final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
            if (n != null && n >= 5) return n;
          }
          return 25;
        }
        if (tier == 3) {
          final v = d?['tarifBarangDokumenLebihDari1ProvinsiPerKm'];
          if (v != null) {
            final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
            if (n != null && n >= 5) return n;
          }
          return 35;
        }
      }

      // Kargo atau null (order lama)
      if (tier == 1) {
        final v = d?['tarifBarangDalamProvinsiPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 10) return n;
        }
        return 15;
      }
      if (tier == 2) {
        final v = d?['tarifBarangBedaProvinsiPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 10) return n;
        }
        return 35;
      }
      if (tier == 3) {
        final v = d?['tarifBarangLebihDari1ProvinsiPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 10) return n;
        }
        return 50;
      }
    } catch (e, st) {
      logError('AppConfigService.getTarifBarangPerKmWithCategory', e, st);
    }
    return tier == 1 ? 15 : tier == 2 ? 35 : 50;
  }

  /// Batas maksimal kontribusi travel per rute (Rp). Opsional; null = tidak ada batas.
  /// Default 30000 agar rute jauh tidak memberatkan driver.
  static Future<int?> getMaxKontribusiTravelPerRuteRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['maxKontribusiTravelPerRuteRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) return n;
      }
    } catch (_) {}
    return 30000;
  }

  /// Minimum kontribusi travel per order (Rp). Admin bisa ubah (mis. kena pajak).
  /// Default 5000.
  static Future<int> getMinKontribusiTravelRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['minKontribusiTravelRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n >= 0) return n;
      }
    } catch (_) {}
    return 5000;
  }

  /// Tarif kontribusi travel per km (Rp) berdasarkan tier provinsi.
  /// Tier 1 = dalam provinsi (90), 2 = beda provinsi sama pulau (110), 3 = beda pulau (140).
  /// Admin bisa ubah di app_config/settings.
  static Future<int> getTarifKontribusiTravelPerKm(int tier) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final d = doc.data();
      if (tier == 1) {
        final v = d?['tarifKontribusiTravelDalamProvinsiPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 0) return n;
        }
        return 90;
      }
      if (tier == 2) {
        final v = d?['tarifKontribusiTravelBedaProvinsiPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 0) return n;
        }
        return 110;
      }
      if (tier == 3) {
        final v = d?['tarifKontribusiTravelBedaPulauPerKm'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 0) return n;
        }
        return 140;
      }
    } catch (e, st) {
      logError('AppConfigService.getTarifKontribusiTravelPerKm', e, st);
    }
    return tier == 1 ? 90 : tier == 2 ? 110 : 140;
  }

  /// Harga kontribusi travel per 1× kapasitas (Rp). Legacy; kontribusi baru berbasis jarak.
  static Future<int> getContributionPriceRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['contributionPriceRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) return n;
      }
    } catch (_) {}
    return 7500;
  }

  /// Biaya Lacak Driver (Rp). Dibaca dari Firestore; default 3000, min 3000.
  /// Google Play tidak mendukung harga di bawah Rp 3.000.
  static Future<int> getLacakDriverFeeRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['lacakDriverFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          return n < 3000 ? 3000 : n;
        }
      }
    } catch (e, st) {
      logError('AppConfigService.getLacakDriverFeeRupiah', e, st);
    }
    return 3000;
  }

  /// ICE servers untuk WebRTC (STUN + TURN opsional).
  /// TURN dibaca dari app_config/settings.voiceCallTurnUrls, voiceCallTurnUsername, voiceCallTurnCredential.
  /// Jika tidak ada, hanya pakai STUN Google.
  static Future<List<Map<String, dynamic>>> getVoiceCallIceServers() async {
    final stun = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final d = doc.data();
      final urls = d?['voiceCallTurnUrls'];
      final username = d?['voiceCallTurnUsername'];
      final credential = d?['voiceCallTurnCredential'];
      if (urls is List && urls.isNotEmpty && username != null && credential != null) {
        final turnUrls = urls.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        if (turnUrls.isNotEmpty) {
          return [
            ...stun,
            {
              'urls': turnUrls,
              'username': username.toString(),
              'credential': credential.toString(),
            },
          ];
        }
      }
    } catch (e, st) {
      logError('AppConfigService.getVoiceCallIceServers', e, st);
    }
    return stun;
  }

  /// Biaya IAP navigasi premium untuk satu rute (Firestore + tier jarak/scope).
  static Future<int> getDriverNavPremiumFeeForRoute({
    String? navPremiumScope,
    int? routeDistanceMeters,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      return DriverNavPremiumPricing.computeRupiah(
        scope: navPremiumScope,
        distanceMeters: routeDistanceMeters?.toDouble(),
        settings: doc.data(),
      );
    } catch (e, st) {
      logError('AppConfigService.getDriverNavPremiumFeeForRoute', e, st);
    }
    return DriverNavPremiumPricing.computeRupiah(
      scope: navPremiumScope,
      distanceMeters: routeDistanceMeters?.toDouble(),
      settings: null,
    );
  }

  /// Stream teks marketing halaman login dari [settings]. Update real-time saat admin mengubah Firestore.
  static Stream<LoginSloganConfig> watchLoginSloganConfig() {
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc('settings')
        .snapshots()
        .map(LoginSloganConfig.fromSnapshot);
  }
}

/// Satu chip marketing di bawah slogan login (ikon + teks ID/EN opsional).
@immutable
class LoginHeroPillConfig {
  const LoginHeroPillConfig({this.iconKey, this.labelId, this.labelEn});

  /// Kunci aman — dipetakan di [loginHeroIconFromKey].
  final String? iconKey;
  final String? labelId;
  final String? labelEn;
}

/// Ikon chip login dari kunci admin (whitelist).
IconData? loginHeroIconFromKey(String? key) {
  switch (key) {
    case 'route':
      return Icons.route_rounded;
    case 'map':
      return Icons.map_rounded;
    case 'inventory':
      return Icons.inventory_2_outlined;
    case 'post':
      return Icons.local_post_office_outlined;
    case 'shipping':
      return Icons.local_shipping_outlined;
    case 'shield':
      return Icons.shield_outlined;
    case 'star':
      return Icons.star_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'taxi':
      return Icons.local_taxi_rounded;
    case 'gps':
      return Icons.my_location_rounded;
    case 'payment':
      return Icons.payments_outlined;
    case 'groups':
      return Icons.groups_outlined;
    case 'favorite':
      return Icons.favorite_rounded;
    default:
      return null;
  }
}

bool _loginHeroIconKeyValid(String? key) =>
    key != null && loginHeroIconFromKey(key) != null;

/// Field opsional di `app_config/settings`: loginSlogan*, loginHeroPills[].
@immutable
class LoginSloganConfig {
  const LoginSloganConfig({
    this.titleId,
    this.subtitleId,
    this.titleEn,
    this.subtitleEn,
    this.heroPills = const [],
  });

  final String? titleId;
  final String? subtitleId;
  final String? titleEn;
  final String? subtitleEn;
  final List<LoginHeroPillConfig> heroPills;

  /// Salinan sales bawaan aplikasi jika admin mengosongkan field.
  static const String defaultTitleId =
      'Travel & kirim barang, tanpa tebak harga.';
  static const String defaultSubtitleId =
      'Driver terpercaya, lacak live, penawaran untuk Anda — pasang Traka & jalan tenang.';
  static const String defaultTitleEn =
      'Rides & delivery with clear, fair pricing.';
  static const String defaultSubtitleEn =
      'Trusted drivers, live tracking, perks for you — install Traka and ride easy.';

  static LoginSloganConfig fromSnapshot(DocumentSnapshot<Object?> snap) {
    final d = snap.data() as Map<String, dynamic>?;
    String? pick(dynamic v) {
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    final pills = _parseHeroPills(d?['loginHeroPills']);

    return LoginSloganConfig(
      titleId: pick(d?['loginSloganTitleId']),
      subtitleId: pick(d?['loginSloganSubtitleId']),
      titleEn: pick(d?['loginSloganTitleEn']),
      subtitleEn: pick(d?['loginSloganSubtitleEn']),
      heroPills: pills,
    );
  }

  static List<LoginHeroPillConfig> _parseHeroPills(dynamic raw) {
    if (raw is! List) return const [];
    final out = <LoginHeroPillConfig>[];
    String? pick(dynamic v) {
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    for (final item in raw.take(3)) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final iconRaw = pick(m['icon']);
      final iconKey = _loginHeroIconKeyValid(iconRaw) ? iconRaw : null;
      out.add(LoginHeroPillConfig(
        iconKey: iconKey,
        labelId: pick(m['labelId']),
        labelEn: pick(m['labelEn']),
      ));
    }
    return out;
  }

  static const _pillIconDefaults = ['route', 'map', 'post'];
  static const _pillLabelIdDefaults = ['Travel', 'Lacak', 'Barang'];
  static const _pillLabelEnDefaults = ['Rides', 'Track', 'Parcel'];

  /// Tiga chip untuk hero login; warna diatur di widget dari tema.
  List<({IconData icon, String label})> resolveHeroPills(bool isIndonesian) {
    final result = <({IconData icon, String label})>[];
    for (var i = 0; i < 3; i++) {
      final defIcon = _pillIconDefaults[i];
      final cfg = i < heroPills.length ? heroPills[i] : null;
      final iconKey = _loginHeroIconKeyValid(cfg?.iconKey) ? cfg!.iconKey! : defIcon;
      final icon = loginHeroIconFromKey(iconKey) ?? Icons.auto_awesome_rounded;
      final label = isIndonesian
          ? (cfg?.labelId != null && cfg!.labelId!.isNotEmpty
              ? cfg.labelId!
              : _pillLabelIdDefaults[i])
          : (cfg?.labelEn != null && cfg!.labelEn!.isNotEmpty
              ? cfg.labelEn!
              : _pillLabelEnDefaults[i]);
      result.add((icon: icon, label: label));
    }
    return result;
  }

  /// Teks untuk locale aktif (fallback ke default bawaan app).
  ({String title, String subtitle}) resolve(bool isIndonesian) {
    if (isIndonesian) {
      return (
        title: titleId ?? defaultTitleId,
        subtitle: subtitleId ?? defaultSubtitleId,
      );
    }
    return (
      title: titleEn ?? defaultTitleEn,
      subtitle: subtitleEn ?? defaultSubtitleEn,
    );
  }
}
