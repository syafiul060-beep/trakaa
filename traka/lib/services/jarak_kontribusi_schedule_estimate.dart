import 'dart:async';

import '../l10n/app_localizations.dart';
import 'app_analytics_service.dart';
import 'geocoding_service.dart';
import 'order_service.dart';
import 'passenger_first_chat_message.dart';

/// Estimasi jarak/kontribusi untuk pesanan **terjadwal** (tanpa koordinat di order):
/// geocode teks asal/tujuan lalu hitung seperti beranda. Gagal geocode → fallback teks jadwal.
class JarakKontribusiScheduleEstimate {
  JarakKontribusiScheduleEstimate._();

  /// Batas waktu geocode + hitung kontribusi (hindari dialog menggantung).
  static const Duration computeTimeout = Duration(seconds: 15);

  static void _logOutcome(String outcome) {
    AppAnalyticsService.logChatEstimateScheduledResult(outcome: outcome);
  }

  /// Blok teks untuk `jarakKontribusiLines` di pesan pertama.
  /// Memakai [AppLocalizations.chatScheduledEstimateNote] jika geocode gagal/kosong/error/timeout.
  static Future<String> chatBlockFromAddressTexts({
    required String originText,
    required String destText,
    required AppLocalizations l10n,
    required String orderType,
    int? jumlahKerabat,
    String? barangCategory,
  }) async {
    final o = originText.trim();
    final d = destText.trim();
    if (o.isEmpty || d.isEmpty) {
      _logOutcome('empty_address');
      return l10n.chatScheduledEstimateNote;
    }
    try {
      return await _computeCore(
        o: o,
        d: d,
        l10n: l10n,
        orderType: orderType,
        jumlahKerabat: jumlahKerabat,
        barangCategory: barangCategory,
      ).timeout(
        computeTimeout,
        onTimeout: () {
          _logOutcome('timeout');
          return l10n.chatScheduledEstimateNote;
        },
      );
    } catch (_) {
      _logOutcome('error');
      return l10n.chatScheduledEstimateNote;
    }
  }

  static Future<String> _computeCore({
    required String o,
    required String d,
    required AppLocalizations l10n,
    required String orderType,
    int? jumlahKerabat,
    String? barangCategory,
  }) async {
    final results = await Future.wait([
      GeocodingService.locationFromAddress(o),
      GeocodingService.locationFromAddress(d),
    ]);
    final originLocs = results[0];
    final destLocs = results[1];
    if (originLocs.isEmpty || destLocs.isEmpty) {
      _logOutcome('fallback_geocode');
      return l10n.chatScheduledEstimateNote;
    }
    final oLat = originLocs.first.latitude;
    final oLng = originLocs.first.longitude;
    final dLat = destLocs.first.latitude;
    final dLng = destLocs.first.longitude;
    final preview = await OrderService.computeJarakKontribusiPreview(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      orderType: orderType,
      jumlahKerabat: jumlahKerabat,
      barangCategory: barangCategory,
    );
    if (preview == null) {
      _logOutcome('unavailable_short');
      return l10n.chatPreviewEstimateUnavailable;
    }
    _logOutcome('numeric');
    return PassengerFirstChatMessage.formatJarakKontribusiLines(l10n, preview);
  }
}
