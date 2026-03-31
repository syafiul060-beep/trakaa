import 'services/travel_admin_region.dart';

/// Dipanggil dari [main] agar modul matching wilayah admin tetap bagian dari
/// graf dependensi aplikasi (release/debug konsisten untuk analisis & tooling).
void trakaTouchTravelAdminRegionInDebug() {
  assert(() {
    TravelAdminRegion.normalizeToken('kabupaten contoh');
    return true;
  }());
}
