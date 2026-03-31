import 'package:flutter/material.dart';

import '../config/traka_pin_assets.dart';

/// Varian pin di form / pemilih peta (aset Traka: biru = awal, merah = akhir).
enum LollipopPinVariant {
  origin,
  destination,
}

/// Warna selaras [GoogleMap] `defaultMarkerWithHue` (hijau / merah).
class LollipopPinPalette {
  LollipopPinPalette._();

  static const Color originHead = Color(0xFF4CAF50);
  static const Color destinationHead = Color(0xFFD32F2F);
}

/// Satu baris penjelasan (marker bawaan Google Maps).
class LollipopPinLegend {
  LollipopPinLegend._();

  static const String shortLine =
      'Biru = tujuan awal · Merah = tujuan akhir — ikon Traka di peta.';
}

Color lollipopHeadColor(LollipopPinVariant variant) =>
    variant == LollipopPinVariant.origin
        ? LollipopPinPalette.originHead
        : LollipopPinPalette.destinationHead;

String lollipopPinSemanticsLabel(LollipopPinVariant variant) =>
    variant == LollipopPinVariant.origin
        ? 'Pin awal Traka'
        : 'Pin akhir Traka';

/// Ikon lokasi kecil untuk label form ([TrakaPinAssets] di `assets/images/pin/`).
class LollipopPinFormIcon extends StatelessWidget {
  const LollipopPinFormIcon({
    super.key,
    required this.variant,
  });

  final LollipopPinVariant variant;

  @override
  Widget build(BuildContext context) {
    final path = variant == LollipopPinVariant.origin
        ? TrakaPinAssets.formAwal
        : TrakaPinAssets.formAhir;
    final c = lollipopHeadColor(variant);
    return Semantics(
      label: lollipopPinSemanticsLabel(variant),
      child: Image.asset(
        path,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.location_on, color: c, size: 22),
      ),
    );
  }
}

/// Pin tengah layar pemilih titik di peta (grafis Traka di `assets/images/pin/`).
class LollipopPinMapCenter extends StatelessWidget {
  const LollipopPinMapCenter({super.key, required this.variant});

  final LollipopPinVariant variant;

  @override
  Widget build(BuildContext context) {
    final path = variant == LollipopPinVariant.origin
        ? TrakaPinAssets.mapPinAwal
        : TrakaPinAssets.mapPinAhir;
    final c = lollipopHeadColor(variant);
    return Semantics(
      label:
          '${lollipopPinSemanticsLabel(variant)} Tetap di tengah layar; geser peta untuk mengubah titik.',
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -36),
          child: Image.asset(
            path,
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                Icon(Icons.location_on, color: c, size: 52),
          ),
        ),
      ),
    );
  }
}
