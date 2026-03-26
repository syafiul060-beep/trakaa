import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/car_icon_service.dart';
import '../services/passenger_driver_car_icon.dart';
import '../services/geocoding_service.dart';
import '../services/route_utils.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide Cluster, ClusterManager;
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_logger.dart';
import '../widgets/traka_l10n_scope.dart';
import '../models/order_model.dart';
import '../services/active_drivers_service.dart';
import '../services/route_category_service.dart';
import '../theme/app_theme.dart';
import '../services/app_analytics_service.dart';
import '../services/locale_service.dart';
import '../services/favorite_driver_service.dart';
import '../services/location_service.dart';
import 'package:geolocator/geolocator.dart';
import '../services/map_style_service.dart';
import '../services/order_service.dart';
import '../widgets/passenger_duplicate_pending_order_dialog.dart'
    show
        PassengerDuplicatePendingChoice,
        passengerDuplicatePendingChoiceAnalyticsValue,
        showPassengerDuplicatePendingOrderDialog;
import '../widgets/styled_google_map_builder.dart';
import '../widgets/shimmer_loading.dart';
import 'chat_room_penumpang_screen.dart';

/// Item untuk cluster manager – wrap ActiveDriverRoute dengan ClusterItem.
class _DriverClusterItem with ClusterItem {
  _DriverClusterItem(this.driver);

  final ActiveDriverRoute driver;

  @override
  LatLng get location => LatLng(driver.driverLat, driver.driverLng);
}

/// Halaman Cari Travel: map + daftar driver dengan rute aktif.
/// Icon mobil + nama driver di map; klik icon → tombol Pesan Travel → Chat.
/// Setelah kirim permintaan → pending_agreement; driver & penumpang kesepakatan → nomor pesanan.
class CariTravelScreen extends StatefulWidget {
  const CariTravelScreen({
    super.key,
    this.prefillAsal,
    this.prefillTujuan,
    this.passengerOriginLat,
    this.passengerOriginLng,
    this.passengerDestLat,
    this.passengerDestLng,
  });

  final String? prefillAsal;
  final String? prefillTujuan;

  /// Koordinat asal/tujuan penumpang untuk filter driver di map (60 km / 10 km).
  final double? passengerOriginLat;
  final double? passengerOriginLng;
  final double? passengerDestLat;
  final double? passengerDestLng;

  @override
  State<CariTravelScreen> createState() => _CariTravelScreenState();
}

class _CariTravelScreenState extends State<CariTravelScreen> {
  List<ActiveDriverRoute> _drivers = [];
  bool _loading = true;
  String? _error;
  /// Filter kategori rute: null = Semua, atau dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  String? _categoryFilter;

  final _asalController = TextEditingController();
  final _tujuanController = TextEditingController();

  late ClusterManager<_DriverClusterItem> _clusterManager;
  Set<Marker> _clusterMarkers = {};
  GoogleMapController? _mapController;

  /// Icon mobil: traka_car_icons_premium (CarIconService).
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;
  PremiumPassengerCarIconSet? _premiumCarIcons;
  double _mapZoomForCarIcons = MapStyleService.searchZoom;
  int _carIconZoomBucket =
      CarIconService.passengerMapZoomBucket(MapStyleService.searchZoom);
  Timer? _carIconZoomDebounce;

  @override
  void initState() {
    super.initState();
    _asalController.text = widget.prefillAsal ?? '';
    _tujuanController.text = widget.prefillTujuan ?? '';
    _clusterManager = ClusterManager<_DriverClusterItem>(
      [],
      _onClusterMarkersUpdated,
      markerBuilder: _buildClusterMarker,
      stopClusteringZoom: 16.0,
    );
    _loadCarIcons();
    _loadDrivers();
  }

