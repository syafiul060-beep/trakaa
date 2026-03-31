import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/tile_layer_service.dart';
import '../widgets/traka_l10n_scope.dart';

/// Pratinjau OSM + cache tile (bukan peta utama Google). Berguna sebelum masuk daerah sinyal lemah.
class OfflineMapPrecacheScreen extends StatelessWidget {
  const OfflineMapPrecacheScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = TrakaL10n.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offlineMapPrecacheTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              l10n.offlineMapPrecacheIntro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                  ),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(-3.31, 114.59),
                initialZoom: 5.2,
                minZoom: 3,
                maxZoom: 18,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              children: [
                TileLayerService.buildTileLayer(darkMode: dark),
                SimpleAttributionWidget(
                  source: Text(
                    l10n.offlineMapPrecacheOsmAttribution,
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              l10n.offlineMapPrecacheFooter,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
