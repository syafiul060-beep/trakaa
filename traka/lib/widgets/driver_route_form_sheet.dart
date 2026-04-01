import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/destination_autocomplete_service.dart';
import '../services/geocoding_service.dart' show GeocodingService, Location, Placemark;
import '../theme/responsive.dart';
import '../services/driver_route_map_pick_validation.dart';
import '../utils/placemark_formatter.dart';
import 'traka_pin_widgets.dart';
import 'map_destination_picker_screen.dart';
import 'traka_l10n_scope.dart';

/// Bottom sheet form: asal (auto), tujuan (autocomplete), tombol Rute Perjalanan.
/// Peta utama tetap dipakai untuk animasi kamera saat memilih dari autocomplete.
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

  /// Penjelasan singkat sesuai jenis rute (dalam provinsi / antar provinsi / seluruh Indonesia).
  final String? routeScopeSubtitle;

  /// Buka [MapDestinationPickerScreen]; hasil mengisi field tujuan (setelah lolos filter kategori).
  final PickDestinationOnMapCallback? onPickDestinationOnMap;

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
    required this.formDestPreviewNotifier,
    required this.onRouteRequest,
    this.routeScopeSubtitle,
    this.onPickDestinationOnMap,
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

  @override
  void dispose() {
    widget.formDestPreviewNotifier.value = null;
    _destController.dispose();
    super.dispose();
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
    await Future.delayed(const Duration(milliseconds: 80));
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
        filterSameProvinceAs: widget.sameProvinceOnly
            ? widget.currentProvinsi
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

  Future<void> _applyDestinationFromMap(MapPickerResult r) async {
    final l10n = TrakaL10n.of(context);
    final err = await DriverRouteMapPickValidation.validatePoint(
      l10n: l10n,
      lat: r.lat,
      lng: r.lng,
      isOrigin: false,
      sameProvinceOnly: widget.sameProvinceOnly,
      sameIslandOnly: widget.sameIslandOnly,
      currentProvinsi: widget.currentProvinsi,
      provincesInIsland: widget.provincesInIsland,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (widget.sameIslandOnly) {
      final err2 =
          await DriverRouteMapPickValidation.validateDestinationDifferentProvinceThan(
        l10n: l10n,
        destLat: r.lat,
        destLng: r.lng,
        referenceProvince: widget.currentProvinsi,
      );
      if (!mounted) return;
      if (err2 != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err2), behavior: SnackBarBehavior.floating),
        );
        return;
      }
    }
    setState(() {
      _destController.text = r.label;
      _showAutocomplete = false;
      _autocompleteResults = [];
      _autocompleteLocations = [];
      _selectedDestLat = r.lat;
      _selectedDestLng = r.lng;
    });
    widget.formDestPreviewNotifier.value = LatLng(r.lat, r.lng);
    widget.mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(r.lat, r.lng), 15),
    );
  }

  void _requestRoute() async {
    final l10nReq = TrakaL10n.of(context);
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
    final geoErr = await DriverRouteMapPickValidation.validatePoint(
      l10n: l10nReq,
      lat: destLat,
      lng: destLng,
      isOrigin: false,
      sameProvinceOnly: widget.sameProvinceOnly,
      sameIslandOnly: widget.sameIslandOnly,
      currentProvinsi: widget.currentProvinsi,
      provincesInIsland: widget.provincesInIsland,
    );
    if (!mounted) return;
    if (geoErr != null) {
      setState(() => _loadingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(geoErr), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (widget.sameIslandOnly) {
      final refProv = widget.currentProvinsi;
      final diffErr =
          await DriverRouteMapPickValidation.validateDestinationDifferentProvinceThan(
        l10n: l10nReq,
        destLat: destLat,
        destLng: destLng,
        referenceProvince: refProv,
      );
      if (!mounted) return;
      if (diffErr != null) {
        setState(() => _loadingRoute = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(diffErr),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    final lat = widget.driverLat!;
    final lng = widget.driverLng!;
    final originText = widget.originText;
    setState(() => _loadingRoute = true);
    widget.onRouteRequest(
      lat,
      lng,
      originText,
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
                if (widget.routeScopeSubtitle != null &&
                    widget.routeScopeSubtitle!.trim().isNotEmpty) ...[
                  SizedBox(height: context.responsive.spacing(8)),
                  Text(
                    widget.routeScopeSubtitle!.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: context.responsive.spacing(8)),
                Text(
                  TrakaL10n.of(context).driverRoutePassengerMatchingHint,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(16)),
                // Form 1: Asal = lokasi GPS (tidak dipilih di peta).
                Row(
                  children: [
                    const TrakaPinFormIcon(
                      variant: TrakaRoutePinVariant.origin,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dari (lokasi driver)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 2),
                  child: Text(
                    'Otomatis dari lokasi perangkat. Tidak perlu pilih di peta.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.88),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
                // Form 2: Tujuan (ketik + autocomplete)
                Row(
                  children: [
                    const TrakaPinFormIcon(
                      variant: TrakaRoutePinVariant.destination,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tujuan',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _destController,
                  scrollPadding: const EdgeInsets.only(bottom: 160),
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText:
                        'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _destController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 22),
                            tooltip: 'Hapus tujuan',
                            onPressed: () {
                              _destController.clear();
                              setState(() {
                                _autocompleteResults = [];
                                _autocompleteLocations = [];
                                _showAutocomplete = false;
                                _selectedDestLat = null;
                                _selectedDestLng = null;
                              });
                              widget.formDestPreviewNotifier.value = null;
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {});
                    _onDestinationChanged(value);
                  },
                  style: const TextStyle(fontSize: 14),
                ),
                if (widget.onPickDestinationOnMap != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      hint: TrakaL10n.of(context).pickOnMapTooltip,
                      child: Tooltip(
                        message: TrakaL10n.of(context).pickOnMapTooltip,
                        excludeFromSemantics: true,
                        child: TextButton.icon(
                          onPressed: _loadingRoute
                              ? null
                              : () async {
                                  final r =
                                      await widget.onPickDestinationOnMap!(
                                    destText: _destController.text,
                                    destLat: _selectedDestLat,
                                    destLng: _selectedDestLng,
                                  );
                                  if (!mounted || r == null) return;
                                  await _applyDestinationFromMap(r);
                                },
                          icon: const Icon(Icons.map_outlined, size: 20),
                          label: Text(
                            TrakaL10n.of(context).pickOnMapActionLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_showAutocomplete && _autocompleteResults.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: context.responsive.spacing(8),
                    ),
                    child: Container(
                      key: _autocompleteKey,
                      height: 200,
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
                        physics: const ClampingScrollPhysics(),
                        itemCount: _autocompleteResults.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        itemBuilder: (context, index) {
                          final p = _autocompleteResults[index];
                          return ListTile(
                            dense: true,
                            leading: const TrakaPinFormIcon(
                              variant: TrakaRoutePinVariant.destination,
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
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadingRoute ? null : _requestRoute,
                  icon: const Icon(Icons.directions_car, size: 20),
                  label: const Text('Rute Perjalanan'),
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