  Future<void> _loadCarIcons() async {
    if (!mounted) return;
    try {
      final premium = await CarIconService.loadPremiumPassengerCarIcons(
        context: context,
        baseSize: 12,
        padding: 4,
        mapZoom: _mapZoomForCarIcons,
      );
      if (!mounted) return;
      final result = await CarIconService.loadCarIcons(
        context: context,
        baseSize: 12,
        padding: 4,
        forPassenger: true,
        mapZoom: _mapZoomForCarIcons,
      );
      if (mounted) {
        setState(() {
          _premiumCarIcons = premium;
          _carIconRed = result.red;
          _carIconGreen = result.green;
        });
        _refreshClusterMarkers();
      }
    } catch (e, st) {
      logError('CariTravelScreen.initState mapController', e, st);
      if (mounted) setState(() {});
    }
  }

  List<ActiveDriverRoute> get _filteredDrivers {
    if (_categoryFilter == null) return _drivers;
    return _drivers.where((d) => d.routeCategory == _categoryFilter).toList();
  }

  void _refreshClusterMarkers() {
    final filtered = _filteredDrivers;
    if (filtered.isEmpty) {
      _clusterManager.setItems([]);
      return;
    }
    _clusterManager.setItems(
      filtered.map((d) => _DriverClusterItem(d)).toList(),
    );
  }

  void _onClusterMarkersUpdated(Set<Marker> markers) {
    if (mounted) setState(() => _clusterMarkers = markers);
  }

