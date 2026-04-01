import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Bitmap marker titik awal/akhir di [GoogleMap]: **pin default Google Maps**
/// (teardrop berwarna), bukan aset PNG aplikasi.
class TrakaPinBitmapService {
  TrakaPinBitmapService._();

  static BitmapDescriptor? _mapAwal;
  static BitmapDescriptor? _mapAhir;

  /// Hijau ≈ titik mulai / asal.
  static BitmapDescriptor? get mapAwal => _mapAwal;

  /// Merah ≈ titik tujuan / akhir.
  static BitmapDescriptor? get mapAhir => _mapAhir;

  static void debugClearCache() {
    _mapAwal = null;
    _mapAhir = null;
  }

  static Future<void> ensureLoaded(BuildContext context) async {
    _mapAwal ??=
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    _mapAhir ??=
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }
}
