import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/destination_autocomplete_service.dart';
import '../services/geocoding_service.dart' show GeocodingService, Location, Placemark;
import '../theme/responsive.dart';
import '../utils/placemark_formatter.dart';
import 'traka_l10n_scope.dart';

/// Bottom sheet form: asal (auto), tujuan (autocomplete + Pilih di Map), tombol Rute Perjalanan.
/// Menggunakan peta utama beranda (bukan maps kecil) seperti form penumpang.
class DriverRouteFormSheet extends StatefulWidget {
  final String originText;
  final String? currentProvinsi;
  final bool sameProvinceOnly;
  final bool sameIslandOnly;
  final List<String> provincesInIsland;
  final double? driverLat;
  final double? driverLng;
  final String? initialDest;
  final String? initialOrigin;
  final GoogleMapController? mapController;
  final ValueNotifier<bool> formDestMapModeNotifier;
  final ValueNotifier<LatLng?> formDestMapTapNotifier;
  final ValueNotifier<LatLng?> formDestPreviewNotifier;
  final void Function(
    double originLat,
    double originLng,
    String originText,
    double destLat,
    double destLng,
    String destText,
  )
      onRouteRequest;

  const DriverRouteFormSheet({
    super.key,
    required this.originText,
    required this.currentProvinsi,
    required this.sameProvinceOnly,
    required this.sameIslandOnly,
    required this.provincesInIsland,
    required this.driverLat,
    required this.driverLng,
    this.initialDest,
    this.initialOrigin,
    this.mapController,
    required this.formDestMapModeNotifier,
    required this.formDestMapTapNotifier,
    required this.formDestPreviewNotifier,
    required this.onRouteRequest,
  });

  @override
  State<DriverRouteFormSheet> createState() => _DriverRouteFormSheetState();
}

class _DriverRouteFormSheetState extends State<DriverRouteFormSheet> {
  late final TextEditingController _destController = TextEditingController(
    text: widget.initialDest ?? '',
  );
  final GlobalKey _autocompleteKey = GlobalKey();
  List<Placemark> _autocompleteResults = [];
  List<Location> _autocompleteLocations = [];
  bool _showAutocomplete = false;
  bool _loadingRoute = false;
  double? _selectedDestLat;
  double? _selectedDestLng;
  bool _isMapSelectionMode = false;

  @override
  void initState() {
    super.initState();
    widget.formDestMapTapNotifier.addListener(_onMainMapTapped);
  }

  @override
  void dispose() {
    widget.formDestMapTapNotifier.removeListener(_onMainMapTapped);
    widget.formDestMapModeNotifier.value = false;
    widget.formDestPreviewNotifier.value = null;
    _destController.dispose();
    super.dispose();
  }

  void _onMainMapTapped() {
    final pos = widget.formDestMapTapNotifier.value;
    if (pos != null && mounted) {
      widget.formDestMapTapNotifier.value = null;
      _onSheetMapTapped(pos);
    }
  }

