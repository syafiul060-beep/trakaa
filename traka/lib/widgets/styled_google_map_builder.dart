import 'package:flutter/material.dart';

import '../services/map_style_service.dart';

/// Builder yang membungkus logika tema untuk GoogleMap.
/// Peta mengikuti setingan tema aplikasi (toggle Tema Gelap), bukan setingan HP.
///
/// [builder]: menerima (style, useDark) → style untuk GoogleMap, useDark untuk MapType.
/// useDark = true hanya saat user mengaktifkan tema gelap di aplikasi.
class StyledGoogleMapBuilder extends StatelessWidget {
  const StyledGoogleMapBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(String? style, bool useDark) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MapStyleService.themeNotifier,
      builder: (context, _) {
        final themeMode = MapStyleService.themeNotifier.value;
        final useDark = themeMode == ThemeMode.dark;
        final style = MapStyleService.getStyleForMap(themeMode, useDark);
        return builder(style, useDark);
      },
    );
  }
}
