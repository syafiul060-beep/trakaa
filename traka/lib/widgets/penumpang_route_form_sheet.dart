import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/destination_autocomplete_service.dart';
import '../services/geocoding_service.dart';
import '../services/recent_destination_service.dart';
import '../theme/app_theme.dart';
import '../utils/placemark_formatter.dart';
import 'traka_l10n_scope.dart';

/// Bottom sheet form pencarian penumpang (seperti form driver: di atas keyboard, pilihan muncul saat ketik).
class PenumpangRouteFormSheet extends StatefulWidget {
  const PenumpangRouteFormSheet({
    super.key,
    required this.originText,
    required this.currentKabupaten,
    required this.currentProvinsi,
    required this.currentPulau,
    required this.originLat,
    required this.originLng,
    this.initialDest,
    this.mapController,
    required this.onSearch,
    this.sheetTitle,
    this.primaryButtonLabel,
    this.primaryButtonIcon,
  });

  /// Judul sheet (default: pencarian tujuan di beranda).
  final String? sheetTitle;
  /// Label tombol utama (default: Cari).
  final String? primaryButtonLabel;
  final IconData? primaryButtonIcon;

  final String originText;
  final String? currentKabupaten;
  final String? currentProvinsi;
  final String? currentPulau;
  final double? originLat;
  final double? originLng;
  final String? initialDest;
  final GoogleMapController? mapController;
  final void Function(String destText, double destLat, double destLng) onSearch;

  @override
  State<PenumpangRouteFormSheet> createState() =>
      _PenumpangRouteFormSheetState();
}

class _PenumpangRouteFormSheetState extends State<PenumpangRouteFormSheet> {
  late final TextEditingController _destController =
      TextEditingController(text: widget.initialDest ?? '');
  final GlobalKey _autocompleteKey = GlobalKey();
  List<Placemark> _autocompleteResults = [];
  List<Location> _autocompleteLocations = [];
  bool _showAutocomplete = false;
  double? _selectedDestLat;
  double? _selectedDestLng;

  @override
  void dispose() {
    _destController.dispose();
    super.dispose();
  }

  Future<void> _onDestinationChanged(String value) async {
    if (value.isEmpty || value.trim().isEmpty) {
      setState(() {
        _autocompleteResults = [];
        _autocompleteLocations = [];
        _showAutocomplete = false;
        _selectedDestLat = null;
        _selectedDestLng = null;
      });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 50));
    if (_destController.text != value || value.trim().isEmpty) return;

    try {
      final config = DestinationAutocompleteConfig(
        buildQueries: (v) {
          final queries = <String>[];
          if ((widget.currentKabupaten ?? '').isNotEmpty) {
            queries.add('$v, ${widget.currentKabupaten}, Indonesia');
          }
          if ((widget.currentProvinsi ?? '').isNotEmpty &&
              widget.currentProvinsi != widget.currentKabupaten) {
            queries.add('$v, ${widget.currentProvinsi}, Indonesia');
          }
          if ((widget.currentPulau ?? '').isNotEmpty) {
            queries.add('$v, ${widget.currentPulau}, Indonesia');
          }
          queries.add('$v, Indonesia');
          return queries;
        },
        maxLocations: 10,
        maxCandidates: 8,
        maxDisplayCount: 8,
      );
      final results = await DestinationAutocompleteService.search(
        value,
        config,
        isStillCurrent: () =>
            mounted && _destController.text == value && value.trim().isNotEmpty,
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
      } else if (results.isEmpty && mounted && _destController.text == value) {
        setState(() {
          _autocompleteResults = [];
          _autocompleteLocations = [];
          _showAutocomplete = false;
        });
      }
    } catch (_) {
      if (mounted && _destController.text == value) {
        setState(() {
          _autocompleteResults = [];
          _autocompleteLocations = [];
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
  }

  void _requestSearch() {
    if (_destController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).fillDestinationFirst),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (widget.originLat == null || widget.originLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).waitingPassengerLocation),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    double? destLat = _selectedDestLat;
    double? destLng = _selectedDestLng;
    if (destLat == null || destLng == null) {
      GeocodingService.locationFromAddress(
            '${_destController.text.trim()}, Indonesia',
            appendIndonesia: false,
          )
          .then((locations) {
        if (locations.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(TrakaL10n.of(context).destinationNotFound),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        final loc = locations.first;
        widget.onSearch(
          _destController.text.trim(),
          loc.latitude,
          loc.longitude,
        );
      }).catchError((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).failedToFindDestination),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
      return;
    }
    widget.onSearch(
      _destController.text.trim(),
      destLat,
      destLng,
    );
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
          padding: const EdgeInsets.only(bottom: 24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.sheetTitle ?? 'Cari Tujuan Perjalanan',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  TrakaL10n.of(context).passengerRouteMatchExplanationShort,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Dari (lokasi Anda)',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                Text(
                  'Tujuan',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                if (_destController.text.trim().isEmpty)
                  FutureBuilder<List<RecentDestination>>(
                    future: RecentDestinationService.getList(),
                    builder: (context, snap) {
                      final list = snap.data ?? [];
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tujuan baru-baru ini',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: list.take(5).map((r) {
                                final colorScheme =
                                    Theme.of(context).colorScheme;
                                return ActionChip(
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  label: Text(
                                    r.text.length > 25
                                        ? '${r.text.substring(0, 25)}...'
                                        : r.text,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _destController.text = r.text;
                                      _selectedDestLat = r.lat;
                                      _selectedDestLng = r.lng;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                TextField(
                  controller: _destController,
                  autofocus: true,
                  scrollPadding: const EdgeInsets.only(bottom: 160),
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
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {});
                    _onDestinationChanged(value);
                  },
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                ),
                if (_showAutocomplete && _autocompleteResults.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.08),
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
                              color: AppTheme.primary,
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
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _requestSearch();
                  },
                  icon: Icon(widget.primaryButtonIcon ?? Icons.search, size: 20),
                  label: Text(widget.primaryButtonLabel ?? 'Cari'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
