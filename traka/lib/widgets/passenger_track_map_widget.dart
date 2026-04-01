import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../config/app_constants.dart';
import '../services/car_icon_service.dart';
import '../services/map_style_service.dart';
import '../services/driver_status_service.dart';
import '../services/geocoding_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../theme/app_theme.dart';
import '../services/directions_service.dart';
import 'traka_l10n_scope.dart';
import '../services/ferry_distance_service.dart';
import '../services/camera_follow_engine.dart';
import '../services/route_utils.dart';
import '../services/traka_pin_bitmap_service.dart';
import '../utils/time_formatter.dart';
import '../utils/app_logger.dart';
import 'driver_map_overlays.dart';
import 'styled_google_map_builder.dart';

/// Widget map untuk Lacak Driver / Lacak Barang dengan pergerakan halus (semut)
/// dan snap-to-road. Polyline rute di-fetch via Directions API.
class PassengerTrackMapWidget extends StatefulWidget {
  const PassengerTrackMapWidget({
    super.key,
    required this.order,
    required this.driverUid,
  required this.originLat,
  required this.originLng,
  required this.destLat,
  required this.destLng,
  required this.destForDistanceLat,
  required this.destForDistanceLng,
  required this.bottomBuilder,
    this.extraMarkers,
    this.enableFerryDetection = false,
    this.showSOS = true,
    this.onSOS,
    this.useDualPartyBoundsCamera = false,
    this.dualPartyFocalLat = 0,
    this.dualPartyFocalLng = 0,
  });

  final OrderModel order;
  final String driverUid;
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final double destForDistanceLat;
  final double destForDistanceLng;
  final Widget Function(
    LatLng driverPosition,
    bool isMoving,
    double? distanceMeters,
    String distanceText,
    String etaText,
    String? driverLocationText,
    FerryStatus? ferryStatus,
  ) bottomBuilder;
  final Set<Marker> Function(LatLng driverPosition)? extraMarkers;
  final bool showSOS;
  final VoidCallback? onSOS;
  /// Jika true (Lacak Barang), deteksi otomatis driver di kapal laut.
  final bool enableFerryDetection;

  /// Kamera mem-framing driver + titik pendamping (penumpang / pengirim / penerima), bukan chase cam mengarah depan mobil.
  final bool useDualPartyBoundsCamera;
  /// Koordinat titik kedua untuk framing (penumpang di travel; pengirim atau penerima di kirim barang sesuai fase).
  final double dualPartyFocalLat;
  final double dualPartyFocalLng;

  @override
  State<PassengerTrackMapWidget> createState() => _PassengerTrackMapWidgetState();
}