  /// Tap di peta utama untuk pilih lokasi tujuan
  Future<void> _onSheetMapTapped(LatLng position) async {
    setState(() {
      _selectedDestLat = position.latitude;
      _selectedDestLng = position.longitude;
      _destController.text = 'Memuat alamat...';
    });
    widget.formDestPreviewNotifier.value = position;
    if (mounted) {
      widget.mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(position, 15),
      );
    }
    await _reverseGeocodeDest(position);
  }

  Future<void> _reverseGeocodeDest(LatLng position) async {
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final displayText = PlacemarkFormatter.formatDetail(placemarks.first);
        if (mounted) {
          setState(() {
            _destController.text = displayText;
            _showAutocomplete = false;
            _autocompleteResults = [];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _destController.text =
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _destController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  Future<void> _onDestinationChanged(String value) async {
    if (value.isEmpty) {
      setState(() {
        _autocompleteResults = [];
        _autocompleteLocations = [];
        _showAutocomplete = false;
        _selectedDestLat = null;
        _selectedDestLng = null;
      });
      widget.formDestPreviewNotifier.value = null;
      return;
    }
    if (widget.driverLat == null || widget.driverLng == null) return;
    await Future.delayed(const Duration(milliseconds: 150));
    if (_destController.text != value) return;

    try {
      final config = DestinationAutocompleteConfig(
        buildQueries: (v) {
          final queries = <String>[];
          if (widget.sameProvinceOnly &&
              (widget.currentProvinsi ?? '').isNotEmpty) {
            queries.add('$v, ${widget.currentProvinsi}, Indonesia');
          } else if (widget.sameIslandOnly &&
              widget.provincesInIsland.isNotEmpty) {
            queries.add('$v, Indonesia');
          } else {
            if ((widget.currentProvinsi ?? '').isNotEmpty) {
              queries.add('$v, ${widget.currentProvinsi}, Indonesia');
            }
            queries.add('$v, Indonesia');
          }
          return queries;
        },
        sortByDistanceFrom: widget.driverLat != null && widget.driverLng != null
            ? LatLng(widget.driverLat!, widget.driverLng!)
            : null,
        filterProvincesInIsland: widget.sameIslandOnly &&
                widget.provincesInIsland.isNotEmpty
            ? widget.provincesInIsland
            : null,
        maxLocations: 20,
        maxCandidates: widget.sameIslandOnly ? 25 : 10,
        maxDisplayCount: 10,
      );
      final results = await DestinationAutocompleteService.search(
        value,
        config,
        isStillCurrent: () => mounted && _destController.text == value,
      );
      if (mounted && _destController.text == value) {
        final placemarks = results.map((r) => r.$1).toList();
        final locations = results.map((r) => r.$2).toList();
        setState(() {
          _autocompleteResults = placemarks;
          _autocompleteLocations = locations;
          _showAutocomplete = placemarks.isNotEmpty;
        });
        if (locations.isNotEmpty && widget.mapController != null && mounted) {
          widget.mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(locations.first.latitude, locations.first.longitude),
              14.0,
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autocompleteKey.currentContext != null) {
            Scrollable.ensureVisible(
              _autocompleteKey.currentContext!,
              alignment: 0.5,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {
      if (mounted && _destController.text == value) {
        setState(() {
          _autocompleteResults = [];
          _showAutocomplete = false;
        });
      }
    }
  }

  void _selectDestination(Placemark placemark, int index) {
    final displayText = PlacemarkFormatter.formatDetail(placemark);
    double? lat;
    double? lng;
    if (index >= 0 && index < _autocompleteLocations.length) {
      lat = _autocompleteLocations[index].latitude;
      lng = _autocompleteLocations[index].longitude;
    }
    setState(() {
      _destController.text = displayText;
      _showAutocomplete = false;
      _autocompleteResults = [];
      _autocompleteLocations = [];
      _selectedDestLat = lat;
      _selectedDestLng = lng;
    });
    if (lat != null && lng != null) {
      final pos = LatLng(lat, lng);
      widget.formDestPreviewNotifier.value = pos;
      if (mounted) {
        widget.mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(pos, 15),
        );
      }
    }
  }

  void _requestRoute() async {
    if (widget.driverLat == null || widget.driverLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi driver belum tersedia.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_destController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi tujuan perjalanan terlebih dahulu.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    double? destLat = _selectedDestLat;
    double? destLng = _selectedDestLng;
    if (destLat == null || destLng == null) {
      setState(() => _loadingRoute = true);
      try {
        final destLocations = await GeocodingService.locationFromAddress(
          '${_destController.text.trim()}, Indonesia',
          appendIndonesia: false,
        );
        if (destLocations.isEmpty) {
          if (mounted) {
            setState(() => _loadingRoute = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tujuan tidak ditemukan.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        final dest = destLocations.first;
        destLat = dest.latitude;
        destLng = dest.longitude;
      } catch (_) {
        if (mounted) {
          setState(() => _loadingRoute = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).failedToLoadRoute),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    final lat = widget.driverLat!;
    final lng = widget.driverLng!;
    setState(() => _loadingRoute = true);
    widget.onRouteRequest(
      lat,
      lng,
      widget.originText,
      destLat,
      destLng,
      _destController.text.trim(),
    );
    if (mounted) setState(() => _loadingRoute = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(bottom: context.responsive.spacing(24)),
          child: Padding(
            padding: EdgeInsets.all(context.responsive.spacing(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Rute Perjalanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Form 1: Asal (auto)
                Text(
                  'Dari (lokasi driver)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.originText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Form 2: Tujuan (ketik + autocomplete + Pilih di Map, seperti penumpang)
                Text(
                  'Tujuan',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (!_isMapSelectionMode &&
                    _showAutocomplete &&
                    _autocompleteResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      key: _autocompleteKey,
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 180
                          : 260,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _autocompleteResults.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        itemBuilder: (context, index) {
                          final p = _autocompleteResults[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              PlacemarkFormatter.formatDetail(p),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectDestination(p, index),
                          );
                        },
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destController,
                        decoration: InputDecoration(
                          hintText: _isMapSelectionMode
                              ? 'Tap di map untuk pilih lokasi'
                              : 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                          hintStyle: TextStyle(
                            color: _isMapSelectionMode
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            fontWeight: _isMapSelectionMode
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: _destController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    _destController.clear();
                                    setState(() {
                                      _autocompleteResults = [];
                                      _autocompleteLocations = [];
                                      _showAutocomplete = false;
                                      _selectedDestLat = null;
                                      _selectedDestLng = null;
                                      _isMapSelectionMode = false;
                                    });
                                    widget.formDestMapModeNotifier.value =
                                        false;
                                    widget.formDestPreviewNotifier.value = null;
                                  },
                                )
                              : null,
                        ),
                        enabled: !_isMapSelectionMode,
                        onChanged: (value) {
                          setState(() {});
                          _onDestinationChanged(value);
                        },
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _isMapSelectionMode
                            ? Icons.check_circle
                            : Icons.location_on,
                      ),
                      color: _isMapSelectionMode
                          ? Colors.blue.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      tooltip: _isMapSelectionMode
                          ? 'Selesai pilih lokasi'
                          : 'Pilih di Map',
                      onPressed: () {
                        setState(() {
                          _isMapSelectionMode = !_isMapSelectionMode;
                        });
                        widget.formDestMapModeNotifier.value =
                            _isMapSelectionMode;
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: _isMapSelectionMode
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                    ),
                  ],
                ),
                if (_isMapSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap di peta utama (bagian atas) untuk memilih lokasi tujuan',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadingRoute ? null : _requestRoute,
                  icon: const Icon(Icons.directions_car, size: 20),
                  label: const Text('Rute Perjalanan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (_loadingRoute)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
