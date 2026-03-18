import 'package:cloud_firestore/cloud_firestore.dart';

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
    final fmt = (int n) =>
        n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
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
}
