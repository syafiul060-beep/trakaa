import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/traka_pin_assets.dart';

/// Memuat [BitmapDescriptor] untuk pin awal/akhir di [GoogleMap].
class TrakaPinBitmapService {
  TrakaPinBitmapService._();

  static BitmapDescriptor? _mapAwal;
  static BitmapDescriptor? _mapAhir;

  static BitmapDescriptor? get mapAwal => _mapAwal;
  static BitmapDescriptor? get mapAhir => _mapAhir;

  static Future<void> ensureLoaded(BuildContext context) async {
    if (_mapAwal != null && _mapAhir != null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const size = 52.0;
    final config = ImageConfiguration(
      devicePixelRatio: dpr,
      size: const Size(size, size),
    );
    try {
      _mapAwal ??= await BitmapDescriptor.asset(
        config,
        TrakaPinAssets.mapPinAwal,
      );
      _mapAhir ??= await BitmapDescriptor.asset(
        config,
        TrakaPinAssets.mapPinAhir,
      );
    } catch (_) {}
  }
}
