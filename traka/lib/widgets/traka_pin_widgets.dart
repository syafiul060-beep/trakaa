import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Varian titik di form / pemilih peta (amber penjemputan ≈ awal, merah ≈ akhir) — ikon Material.
enum TrakaRoutePinVariant {
  origin,
  destination,
}

class TrakaRoutePinPalette {
  TrakaRoutePinPalette._();

  static const Color originHead = AppTheme.mapPickupAccent;
  static const Color destinationHead = AppTheme.mapStopRed;
}

class TrakaRoutePinLegend {
  TrakaRoutePinLegend._();

  static const String shortLine =
      '«Pilih di peta» mengikuti isian tujuan; jika kosong, mulai dari lokasi Anda.';
}

Color trakaRoutePinFallbackColor(TrakaRoutePinVariant variant) =>
    variant == TrakaRoutePinVariant.origin
        ? TrakaRoutePinPalette.originHead
        : TrakaRoutePinPalette.destinationHead;

String trakaRoutePinSemanticsLabel(TrakaRoutePinVariant variant) =>
    variant == TrakaRoutePinVariant.origin
        ? 'Titik awal'
        : 'Titik akhir';

/// Ikon kecil di label form (amber penjemputan / merah tujuan).
class TrakaPinFormIcon extends StatelessWidget {
  const TrakaPinFormIcon({
    super.key,
    required this.variant,
  });

  final TrakaRoutePinVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = trakaRoutePinFallbackColor(variant);
    return Semantics(
      label: trakaRoutePinSemanticsLabel(variant),
      child: Icon(Icons.location_on, color: c, size: 22),
    );
  }
}

/// Penanda tetap di tengah layar pemilih titik di peta (gaya pin lokasi, bukan PNG kustom).
class TrakaPinMapCenter extends StatelessWidget {
  const TrakaPinMapCenter({super.key, required this.variant});

  final TrakaRoutePinVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = trakaRoutePinFallbackColor(variant);
    return Semantics(
      label:
          '${trakaRoutePinSemanticsLabel(variant)}. Tetap di tengah layar; geser peta untuk mengubah titik.',
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -28),
          child: Icon(
            Icons.location_on,
            color: c,
            size: 48,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