  Future<void> _onTravelMapCameraIdle() async {
    _clusterManager.updateMap();
    final ctrl = _mapController;
    if (!mounted || ctrl == null) return;
    final z = await ctrl.getZoomLevel();
    if (!mounted) return;
    final b = CarIconService.passengerMapZoomBucket(z);
    if (b == _carIconZoomBucket) return;
    _carIconZoomBucket = b;
    _mapZoomForCarIcons = z;
    _carIconZoomDebounce?.cancel();
    _carIconZoomDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) unawaited(_loadCarIcons());
    });
  }

  Future<Marker> _buildClusterMarker(Cluster<_DriverClusterItem> cluster) async {
    if (cluster.isMultiple) {
      final icon = await _buildClusterIcon(cluster.count.toString());
      return Marker(
        markerId: MarkerId(cluster.getId()),
        position: cluster.location,
        icon: icon,
        onTap: () {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(cluster.location, 17),
          );
        },
      );
    }
    final driver = cluster.items.first.driver;
    String? recommendedUid;
    if (widget.passengerOriginLat != null && widget.passengerOriginLng != null) {
      final sorted = List<ActiveDriverRoute>.from(_filteredDrivers);
      sorted.sort((a, b) {
        final da = Geolocator.distanceBetween(
          widget.passengerOriginLat!,
          widget.passengerOriginLng!,
          a.driverLat,
          a.driverLng,
        );
        final db = Geolocator.distanceBetween(
          widget.passengerOriginLat!,
          widget.passengerOriginLng!,
          b.driverLat,
          b.driverLng,
        );
        return da.compareTo(db);
      });
      if (sorted.isNotEmpty) recommendedUid = sorted.first.driverUid;
    }
    final icon = PassengerDriverMapCarIcon.pick(
      driver: driver,
      isMoving: driver.isMoving,
      recommendedDriverUid: recommendedUid,
      premium: _premiumCarIcons,
      legacyGreen: _carIconGreen,
      legacyRed: _carIconRed,
    );
    double bearing = 0;
    try {
      final driverPos = LatLng(driver.driverLat, driver.driverLng);
      final destPos = LatLng(driver.routeDestLat, driver.routeDestLng);
      bearing = RouteUtils.bearingBetween(driverPos, destPos);
    } catch (_) {}
    final rotation = CarIconService.markerRotationDegrees(
      bearing,
      premiumAssetFrontUp: _premiumCarIcons?.assetFrontFacesNorth ?? false,
    );
    return Marker(
      markerId: MarkerId(cluster.getId()),
      position: cluster.location,
      icon: icon,
      rotation: rotation,
      flat: defaultTargetPlatform != TargetPlatform.android,
      anchor: const Offset(0.5, 0.5),
      infoWindow: InfoWindow(
        title: driver.driverName ?? 'Driver',
        snippet: driver.routeDestText.isNotEmpty ? driver.routeDestText : null,
      ),
      onTap: () => _showPesanTravelSheet(driver),
    );
  }

  Future<BitmapDescriptor> _buildClusterIcon(String text) async {
    const size = 120;
    final s = kIsWeb ? (size / 2).floor() : size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const color = Color(0xFF2196F3); // Biru Traka
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2.0, Paint()..color = color);
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2.2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2.8, Paint()..color = color);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: s / 3,
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(s / 2 - painter.width / 2, s / 2 - painter.height / 2),
    );
    final img = await recorder.endRecording().toImage(s, s);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
    return BitmapDescriptor.bytes(data.buffer.asUint8List());
  }

  @override
  void dispose() {
    _carIconZoomDebounce?.cancel();
    _asalController.dispose();
    _tujuanController.dispose();
    super.dispose();
  }

  /// Sama dengan batas driver di map beranda (mode Driver sekitar).
  static const int _maxNearbyDriversOnMap = 15;

  Future<void> _loadDrivers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      double? destLat = widget.passengerDestLat;
      double? destLng = widget.passengerDestLng;
      double? originLat = widget.passengerOriginLat;
      double? originLng = widget.passengerOriginLng;

      final originText = _asalController.text.trim();
      final destText = _tujuanController.text.trim();

      if ((originLat == null || originLng == null) && originText.isNotEmpty) {
        try {
          final list = await GeocodingService.locationFromAddress(originText);
          if (list.isNotEmpty) {
            originLat = list.first.latitude;
            originLng = list.first.longitude;
          }
        } catch (_) {}
      }
      if ((destLat == null || destLng == null) && destText.isNotEmpty) {
        try {
          final list = await GeocodingService.locationFromAddress(destText);
          if (list.isNotEmpty) {
            destLat = list.first.latitude;
            destLng = list.first.longitude;
          }
        } catch (_) {}
      }

      final originGeocodeFailed =
          originText.isNotEmpty && (originLat == null || originLng == null);
      final destGeocodeFailed =
          destText.isNotEmpty && (destLat == null || destLng == null);

      // Mode rute: keempat koordinat harus ada (polyline + RouteUtils).
      // Selain itu: mode sekitar — radius 40 km dari GPS, tanpa Directions.
      final bool hasFullRoute = originLat != null &&
          originLng != null &&
          destLat != null &&
          destLng != null;

      List<ActiveDriverRoute> list;
      if (hasFullRoute) {
        list = await ActiveDriversService.getActiveDriversForMap(
          passengerOriginLat: originLat,
          passengerOriginLng: originLng,
          passengerDestLat: destLat,
          passengerDestLng: destLng,
        );
      } else {
        final all = await ActiveDriversService.getActiveDriverRoutes();
        final pos = await LocationService.getCurrentPosition();
        if (pos != null) {
          list = ActiveDriversService.filterByDistanceFromCenter(
            all,
            pos.latitude,
            pos.longitude,
          );
          list.sort((a, b) {
            final distA = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              a.driverLat,
              a.driverLng,
            );
            final distB = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              b.driverLat,
              b.driverLng,
            );
            return distA.compareTo(distB);
          });
        } else {
          list = all;
        }
        if (list.length > _maxNearbyDriversOnMap) {
          list = list.take(_maxNearbyDriversOnMap).toList();
        }
      }
      if (mounted) {
        setState(() {
          _drivers = list;
          _loading = false;
        });
        _refreshClusterMarkers();
        if (!hasFullRoute && (originGeocodeFailed || destGeocodeFailed)) {
          final l10n = TrakaL10n.of(context);
          final parts = <String>[];
          if (originGeocodeFailed) parts.add(l10n.cariTravelGeocodeOriginFailed);
          if (destGeocodeFailed) parts.add(l10n.cariTravelGeocodeDestFailed);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(parts.join('\n')),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, st) {
      logError('CariTravelScreen._loadDrivers', e, st);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        _clusterManager.setItems([]);
      }
    }
  }

  Future<void> _onPesanTravel(
    ActiveDriverRoute driver, {
    bool bypassDuplicatePendingTravel = false,
  }) async {
    if (!mounted) return;
    Navigator.pop(context);
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!bypassDuplicatePendingTravel) {
      final pendingT = await OrderService.getPassengerPendingTravelWithDriver(
        user.uid,
        driver.driverUid,
      );
      if (!mounted) return;
      if (pendingT != null) {
        final l10n = TrakaL10n.of(context);
        final choice = await showPassengerDuplicatePendingOrderDialog(
          context,
          title: l10n.passengerPendingTravelDuplicateTitle,
          body: l10n.passengerPendingTravelDuplicateBody,
        );
        if (!mounted) return;
        AppAnalyticsService.logPassengerDuplicatePendingDialog(
          orderKind: 'travel',
          choice: passengerDuplicatePendingChoiceAnalyticsValue(choice),
          surface: 'cari_travel',
        );
        if (choice == null ||
            choice == PassengerDuplicatePendingChoice.cancel) {
          return;
        }
        if (choice == PassengerDuplicatePendingChoice.openExisting) {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatRoomPenumpangScreen(
                orderId: pendingT.id,
                driverUid: driver.driverUid,
                driverName: driver.driverName ?? 'Driver',
                driverPhotoUrl: driver.driverPhotoUrl,
                driverVerified: driver.isVerified,
              ),
            ),
          );
          return;
        }
        if (choice == PassengerDuplicatePendingChoice.forceNew) {
          await _onPesanTravel(driver, bypassDuplicatePendingTravel: true);
        }
        return;
      }
    }

    String? passengerName;
    String? passengerPhotoUrl;
    String? passengerAppLocale;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final d = userDoc.data()!;
        passengerName = d['displayName'] as String?;
        passengerPhotoUrl = d['photoUrl'] as String?;
        passengerAppLocale = (d['appLocale'] as String?) ?? (LocaleService.current == AppLocale.id ? 'id' : 'en');
      } else {
        passengerAppLocale = LocaleService.current == AppLocale.id ? 'id' : 'en';
      }
    } catch (_) {
      passengerAppLocale = LocaleService.current == AppLocale.id ? 'id' : 'en';
    }
    passengerName ??= user.email ?? 'Penumpang';

    final asal = _asalController.text.trim().isEmpty
        ? 'Lokasi penjemputan'
        : _asalController.text.trim();
    final tujuan = _tujuanController.text.trim().isEmpty
        ? 'Tujuan'
        : _tujuanController.text.trim();

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driver.driverUid,
      routeJourneyNumber: driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerAppLocale: passengerAppLocale,
      originText: asal,
      destText: tujuan,
      originLat: null,
      originLng: null,
      destLat: null,
      destLng: null,
      bypassDuplicatePendingTravel: bypassDuplicatePendingTravel,
    );

    if (!mounted) return;
    AppAnalyticsService.logOrderCreated(
      orderType: OrderModel.typeTravel,
      success: orderId != null,
    );
    if (orderId != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomPenumpangScreen(
            orderId: orderId,
            driverUid: driver.driverUid,
            driverName: driver.driverName ?? 'Driver',
            driverPhotoUrl: driver.driverPhotoUrl,
            driverVerified: driver.isVerified,
          ),
        ),
      );
      if (bypassDuplicatePendingTravel) {
        _showNewSplitOrderThreadSnackCariTravel();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).failedToCreateOrderTryAgain),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showNewSplitOrderThreadSnackCariTravel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).passengerNewOrderThreadSnack),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  void _onSelectDriver(ActiveDriverRoute driver) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: _RequestFormSheet(
              driver: driver,
              asalController: _asalController,
              tujuanController: _tujuanController,
              onSubmitted: ({bool newThreadFromDuplicate = false}) {
                Navigator.pop(ctx);
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  SnackBar(
                    content:
                        Text(TrakaL10n.of(context).requestSentWaitingDriver),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                if (newThreadFromDuplicate) {
                  Future<void>.delayed(const Duration(milliseconds: 500), () {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          TrakaL10n.of(context).passengerNewOrderThreadSnack,
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  });
                }
              },
            ),
          ),
        );
      },
    );
  }

  static Color _routeCategoryColor(String category) {
    switch (category) {
      case RouteCategoryService.categoryDalamKota:
        return Colors.green.shade700;
      case RouteCategoryService.categoryAntarKabupaten:
        return Colors.teal.shade700;
      case RouteCategoryService.categoryAntarProvinsi:
        return Colors.blue.shade700;
      case RouteCategoryService.categoryNasional:
        return Colors.orange.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  void _showPesanTravelSheet(ActiveDriverRoute driver) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (driver.driverPhotoUrl != null &&
                            driver.driverPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(driver.driverPhotoUrl!)
                        : null,
                    child:
                        (driver.driverPhotoUrl == null ||
                            driver.driverPhotoUrl!.isEmpty)
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.driverName ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (driver.averageRating != null && driver.reviewCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '${driver.averageRating!.toStringAsFixed(1)} (${driver.reviewCount} ulasan)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          'Tujuan: ${driver.routeDestText.isNotEmpty ? driver.routeDestText : "-"}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: FutureBuilder<
                              ({String category, String label, String estimatedDuration})>(
                            future: RouteCategoryService.getRouteCategory(
                              originLat: driver.routeOriginLat,
                              originLng: driver.routeOriginLng,
                              destLat: driver.routeDestLat,
                              destLng: driver.routeDestLng,
                            ),
                            builder: (context, snap) {
                              if (!snap.hasData) return const SizedBox.shrink();
                              final data = snap.data!;
                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _routeCategoryColor(data.category)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      data.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: _routeCategoryColor(data.category),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    data.estimatedDuration,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        if (driver.remainingPassengerCapacity != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              driver.hasPassengerCapacity
                                  ? 'Sisa ${driver.remainingPassengerCapacity} kursi'
                                  : 'Penuh',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: driver.hasPassengerCapacity
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: driver.hasPassengerCapacity
                    ? () => _onPesanTravel(driver)
                    : null,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(
                  driver.hasPassengerCapacity ? 'Pesan Travel' : 'Kursi penuh',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: driver.hasPassengerCapacity
                    ? () {
                        Navigator.pop(ctx);
                        _onSelectDriver(driver);
                      }
                    : null,
                icon: const Icon(Icons.send),
                label: const Text('Kirim permintaan (form asal/tujuan)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverList() {
    final filtered = _filteredDrivers;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildDriverCard(context, filtered[index], {}),
      );
    }
    return StreamBuilder<List<String>>(
      stream: FavoriteDriverService.streamFavoriteDriverIds(user.uid),
      builder: (context, snap) {
        final favSet = (snap.data ?? []).toSet();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          cacheExtent: 200,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final d = filtered[index];
            return _buildDriverCard(context, d, favSet);
          },
        );
      },
    );
  }

  Widget _buildDriverCard(BuildContext context, ActiveDriverRoute d, Set<String> favIds) {
    final user = FirebaseAuth.instance.currentUser;
    final isFav = user != null && favIds.contains(d.driverUid);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          backgroundImage: (d.driverPhotoUrl != null && d.driverPhotoUrl!.isNotEmpty)
              ? CachedNetworkImageProvider(d.driverPhotoUrl!)
              : null,
          child: (d.driverPhotoUrl == null || d.driverPhotoUrl!.isEmpty)
              ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                d.driverName ?? 'Driver',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (user != null)
              IconButton(
                icon: Icon(isFav ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 22),
                onPressed: () async {
                  await FavoriteDriverService.toggleFavorite(user.uid, d.driverUid, isFav);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            if (d.averageRating != null && d.reviewCount > 0)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(d.averageRating!.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text('Dari: ${d.routeOriginText.isNotEmpty ? d.routeOriginText : "-"}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Tujuan: ${d.routeDestText.isNotEmpty ? d.routeDestText : "-"}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (d.remainingPassengerCapacity != null)
              Text(d.hasPassengerCapacity ? 'Sisa ${d.remainingPassengerCapacity} kursi' : 'Penuh', style: TextStyle(fontSize: 12, color: d.hasPassengerCapacity ? Colors.green.shade700 : Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _onSelectDriver(d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Travel'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: ShimmerLoading())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _loadDrivers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            )
          : _drivers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada driver dengan rute aktif',
                      style: TextStyle(
                        fontSize: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Driver yang sedang "Siap Kerja" dengan rute akan muncul di sini.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Semua'),
                        selected: _categoryFilter == null,
                        onSelected: (_) => setState(() {
                          _categoryFilter = null;
                          _refreshClusterMarkers();
                        }),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(RouteCategoryService.getLabel(RouteCategoryService.categoryDalamKota)),
                        selected: _categoryFilter == RouteCategoryService.categoryDalamKota,
                        onSelected: (_) => setState(() {
                          _categoryFilter = RouteCategoryService.categoryDalamKota;
                          _refreshClusterMarkers();
                        }),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(RouteCategoryService.getLabel(RouteCategoryService.categoryAntarKabupaten)),
                        selected: _categoryFilter == RouteCategoryService.categoryAntarKabupaten,
                        onSelected: (_) => setState(() {
                          _categoryFilter = RouteCategoryService.categoryAntarKabupaten;
                          _refreshClusterMarkers();
                        }),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(RouteCategoryService.getLabel(RouteCategoryService.categoryAntarProvinsi)),
                        selected: _categoryFilter == RouteCategoryService.categoryAntarProvinsi,
                        onSelected: (_) => setState(() {
                          _categoryFilter = RouteCategoryService.categoryAntarProvinsi;
                          _refreshClusterMarkers();
                        }),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(RouteCategoryService.getLabel(RouteCategoryService.categoryNasional)),
                        selected: _categoryFilter == RouteCategoryService.categoryNasional,
                        onSelected: (_) => setState(() {
                          _categoryFilter = RouteCategoryService.categoryNasional;
                          _refreshClusterMarkers();
                        }),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                SizedBox(
                  height: 220,
                  child: ClipRect(
                    child: StyledGoogleMapBuilder(
                      builder: (style, _) => GoogleMap(
                        buildingsEnabled: true,
                        indoorViewEnabled: true,
                        mapToolbarEnabled: false,
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            (_filteredDrivers.isNotEmpty ? _filteredDrivers.first : _drivers.first).driverLat,
                            (_filteredDrivers.isNotEmpty ? _filteredDrivers.first : _drivers.first).driverLng,
                          ),
                          zoom: MapStyleService.searchZoom,
                          tilt: MapStyleService.defaultTilt,
                        ),
                        style: style,
                        markers: _clusterMarkers,
                        myLocationEnabled: true,
                        zoomControlsEnabled: false,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          _clusterManager.setMapId(controller.mapId);
                          _clusterManager.updateMap();
                          unawaited(_onTravelMapCameraIdle());
                        },
                        onCameraMove: _clusterManager.onCameraMove,
                        onCameraIdle: () => unawaited(_onTravelMapCameraIdle()),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Klik icon mobil di map → Pesan Travel atau kirim permintaan',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadDrivers,
                    child: _buildDriverList(),
                  ),
                ),
              ],
            ),
    );
  }
}

class _RequestFormSheet extends StatefulWidget {
  const _RequestFormSheet({
    required this.driver,
    required this.asalController,
    required this.tujuanController,
    required this.onSubmitted,
  });

  final ActiveDriverRoute driver;
  final TextEditingController asalController;
  final TextEditingController tujuanController;
  final void Function({bool newThreadFromDuplicate}) onSubmitted;

  @override
  State<_RequestFormSheet> createState() => _RequestFormSheetState();
}

class _RequestFormSheetState extends State<_RequestFormSheet> {
  bool _sending = false;

  Future<void> _submit({bool bypassDuplicatePendingTravel = false}) async {
    final asal = widget.asalController.text.trim();
    final tujuan = widget.tujuanController.text.trim();
    if (asal.isEmpty || tujuan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).fillOriginAndDestination),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!widget.driver.hasPassengerCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).driverSeatsFull),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!bypassDuplicatePendingTravel) {
      final pendingT = await OrderService.getPassengerPendingTravelWithDriver(
        user.uid,
        widget.driver.driverUid,
      );
      if (!mounted) return;
      if (pendingT != null) {
        final l10n = TrakaL10n.of(context);
        final choice = await showPassengerDuplicatePendingOrderDialog(
          context,
          title: l10n.passengerPendingTravelDuplicateTitle,
          body: l10n.passengerPendingTravelDuplicateBody,
        );
        if (!mounted) return;
        AppAnalyticsService.logPassengerDuplicatePendingDialog(
          orderKind: 'travel',
          choice: passengerDuplicatePendingChoiceAnalyticsValue(choice),
          surface: 'cari_travel_request_form',
        );
        if (choice == null ||
            choice == PassengerDuplicatePendingChoice.cancel) {
          return;
        }
        if (choice == PassengerDuplicatePendingChoice.openExisting) {
          Navigator.pop(context);
          if (!mounted) return;
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatRoomPenumpangScreen(
                orderId: pendingT.id,
                driverUid: widget.driver.driverUid,
                driverName: widget.driver.driverName ?? 'Driver',
                driverPhotoUrl: widget.driver.driverPhotoUrl,
                driverVerified: widget.driver.isVerified,
              ),
            ),
          );
          return;
        }
        if (choice == PassengerDuplicatePendingChoice.forceNew) {
          await _submit(bypassDuplicatePendingTravel: true);
        }
        return;
      }
    }

    setState(() => _sending = true);
    try {
      String? passengerName;
      String? passengerPhotoUrl;
      String? passengerAppLocale;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final d = userDoc.data()!;
        passengerName = d['displayName'] as String?;
        passengerPhotoUrl = d['photoUrl'] as String?;
        passengerAppLocale = (d['appLocale'] as String?) ?? (LocaleService.current == AppLocale.id ? 'id' : 'en');
      } else {
        passengerAppLocale = LocaleService.current == AppLocale.id ? 'id' : 'en';
      }
      passengerName ??= user.email ?? 'Penumpang';

      final orderId = await OrderService.createOrder(
        passengerUid: user.uid,
        driverUid: widget.driver.driverUid,
        routeJourneyNumber: widget.driver.routeJourneyNumber,
        passengerName: passengerName,
        passengerPhotoUrl: passengerPhotoUrl,
        passengerAppLocale: passengerAppLocale,
        originText: asal,
        destText: tujuan,
        originLat: null,
        originLng: null,
        destLat: null,
        destLng: null,
        bypassDuplicatePendingTravel: bypassDuplicatePendingTravel,
      );
      if (mounted) {
        AppAnalyticsService.logOrderCreated(
          orderType: OrderModel.typeTravel,
          success: orderId != null,
        );
      }
      if (orderId != null && mounted) {
        widget.onSubmitted(
          newThreadFromDuplicate: bypassDuplicatePendingTravel,
        );
      }
    } catch (e, st) {
      logError('CariTravelScreen._RequestFormSheet._submit', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).failedToSendDetail(e)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TrakaL10n.of(context).sendRequestTo(widget.driver.driverName ?? 'driver'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (widget.driver.remainingPassengerCapacity != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.driver.hasPassengerCapacity
                      ? 'Sisa ${widget.driver.remainingPassengerCapacity} kursi'
                      : 'Kursi penuh – tidak dapat mengirim permintaan travel.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.driver.hasPassengerCapacity
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.asalController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Dari (asal Anda)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.tujuanController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Tujuan',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_sending || !widget.driver.hasPassengerCapacity)
                  ? null
                  : _submit,
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _sending
                    ? 'Mengirim...'
                    : (widget.driver.hasPassengerCapacity
                          ? 'Kirim permintaan'
                          : 'Kursi penuh'),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
