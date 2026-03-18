import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Service untuk tile layer peta dengan caching offline.
/// Tile yang pernah dilihat akan di-cache dan tersedia saat sinyal lemah.
///
/// Sesuai kebijakan OpenStreetMap (osm.wiki/Blocked), aplikasi harus mengirim
/// User-Agent yang mengidentifikasi client agar tidak diblokir (403).
class TileLayerService {
  TileLayerService._();

  static CacheStore? _cacheStore;
  static bool _initialized = false;

  /// User-Agent untuk tile request. Diwajibkan oleh OpenStreetMap.
  /// Format: AppName/version (package; +url; contact: email)
  static const String _userAgent =
      'Traka/1.0.6 (id.traka.app; +https://traka.id; contact: support@traka.id)';

  /// Dio instance dengan User-Agent yang sesuai kebijakan OSM.
  static Dio _createOsmDio() {
    return Dio(BaseOptions(
      headers: {'User-Agent': _userAgent},
    ));
  }

  /// Inisialisasi cache store (panggil sekali di main).
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      final dir = await getTemporaryDirectory();
      _cacheStore = FileCacheStore(
        path.join(dir.path, 'TrakaMapTiles'),
      );
      _initialized = true;
    } catch (_) {
      _initialized = true; // Fallback: tile layer tanpa cache
    }
  }

  /// URL fallback jika OSM 403. Carto gratis, tidak perlu API key.
  static const String _fallbackTemplate =
      'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';

  /// Tile layer OSM dengan cache. Peta tetap tampil di area yang pernah dikunjungi.
  /// Jika OSM 403, otomatis fallback ke Carto.
  static TileLayer buildTileLayer({bool darkMode = false}) {
    final template = darkMode
        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    if (_cacheStore != null) {
      return TileLayer(
        urlTemplate: template,
        fallbackUrl: _fallbackTemplate,
        userAgentPackageName: 'id.traka.app',
        tileProvider: CachedTileProvider(
          store: _cacheStore!,
          maxStale: const Duration(days: 30),
          dio: _createOsmDio(),
        ),
        maxZoom: 19,
        minZoom: 1,
      );
    }

    return TileLayer(
      urlTemplate: template,
      fallbackUrl: _fallbackTemplate,
      userAgentPackageName: 'id.traka.app',
      maxZoom: 19,
      minZoom: 1,
    );
  }
}
