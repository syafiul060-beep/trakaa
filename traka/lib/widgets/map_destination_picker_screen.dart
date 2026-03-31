import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/geocoding_service.dart';
import '../services/map_style_service.dart';
import '../utils/placemark_formatter.dart';
import 'lollipop_pin_widgets.dart';

/// Hasil pemilihan titik tujuan di peta (label konsisten dengan geocoding lain di app).
class MapPickerResult {
  const MapPickerResult({
    required this.label,
    required this.lat,
    required this.lng,
  });

  final String label;
  final double lat;
  final double lng;
}

/// Layar peta: pin tetap di pusat area peta **di atas** panel alamat; [GoogleMap.padding]
/// menyelaraskan titik kamera dengan ujung pin (mirip Google Maps).
/// Alamat diambil dari reverse geocode titik tersebut.
class MapDestinationPickerScreen extends StatefulWidget {
  const MapDestinationPickerScreen({
    super.key,
    required this.initialCameraTarget,
    this.deviceLocation,
    this.title = 'Pilih lokasi di peta',
    this.pinVariant = LollipopPinVariant.destination,
  });

  /// Titik awal kamera (dari tujuan yang sudah dipilih, geocode teks, atau lokasi perangkat).
  final LatLng initialCameraTarget;

  /// Lokasi perangkat untuk tombol kembali ke posisi Anda (opsional).
  final LatLng? deviceLocation;

  final String title;

  /// [origin] = pin hijau (tujuan awal), [destination] = pin merah (tujuan akhir).
  final LollipopPinVariant pinVariant;

  @override
  State<MapDestinationPickerScreen> createState() =>
      _MapDestinationPickerScreenState();
}

bool _isLikelyNetworkError(Object e) {
  if (e is SocketException) return true;
  final m = e.toString().toLowerCase();
  return m.contains('socket') ||
      m.contains('failed host lookup') ||
      m.contains('network is unreachable') ||
      m.contains('connection reset') ||
      m.contains('connection refused') ||
      m.contains('timed out');
}

class _MapDestinationPickerScreenState extends State<MapDestinationPickerScreen> {
  GoogleMapController? _controller;
  LatLng? _lastCameraTarget;
  Placemark? _placemark;
  bool _loadingAddress = true;
  int _geocodeGen = 0;
  bool _firstResolveHapticPending = true;
  bool _lastReverseGeocodeNetworkError = false;

  void _scheduleReverseGeocode(LatLng target) {
    final gen = ++_geocodeGen;
    if (mounted) {
      setState(() => _loadingAddress = true);
    }
    unawaited(Future<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 360));
      if (!mounted || gen != _geocodeGen) return;
      try {
        final list = await GeocodingService.placemarkFromCoordinates(
          target.latitude,
          target.longitude,
        );
        if (!mounted || gen != _geocodeGen) return;
        final firstGoodResolve =
            _firstResolveHapticPending && list.isNotEmpty;
        if (firstGoodResolve) {
          _firstResolveHapticPending = false;
        }
        setState(() {
          _placemark = list.isNotEmpty ? list.first : null;
          _loadingAddress = false;
          _lastReverseGeocodeNetworkError = false;
        });
        if (firstGoodResolve) {
          HapticFeedback.selectionClick();
        }
      } catch (e) {
        if (!mounted || gen != _geocodeGen) return;
        final net = _isLikelyNetworkError(e);
        setState(() {
          _placemark = null;
          _loadingAddress = false;
          _lastReverseGeocodeNetworkError = net;
        });
      }
    }));
  }

  Future<void> _recenterDevice() async {
    final loc = widget.deviceLocation;
    if (loc == null || _controller == null) return;
    await _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(loc, MapStyleService.defaultZoom),
    );
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    final target = _lastCameraTarget ?? widget.initialCameraTarget;
    final p = _placemark;
    final label = p != null
        ? PlacemarkFormatter.formatDetail(p)
        : 'Lokasi di peta (${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)})';
    Navigator.of(context).pop(
      MapPickerResult(label: label, lat: target.latitude, lng: target.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineList = _placemark != null
        ? PlacemarkFormatter.mapPickerLines(_placemark!)
        : null;
    final addressTitle = (lineList != null && lineList.isNotEmpty)
        ? lineList.first
        : null;
    final addressSubtitle = (lineList != null && lineList.length > 1)
        ? lineList.sublist(1).join(', ')
        : null;

    final emptyHeadline = widget.pinVariant == LollipopPinVariant.origin
        ? 'Geser peta ke titik tujuan awal'
        : 'Geser peta ke titik tujuan akhir';
    final pinFootnote = widget.pinVariant == LollipopPinVariant.origin
        ? 'Pin biru Traka di tengah. Geser peta — ujung pin = titik yang dipilih.'
        : 'Pin merah Traka di tengah. Geser peta — ujung pin = titik yang dipilih.';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      // Column + Expanded: constraint tinggi eksplisit untuk GoogleMap (hindari Stack-only → area abu-abu).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GoogleMap(
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  // Citra satelit + label jalan (sama seperti lapisan «Satelit» di Google Maps).
                  mapType: MapStyleService.mapTypeForGoogleMap,
                  style: null,
                  liteModeEnabled: false,
                  buildingsEnabled: false,
                  indoorViewEnabled: false,
                  padding: EdgeInsets.zero,
                  initialCameraPosition: CameraPosition(
                    target: widget.initialCameraTarget,
                    zoom: MapStyleService.defaultZoom,
                    tilt: 0,
                  ),
                  onMapCreated: (c) {
                    _controller = c;
                    _lastCameraTarget = widget.initialCameraTarget;
                    _firstResolveHapticPending = true;
                    _scheduleReverseGeocode(widget.initialCameraTarget);
                  },
                  onCameraMove: (pos) {
                    _lastCameraTarget = pos.target;
                  },
                  onCameraIdle: () {
                    final t = _lastCameraTarget;
                    if (t != null) {
                      _scheduleReverseGeocode(t);
                    }
                  },
                ),
                IgnorePointer(
                  child: LollipopPinMapCenter(variant: widget.pinVariant),
                ),
                if (widget.deviceLocation != null)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Material(
                      elevation: 2,
                      shape: const CircleBorder(),
                      color: scheme.surface,
                      child: IconButton(
                        tooltip: 'Kembali ke lokasi Anda',
                        onPressed: _recenterDevice,
                        icon: Icon(Icons.my_location, color: scheme.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                color: scheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingAddress)
                        LinearProgressIndicator(
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 3,
                        )
                      else
                        const SizedBox(height: 3),
                      const SizedBox(height: 12),
                      Text(
                        addressTitle ?? emptyHeadline,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (addressSubtitle != null &&
                          addressSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          addressSubtitle,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (!_loadingAddress && _placemark == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _lastReverseGeocodeNetworkError
                              ? 'Tidak ada koneksi atau layanan alamat tidak menjawab. Periksa internet; Anda tetap bisa memakai koordinat titik ini.'
                              : 'Alamat tidak terbaca di titik ini; Anda tetap bisa memakai koordinat.',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        LollipopPinLegend.shortLine,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pinFootnote,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _loadingAddress ? null : _confirm,
                        child: const Text('Gunakan lokasi ini'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
