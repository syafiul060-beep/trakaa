import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'active_drivers_service.dart';
import 'car_icon_service.dart';

/// Memilih [BitmapDescriptor] mobil di map penumpang.
///
/// Premium: hijau = masih ada kursi; merah = penuh; biru = rekomendasi terbaik (terdekat / skor).
/// Legacy: hijau/merau dari gerak jika premium tidak termuat.
class PassengerDriverMapCarIcon {
  PassengerDriverMapCarIcon._();

  static BitmapDescriptor pick({
    required ActiveDriverRoute driver,
    required bool isMoving,
    String? recommendedDriverUid,
    PremiumPassengerCarIconSet? premium,
    BitmapDescriptor? legacyGreen,
    BitmapDescriptor? legacyRed,
  }) {
    final hasPremium = premium != null;

    if (!driver.hasPassengerCapacity) {
      if (hasPremium) return premium.red;
      return legacyRed ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }

    if (recommendedDriverUid != null &&
        recommendedDriverUid == driver.driverUid &&
        hasPremium) {
      return premium.blue;
    }

    if (hasPremium) return premium.green;

    return (isMoving ? legacyGreen : legacyRed) ??
        BitmapDescriptor.defaultMarkerWithHue(
          isMoving ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
        );
  }
}