class _PassengerTrackMapWidgetState extends State<PassengerTrackMapWidget>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  final CameraFollowEngine _cameraFollowEngine = CameraFollowEngine();
  StreamSubscription<Map<String, dynamic>?>? _driverSub;
  List<LatLng>? _routePolyline;
  LatLng? _displayedPosition;
  LatLng? _targetPosition;
  int _interpEndSeg = -1;
  double _interpEndRatio = 0;
  double _interpolationProgress = 0;
  Timer? _interpolationTimer;
  Timestamp? _lastUpdated;
  double _displayedBearing = 0;
  double _smoothedBearing = 0;
  static const double _trackingTilt = 58.0;
  static const double _trackingZoom = 18.0;
  /// Offset ala Grab: mobil selalu terlihat. Sinkron dengan driver (120-320m).
  static const double _cameraOffsetAheadMeters = 220.0;
  static const double _bearingHysteresisDeg = 18.0;
  static const double _bearingSmoothAlpha = 0.025;
  String? _driverLocationText;
  bool _noDriverStatus = false;
  bool _invalidCoordinates = false;
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;
  PremiumPassengerCarIconSet? _premiumCarIcons;
  /// Diselaraskan dengan [_trackingZoom] sebagai zoom kerja map lacak.
  double _mapZoomForCarIcons = 18.0;
  int _carIconZoomBucket = CarIconService.passengerMapZoomBucket(18.0);
  Timer? _carIconZoomDebounce;
  BitmapDescriptor? _shipIcon;
  FerryStatus? _ferryStatus;
  DateTime? _lastFerryCheckAt;
  bool _connectionError = false;
  static const int _movingThresholdSeconds =
      AppConstants.penumpangIsMovingThresholdSeconds;
  static const int _ferryCheckDebounceSeconds = 8;
  static const int _staleDataSeconds = 60;
  /// Jarak minimal (m) driver bergerak sebelum re-fetch rute (hemat API).
  static const double _routeRefetchDistanceMeters = 200.0;
  /// Interval minimal (detik) antar re-fetch rute.
  static const int _routeRefetchIntervalSeconds = 30;
  LatLng? _lastRouteFetchOrigin;
  DateTime? _lastRouteFetchAt;
  /// Untuk ETA dinamis: posisi & waktu terakhir (hitung kecepatan aktual).
  LatLng? _lastPositionForSpeed;
  DateTime? _lastPositionTime;
  /// Kecepatan estimasi (km/jam) dari pergerakan terakhir. Null = pakai default 40.
  double? _estimatedSpeedKmh;
  bool _isRefreshing = false;
  /// Target kamera terakhir yang berhasil di-animate (disinkronkan dengan engine).
  LatLng? _lastCameraTarget;
  /// Kamera mengikuti driver. False = user pan/zoom manual, tampilkan tombol Fokus.
  bool _cameraTrackingEnabled = true;
  /// Abaikan onCameraMoveStarted berikutnya (dari animateCamera programatik).
  bool _suppressNextCameraMoveStarted = false;
  Timer? _dualPartyFitDebounce;
  DateTime? _lastDualPartyFitAt;
  LatLng? _viewerLocation;
  StreamSubscription<Position>? _viewerPosSub;

  bool _routeCoordUsable(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat != 0 || lng != 0;
  }

  Future<void> _startViewerLocationStream() async {
    if (!mounted) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final current = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _viewerLocation = LatLng(current.latitude, current.longitude);
      });
      await _viewerPosSub?.cancel();
      _viewerPosSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          distanceFilter: 12,
          accuracy: LocationAccuracy.medium,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() {
          _viewerLocation = LatLng(p.latitude, p.longitude);
        });
      });
    } catch (_) {}
  }

  void _focusOnCar() {
    _cameraFollowEngine.resetThrottle();
    _lastCameraTarget = null;
    setState(() => _cameraTrackingEnabled = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.useDualPartyBoundsCamera) {
        _fitDualPartyBounds(force: true);
      } else {
        _syncCameraFollow(force: true);
      }
    });
  }

  bool _dualPartyFocalValid() {
    final lat = widget.dualPartyFocalLat;
    final lng = widget.dualPartyFocalLng;
    return (lat.abs() > 1e-7 || lng.abs() > 1e-7) &&
        lat.isFinite &&
        lng.isFinite;
  }

  void _scheduleDualPartyFit() {
    if (!widget.useDualPartyBoundsCamera ||
        !_cameraTrackingEnabled ||
        !_dualPartyFocalValid()) {
      return;
    }
    _dualPartyFitDebounce?.cancel();
    _dualPartyFitDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _fitDualPartyBounds(force: false);
    });
  }

  void _fitDualPartyBounds({required bool force}) {
    if (!widget.useDualPartyBoundsCamera || !_dualPartyFocalValid()) return;
    final c = _mapController;
    if (c == null || !mounted || !_cameraTrackingEnabled) return;
    final driver = _displayedPosition ?? _targetPosition;
    if (driver == null) return;

    if (!force &&
        _lastDualPartyFitAt != null &&
        DateTime.now().difference(_lastDualPartyFitAt!) <
            const Duration(milliseconds: 350)) {
      return;
    }
    _lastDualPartyFitAt = DateTime.now();

    LatLng other = LatLng(widget.dualPartyFocalLat, widget.dualPartyFocalLng);
    var minLat = math.min(driver.latitude, other.latitude);
    var maxLat = math.max(driver.latitude, other.latitude);
    var minLng = math.min(driver.longitude, other.longitude);
    var maxLng = math.max(driver.longitude, other.longitude);
    const pad = 0.00035;
    if ((maxLat - minLat).abs() < pad) {
      minLat -= pad;
      maxLat += pad;
    }
    if ((maxLng - minLng).abs() < pad) {
      minLng -= pad;
      maxLng += pad;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _suppressNextCameraMoveStarted = true;
    unawaited(() async {
      try {
        await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 88));
      } catch (_) {}
    }());
  }

  /// Chase cam: sama sumber dengan marker interpolasi — bukan dari [build] tiap frame.
  void _syncCameraFollow({bool force = false}) {
    if (widget.useDualPartyBoundsCamera) return;
    if (!mounted || _mapController == null || !_cameraTrackingEnabled) return;
    final pos = _displayedPosition ?? _targetPosition;
    if (pos == null) return;

    final polyline = _routePolyline;
    final cameraTarget = (polyline != null && polyline.length >= 2)
        ? RouteUtils.pointAheadOnPolyline(
            pos,
            polyline,
            _cameraOffsetAheadMeters,
            maxDistanceMeters: 400,
          )
        : null;
    final target = cameraTarget ??
        RouteUtils.offsetPoint(
          pos,
          _smoothedBearing,
          80.0,
        );

    final cameraMoveDistanceM = _lastCameraTarget != null
        ? Geolocator.distanceBetween(
            _lastCameraTarget!.latitude,
            _lastCameraTarget!.longitude,
            target.latitude,
            target.longitude,
          )
        : 999.0;

    if (!force && cameraMoveDistanceM < 5) {
      _lastCameraTarget = target;
      return;
    }

    final preferredDuration = _cameraDurationForDistance(cameraMoveDistanceM);
    _suppressNextCameraMoveStarted = true;
    final scheduled = _cameraFollowEngine.tryAnimateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          bearing: _smoothedBearing,
          tilt: _trackingTilt,
          zoom: _trackingZoom,
        ),
      ),
      duration: preferredDuration,
      force: force,
    );
    if (scheduled) {
      _lastCameraTarget = target;
    }
  }

  /// Durasi animasi kamera: proporsional dengan jarak perpindahan.
  static Duration _cameraDurationForDistance(double distanceMeters) {
    if (distanceMeters <= 0) return const Duration(milliseconds: 200);
    final ms = (200 + (distanceMeters / 200) * 600).round().clamp(200, 800);
    return Duration(milliseconds: ms);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCarIcons();
    _loadShipIcon();
    _driverSub = DriverStatusService.streamDriverStatusData(widget.driverUid).listen(
      _onDriverStatus,
      onError: (e) {
        if (mounted) setState(() => _connectionError = true);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        await TrakaPinBitmapService.ensureLoaded(context);
        if (mounted) setState(() {});
      }());
      unawaited(_startViewerLocationStream());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driverSub?.cancel();
    _interpolationTimer?.cancel();
    _carIconZoomDebounce?.cancel();
    _dualPartyFitDebounce?.cancel();
    _viewerPosSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PassengerTrackMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final destChanged =
        oldWidget.destForDistanceLat != widget.destForDistanceLat ||
            oldWidget.destForDistanceLng != widget.destForDistanceLng;
    if (destChanged) {
      setState(() {
        _routePolyline = null;
        _lastRouteFetchOrigin = null;
        _lastRouteFetchAt = null;
      });
    }
    final dualFocalChanged = widget.useDualPartyBoundsCamera &&
        (oldWidget.dualPartyFocalLat != widget.dualPartyFocalLat ||
            oldWidget.dualPartyFocalLng != widget.dualPartyFocalLng ||
            oldWidget.useDualPartyBoundsCamera != widget.useDualPartyBoundsCamera);

    if (destChanged || dualFocalChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (destChanged) {
          final pos = _displayedPosition ?? _targetPosition;
          if (pos != null) {
            unawaited(_fetchRouteFromDriver(pos.latitude, pos.longitude));
          }
        }
        if (widget.useDualPartyBoundsCamera &&
            (destChanged || dualFocalChanged)) {
          _fitDualPartyBounds(force: true);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _pullLatestDriverStatusOnResume();
    }
  }

  /// Setelah multitasking/background, Firestore stream bisa tertunda — ambil snapshot sekali.
  Future<void> _pullLatestDriverStatusOnResume() async {
    if (!mounted) return;
    try {
      final d = await DriverStatusService.fetchDriverStatusOnce(widget.driverUid);
      if (mounted) _onDriverStatus(d);
    } catch (_) {}
  }

  Future<void> _syncCarIconsZoomFromMap() async {
    final c = _mapController;
    if (!mounted || c == null) return;
    final z = await c.getZoomLevel();
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

  /// Premium + legacy untuk marker lacak; ukuran mengikuti zoom peta.
  Future<void> _loadCarIcons() async {
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
        _premiumCarIcons = premium;
        _carIconRed = result.red;
        _carIconGreen = result.green;
        setState(() {});
      }
    } catch (_) {
      _carIconRed = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      _carIconGreen = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadShipIcon() async {
    try {
      _shipIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(56, 56)),
        'assets/images/ship_icon.png',
      );
    } catch (_) {
      _shipIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }
    if (mounted) setState(() {});
  }

  /// Fetch rute dari posisi driver ke titik [destForDistance] (penumpang/pengirim/penerima sesuai layar & fase).
  Future<void> _fetchRouteFromDriver(double driverLat, double driverLng) async {
    final destLat = widget.destForDistanceLat;
    final destLng = widget.destForDistanceLng;
    if (destLat == 0 && destLng == 0) return;

    final result = await DirectionsService.getRoute(
      originLat: driverLat,
      originLng: driverLng,
      destLat: destLat,
      destLng: destLng,
    );
    if (mounted && result != null && result.points.length >= 2) {
      setState(() {
        _routePolyline = result.points;
        _lastRouteFetchOrigin = LatLng(driverLat, driverLng);
        _lastRouteFetchAt = DateTime.now();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cameraTrackingEnabled) {
          _cameraFollowEngine.resetThrottle();
          if (widget.useDualPartyBoundsCamera) {
            _fitDualPartyBounds(force: true);
          } else {
            _syncCameraFollow(force: true);
          }
        }
      });
    }
  }

  void _maybeFetchRouteFromDriver(double driverLat, double driverLng) {
    final last = _lastRouteFetchOrigin;
    final now = DateTime.now();

    if (last == null) {
      _fetchRouteFromDriver(driverLat, driverLng);
      return;
    }

    final dist = Geolocator.distanceBetween(
      last.latitude, last.longitude,
      driverLat, driverLng,
    );
    final lastFetch = _lastRouteFetchAt;
    final intervalOk = lastFetch == null ||
        now.difference(lastFetch).inSeconds >= _routeRefetchIntervalSeconds;

    if (dist >= _routeRefetchDistanceMeters && intervalOk) {
      _fetchRouteFromDriver(driverLat, driverLng);
    }
  }

  void _onDriverStatus(Map<String, dynamic>? d) {
    if (!mounted) return;
    if (d == null) {
      setState(() {
        _noDriverStatus = true;
        _invalidCoordinates = false;
      });
      return;
    }
    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    final lastUpdatedRaw = d['lastUpdated'];
    Timestamp? lastUpdated;
    if (lastUpdatedRaw is Timestamp) {
      lastUpdated = lastUpdatedRaw;
    } else if (lastUpdatedRaw is String) {
      final dt = DateTime.tryParse(lastUpdatedRaw);
      lastUpdated = dt != null ? Timestamp.fromDate(dt) : null;
    }
    if (lat == null || lng == null) {
      setState(() {
        _invalidCoordinates = true;
        _noDriverStatus = false;
      });
      return;
    }

    final prevLastUpdated = _lastUpdated;
    setState(() {
      _lastUpdated = lastUpdated;
      _noDriverStatus = false;
      _invalidCoordinates = false;
      _connectionError = false;
    });

    _maybeFetchRouteFromDriver(lat, lng);

    // Posisi aktual GPS (tidak di-snap ke jalan—driver bisa parkir/di samping jalan)
    final rawLatLng = LatLng(lat, lng);
    int targetSeg = -1;
    double targetRatio = 0;
    final polyline = _routePolyline;
    if (polyline != null && polyline.length >= 2) {
      final projected = RouteUtils.projectPointOntoPolyline(
        rawLatLng,
        polyline,
        maxDistanceMeters: 150,
      );
      targetSeg = projected.$2;
      targetRatio = projected.$3;
    }

    _updateDriverLocationText(lat, lng);

    if (widget.enableFerryDetection) {
      final now = DateTime.now();
      final shouldCheck = _lastFerryCheckAt == null ||
          now.difference(_lastFerryCheckAt!).inSeconds >= _ferryCheckDebounceSeconds;
      if (shouldCheck) {
        _lastFerryCheckAt = now;
        _checkFerryWithRetry(lat, lng);
      }
    }

    // ETA dinamis: hitung kecepatan dari perpindahan
    if (_lastPositionForSpeed != null && lastUpdated != null) {
      final dtSec = lastUpdated.toDate().difference(_lastPositionTime!).inSeconds;
      if (dtSec >= 8) {
        final distM = Geolocator.distanceBetween(
          _lastPositionForSpeed!.latitude,
          _lastPositionForSpeed!.longitude,
          lat,
          lng,
        );
        if (distM > 20) {
          final speedKmh = (distM / 1000) / (dtSec / 3600);
          _estimatedSpeedKmh = speedKmh.clamp(10.0, 90.0);
        }
      }
    }
    _lastPositionForSpeed = rawLatLng;
    _lastPositionTime = lastUpdated?.toDate() ?? DateTime.now();

    if (_displayedPosition == null) {
      _displayedPosition = rawLatLng;
      _targetPosition = rawLatLng;
      _interpEndSeg = targetSeg;
      _interpEndRatio = targetRatio;
      if (polyline != null && polyline.length >= 2 && targetSeg >= 0) {
        _displayedBearing = RouteUtils.computeBearingFromPolyline(
          rawLatLng,
          polyline,
          segmentIndex: targetSeg,
          ratio: targetRatio,
        );
        _smoothedBearing = _displayedBearing;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.useDualPartyBoundsCamera) {
            _fitDualPartyBounds(force: true);
          } else {
            _syncCameraFollow(force: true);
          }
        }
      });
    } else {
      _targetPosition = rawLatLng;
      _interpEndSeg = targetSeg;
      _interpEndRatio = targetRatio;
      if (polyline != null && polyline.length >= 2 && targetSeg >= 0) {
        final b = RouteUtils.computeBearingFromPolyline(
          rawLatLng,
          polyline,
          segmentIndex: targetSeg,
          ratio: targetRatio,
        );
        _displayedBearing = b;
        _smoothedBearing = _smoothBearing(_smoothedBearing, b);
      }
      final durationMs = lastUpdated != null && prevLastUpdated != null
          ? lastUpdated.toDate().difference(prevLastUpdated.toDate()).inMilliseconds
          : 1500;
      _startInterpolation(durationMs: durationMs);
    }
    if (mounted) {
      setState(() {});
      if (widget.useDualPartyBoundsCamera) {
        _scheduleDualPartyFit();
      }
    }
  }

  bool _isDataStale() {
    if (_lastUpdated == null || _displayedPosition == null) return false;
    return DateTime.now().difference(_lastUpdated!.toDate()).inSeconds > _staleDataSeconds;
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final d = await DriverStatusService.fetchDriverStatusOnce(widget.driverUid);
      if (mounted) _onDriverStatus(d);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _checkFerryWithRetry(double lat, double lng) async {
    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final status = await FerryDistanceService.checkDriverOnFerry(
          originLat: widget.originLat,
          originLng: widget.originLng,
          destLat: widget.destLat,
          destLng: widget.destLng,
          driverLat: lat,
          driverLng: lng,
        );
        if (mounted) setState(() => _ferryStatus = status);
        return;
      } catch (_) {
        if (attempt < maxRetries) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } else if (mounted) {
          setState(() => _ferryStatus = const FerryStatus(isOnFerry: false));
        }
      }
    }
  }

  Future<void> _updateDriverLocationText(double lat, double lng) async {
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = [
          p.thoroughfare,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].whereType<String>().where((s) => s.trim().isNotEmpty);
        setState(() {
          _driverLocationText = parts.isNotEmpty
              ? parts.take(3).join(', ')
              : 'Lat ${lat.toStringAsFixed(4)}, Lng ${lng.toStringAsFixed(4)}';
        });
      }
    } catch (e, st) {
      logError('PassengerTrackMapWidget._updateDriverLocationText', e, st);
      if (mounted) {
        setState(() => _driverLocationText = TrakaL10n.of(context).driverEnRoute);
      }
    }
  }

  static const int _animDurationMinMs = 200;
  static const int _animDurationMaxMs = 3000;
  static const int _animTickMs = 100;

  void _startInterpolation({int durationMs = 1500}) {
    _interpolationTimer?.cancel();
    if (_displayedPosition == null || _targetPosition == null) return;

    final clampedDuration = durationMs.clamp(_animDurationMinMs, _animDurationMaxMs);
    final progressIncrement = _animTickMs / clampedDuration;
    final polyline = _routePolyline;
    _interpolationProgress = 0;

    _interpolationTimer = Timer.periodic(const Duration(milliseconds: _animTickMs), (_) {
      if (!mounted || _displayedPosition == null || _targetPosition == null) {
        _interpolationTimer?.cancel();
        return;
      }
      _interpolationProgress += progressIncrement;
      if (_interpolationProgress >= 1) {
        _displayedPosition = _targetPosition;
        _interpolationTimer?.cancel();
        double b = 0;
        if (polyline != null && polyline.length >= 2 && _interpEndSeg >= 0) {
          b = RouteUtils.computeBearingFromPolyline(
            _targetPosition!,
            polyline,
            segmentIndex: _interpEndSeg,
            ratio: _interpEndRatio,
          );
        } else {
          b = RouteUtils.bearingBetween(_displayedPosition!, _targetPosition!);
        }
        _displayedBearing = b;
        _smoothedBearing = _smoothBearing(_smoothedBearing, b);
      } else {
        final t = _interpolationProgress.clamp(0.0, 1.0);
        final lat = _displayedPosition!.latitude +
            (_targetPosition!.latitude - _displayedPosition!.latitude) * t;
        final lng = _displayedPosition!.longitude +
            (_targetPosition!.longitude - _displayedPosition!.longitude) * t;
        _displayedPosition = LatLng(lat, lng);
        final b = RouteUtils.bearingBetween(_displayedPosition!, _targetPosition!);
        _displayedBearing = b;
        _smoothedBearing = _smoothBearing(_smoothedBearing, b);
      }
      if (mounted) {
        if (_cameraTrackingEnabled) {
          if (widget.useDualPartyBoundsCamera) {
            _scheduleDualPartyFit();
          } else {
            _syncCameraFollow();
          }
        }
        setState(() {});
      }
    });
  }

  /// Smooth bearing: EMA + hysteresis (abaikan perubahan kecil). Sinkron dengan driver.
  double _smoothBearing(double current, double newBearing) {
    double diff = newBearing - current;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    if (diff.abs() < _bearingHysteresisDeg) return current;
    return (current + diff * _bearingSmoothAlpha) % 360;
  }

  /// Garis biru rute: hanya sisa perjalanan (driver ke tujuan). Bagian yang sudah dilewati tidak ditampilkan.
  Set<Polyline> _buildPolylines() {
    final Set<Polyline> polylines = {};
    final route = _routePolyline;
    if (route == null || route.length < 2) return polylines;

    final driverPos = _displayedPosition ?? _targetPosition;
    List<LatLng> pointsToDraw;

    if (driverPos != null) {
      final (projPoint, segmentIndex, ratio) = RouteUtils.projectPointOntoPolyline(
        driverPos,
        route,
        maxDistanceMeters: 150,
      );

      if (segmentIndex >= 0) {
        final remaining = <LatLng>[projPoint];
        for (int i = segmentIndex + 1; i < route.length; i++) {
          remaining.add(route[i]);
        }
        if (remaining.length >= 2) {
          pointsToDraw = remaining;
        } else {
          return polylines;
        }
      } else {
        pointsToDraw = route;
      }
    } else {
      pointsToDraw = route;
    }

    polylines.add(
      Polyline(
        polylineId: const PolylineId('route_to_destination'),
        points: pointsToDraw,
        color: AppTheme.primary,
        width: 5,
      ),
    );
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (_noDriverStatus) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Lokasi driver belum tersedia',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Driver mungkin belum mulai rute atau tidak aktif. Lokasi akan muncul setelah driver memulai perjalanan. Periksa koneksi internet jika driver sudah aktif.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: TrakaL10n.of(context).back,
              ),
            ),
          ),
        ],
      );
    }
    if (_invalidCoordinates) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Koordinat driver tidak valid',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Driver mungkin belum mengirim lokasi. Coba refresh atau tunggu sebentar.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: TrakaL10n.of(context).back,
              ),
            ),
          ),
        ],
      );
    }

    final pos = _displayedPosition ?? _targetPosition;
    if (pos == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Memuat lokasi driver...'),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surface,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: TrakaL10n.of(context).back,
              ),
            ),
          ),
        ],
      );
    }

    final isMoving = _lastUpdated != null &&
        DateTime.now().difference(_lastUpdated!.toDate()).inSeconds <=
            _movingThresholdSeconds;

    double? distanceMeters;
    String distanceText = '-';
    String etaText = '-';
    if (widget.destForDistanceLat != 0 || widget.destForDistanceLng != 0) {
      distanceMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.destForDistanceLat,
        widget.destForDistanceLng,
      );
      if (distanceMeters < 1000) {
        distanceText = '${distanceMeters.round()} m';
      } else {
        distanceText = '${(distanceMeters / 1000).toStringAsFixed(1)} km';
      }
      // ETA dinamis: kecepatan aktual driver jika tersedia, else 40 km/jam
      final speedKmh = _estimatedSpeedKmh ?? 40.0;
      final durationSeconds = (distanceMeters / 1000) / speedKmh * 3600;
      final eta = DateTime.now().add(Duration(seconds: durationSeconds.round()));
      etaText = TimeFormatter.format12h(eta);
    }

    final onFerry = _ferryStatus?.isOnFerry ?? false;
    final BitmapDescriptor driverIcon;
    final String driverSnippet;
    if (onFerry) {
      driverIcon = _shipIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
      driverSnippet = 'Sedang di kapal laut';
    } else {
      final premium = _premiumCarIcons;
      if (premium != null) {
        driverIcon = isMoving ? premium.green : premium.red;
      } else {
        driverIcon = (isMoving ? _carIconGreen : _carIconRed) ??
            BitmapDescriptor.defaultMarkerWithHue(
              isMoving ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
            );
      }
      driverSnippet = isMoving ? 'Sedang bergerak' : 'Berhenti';
    }

    final rotation = CarIconService.markerRotationDegrees(
      _smoothedBearing,
      premiumAssetFrontUp:
          !onFerry && (_premiumCarIcons?.assetFrontFacesNorth ?? false),
    );
    final pinAwal = TrakaPinBitmapService.mapAwal;
    final pinAhir = TrakaPinBitmapService.mapAhir;
    // Pin awal/akhir rute + lokasi penonton (bukan layer myLocation Google).
    final markers = <Marker>{
      if (_routeCoordUsable(widget.originLat, widget.originLng))
        Marker(
          markerId: const MarkerId('route_origin'),
          position: LatLng(widget.originLat, widget.originLng),
          icon: pinAwal ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 1.0),
          zIndexInt: 2,
          infoWindow: const InfoWindow(title: 'Titik awal'),
        ),
      if (_routeCoordUsable(widget.destLat, widget.destLng))
        Marker(
          markerId: const MarkerId('route_destination'),
          position: LatLng(widget.destLat, widget.destLng),
          icon: pinAhir ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
          zIndexInt: 2,
          infoWindow: const InfoWindow(title: 'Tujuan akhir'),
        ),
      if (_viewerLocation != null)
        Marker(
          markerId: const MarkerId('viewer_location'),
          position: _viewerLocation!,
          icon: pinAwal ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: Offset(0.5, pinAwal != null ? 1.0 : 0.5),
          zIndexInt: 3,
          infoWindow: const InfoWindow(title: 'Lokasi Anda'),
        ),
      if (onFerry)
        Marker(
          markerId: const MarkerId('driver'),
          position: pos,
          icon: driverIcon,
          rotation: rotation,
          flat: defaultTargetPlatform != TargetPlatform.android,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: 'Driver',
            snippet: driverSnippet,
          ),
        ),
      ...?widget.extraMarkers?.call(pos),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        StyledGoogleMapBuilder(
          builder: (style, _) => GoogleMap(
            buildingsEnabled: true,
            indoorViewEnabled: true,
            mapToolbarEnabled: false,
            initialCameraPosition: CameraPosition(
              target: pos,
              zoom: MapStyleService.defaultZoom,
              tilt: MapStyleService.defaultTilt,
            ),
            onMapCreated: (c) {
              _mapController = c;
              _cameraFollowEngine.attach(c);
              unawaited(_syncCarIconsZoomFromMap());
              if (widget.useDualPartyBoundsCamera) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _fitDualPartyBounds(force: true);
                });
              }
            },
            onCameraIdle: _syncCarIconsZoomFromMap,
            onCameraMoveStarted: () {
              if (_suppressNextCameraMoveStarted) {
                _suppressNextCameraMoveStarted = false;
                return;
              }
              setState(() => _cameraTrackingEnabled = false);
            },
            mapType: MapType.normal,
            style: style,
            markers: markers,
            polylines: _buildPolylines(),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surface,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: TrakaL10n.of(context).back,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surface,
                child: IconButton(
                  icon: _isRefreshing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isRefreshing ? null : _onRefresh,
                  tooltip: TrakaL10n.of(context).reload,
                ),
              ),
            ],
          ),
        ),
        if (_connectionError || _isDataStale())
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 56,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, size: 20, color: Theme.of(context).colorScheme.onTertiaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lokasi mungkin tidak terbaru. Periksa koneksi internet.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isRefreshing ? null : _onRefresh,
                      child: _isRefreshing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : Text(TrakaL10n.of(context).reload),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.showSOS && widget.onSOS != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: IconButton(
                icon: Icon(Icons.emergency, color: Colors.red.shade700),
                onPressed: widget.onSOS,
                tooltip: 'SOS Darurat',
              ),
            ),
          ),
        // Overlay icon mobil tetap di bawah tengah (head unit style) saat tidak di kapal
        if (!onFerry)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 140,
            left: 0,
            right: 0,
            child: Center(
              child: CarOverlayWidget(
                bearing: _smoothedBearing,
                isMoving: isMoving,
                size: 28,
              ),
            ),
          ),
        // Tombol Fokus: recenter ke mobil saat user pan/zoom manual
        if (!_cameraTrackingEnabled)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 200,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).colorScheme.surface,
                child: InkWell(
                  onTap: _focusOnCar,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.my_location,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Fokus ke mobil',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          child: widget.bottomBuilder(
            pos,
            isMoving,
            distanceMeters,
            distanceText,
            etaText,
            _driverLocationText,
            _ferryStatus,
          ),
        ),
      ],
    );
  }
}
