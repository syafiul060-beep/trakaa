import 'dart:async';

import '../models/order_model.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/geocoding_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/province_island.dart';
import '../theme/responsive.dart';
import '../widgets/traka_l10n_scope.dart';
import '../utils/app_logger.dart';
import '../utils/placemark_formatter.dart';
import '../utils/instruction_formatter.dart';
import '../services/directions_service.dart';
import '../services/map_style_service.dart';
import '../services/theme_service.dart';
import '../services/driver_schedule_service.dart';
import '../widgets/styled_google_map_builder.dart';
import '../services/driver_status_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/chat_badge_service.dart';
import '../services/app_config_service.dart';
import '../services/order_service.dart';
import '../services/route_background_handler.dart';
import '../services/route_journey_number_service.dart';
import '../services/route_persistence_service.dart';
import '../services/car_icon_service.dart';
import '../config/marker_assets.dart';
import '../services/driver_car_marker_service.dart';
import '../services/driver_location_icon_service.dart';
import '../services/marker_icon_service.dart';
import '../services/route_utils.dart';
import '../services/route_optimization_service.dart';
import '../services/route_session_service.dart';
import '../services/driver_contribution_service.dart';
import '../services/verification_service.dart';
import '../services/pending_purchase_recovery_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/auth_session_service.dart';
import '../services/low_ram_warning_service.dart';
import '../services/trip_service.dart';
import '../services/voice_navigation_service.dart';
import '../services/routes_toll_service.dart';
import '../widgets/driver_map_overlays.dart';
import '../widgets/driver_route_form_sheet.dart';
import '../widgets/driver_focus_button.dart';
import '../widgets/driver_turn_direction_overlay.dart';
import '../widgets/oper_driver_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/driver_route_info_panel.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/navigating_to_destination_overlay.dart';
import '../widgets/navigating_to_passenger_overlay.dart';
import '../widgets/turn_by_turn_banner.dart';
import '../widgets/driver_stops_list_overlay.dart';
import '../widgets/promotion_banner_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'chat_list_driver_screen.dart';
import 'contribution_driver_screen.dart';
import 'data_order_driver_screen.dart';
import 'driver_jadwal_rute_screen.dart';
import 'login_screen.dart';
import 'profile_driver_screen.dart';

/// Tipe rute: dalam provinsi, antar provinsi, dalam negara.
enum RouteType { dalamProvinsi, antarProvinsi, dalamNegara }

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  /// Tab yang sudah pernah dikunjungi (lazy build: hanya build saat pertama kali).
  final Set<int> _visitedTabIndices = {};
  /// Increment saat tab Data Order dipilih agar Data Order refresh (mis. setelah kesepakatan di chat).
  int _dataOrderRefreshKey = 0;
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal; // Default: peta jalan
  /// Layer kemacetan lalu lintas (seperti Grab). Default on saat navigasi.
  bool _trafficEnabled = true;
  /// Rekomendasi rute alternatif saat macet: menit lebih cepat (null = tidak ada).
  int? _fasterAlternativeMinutesSaved;
  Timer? _trafficAlternativesCheckTimer;
  Position? _currentPosition;
  Timer? _locationRefreshTimer;
  Timer? _interpolationTimer;
  /// Timer untuk refresh token auth berkala (agar tidak kadaluarsa saat pakai lama).
  Timer? _authTokenRefreshTimer;

  /// Posisi yang ditampilkan di map (interpolasi untuk pergerakan halus).
  LatLng? _displayedPosition;

  /// Target posisi untuk interpolasi.
  LatLng? _targetPosition;

  /// Posisi awal interpolasi saat ini (untuk easing).
  LatLng? _interpStartPos;

  /// Queue posisi (Grab-style): data masuk queue, tidak restart interpolasi.
  final List<({LatLng pos, int seg, double ratio})> _positionQueue = [];
  static const int _maxPositionQueue = 3;

  /// Posisi terakhir dari GPS (untuk prediksi saat data telat).
  LatLng? _lastReceivedTarget;
  LatLng? _positionBeforeLast;

  /// Untuk interpolasi sepanjang jalan: (segmentIndex, ratio) awal dan akhir.
  int _interpEndSeg = -1;
  double _interpEndRatio = 0;
  int _interpStartSeg = -1;
  double _interpStartRatio = 0;
  double _interpolationProgress = 0;
  /// Timestamp posisi terakhir (untuk durasi animasi proporsional).
  DateTime? _lastPositionTimestamp;

  // Lokasi driver (reverse geocode) untuk form asal
  String _originLocationText = 'Mengambil lokasi...';
  String? _currentProvinsi;

  // Status kerja: true = sedang kerja (tombol merah), false = siap kerja (tombol hijau)
  bool _isDriverWorking = false;
  // Rute saat ini
  LatLng? _routeOriginLatLng;
  String _routeOriginText = '';
  LatLng? _routeDestLatLng;
  String _routeDestText = '';
  List<LatLng>? _routePolyline;
  String _routeDistanceText = '';
  String _routeDurationText = '';
  // Jarak dan estimasi waktu dinamis berdasarkan posisi driver saat ini
  String _currentDistanceText = '';
  String _currentDurationText = '';
  // Alternatif rute untuk dipilih driver
  List<DirectionsResult> _alternativeRoutes = [];
  int _selectedRouteIndex = -1; // Index rute yang dipilih (-1 = belum dipilih)
  bool _routeSelected =
      false; // Apakah driver sudah memilih rute dari alternatif
  bool _isStartRouteLoading = false; // Loading saat tap Mulai Rute ini
  bool _activeRouteFromJadwal =
      false; // True jika rute aktif berasal dari halaman Jadwal & Rute
  /// Kategori rute dari jadwal: dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  String? _currentRouteCategory;
  /// True saat akan load rute dari jadwal—jangan zoom di _onMapCreated.
  bool _pendingJadwalRouteLoad = false;
  /// ID jadwal yang dijalankan (untuk sinkron pesanan terjadwal dengan Data Order).
  String? _currentScheduleId;
  // Tracking untuk auto-switch rute
  DateTime? _lastRouteSwitchTime; // Waktu terakhir switch rute
  int _originalRouteIndex = -1; // Index rute awal sebelum auto-switch
  DateTime? _destinationReachedAt;
  static const Duration _autoEndDuration = Duration(hours: 1, minutes: 30);
  static const double _atDestinationMeters = 500;
  // Nomor rute perjalanan (unik), waktu mulai rute, estimasi durasi untuk auto-end
  String? _routeJourneyNumber;
  DateTime? _routeStartedAt;
  int? _routeEstimatedDurationSeconds;
  // Rute terakhir (untuk opsi "Putar Arah" saat tombol hijau dan driver masih di tujuan)
  LatLng? _lastRouteOriginLatLng;
  LatLng? _lastRouteDestLatLng;
  String _lastRouteOriginText = '';
  String _lastRouteDestText = '';

  // Tracking update lokasi ke Firestore (efisien: jika pindah 1.5 km atau per 12 menit)
  Position? _lastUpdatedPosition;
  DateTime? _lastUpdatedTime;

  // Icon mobil untuk marker lokasi driver (cache sekali, pakai Marker.rotation)
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;

  /// Custom marker dot/arrow (Opsi C). Cache per (streetName, isMovingStable, speedTier).
  final Map<String, BitmapDescriptor> _driverCarMarkerCache = {};
  static const int _maxDriverCarMarkerCache = 8;

  /// Titik biru untuk posisi driver saat !chaseCamActive (rute dipilih, belum mulai).
  BitmapDescriptor? _blueDotIcon;

  /// Bearing tampilan untuk rotasi icon (derajat). Dari polyline (prioritas) atau GPS.
  double _displayedBearing = 0.0;

  /// Bearing yang di-smooth untuk menghindari loncatan (head unit style).
  double _smoothedBearing = 0.0;
  Position?
  _positionWhenStarted; // Posisi saat mulai bekerja (untuk deteksi pergerakan)
  bool _hasMovedAfterStart =
      false; // Apakah lokasi sudah bergerak setelah mulai bekerja
  /// Debounced: gak bolak-balik merah↔biru saat GPS noise.
  bool _isMovingStable = false;
  Timer? _movementDebounceTimer;
  bool _needsBearingSetState = false; // Cegah setState berlebihan (goyangan)

  /// Tunggu sebelum tampilkan "Sesi tidak valid" — hindari logout palsu saat token refresh (mis. setelah telpon WA).
  Timer? _sessionInvalidCheckTimer;
  bool _sessionInvalidConfirmed = false;
  StreamSubscription<User?>? _authStateSub;
  Position?
  _lastPositionForMovement; // Posisi terakhir untuk deteksi pergerakan real-time

  /// Kecepatan terakhir (m/s) untuk offset kamera dinamis.
  double _currentSpeedMps = 0.0;

  // Long press detection untuk pilih rute alternatif
  // Badge chat: jumlah order dengan pesan belum dibaca driver
  StreamSubscription<List<OrderModel>>? _driverOrdersSub;
  List<OrderModel> _driverOrders = [];
  /// Cache untuk #8 insert optimization: route dan order IDs terakhir.
  List<({OrderModel order, bool isPickup})>? _lastOptimizedStops;
  final Set<String> _lastPickupOrderIds = {};
  final Set<String> _lastDropoffOrderIds = {};
  /// Posisi saat cache insert dibuat (Tahap 3.2: invalidate jika driver pindah > 2 km).
  LatLng? _lastPositionForOptimizedStops;
  static const double _invalidateCacheDistanceMeters = 2000;
  /// Kapasitas mobil & kargo slot untuk validasi route (Tahap 3.1). Di-set saat fetch.
  int? _cachedDriverMaxCapacity;
  double _cachedKargoSlotPerOrder = 1.0;
  final Map<String, BitmapDescriptor> _passengerMarkerIcons = {};
  int _chatUnreadCount = 0;
  int _jumlahPenumpang = 0;
  int _jumlahBarang = 0;

  /// Jumlah penumpang yang sudah dijemput (picked_up) - untuk enable tombol Oper Driver.
  int _jumlahPenumpangPickedUp = 0;

  // State untuk tracking active order (agreed/picked_up) - travel atau kirim_barang
  bool _hasActiveOrder = false;

  // Koordinasi form tujuan dengan peta utama (seperti penumpang: map utama bergerak ke lokasi pilihan)
  final ValueNotifier<bool> _formDestMapModeNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<LatLng?> _formDestMapTapNotifier = ValueNotifier<LatLng?>(
    null,
  );
  final ValueNotifier<LatLng?> _formDestPreviewNotifier =
      ValueNotifier<LatLng?>(null);

  /// Mode navigasi ke penumpang: driver klik "Ya, arahkan" → tetap di Beranda, rute ke penumpang di peta.
  /// Setelah scan/konfirmasi otomatis, kembali ke rute utama.
  String? _navigatingToOrderId;
  List<LatLng>? _polylineToPassenger;
  List<RouteStep> _routeSteps = [];
  int _currentStepIndex = -1;
  String _routeToPassengerDistanceText = '';
  String _routeToPassengerDurationText = '';
  double? _routeToPassengerDistanceMeters;
  int? _routeToPassengerDurationSeconds;
  List<String> _routeWarnings = [];
  String? _routeTollInfo;
  double? _lastPassengerLat;

  /// Posisi driver saat terakhir fetch rute ke penumpang. Untuk re-fetch saat bergerak 2.5 km.
  LatLng? _lastFetchRouteToPassengerPosition;
  static const double _refetchRouteToPassengerDistanceMeters = 2500;
  double? _lastPassengerLng;

  /// Mode pengantaran: true = rute ke tujuan (destLat/destLng), false = rute ke penumpang.
  bool _navigatingToDestination = false;
  List<LatLng>? _polylineToDestination;
  double? _lastDestinationLat;
  double? _lastDestinationLng;
  LatLng? _lastFetchRouteToDestinationPosition;

  /// Driver keluar dari rute (>200m dari polyline). Untuk banner indikator.
  bool _isOffRoute = false;

  /// Re-routing saat keluar rute: debounce.
  LatLng? _lastReroutePosition;
  DateTime? _lastRerouteAt;
  static const int _rerouteDebounceSeconds = 30;
  static const double _rerouteDebounceDistanceMeters = 100;

  /// Abaikan onCameraMoveStarted berikutnya (dari animateCamera programatik).
  bool _suppressNextCameraMoveStarted = false;

  /// Sudah bicara "Hampir sampai" sekali (jangan ulang).
  bool _hasSpokenNearArrival = false;

  /// Nama jalan saat ini (reverse geocode, throttle).
  String _currentStreetName = '';

  /// Slug kota/kabupaten untuk GEO matching (#9). Dari subAdministrativeArea.
  String? _currentCitySlug;

  /// Posisi terakhir untuk throttle reverse geocode nama jalan (meter).
  static const double _streetNameGeocodeMinDistanceMeters = 50;
  LatLng? _lastStreetNameGeocodePosition;

  /// Request ID untuk debounce: abaikan hasil geocode jika posisi sudah berubah.
  int _streetNameGeocodeRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        _sessionInvalidCheckTimer?.cancel();
        _sessionInvalidConfirmed = false;
        setState(() {});
      }
    });
    PendingPurchaseRecoveryService.startRecoveryListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationNavigationService.maybeExecutePendingNavigation(context);
    });
    // Load icon mobil & titik biru segera agar driver punya patokan di peta.
    _loadCarIconsOnce();
    _loadBlueDotOnce();
    _startAuthTokenRefreshTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_carIconRed == null || _carIconGreen == null)) {
        _loadCarIconsOnce().then((_) {
          if (mounted && (_carIconRed == null || _carIconGreen == null)) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) _loadCarIconsOnce();
            });
          }
        });
      }
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _driverOrdersSub = OrderService.streamOrdersForDriver(uid).listen((
        orders,
      ) {
        if (!mounted) return;
        int count = 0;
        bool hasActive = false;
        int penumpang = 0;
        int barang = 0;
        int penumpangPickedUp = 0;
        final badgeService = ChatBadgeService.instance;
        for (final o in orders) {
          // Exclude completed/cancelled - sama dengan filter chat list
          if (o.isCompleted || o.status == OrderService.statusCancelled)
            continue;
          if (!badgeService.isOptimisticRead(o.id) &&
              o.lastMessageAt != null &&
              o.lastMessageSenderUid != uid &&
              (o.driverLastReadAt == null ||
                  o.lastMessageAt!.isAfter(o.driverLastReadAt!))) {
            count++;
          }
          final isActive =
              o.status == OrderService.statusAgreed ||
              o.status == OrderService.statusPickedUp;
          if (isActive &&
              (o.orderType == OrderModel.typeTravel ||
                  o.orderType == OrderModel.typeKirimBarang)) {
            hasActive = true;
            if (o.orderType == OrderModel.typeTravel) {
              penumpang++;
              if (o.status == OrderService.statusPickedUp) penumpangPickedUp++;
            } else {
              barang++;
            }
          }
        }
        final navId = _navigatingToOrderId;
        if (navId != null) {
          OrderModel? navOrder;
          for (final o in orders) {
            if (o.id == navId) {
              navOrder = o;
              break;
            }
          }
          if (navOrder != null) {
            if (navOrder.isCompleted && _navigatingToDestination) {
              VoiceNavigationService.instance.stop();
              if (mounted) {
    setState(() {
      _navigatingToOrderId = null;
      _navigatingToDestination = false;
      _polylineToPassenger = null;
      _polylineToDestination = null;
      _isOffRoute = false;
      _routeSteps = [];
                  _currentStepIndex = -1;
                  _routeToPassengerDistanceText = '';
                  _routeToPassengerDurationText = '';
                  _routeToPassengerDistanceMeters = null;
                  _routeToPassengerDurationSeconds = null;
                  _routeWarnings = [];
                  _routeTollInfo = null;
                  _hasSpokenNearArrival = false;
                  _lastPassengerLat = null;
                  _lastPassengerLng = null;
                  _lastFetchRouteToPassengerPosition = null;
                  _lastDestinationLat = null;
                  _lastDestinationLng = null;
                  _lastFetchRouteToDestinationPosition = null;
                });
                _fitMapToMainRoute();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Perjalanan selesai. Kembali ke rute tujuan.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } else if (navOrder.hasDriverScannedPassenger && !_navigatingToDestination) {
              OrderService.clearDriverNavigatingToPickup(navId);
              if (mounted) {
                // #5: Auto-transisi pickup → dropoff: langsung arahkan ke tujuan pengantaran
                final (destLat, destLng) = _getOrderDestinationLatLng(navOrder);
                if (destLat != null && destLng != null) {
                  setState(() {
                    _navigatingToDestination = true;
                    _polylineToPassenger = null;
                    _lastPassengerLat = null;
                    _lastPassengerLng = null;
                    _lastDestinationLat = destLat;
                    _lastDestinationLng = destLng;
                  });
                  _fetchAndShowRouteToDestination(navOrder);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${TrakaL10n.of(context).passengerPickedUp} Mengarahkan ke tujuan.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  setState(() {
                    _navigatingToOrderId = null;
                    _polylineToPassenger = null;
                    _routeSteps = [];
                    _currentStepIndex = -1;
                    _routeToPassengerDistanceText = '';
                    _routeToPassengerDurationText = '';
                    _lastPassengerLat = null;
                    _lastPassengerLng = null;
                  });
                  _fitMapToMainRoute();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(TrakaL10n.of(context).passengerPickedUp),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            } else if (navOrder.passengerLat != null &&
                navOrder.passengerLng != null) {
              final liveLat =
                  navOrder.passengerLiveLat ?? navOrder.passengerLat;
              final liveLng =
                  navOrder.passengerLiveLng ?? navOrder.passengerLng;
              if (_lastPassengerLat != liveLat ||
                  _lastPassengerLng != liveLng) {
                final shouldRefetch =
                    _lastPassengerLat != null &&
                    _lastPassengerLng != null &&
                    Geolocator.distanceBetween(
                          _lastPassengerLat!,
                          _lastPassengerLng!,
                          liveLat!,
                          liveLng!,
                        ) >
                        300;
                _lastPassengerLat = liveLat;
                _lastPassengerLng = liveLng;
                if (shouldRefetch) {
                  _fetchAndShowRouteToPassenger(navOrder);
                }
              }
            }
          }
        }
        setState(() {
          _driverOrders = orders;
          _chatUnreadCount = count;
          _hasActiveOrder = hasActive;
          _jumlahPenumpang = penumpang;
          _jumlahBarang = barang;
          _jumlahPenumpangPickedUp = penumpangPickedUp;
        });
        _loadPassengerMarkerIconsIfNeeded();
      });
      ChatBadgeService.instance.addListener(_onDriverBadgeOptimisticChanged);
    }
    // Peringatan RAM rendah (sekali saja, jika < 4GB)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LowRamWarningService.checkAndShowIfNeeded(context);
    });
    // Tampilkan lokasi cache dulu (cepat), lalu lokasi akurat di background
    Future.microtask(() async {
      if (!mounted) return;
      final cached = await LocationService.getCachedPosition();
      if (cached != null && mounted) {
        setState(() => _currentPosition = cached);
        _updateLocationText(cached);
        // Jangan zoom otomatis sebelum driver klik "Mulai Rute ini"
        if (_mapController != null &&
            mounted &&
            !_pendingJadwalRouteLoad &&
            _alternativeRoutes.isEmpty &&
            (_routePolyline == null || _routePolyline!.isEmpty)) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(cached.latitude, cached.longitude),
              14.0,
            ),
          );
        }
      }
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _getCurrentLocation();
      });
    });
    _tryRestoreActiveRoute();
    _formDestPreviewNotifier.addListener(_onFormDestPreviewChanged);
    _formDestMapModeNotifier.addListener(_onFormDestPreviewChanged);
    _restartLocationTimer();
  }

  void _onDriverBadgeOptimisticChanged() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    int count = 0;
    final badgeService = ChatBadgeService.instance;
    for (final o in _driverOrders) {
      // Exclude completed/cancelled - sama dengan filter chat list
      if (o.isCompleted || o.status == OrderService.statusCancelled) continue;
      if (!badgeService.isOptimisticRead(o.id) &&
          o.lastMessageAt != null &&
          o.lastMessageSenderUid != uid &&
          (o.driverLastReadAt == null ||
              o.lastMessageAt!.isAfter(o.driverLastReadAt!))) {
        count++;
      }
    }
    setState(() => _chatUnreadCount = count);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshAuthTokenSilently();
    }
  }

  /// Refresh token auth di background agar sesi tetap valid (dengan retry).
  void _refreshAuthTokenSilently() {
    AuthSessionService.refreshTokenSilently();
  }

  void _startAuthTokenRefreshTimer() {
    _authTokenRefreshTimer?.cancel();
    // Refresh setiap 25 menit (token berlaku ~1 jam, refresh sebelum kadaluarsa)
    _authTokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 25),
      (_) => _refreshAuthTokenSilently(),
    );
  }

  void _disposeDriverOrdersSub() {
    _driverOrdersSub?.cancel();
    ChatBadgeService.instance.removeListener(_onDriverBadgeOptimisticChanged);
  }

  /// Restart timer lokasi: 4 detik saat bekerja (halus), 30 detik saat tidak.

  /// Throttle setState: max ~10 fps agar map tetap responsif.
  DateTime? _lastInterpolationSetStateTime;

  /// Durasi animasi kamera: proporsional jarak + bearing. Belok besar = lebih lama (map bergerak halus, bukan HP berputar).
  static Duration _cameraDurationForMovement({
    required double distanceMeters,
    required double newBearing,
    double? lastBearing,
  }) {
    int msFromDistance = 250;
    if (distanceMeters > 0) {
      msFromDistance = (250 + (distanceMeters / 150) * 500).round().clamp(250, 1100);
    }
    int msFromBearing = 250;
    if (lastBearing != null) {
      double diff = (newBearing - lastBearing) % 360;
      if (diff > 180) diff -= 360;
      final bearingDeg = diff.abs();
      if (bearingDeg > 45) {
        msFromBearing = (350 + (bearingDeg / 90) * 250).round().clamp(450, 700);
      }
    }
    return Duration(milliseconds: msFromDistance > msFromBearing ? msFromDistance : msFromBearing);
  }

  /// Target kamera terakhir untuk hitung durasi animasi proporsional.
  LatLng? _lastCameraTarget;
  /// Bearing kamera terakhir (untuk durasi rotasi halus saat belok).
  double? _lastCameraBearing;

  /// Chase cam: icon di bawah tengah, peta bergerak menurun (lurus) atau berputar (belok).
  /// Tilt & zoom adaptif: idle lebih flat, cepat lebih dekat (ala Grab).
  static const double _trackingTiltMoving = 52.0;
  static const double _trackingTiltIdle = 30.0;
  double _displayedZoom = 17.0;
  double _displayedTilt = 40.0;

  /// Auto zoom berdasarkan kecepatan: lambat=lebih jauh, cepat=lebih dekat (ala Grab).
  double _getTrackingZoom(double speedKmh) {
    if (speedKmh < 5) return 16.5;
    if (speedKmh < 20) return 17.2;
    return 18.0;
  }

  /// Tilt adaptif: idle flat (30°), moving 52°.
  double _getTrackingTilt(double speedKmh) {
    return speedKmh < 2 ? _trackingTiltIdle : _trackingTiltMoving;
  }

  /// Update zoom/tilt yang di-display (lerp halus ke target).
  void _updateDisplayedZoomTilt() {
    final speedKmh = _currentSpeedMps * 3.6;
    final targetZoom = _getTrackingZoom(speedKmh);
    final targetTilt = _getTrackingTilt(speedKmh);
    _displayedZoom += (targetZoom - _displayedZoom) * 0.35;
    _displayedTilt += (targetTilt - _displayedTilt) * 0.35;
  }

  /// Offset kamera (m) ala Grab: target dekat mobil agar ikon selalu terlihat di layar.
  /// Batas maks 320m mencegah mobil keluar layar saat zoom 20 + tilt 58°.
  double _getCameraOffsetAheadMeters() {
    final speedKmh = _currentSpeedMps * 3.6;
    if (speedKmh < 15) return 100.0; // Macet/kota (zoom 20)
    if (speedKmh < 45) return 150.0; // Kota sedang
    if (speedKmh < 80) return 200.0; // Jalan cepat
    return 260.0; // Tol (cap agar mobil tetap terlihat)
  }

  /// Tracking kamera: true = ikuti posisi, false = driver geser manual.
  bool _cameraTrackingEnabled = true;

  /// Durasi animasi: min 200ms, max 3000ms (proporsional dengan waktu gerak nyata).
  static const int _animDurationMinMs = 200;
  static const int _animDurationMaxMs = 3000;
  static const int _animTickMs = 100;

  void _startInterpolation({int durationMs = 1500}) {
    _interpolationTimer?.cancel();
    final hasRoute = _isDriverWorking || _navigatingToOrderId != null;
    if (!hasRoute || _displayedPosition == null || _targetPosition == null) {
      return;
    }
    _interpStartPos = _displayedPosition;
    final clampedDuration = durationMs.clamp(_animDurationMinMs, _animDurationMaxMs);
    final progressIncrement = _animTickMs / clampedDuration;
    final polyline = _routePolyline ?? _activeNavigationPolyline;
    _interpolationProgress = 0;
    // Snap-to-road: simpan seg/ratio awal untuk interpolasi sepanjang jalan
    if (polyline != null && polyline.length >= 2 && _interpStartPos != null) {
      final proj = RouteUtils.projectPointOntoPolyline(
        _interpStartPos!,
        polyline,
        maxDistanceMeters: 350,
      );
      _interpStartSeg = proj.$2;
      _interpStartRatio = proj.$3;
    } else {
      _interpStartSeg = -1;
      _interpStartRatio = 0;
    }

    _interpolationTimer = Timer.periodic(const Duration(milliseconds: _animTickMs), (
      _,
    ) {
      if (!mounted || _interpStartPos == null || _targetPosition == null) {
        _interpolationTimer?.cancel();
        return;
      }
      _interpolationProgress += progressIncrement;
      if (_interpolationProgress >= 1) {
        _displayedPosition = _targetPosition;
        _interpStartPos = null;
        _interpolationTimer?.cancel();
        double bearing = 0;
        if (polyline != null && polyline.length >= 2 && _interpEndSeg >= 0) {
          bearing = RouteUtils.computeBearingFromPolyline(
            _targetPosition!,
            polyline,
            segmentIndex: _interpEndSeg,
            ratio: _interpEndRatio,
          );
        } else {
          bearing = RouteUtils.bearingBetween(
            _displayedPosition!,
            _targetPosition!,
          );
        }
        _displayedBearing = bearing;
        _smoothedBearing = _smoothBearing(_smoothedBearing, bearing);
        _processPositionQueue();
      } else {
        final tRaw = _interpolationProgress.clamp(0.0, 1.0);
        final t = Curves.easeInOut.transform(tRaw);
        final start = _interpStartPos!;
        final end = _targetPosition!;
        // Interpolasi sepanjang jalan jika kedua titik di polyline (snap-to-road)
        if (polyline != null &&
            polyline.length >= 2 &&
            _interpStartSeg >= 0 &&
            _interpEndSeg >= 0) {
          final (point, bearing) = RouteUtils.interpolateWithBearing(
            polyline,
            _interpStartSeg,
            _interpStartRatio,
            _interpEndSeg,
            _interpEndRatio,
            t,
          );
          _displayedPosition = point;
          _displayedBearing = bearing;
          _smoothedBearing = _smoothBearing(_smoothedBearing, bearing);
        } else {
          final lat = start.latitude + (end.latitude - start.latitude) * t;
          final lng = start.longitude + (end.longitude - start.longitude) * t;
          _displayedPosition = LatLng(lat, lng);
          final bearing = RouteUtils.bearingBetween(
            _displayedPosition!,
            _targetPosition!,
          );
          _displayedBearing = bearing;
          _smoothedBearing = _smoothBearing(_smoothedBearing, bearing);
        }
      }
      if (mounted && _displayedPosition != null) {
        if (_cameraTrackingEnabled)
          _animateCameraToDisplayed(_smoothedBearing);
      }
      if (mounted) {
        final now = DateTime.now();
        if (_lastInterpolationSetStateTime == null ||
            now.difference(_lastInterpolationSetStateTime!).inMilliseconds >=
                100) {
          _lastInterpolationSetStateTime = now;
          setState(() {});
        }
      }
    });
  }

  void _processPositionQueue() {
    if (_positionQueue.isEmpty || _displayedPosition == null) return;
    final next = _positionQueue.removeAt(0);
    _targetPosition = next.pos;
    _interpEndSeg = next.seg;
    _interpEndRatio = next.ratio;
    _startInterpolation(durationMs: 500);
  }

  void _enqueuePosition(LatLng pos, int seg, double ratio) {
    while (_positionQueue.length >= _maxPositionQueue) {
      _positionQueue.removeAt(0);
    }
    _positionQueue.add((pos: pos, seg: seg, ratio: ratio));
  }

  LatLng _predictPosition(LatLng last, LatLng current) {
    return LatLng(
      current.latitude + (current.latitude - last.latitude),
      current.longitude + (current.longitude - last.longitude),
    );
  }

  /// Prediksi saat data GPS telat: mobil tetap jalan (Grab-style).
  void _applyPredictionWhenDataLate() {
    final hasRoute = _isDriverWorking || _navigatingToOrderId != null;
    if (!hasRoute) return;
    if (_lastReceivedTarget == null || _positionBeforeLast == null) return;
    final now = DateTime.now();
    if (_lastPositionTimestamp != null &&
        now.difference(_lastPositionTimestamp!).inMilliseconds < 2000) {
      return;
    }
    final predicted = _predictPosition(_positionBeforeLast!, _lastReceivedTarget!);
    final isAnimating = _interpolationTimer?.isActive ?? false;
    _enqueuePosition(predicted, _interpEndSeg, _interpEndRatio);
    if (!isAnimating && _displayedPosition != null) {
      _processPositionQueue();
    }
    if (mounted) setState(() {});
  }

  /// Smooth bearing: EMA + hysteresis (abaikan perubahan kecil). Minim goyangan.
  static const double _bearingHysteresisDeg = 28.0;
  static const double _bearingSmoothAlpha = 0.015;
  /// Saat belok: tidak terlalu cepat agar map bergerak halus (bukan HP berputar).
  static const double _bearingSmoothAlphaTurn = 0.06;
  /// Hanya pakai alphaTurn saat belok besar (>30°).
  static const double _bearingTurnThresholdDeg = 30.0;
  /// Kecepatan minimum (m/s) untuk update bearing dari GPS (kurangi noise saat lambat).
  static const double _bearingMinSpeedMps = 3.5; // ~12.6 km/jam
  /// Di bawah ini = diam: bekukan bearing & target kamera di posisi mobil.
  static const double _stationarySpeedMps = 1.5; // ~5.4 km/jam

  double _smoothBearing(
    double current,
    double newBearing, {
    double alpha = _bearingSmoothAlpha,
    double hysteresis = _bearingHysteresisDeg,
  }) {
    double diff = newBearing - current;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    if (diff.abs() < hysteresis) return current; // Hysteresis: abaikan getar
    final effectiveAlpha = diff.abs() > _bearingTurnThresholdDeg
        ? _bearingSmoothAlphaTurn
        : alpha;
    return (current + diff * effectiveAlpha) % 360;
  }

  /// Animate kamera: target di depan, bearing dari rute. Saat diam: target = posisi mobil.
  void _animateCameraToDisplayed(double bearing) {
    if (_mapController == null || !mounted || _displayedPosition == null)
      return;
    if (!_isDriverWorking && _navigatingToOrderId == null) return;
    try {
      final polyline = _activeNavigationPolyline ?? _routePolyline;
      final pos = _displayedPosition!;
      final isStationary = _currentSpeedMps < _stationarySpeedMps;
      final LatLng target;
      if (isStationary) {
        target = pos;
      } else if (polyline != null && polyline.length >= 2) {
        final cameraTarget = RouteUtils.pointAheadOnPolyline(
          pos,
          polyline,
          _getCameraOffsetAheadMeters(),
          maxDistanceMeters: 320,
        );
        target = cameraTarget ?? pos;
      } else {
        target = pos;
      }
      final camBearing =
          (polyline != null && polyline.length >= 2) ? bearing : 0.0;
      final distanceMeters = _lastCameraTarget != null
          ? Geolocator.distanceBetween(
              _lastCameraTarget!.latitude,
              _lastCameraTarget!.longitude,
              target.latitude,
              target.longitude,
            )
          : 0.0;
      _lastCameraTarget = target;
      // Saat berhenti: target kamera hampir sama, skip animasi agar stabil.
      if (distanceMeters < 5) return;
      final duration = _cameraDurationForMovement(
        distanceMeters: distanceMeters,
        newBearing: camBearing,
        lastBearing: _lastCameraBearing,
      );
      _lastCameraBearing = camBearing;
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            bearing: camBearing,
            tilt: _displayedTilt,
            zoom: _displayedZoom,
          ),
        ),
        duration: duration,
      );
    } catch (_) {}
  }

  /// Intro cinematic: center + zoom ke driver saat pertama kali mulai kerja (ala Grab).
  void _animateCameraIntroOnStart() {
    if (_mapController == null || !mounted) return;
    final pos = _displayedPosition ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : null);
    if (pos == null) return;
    try {
      setState(() => _cameraTrackingEnabled = true);
      _lastCameraTarget = pos;
      _lastCameraBearing = _smoothedBearing;
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            bearing: _smoothedBearing,
            tilt: _displayedTilt,
            zoom: _displayedZoom,
          ),
        ),
        duration: const Duration(milliseconds: 450),
      );
    } catch (_) {}
  }

  /// Tombol Fokus: recenter ke mobil, kembali ke mode ikuti (Grab/Google Maps style).
  void _focusOnCar() {
    setState(() => _cameraTrackingEnabled = true);
    if (_displayedPosition != null) {
      _animateCameraToDisplayed(_smoothedBearing);
    }
  }

  void _restartLocationTimer() {
    _locationRefreshTimer?.cancel();
    // Saat bekerja: 1 detik saat bergerak (halus), 2 detik saat diam (hemat baterai).
    final interval = _isDriverWorking
        ? (_hasMovedAfterStart
            ? const Duration(seconds: 1)
            : const Duration(seconds: 2))
        : const Duration(seconds: 30);
    _locationRefreshTimer = Timer.periodic(interval, (_) async {
      _getCurrentLocation(forTracking: true);
      if (_isDriverWorking &&
          _routeDestLatLng != null &&
          _currentPosition != null) {
        _checkDestinationAndAutoEnd();
      }
      if (_isDriverWorking &&
          _routeJourneyNumber != null &&
          _routeStartedAt != null &&
          _routeEstimatedDurationSeconds != null) {
        await _checkAutoEndByEstimatedTime();
      }
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted &&
        _cameraTrackingEnabled &&
        (_isDriverWorking || _navigatingToOrderId != null) &&
        _displayedPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateCameraToDisplayed(_smoothedBearing);
      });
    }
  }

  void _onFormDestPreviewChanged() {
    if (mounted) setState(() {});
  }

  /// Layar tetap menyala hanya saat rute aktif dan di Beranda. Tab lain ikut setelan HP.
  void _updateWakelock() {
    if (_isDriverWorking && _currentIndex == 0) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authTokenRefreshTimer?.cancel();
    _sessionInvalidCheckTimer?.cancel();
    _authStateSub?.cancel();
    WakelockPlus.disable();
    _formDestPreviewNotifier.removeListener(_onFormDestPreviewChanged);
    _formDestMapModeNotifier.removeListener(_onFormDestPreviewChanged);
    _disposeDriverOrdersSub();
    _locationRefreshTimer?.cancel();
    _interpolationTimer?.cancel();
    _movementDebounceTimer?.cancel();
    _trafficAlternativesCheckTimer?.cancel();
    _mapController?.dispose();
    RouteBackgroundHandler.unregister();
    // Hapus status driver dari Firestore saat screen dispose (agar driver tidak tampil siap kerja).
    DriverStatusService.removeDriverStatus();
    // Jangan clear RoutePersistenceService di dispose - agar rute bisa direstore
    // saat app dibuka kembali. Origin/dest dari jadwal tetap dipakai (tidak ikut lokasi driver).
    super.dispose();
  }

  void _registerRouteBackgroundHandler() {
    RouteBackgroundHandler.register(
      onEndRoute: _endWork,
      onShowSnackBar: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      onPersistRequest: _updateBackgroundSince,
    );
  }

  /// Simpan rute ke disk (dipanggil saat rute aktif, agar tetap ada jika app ditutup paksa)
  Future<void> _persistCurrentRoute() async {
    if (_routeOriginLatLng == null || _routeDestLatLng == null) return;
    await RoutePersistenceService.save(
      originLat: _routeOriginLatLng!.latitude,
      originLng: _routeOriginLatLng!.longitude,
      destLat: _routeDestLatLng!.latitude,
      destLng: _routeDestLatLng!.longitude,
      originText: _routeOriginText,
      destText: _routeDestText,
      fromJadwal: _activeRouteFromJadwal,
      selectedRouteIndex: _selectedRouteIndex >= 0 ? _selectedRouteIndex : 0,
      backgroundSince: null,
    );
  }

  /// Update timestamp background (dipanggil saat app ke background)
  Future<void> _updateBackgroundSince() async {
    await RoutePersistenceService.updateBackgroundSince(DateTime.now());
  }

  /// Restore rute kerja aktif: prioritas Firestore (sumber utama), fallback SharedPreferences.
  Future<void> _tryRestoreActiveRoute() async {
    double? originLat;
    double? originLng;
    double? destLat;
    double? destLng;
    String originText = '';
    String destText = '';
    bool? fromJadwal;
    int savedRouteIndex = 0;

    // 1. Cek Firestore dulu (rute aktif tersimpan saat driver set rute; tetap ada meski app ditutup)
    final firestoreRoute =
        await DriverStatusService.getActiveRouteFromFirestore();
    if (firestoreRoute != null) {
      originLat = firestoreRoute.originLat;
      originLng = firestoreRoute.originLng;
      destLat = firestoreRoute.destLat;
      destLng = firestoreRoute.destLng;
      originText = firestoreRoute.originText;
      destText = firestoreRoute.destText;
      fromJadwal = firestoreRoute.routeFromJadwal;
      savedRouteIndex = firestoreRoute.routeSelectedIndex;
    }

    // 2. Fallback: SharedPreferences (jika Firestore belum sempat ter-update)
    PersistedRoute? persisted;
    if (originLat == null ||
        originLng == null ||
        destLat == null ||
        destLng == null) {
      persisted = await RoutePersistenceService.load();
      if (persisted == null || !mounted) return;
      originLat = persisted.originLat;
      originLng = persisted.originLng;
      destLat = persisted.destLat;
      destLng = persisted.destLng;
      originText = persisted.originText;
      destText = persisted.destText;
      fromJadwal = persisted.fromJadwal;
      savedRouteIndex = persisted.selectedRouteIndex;
    }

    if (!mounted) return;
    final oLat = originLat;
    final oLng = originLng;
    final dLat = destLat;
    final dLng = destLng;

    // Ambil semua alternatif rute (dengan ETA lalu lintas jika layer aktif)
    final alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      trafficAware: _trafficEnabled,
    );
    if (!mounted || alternatives.isEmpty) return;

    // Restore rute yang dulu dipilih (bukan selalu index 0)
    final selectedIndex = savedRouteIndex.clamp(0, alternatives.length - 1);
    final selectedRoute = alternatives[selectedIndex];
    String? journeyNumber;
    if (firestoreRoute != null) {
      journeyNumber = firestoreRoute.routeJourneyNumber;
    }
    if (journeyNumber == null || journeyNumber.isEmpty) {
      journeyNumber =
          await RouteJourneyNumberService.generateRouteJourneyNumber();
    }
    if (!mounted) return;
    final startedAt = DateTime.now();

    setState(() {
      _routeOriginLatLng = LatLng(oLat, oLng);
      _routeDestLatLng = LatLng(dLat, dLng);
      _routeOriginText = originText;
      _routeDestText = destText;
      _routePolyline = selectedRoute.points;
      _routeDistanceText = selectedRoute.distanceText;
      _routeDurationText = selectedRoute.durationText;
      _alternativeRoutes = alternatives;
      _selectedRouteIndex = selectedIndex;
      _routeSelected = true; // Restore berarti sudah dipilih sebelumnya
      _originalRouteIndex = selectedIndex; // Set rute awal saat restore
      _lastRouteSwitchTime = null; // Reset waktu switch
      _isDriverWorking = true;
      _destinationReachedAt = null;
      _routeJourneyNumber = journeyNumber;
      _routeStartedAt = firestoreRoute?.routeStartedAt ?? startedAt;
      _routeEstimatedDurationSeconds =
          firestoreRoute?.estimatedDurationSeconds ??
          selectedRoute.durationSeconds;
      _activeRouteFromJadwal = fromJadwal ?? false;
      // Saat restore, asumsikan sudah bergerak (pakai icon hijau)
      _hasMovedAfterStart = true;
      _positionWhenStarted = _currentPosition;
      if (_currentPosition != null) {
        final raw = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        // Selalu pakai GPS mentah agar titik biru = lokasi HP/driver akurat.
        _displayedPosition = raw;
        _targetPosition = raw;
      }
    });

    // Icon sudah di-load di initState. Bearing dari heading atau 0.
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      _displayedBearing = _currentPosition!.heading;
      _smoothedBearing = _displayedBearing;
    }

    _registerRouteBackgroundHandler();
    _persistCurrentRoute();
    // Tulis driver_status ke Firestore agar penumpang bisa menemukan driver (penting setelah ganti project id.traka.app).
    if (_currentPosition != null) {
      _updateDriverStatusToFirestore(_currentPosition!);
    } else {
      // Lokasi belum siap; update nanti saat _getCurrentLocation selesai (shouldUpdateLocation true saat lastUpdated null).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final pos = _currentPosition;
        if (pos != null && _isDriverWorking) {
          await _updateDriverStatusToFirestore(pos);
        }
      });
    }
    _restartLocationTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Rute tujuan anda masih aktif. Waktu diperpanjang 1 jam.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _getCurrentLocation({bool forTracking = false}) async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) return;

    // Pastikan GPS aktif - retry beberapa kali jika belum aktif
    // Retry lebih banyak untuk kompatibilitas HP China yang mungkin memerlukan waktu lebih lama
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Retry 4 kali dengan delay progresif untuk memastikan GPS aktif di berbagai HP Android
      for (int retry = 0; retry < 4; retry++) {
        await Future.delayed(Duration(milliseconds: 600 * (retry + 1)));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) break;
      }
      if (!serviceEnabled) return;
    }

    try {
      // Retry maksimal 3 kali untuk kompatibilitas HP China yang mungkin memerlukan waktu lebih lama
      Position? position;
      for (int retry = 0; retry < 3; retry++) {
        final result = await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: retry == 0,
          forTracking: forTracking,
        );
        // Fake GPS terdeteksi: tampilkan overlay full-screen, blokir penggunaan
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
        if (position != null) break;
        if (retry < 2) {
          // Tunggu lebih lama sebelum retry untuk HP yang lebih lambat
          await Future.delayed(Duration(milliseconds: 1500 * (retry + 1)));
        }
      }

      if (position == null) {
        // Jika semua retry gagal, coba sekali lagi dengan forceRefresh dan delay lebih lama
        await Future.delayed(const Duration(milliseconds: 2000));
        final result = await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
          forTracking: forTracking,
        );
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
      }

      if (position == null && mounted && forTracking) {
        _applyPredictionWhenDataLate();
        return;
      }

      if (position != null && mounted) {
        setState(() => _currentPosition = position);

        // Posisi: selalu pakai GPS mentah agar titik biru = lokasi HP/driver akurat.
        final rawLatLng = LatLng(position.latitude, position.longitude);
        int targetSeg = -1;
        double targetRatio = 0;
        LatLng targetPos = rawLatLng;
        final polyline = _routePolyline ?? _activeNavigationPolyline;
        if (polyline != null && polyline.length >= 2) {
          final projected = RouteUtils.projectPointOntoPolyline(
            rawLatLng,
            polyline,
            maxDistanceMeters: 350,
          );
          targetSeg = projected.$2;
          targetRatio = projected.$3;
          // Snap-to-road: pakai titik proyeksi jika dekat rute
          if (targetSeg >= 0) targetPos = projected.$1;
        }

        // Prediction engine: blend GPS dengan prediksi untuk pergerakan lebih halus (bukan hanya saat data telat)
        if (_positionBeforeLast != null && _lastReceivedTarget != null) {
          final predicted = _predictPosition(_positionBeforeLast!, _lastReceivedTarget!);
          targetPos = LatLng(
            targetPos.latitude * 0.88 + predicted.latitude * 0.12,
            targetPos.longitude * 0.88 + predicted.longitude * 0.12,
          );
        }

        // Hitung kecepatan untuk offset kamera dinamis (smoothing + outlier filter)
        if (_lastPositionForMovement != null && _lastPositionTimestamp != null) {
          final distM = Geolocator.distanceBetween(
            _lastPositionForMovement!.latitude,
            _lastPositionForMovement!.longitude,
            position.latitude,
            position.longitude,
          );
          final durSec = position.timestamp
              .difference(_lastPositionTimestamp!)
              .inMilliseconds /
              1000.0;
          if (durSec > 0.1) {
            var rawSpeedMps = distM / durSec;
            // Outlier filter: GPS glitch jika >100m dalam <1s (360 km/h)
            if (distM > 100 && durSec < 1.0) {
              rawSpeedMps = (rawSpeedMps + _currentSpeedMps) * 0.5;
            }
            // Smoothing: EMA 0.2 agar tidak loncat-loncat
            _currentSpeedMps = _currentSpeedMps * 0.8 + rawSpeedMps * 0.2;
          }
        }

        _positionBeforeLast = _lastReceivedTarget;
        _lastReceivedTarget = targetPos;

        if (_displayedPosition == null) {
          _displayedPosition = targetPos;
          _targetPosition = targetPos;
          _interpEndSeg = targetSeg;
          _interpEndRatio = targetRatio;
          _lastPositionTimestamp = position.timestamp;
        } else {
          final isAnimating = _interpolationTimer?.isActive ?? false;
          if (isAnimating) {
            _enqueuePosition(targetPos, targetSeg, targetRatio);
          } else {
            _targetPosition = targetPos;
            _interpEndSeg = targetSeg;
            _interpEndRatio = targetRatio;
            final now = position.timestamp;
            final durationMs = _lastPositionTimestamp != null
                ? now.difference(_lastPositionTimestamp!).inMilliseconds
                : 1500;
            _lastPositionTimestamp = now;
            _startInterpolation(durationMs: durationMs);
          }
        }

        // Indikator off-route untuk banner.
        final hasActiveRoute = polyline != null &&
            polyline.length >= 2 &&
            (_isDriverWorking || _navigatingToOrderId != null);
        final isOffRoute = hasActiveRoute && targetSeg < 0;
        if (mounted && _isOffRoute != isOffRoute) {
          setState(() => _isOffRoute = isOffRoute);
        }

        // Re-routing saat keluar rute (garis biru ke jalan lain untuk kembali).
        if (targetSeg < 0 && _isDriverWorking && _currentPosition != null) {
          if (_navigatingToOrderId != null) {
            final lastFetch = _navigatingToDestination
                ? _lastFetchRouteToDestinationPosition
                : _lastFetchRouteToPassengerPosition;
            final shouldRefetch = lastFetch == null ||
                Geolocator.distanceBetween(
                      lastFetch.latitude,
                      lastFetch.longitude,
                      rawLatLng.latitude,
                      rawLatLng.longitude,
                    ) >
                    _rerouteDebounceDistanceMeters;
            if (shouldRefetch) {
              OrderModel? navOrder;
              for (final o in _driverOrders) {
                if (o.id == _navigatingToOrderId) {
                  navOrder = o;
                  break;
                }
              }
              if (navOrder != null) {
                if (_navigatingToDestination) {
                  _fetchAndShowRouteToDestination(navOrder);
                } else {
                  _fetchAndShowRouteToPassenger(navOrder);
                }
              }
            }
          } else if (_routeDestLatLng != null) {
            _maybeRerouteFromCurrentPosition(rawLatLng);
          }
        }

        await _updateLocationText(position);

        // Nama jalan (reverse geocode, throttle 50m)
        final pos = _displayedPosition ?? rawLatLng;
        if (_lastStreetNameGeocodePosition == null ||
            Geolocator.distanceBetween(
                  _lastStreetNameGeocodePosition!.latitude,
                  _lastStreetNameGeocodePosition!.longitude,
                  pos.latitude,
                  pos.longitude,
                ) >
                _streetNameGeocodeMinDistanceMeters) {
          _lastStreetNameGeocodePosition = pos;
          _updateStreetName(pos);
        }

        // Deteksi pergerakan real-time: merah = diam, hijau = bergerak
        bool isMoving = false;
        if (_isDriverWorking) {
          if (_lastPositionForMovement != null) {
            // Hitung jarak dari posisi sebelumnya
            final distance = Geolocator.distanceBetween(
              _lastPositionForMovement!.latitude,
              _lastPositionForMovement!.longitude,
              position.latitude,
              position.longitude,
            );
            // Jika bergerak lebih dari 5 meter, dianggap sedang bergerak
            isMoving = distance > 5;
          } else {
            // Jika belum ada posisi sebelumnya, cek dari posisi saat mulai bekerja
            if (_positionWhenStarted != null) {
              final distance = Geolocator.distanceBetween(
                _positionWhenStarted!.latitude,
                _positionWhenStarted!.longitude,
                position.latitude,
                position.longitude,
              );
              isMoving =
                  distance > 10; // Threshold lebih besar untuk deteksi awal
            }
          }

          // Bearing: prioritas polyline (arah jalan), fallback GPS heading.
          // Saat diam (<5 km/jam): bekukan bearing agar kamera tidak kemana-mana.
          double rawBearing = 0.0;
          bool skipBearingUpdate = false;
          final speedMps = position.speed;
          final isStationary = !speedMps.isFinite || speedMps < _stationarySpeedMps;
          if (isStationary) {
            skipBearingUpdate = true;
          } else if (polyline != null && polyline.length >= 2 && targetSeg >= 0) {
            rawBearing = RouteUtils.computeBearingFromPolyline(
              rawLatLng,
              polyline,
              segmentIndex: targetSeg,
              ratio: targetRatio,
            );
          } else if (position.heading.isFinite) {
            rawBearing = position.heading;
            if (!speedMps.isFinite || speedMps < _bearingMinSpeedMps) {
              skipBearingUpdate = true;
            }
          } else if (polyline != null && polyline.length >= 2) {
            rawBearing = RouteUtils.bearingBetween(rawLatLng, polyline.last);
          }
          if (!skipBearingUpdate) {
            _displayedBearing = rawBearing;
            final prevSmoothed = _smoothedBearing;
            _smoothedBearing = _smoothBearing(_smoothedBearing, rawBearing);
            // Hanya setState jika bearing berubah >3° (cegah goyangan dari noise)
            final rotDiff = ((_smoothedBearing - prevSmoothed + 180) % 360 - 180).abs();
            if (rotDiff > 3) _needsBearingSetState = true;
          }

          final targetIconColor = isMoving ? 'hijau' : 'merah';
          final currentIconColor = _hasMovedAfterStart ? 'hijau' : 'merah';
          if (targetIconColor != currentIconColor) {
            _hasMovedAfterStart = isMoving;
            _movementDebounceTimer?.cancel();
            final capturedMoving = isMoving;
            _movementDebounceTimer = Timer(const Duration(milliseconds: 300), () {
              if (mounted && _isMovingStable != capturedMoving) {
                setState(() => _isMovingStable = capturedMoving);
              }
            });
            _restartLocationTimer(); // 1 detik saat bergerak, 2 detik saat diam
          } else if (_needsBearingSetState) {
            _needsBearingSetState = false;
            setState(() {}); // Update bearing untuk Marker.rotation
          }

          // Update posisi terakhir untuk deteksi pergerakan berikutnya
          _lastPositionForMovement = position;
        } else {
          // Idle: update bearing untuk rotasi icon (smooth)
          if (position.heading.isFinite) {
            final speedMps = position.speed;
            if (speedMps.isFinite && speedMps >= _bearingMinSpeedMps) {
              _displayedBearing = position.heading;
              final prevSmoothed = _smoothedBearing;
              _smoothedBearing = _smoothBearing(
                _smoothedBearing,
                position.heading,
              );
              final rotDiff = ((_smoothedBearing - prevSmoothed + 180) % 360 - 180).abs();
              if (rotDiff > 3) setState(() {});
            }
          }
        }

        // Update jarak dan estimasi waktu dinamis dari posisi driver saat ini ke tujuan
        if (_isDriverWorking && _routeDestLatLng != null) {
          await _updateCurrentDistanceAndDuration(position);
        }

        // Re-fetch rute ke penumpang/tujuan jika driver bergerak >2.5 km dari posisi terakhir fetch
        final navId = _navigatingToOrderId;
        if (navId != null) {
          final lastFetch = _navigatingToDestination
              ? _lastFetchRouteToDestinationPosition
              : _lastFetchRouteToPassengerPosition;
          if (lastFetch != null) {
            final distFromLastFetch = Geolocator.distanceBetween(
              lastFetch.latitude,
              lastFetch.longitude,
              position.latitude,
              position.longitude,
            );
            if (distFromLastFetch > _refetchRouteToPassengerDistanceMeters) {
              OrderModel? navOrder;
              for (final o in _driverOrders) {
                if (o.id == navId) {
                  navOrder = o;
                  break;
                }
              }
              if (navOrder != null) {
                if (_navigatingToDestination) {
                  _fetchAndShowRouteToDestination(navOrder);
                } else {
                  _fetchAndShowRouteToPassenger(navOrder);
                }
              }
            }
          }
        }

        // Update jarak & ETA dinamis ke penumpang (ringan, tanpa API)
        if (navId != null) {
          _updateRouteToPassengerDistance(position);
        }

        // Cek auto-switch rute jika driver sedang bekerja dan ada alternatif rute
        if (_isDriverWorking &&
            _alternativeRoutes.isNotEmpty &&
            _routeSelected &&
            _selectedRouteIndex >= 0) {
          await _checkAndAutoSwitchRoute(position);
        }

        // Update status & lokasi ke Firestore agar penumpang bisa menemukan driver.
        // Saat menuju jemput: update sering (50m/5s) untuk Lacak Driver.
        // Saat rute biasa: update hemat (2km/15min).
        if (_isDriverWorking &&
            (_lastUpdatedTime == null || _shouldUpdateFirestore(position))) {
          await _updateDriverStatusToFirestore(position);
        }

        // Kamera: ikuti posisi saat tracking enabled. Saat diam: target = posisi mobil, skip animasi kecil.
        if (_mapController != null && mounted && _cameraTrackingEnabled) {
          final interpolationActive = _interpolationTimer?.isActive ?? false;
          final hasRoute = (_isDriverWorking || _navigatingToOrderId != null) &&
              (polyline != null && polyline.length >= 2);
          final isStationary = _currentSpeedMps < _stationarySpeedMps;
          if (hasRoute && !interpolationActive) {
            final pos = _displayedPosition ?? rawLatLng;
            // Saat diam: target = posisi mobil (stabil). Saat bergerak: target di depan polyline.
            final LatLng target;
            if (isStationary) {
              target = pos;
            } else {
              final cameraTarget = RouteUtils.pointAheadOnPolyline(
                pos,
                polyline,
                _getCameraOffsetAheadMeters(),
                maxDistanceMeters: 400,
              );
              target = cameraTarget ?? pos;
            }
            final distanceMeters = _lastCameraTarget != null
                ? Geolocator.distanceBetween(
                    _lastCameraTarget!.latitude,
                    _lastCameraTarget!.longitude,
                    target.latitude,
                    target.longitude,
                  )
                : 0.0;
            if (distanceMeters < 5) return; // Skip animasi saat target hampir sama (stabil)
            final duration = _cameraDurationForMovement(
              distanceMeters: distanceMeters,
              newBearing: _smoothedBearing,
              lastBearing: _lastCameraBearing,
            );
            _lastCameraTarget = target;
            _lastCameraBearing = _smoothedBearing;
            _suppressNextCameraMoveStarted = true;
            _updateDisplayedZoomTilt();
            _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: target,
                  bearing: _smoothedBearing,
                  tilt: _displayedTilt,
                  zoom: _displayedZoom,
                ),
              ),
              duration: duration,
            );
          } else if (!hasRoute) {
            final pos = _displayedPosition ??
                LatLng(position.latitude, position.longitude);
            final distanceMeters = _lastCameraTarget != null
                ? Geolocator.distanceBetween(
                    _lastCameraTarget!.latitude,
                    _lastCameraTarget!.longitude,
                    pos.latitude,
                    pos.longitude,
                  )
                : 0.0;
            if (distanceMeters < 5) return;
            final duration = _cameraDurationForMovement(
              distanceMeters: distanceMeters,
              newBearing: 0,
              lastBearing: null,
            );
            _lastCameraTarget = pos;
            _suppressNextCameraMoveStarted = true;
            _updateDisplayedZoomTilt();
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(pos, _displayedZoom),
              duration: duration,
            );
          }
        }
      }
    } catch (_) {}
  }

  /// Update jarak dan estimasi waktu dari posisi driver saat ini ke tujuan
  Future<void> _updateCurrentDistanceAndDuration(Position position) async {
    if (_routeDestLatLng == null) return;

    try {
      final result = await DirectionsService.getRoute(
        originLat: position.latitude,
        originLng: position.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
      );

      if (result != null && mounted) {
        setState(() {
          _currentDistanceText = result.distanceText;
          _currentDurationText = result.durationText;
        });
      }
    } catch (_) {
      // Jika gagal, gunakan jarak langsung (straight line distance)
      if (mounted) {
        final distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _routeDestLatLng!.latitude,
          _routeDestLatLng!.longitude,
        );
        final distanceKm = distanceMeters / 1000;
        setState(() {
          _currentDistanceText = '${distanceKm.toStringAsFixed(1)} km';
          // Estimasi waktu kasar: asumsi kecepatan rata-rata 60 km/jam
          final estimatedHours = distanceKm / 60;
          if (estimatedHours < 1) {
            final minutes = (estimatedHours * 60).round();
            _currentDurationText = '$minutes mins';
          } else {
            final hours = estimatedHours.floor();
            final minutes = ((estimatedHours - hours) * 60).round();
            _currentDurationText = hours > 0 && minutes > 0
                ? '$hours hours $minutes mins'
                : hours > 0
                ? '$hours hours'
                : '$minutes mins';
          }
        });
      }
    }
  }

  /// Cek dan auto-switch rute jika driver berada di rute alternatif lain.
  /// Syarat: driver berada dalam 10 km dan 15 menit dari rute alternatif lain.
  /// Jika driver kembali ke rute awal dalam 10 km dan 15 menit, switch kembali.
  Future<void> _checkAndAutoSwitchRoute(Position position) async {
    if (_alternativeRoutes.isEmpty || _selectedRouteIndex < 0) return;

    try {
      final driverPos = LatLng(position.latitude, position.longitude);
      final now = DateTime.now();

      // Konversi alternatif rute ke List<List<LatLng>> untuk RouteUtils
      final alternativePolylines = _alternativeRoutes
          .map((r) => r.points)
          .toList();

      // Cari rute terdekat dari posisi driver saat ini
      final nearestRouteIndex = RouteUtils.findNearestRouteIndex(
        driverPos,
        alternativePolylines,
        toleranceMeters: 10000, // 10 km
      );

      // Jika tidak ada rute dalam toleransi, tidak perlu switch
      if (nearestRouteIndex < 0) return;

      // Jika rute terdekat berbeda dengan rute yang dipilih saat ini
      if (nearestRouteIndex != _selectedRouteIndex) {
        // Cek apakah sudah lebih dari 15 menit sejak switch terakhir
        final canSwitch =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >=
                const Duration(minutes: 15);

        if (canSwitch) {
          // Simpan index rute awal jika belum pernah switch
          if (_originalRouteIndex < 0) {
            _originalRouteIndex = _selectedRouteIndex;
          }

          // Switch ke rute terdekat
          if (mounted) {
            setState(() {
              _selectedRouteIndex = nearestRouteIndex;
              _routePolyline = _alternativeRoutes[nearestRouteIndex].points;
              _lastRouteSwitchTime = now;
            });

            // Update Firestore dengan rute baru
            await DriverStatusService.updateDriverStatus(
              status: DriverStatusService.statusSiapKerja,
              position: position,
              routeOrigin: _routeOriginLatLng,
              routeDestination: _routeDestLatLng,
              routeOriginText: _routeOriginText,
              routeDestinationText: _routeDestText,
              routeJourneyNumber: _routeJourneyNumber,
              routeStartedAt: _routeStartedAt,
              estimatedDurationSeconds: _routeEstimatedDurationSeconds,
              routeFromJadwal: _activeRouteFromJadwal,
              routeSelectedIndex: _selectedRouteIndex,
              routeCategory: _currentRouteCategory,
            );

            if (kDebugMode)
              debugPrint(
                'DriverScreen: Auto-switch ke rute index $nearestRouteIndex',
              );
          }
        }
      } else if (_originalRouteIndex >= 0 &&
          nearestRouteIndex == _originalRouteIndex &&
          _selectedRouteIndex != _originalRouteIndex) {
        // Jika driver kembali ke rute awal, cek apakah sudah 15 menit
        final canSwitchBack =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >=
                const Duration(minutes: 15);

        if (canSwitchBack) {
          // Switch kembali ke rute awal
          if (mounted) {
            setState(() {
              _selectedRouteIndex = _originalRouteIndex;
              _routePolyline = _alternativeRoutes[_originalRouteIndex].points;
              _lastRouteSwitchTime = now;
              _originalRouteIndex =
                  -1; // Reset karena sudah kembali ke rute awal
            });

            // Update Firestore dengan rute awal
            await DriverStatusService.updateDriverStatus(
              status: DriverStatusService.statusSiapKerja,
              position: position,
              routeOrigin: _routeOriginLatLng,
              routeDestination: _routeDestLatLng,
              routeOriginText: _routeOriginText,
              routeDestinationText: _routeDestText,
              routeJourneyNumber: _routeJourneyNumber,
              routeStartedAt: _routeStartedAt,
              estimatedDurationSeconds: _routeEstimatedDurationSeconds,
              routeFromJadwal: _activeRouteFromJadwal,
              routeSelectedIndex: _selectedRouteIndex,
              routeCategory: _currentRouteCategory,
            );

            if (kDebugMode)
              debugPrint(
                'DriverScreen: Auto-switch kembali ke rute awal index $_originalRouteIndex',
              );
          }
        }
      }
    } catch (e, st) {
      logError('DriverScreen._checkAndAutoSwitchRoute', e, st);
    }
  }

  Future<void> _updateLocationText(Position position) async {
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final prov = place.administrativeArea ?? '';
        setState(() {
          _currentProvinsi = prov.isNotEmpty ? prov : null;
          _originLocationText = _formatPlacemarkShort(place);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _originLocationText =
              '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
        );
      }
    }
  }

  /// Update nama jalan dari reverse geocode (throttle di pemanggil).
  /// Juga cache city slug untuk GEO matching (#9).
  Future<void> _updateStreetName(LatLng position) async {
    final requestId = ++_streetNameGeocodeRequestId;
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (!mounted || requestId != _streetNameGeocodeRequestId) return;
      final name = placemarks.isNotEmpty
          ? PlacemarkFormatter.streetNameOnly(placemarks.first)
          : '';
      String? citySlug;
      if (placemarks.isNotEmpty) {
        final subAdmin = placemarks.first.subAdministrativeArea?.trim() ?? '';
        if (subAdmin.isNotEmpty) {
          citySlug = _toCitySlug(subAdmin);
        }
      }
      setState(() {
        _currentStreetName = name;
        if (citySlug != null) _currentCitySlug = citySlug;
      });
    } catch (_) {
      if (mounted && requestId == _streetNameGeocodeRequestId) {
        setState(() => _currentStreetName = TrakaL10n.of(context).offline);
      }
    }
  }

  /// Konversi subAdministrativeArea ke slug untuk Redis GEO (bandung, banjarmasin).
  static String? _toCitySlug(String subAdmin) {
    var s = subAdmin.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.startsWith('kota ')) s = s.substring(5);
    if (s.startsWith('kabupaten ')) s = s.substring(10);
    final slug = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? null : slug;
  }

  String _formatPlacemarkShort(Placemark place) =>
      PlacemarkFormatter.formatShort(place);

  /// Cek apakah perlu update lokasi ke Firestore (jika pindah 1.5 km atau sudah 12 menit).
  bool _shouldUpdateFirestore(Position currentPosition) {
    // Live tracking: driver menuju jemput ATAU dalam perjalanan dengan penumpang/barang (Lacak Driver/Barang aktif).
    final useLiveTracking = _navigatingToOrderId != null ||
        _jumlahPenumpangPickedUp > 0 ||
        _jumlahBarang > 0;
    return useLiveTracking
        ? DriverStatusService.shouldUpdateLocationForLiveTracking(
            currentPosition: currentPosition,
            lastUpdatedPosition: _lastUpdatedPosition,
            lastUpdatedTime: _lastUpdatedTime,
          )
        : DriverStatusService.shouldUpdateLocation(
            currentPosition: currentPosition,
            lastUpdatedPosition: _lastUpdatedPosition,
            lastUpdatedTime: _lastUpdatedTime,
          );
  }

  /// Auto-end pekerjaan jika waktu estimasi sudah lewat dan driver belum dapat penumpang.
  Future<void> _checkAutoEndByEstimatedTime() async {
    if (_routeStartedAt == null || _routeEstimatedDurationSeconds == null) {
      return;
    }
    final elapsed = DateTime.now().difference(_routeStartedAt!).inSeconds;
    if (elapsed < _routeEstimatedDurationSeconds!) return;
    final count = await OrderService.countActiveOrdersForRoute(
      _routeJourneyNumber!,
    );
    if (count > 0) return;
    if (!mounted) return;
    _endWork();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Waktu estimasi perjalanan telah habis. Pekerjaan diakhiri otomatis.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Update status dan lokasi driver ke Firestore.
  Future<void> _updateDriverStatusToFirestore(Position position) async {
    try {
      int? passengerCount;
      int? maxPassengers;
      if (_isDriverWorking &&
          _routeJourneyNumber != null &&
          _routeJourneyNumber!.isNotEmpty) {
        if (_routeJourneyNumber == OrderService.routeJourneyNumberScheduled &&
            _currentScheduleId != null &&
            _currentScheduleId!.isNotEmpty) {
          final counts = await OrderService.getScheduledBookingCounts(
            _currentScheduleId!,
          );
          final kargoSlot = await AppConfigService.getKargoSlotPerOrder();
          passengerCount = counts.totalPenumpang +
              ((counts.kargoCount * kargoSlot).ceil()).clamp(0, 100);
        } else {
          passengerCount = await OrderService.countUsedSlotsForRoute(
            _routeJourneyNumber!,
          );
        }
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            final jp = userDoc.data()?['vehicleJumlahPenumpang'] as num?;
            if (jp != null && jp > 0) {
              maxPassengers = jp.toInt();
              if (mounted) setState(() => _cachedDriverMaxCapacity = maxPassengers);
            }
          } catch (_) {}
        }
        final kargoSlot = await AppConfigService.getKargoSlotPerOrder();
        if (mounted) setState(() => _cachedKargoSlotPerOrder = kargoSlot);
      }
      await DriverStatusService.updateDriverStatus(
        status: _isDriverWorking
            ? DriverStatusService.statusSiapKerja
            : DriverStatusService.statusTidakAktif,
        position: position,
        routeOrigin: _routeOriginLatLng,
        routeDestination: _routeDestLatLng,
        routeOriginText: _routeOriginText,
        routeDestinationText: _routeDestText,
        routeJourneyNumber: _routeJourneyNumber,
        routeStartedAt: _routeStartedAt,
        estimatedDurationSeconds: _routeEstimatedDurationSeconds,
        currentPassengerCount: passengerCount,
        routeFromJadwal: _activeRouteFromJadwal,
        routeSelectedIndex: _selectedRouteIndex >= 0 ? _selectedRouteIndex : 0,
        scheduleId: _activeRouteFromJadwal ? _currentScheduleId : null,
        routeCategory: _currentRouteCategory,
        city: _currentCitySlug,
        maxPassengers: maxPassengers,
      );
      // Update tracking untuk pengecekan berikutnya
      setState(() {
        _lastUpdatedPosition = position;
        _lastUpdatedTime = DateTime.now();
      });
    } catch (_) {
      // Gagal update ke Firestore - tidak perlu tampilkan error, coba lagi nanti
    }
  }

  void _checkDestinationAndAutoEnd() {
    if (_routeDestLatLng == null || _currentPosition == null) return;
    final dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _routeDestLatLng!.latitude,
      _routeDestLatLng!.longitude,
    );
    if (dist <= _atDestinationMeters) {
      final now = DateTime.now();
      _destinationReachedAt ??= now;
      if (now.difference(_destinationReachedAt!) >= _autoEndDuration) {
        _endWork();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pekerjaan diakhiri otomatis. Anda sudah sampai tujuan lebih dari 1,5 jam.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {});
      }
    } else {
      setState(() => _destinationReachedAt = null);
    }
  }

  Future<void> _endWork() async {
    // Simpan nilai untuk dipakai setelah setState (sebelum di-clear)
    final journeyNumber = _routeJourneyNumber;
    final scheduleId = _currentScheduleId;
    final originText = _routeOriginText;
    final destText = _routeDestText;
    final originLatLng = _routeOriginLatLng;
    final destLatLng = _routeDestLatLng;
    final startedAt = _routeStartedAt;
    final currentPos = _currentPosition;

    // Update UI dulu agar tombol langsung jadi "Siap Kerja" (jangan tunggu async)
    if (!mounted) return;
    RouteBackgroundHandler.unregister();
    RoutePersistenceService.clear();
    setState(() {
      if (_routeOriginLatLng != null && _routeDestLatLng != null) {
        _lastRouteOriginLatLng = _routeOriginLatLng;
        _lastRouteDestLatLng = _routeDestLatLng;
        _lastRouteOriginText = _routeOriginText;
        _lastRouteDestText = _routeDestText;
      }
      _isDriverWorking = false;
      _routePolyline = null;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
      _routeDistanceText = '';
      _currentScheduleId = null;
      _routeDurationText = '';
      _destinationReachedAt = null;
      _routeJourneyNumber = null;
      _routeStartedAt = null;
      _routeEstimatedDurationSeconds = null;
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routeSelected = false;
      _lastReroutePosition = null;
      _lastRerouteAt = null;
      _isOffRoute = false;
      _originalRouteIndex = -1;
      _lastRouteSwitchTime = null;
      _carIconRed = null;
      _carIconGreen = null;
      _positionWhenStarted = null;
      _hasMovedAfterStart = false;
      _isMovingStable = false;
      _movementDebounceTimer?.cancel();
      _lastPositionForMovement = null;
      _activeRouteFromJadwal = false;
      _interpolationTimer?.cancel();
      _displayedPosition = null;
      _targetPosition = null;
      _interpStartPos = null;
      _interpStartSeg = -1;
      _interpStartRatio = 0;
      _positionQueue.clear();
      _lastReceivedTarget = null;
      _positionBeforeLast = null;
      _lastCameraTarget = null;
      _lastCameraBearing = null;
      _displayedZoom = 17.0;
      _displayedTilt = 40.0;
      _currentSpeedMps = 0.0;
    });
    _restartLocationTimer();

    // Update status ke Firestore: tidak aktif (supaya penumpang tidak lihat driver aktif)
    if (currentPos != null) {
      _updateDriverStatusToFirestore(currentPos);
    }

    // Simpan sesi & riwayat hanya jika ada penumpang/kirim barang yang sudah selesai.
    // Rute tanpa penumpang/barang selesai tidak disimpan (tidak perlu kontribusi).
    try {
      final completedOrders = await OrderService.getCompletedOrdersForRoute(
        journeyNumber ?? '',
        scheduleId: scheduleId,
        legacyScheduleId:
            scheduleId != null ? ScheduleIdUtil.toLegacy(scheduleId) : null,
      );
      if (completedOrders.isEmpty) return;

      final effectiveOrigin = originText.trim().isNotEmpty
          ? originText.trim()
          : 'Lokasi awal';
      final effectiveDest = destText.trim().isNotEmpty
          ? destText.trim()
          : 'Tujuan';
      await RouteSessionService.saveCurrentRouteSession(
        routeJourneyNumber: journeyNumber ?? '',
        scheduleId: scheduleId,
        routeOriginText: effectiveOrigin,
        routeDestText: effectiveDest,
        routeOriginLat: originLatLng?.latitude,
        routeOriginLng: originLatLng?.longitude,
        routeDestLat: destLatLng?.latitude,
        routeDestLng: destLatLng?.longitude,
        routeStartedAt: startedAt,
      );
      if (originLatLng != null && destLatLng != null) {
        await TripService.saveCompletedTrip(
          routeOriginLat: originLatLng.latitude,
          routeOriginLng: originLatLng.longitude,
          routeDestLat: destLatLng.latitude,
          routeDestLng: destLatLng.longitude,
          routeOriginText: effectiveOrigin,
          routeDestText: effectiveDest,
          routeJourneyNumber: journeyNumber,
          routeStartedAt: startedAt,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Riwayat rute disimpan sebagian. ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _onToggleButtonTap({bool isDriverVerified = true}) async {
    HapticFeedback.mediumImpact();
    // Jika ada alternatif rute tapi belum dipilih, tidak bisa mulai bekerja
    if (_alternativeRoutes.isNotEmpty && !_routeSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih rute yang diinginkan di map terlebih dahulu dengan tap pada polyline rute.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Tombol "Mulai" akan menangani mulai bekerja (lihat method _onStartButtonTap)

    if (_isDriverWorking) {
      // Jika masih ada penumpang/barang (agreed atau picked_up), tidak boleh berhenti bekerja
      if (_hasActiveOrder) {
        String msg;
        if (_jumlahPenumpang > 0 && _jumlahBarang > 0) {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahPenumpang penumpang dan $_jumlahBarang kirim barang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        } else if (_jumlahPenumpang > 0) {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahPenumpang penumpang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        } else {
          msg =
              'Tidak bisa berhenti bekerja. Masih ada $_jumlahBarang kirim barang yang belum selesai. Selesaikan semua pesanan terlebih dahulu.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      // Konfirmasi: Apakah pekerjaan telah selesai? Ya -> selesai, tombol kembali ke Siap Kerja
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(TrakaL10n.of(context).finishWork),
          content: Text(TrakaL10n.of(context).finishWorkConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Tidak'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ya'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await _endWork();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pekerjaan selesai. Tombol kembali ke Siap Kerja.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // Tombol hijau: cek pesanan terjadwal dulu, lalu pilih rute atau gunakan rute jadwal
      _checkScheduledOrdersThenShowRouteSheet(
        isDriverVerified: isDriverVerified,
      );
    }
  }

  /// Jika driver punya pesanan terjadwal (agreed/picked_up), tawarkan gunakan rute jadwal; else tampilkan sheet pilih jenis rute.
  Future<void> _checkScheduledOrdersThenShowRouteSheet({
    required bool isDriverVerified,
  }) async {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    final orders = await OrderService.getDriverScheduledOrdersWithAgreed();
    if (!mounted) return;
    if (orders.isEmpty) {
      _showRouteTypeSheet(isDriverVerified: isDriverVerified);
      return;
    }
    final first = orders.first;
    final scheduleId = first.scheduleId;
    final originText = first.originText;
    final destText = first.destText;
    final dateLabel = _formatScheduledDateForDialog(first.scheduledDate ?? '');

    final useJadwal = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesanan terjadwal'),
        content: Text(
          'Anda punya pesanan terjadwal di tanggal $dateLabel dan sudah ada pemesan yang setuju. '
          'Tinggal klik icon Rute di Jadwal & Rute, rute akan berjalan otomatis tanpa atur ulang.\n\n'
          'Gunakan rute sesuai jadwal?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sesuai rute'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (useJadwal == true &&
        scheduleId != null &&
        originText.isNotEmpty &&
        destText.isNotEmpty) {
      setState(() {
        _currentIndex = 0;
        _pendingJadwalRouteLoad = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isDriverVerified)
          _loadRouteFromJadwal(originText, destText, scheduleId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih rute di map (tap garis), lalu tap Mulai Rute ini untuk mulai bekerja.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      _showRouteTypeSheet(isDriverVerified: isDriverVerified);
    }
  }

  static String _formatScheduledDateForDialog(String ymd) {
    if (ymd.length != 10 || ymd[4] != '-' || ymd[7] != '-') return ymd;
    final y = ymd.substring(0, 4);
    final m = int.tryParse(ymd.substring(5, 7)) ?? 0;
    final d = ymd.substring(8, 10);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    if (m < 1 || m > 12) return ymd;
    return '$d ${months[m - 1]} $y';
  }

  void _showSessionInvalidSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Sesi tidak valid. Silakan login ulang untuk melanjutkan.',
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Ke Profil',
          textColor: Colors.white,
          onPressed: () => setState(() => _currentIndex = 4),
        ),
      ),
    );
  }

  /// Handler untuk tombol "Mulai" - mulai bekerja setelah rute dipilih
  Future<void> _onStartButtonTap() async {
    HapticFeedback.mediumImpact();
    if (!_routeSelected || _selectedRouteIndex < 0) return;
    if (_isStartRouteLoading) return;

    if (mounted) setState(() => _isStartRouteLoading = true);
    try {
      await _onStartButtonTapImpl();
    } finally {
      if (mounted) setState(() => _isStartRouteLoading = false);
    }
  }

  Future<void> _onStartButtonTapImpl() async {
    // Pastikan journey number sudah ada (bisa masih di-generate di background)
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      if (FirebaseAuth.instance.currentUser == null) {
        if (mounted) {
          _showSessionInvalidSnackBar();
        }
        return;
      }
      try {
        final jn =
            await RouteJourneyNumberService.generateRouteJourneyNumber();
        if (!mounted) return;
        setState(() => _routeJourneyNumber = jn);
      } on FirebaseFunctionsException catch (e) {
        if (mounted) {
          final msg = e.code == 'unauthenticated'
              ? 'Sesi tidak valid. Silakan login ulang untuk melanjutkan.'
              : 'Gagal mempersiapkan rute: ${e.message}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red,
              action: e.code == 'unauthenticated'
                  ? SnackBarAction(
                      label: 'Ke Profil',
                      textColor: Colors.white,
                      onPressed: () => setState(() => _currentIndex = 4),
                    )
                  : null,
            ),
          );
        }
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal mempersiapkan rute: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mulai bekerja'),
        content: const Text('Mulai bekerja dengan rute ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDriverWorking = true;
      _destinationReachedAt = null;
      // Simpan posisi saat mulai bekerja untuk deteksi pergerakan
      _positionWhenStarted = _currentPosition;
      _hasMovedAfterStart = false; // Reset flag pergerakan
      _isMovingStable = false;
      _movementDebounceTimer?.cancel();
      _lastPositionForMovement =
          null; // Reset posisi untuk deteksi pergerakan real-time
      if (_currentPosition != null) {
        final raw = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        // Selalu pakai GPS mentah agar titik biru = lokasi HP/driver akurat.
        _displayedPosition = raw;
        _targetPosition = raw;
      }
    });
    _restartLocationTimer();

    // Load icon mobil MERAH saat mulai bekerja (belum bergerak)
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      _displayedBearing = _currentPosition!.heading;
      _smoothedBearing = _displayedBearing;
    }
    await _loadCarIconsOnce();

    // Hitung jarak dan estimasi waktu awal dari posisi driver ke tujuan
    if (_currentPosition != null && _routeDestLatLng != null) {
      await _updateCurrentDistanceAndDuration(_currentPosition!);
    }

    _registerRouteBackgroundHandler();
    _persistCurrentRoute();
    if (_currentPosition != null) {
      _updateDriverStatusToFirestore(_currentPosition!);
    }
    // Sembunyikan jadwal hari ini agar tidak tampil ke penumpang saat mencari travel
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      DriverScheduleService.markTodaySchedulesHidden(uid);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pekerjaan dimulai. Status: Berhenti Kerja.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _showDriverMapHintOnce();
      // Intro cinematic: center + zoom ke driver (delay 200ms biar UI settle dulu, ala Grab)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && _isDriverWorking) _animateCameraIntroOnStart();
      });
    }
  }

  static const String _keyDriverMapHintShown = 'driver_map_hint_shown';

  Future<void> _showDriverMapHintOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyDriverMapHintShown) == true) return;
      await prefs.setBool(_keyDriverMapHintShown, true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ini posisi Anda. Garis biru = rute Anda. Geser peta untuk lihat jalan lain.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF1976D2),
        ),
      );
    } catch (_) {}
  }

  void _showRouteInfoBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                controller: controller,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                  ),
                  child: DriverRouteInfoPanel(
              isNavigatingToPassenger: _navigatingToOrderId != null,
              routeToPassengerDistanceText: _routeToPassengerDistanceText,
              routeToPassengerDurationText: _routeToPassengerDurationText,
              waitingPassengerCount: _waitingPassengerCount,
              routeInfoPanelExpanded: true,
              onTogglePanel: () => Navigator.pop(ctx),
              onExitNavigating: _exitNavigatingToPassenger,
              onOperDriver: () {
                Navigator.pop(ctx);
                _showOperDriverSheet();
              },
              displayDistance: _currentDistanceText.isNotEmpty
                  ? _currentDistanceText
                  : _routeDistanceText,
              displayDuration: _currentDurationText.isNotEmpty
                  ? _currentDurationText
                  : _routeDurationText,
              originLocationText: _originLocationText,
              currentPosition: _currentPosition,
              routeDestText: _routeDestText,
              jumlahPenumpang: _jumlahPenumpang,
              jumlahBarang: _jumlahBarang,
              jumlahPenumpangPickedUp: _jumlahPenumpangPickedUp,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOperDriverSheet() {
    final pickedUpOrders = _driverOrders
        .where(
          (o) =>
              o.status == OrderService.statusPickedUp &&
              o.orderType == OrderModel.typeTravel,
        )
        .toList();
    if (pickedUpOrders.isEmpty) return;

    showOperDriverSheet(
      context,
      orders: pickedUpOrders,
      onTransfersCreated: (transfers) =>
          showOperDriverBarcodeDialog(context, transfers: transfers),
    );
  }

  void _showRouteTypeSheet({required bool isDriverVerified}) {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    final hasPreviousRoute =
        _routeOriginLatLng != null && _routeDestLatLng != null;
    final atDestination =
        _routeDestLatLng != null &&
        _currentPosition != null &&
        Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              _routeDestLatLng!.latitude,
              _routeDestLatLng!.longitude,
            ) <=
            _atDestinationMeters;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih jenis rute',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih area tujuan perjalanan Anda',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.location_city,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Dalam provinsi'),
              subtitle: const Text('Tujuan hanya di provinsi Anda'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.dalamProvinsi,
                  isDriverVerified: isDriverVerified,
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.landscape,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Antar provinsi (satu pulau)'),
              subtitle: const Text('Ke provinsi lain di pulau yang sama'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.antarProvinsi,
                  isDriverVerified: isDriverVerified,
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.public,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Seluruh Indonesia'),
              subtitle: const Text('Ke mana saja di Indonesia (lintas pulau)'),
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.dalamNegara,
                  isDriverVerified: isDriverVerified,
                );
              },
            ),
            if (hasPreviousRoute && atDestination) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.green),
                title: const Text('Putar Arah Rute sebelumnya'),
                subtitle: const Text(
                  'Arah perjalanan dibalik (tujuan jadi awal, awal jadi tujuan)',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _reversePreviousRoute();
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Dari Jadwal & Rute (icon rute): muat rute langsung dari tujuan awal/akhir jadwal.
  /// Jika [routePolyline] tersimpan, pakai langsung dan pre-select. Jika tidak, fetch alternatif.
  Future<void> _loadRouteFromJadwal(
    String originText,
    String destText, [
    String? scheduleId,
    List<LatLng>? routePolyline,
    String? routeCategory,
  ]) async {
    try {
      final originLocations = await GeocodingService.locationFromAddress(
        '$originText, Indonesia',
        appendIndonesia: false,
      );
      final destLocations = await GeocodingService.locationFromAddress(
        '$destText, Indonesia',
        appendIndonesia: false,
      );
      if (originLocations.isEmpty || destLocations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lokasi awal atau tujuan tidak ditemukan.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final originLat = originLocations.first.latitude;
      final originLng = originLocations.first.longitude;
      final destLat = destLocations.first.latitude;
      final destLng = destLocations.first.longitude;

      List<DirectionsResult> alternatives;
      int preSelectedIndex;
      bool preSelected;

      if (routePolyline != null && routePolyline.length >= 2) {
        // Rute tersimpan: pakai langsung, pre-select
        double totalM = 0;
        for (int i = 0; i < routePolyline.length - 1; i++) {
          totalM += Geolocator.distanceBetween(
            routePolyline[i].latitude,
            routePolyline[i].longitude,
            routePolyline[i + 1].latitude,
            routePolyline[i + 1].longitude,
          );
        }
        final km = totalM / 1000;
        final durSec = (totalM / 1000 * 3600 / 40).round(); // ~40 km/jam
        alternatives = [
          DirectionsResult(
            points: routePolyline,
            distanceKm: km,
            distanceText: '${km.toStringAsFixed(1)} km',
            durationSeconds: durSec,
            durationText: durSec >= 3600
                ? '${durSec ~/ 3600} jam ${(durSec % 3600) ~/ 60} mnt'
                : '${durSec ~/ 60} menit',
          ),
        ];
        preSelectedIndex = 0;
        preSelected = true;
      } else {
        // Belum ada rute tersimpan: fetch alternatif
        alternatives = await DirectionsService.getAlternativeRoutes(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          trafficAware: _trafficEnabled,
        );
        preSelectedIndex = -1;
        preSelected = false;
      }

      if (!mounted) return;
      if (alternatives.isEmpty) {
        setState(() => _pendingJadwalRouteLoad = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).failedToLoadRoute),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final selRoute = preSelected && preSelectedIndex >= 0 && preSelectedIndex < alternatives.length
          ? alternatives[preSelectedIndex]
          : null;

      setState(() {
        _routeOriginLatLng = LatLng(originLat, originLng);
        _routeDestLatLng = LatLng(destLat, destLng);
        _routeOriginText = originText;
        _routeDestText = destText;
        _alternativeRoutes = alternatives;
        _selectedRouteIndex = preSelectedIndex;
        _routeSelected = preSelected;
        _isDriverWorking = false;
        _routePolyline = selRoute?.points;
        _routeDistanceText = selRoute?.distanceText ?? '';
        _routeDurationText = selRoute?.durationText ?? '';
        _activeRouteFromJadwal = true;
        _currentScheduleId = scheduleId;
        _currentRouteCategory = routeCategory;
        _pendingJadwalRouteLoad = false;
      });

      if (mounted) {
        if (preSelected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rute sudah dipilih. Tap Mulai Rute ini untuk mulai bekerja.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).selectRouteOnMapHint),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitAlternativeRoutesBounds();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pendingJadwalRouteLoad = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TrakaL10n.of(context).failedToLoadRoute} $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _reversePreviousRoute() async {
    final origin = _routeOriginLatLng ?? _lastRouteOriginLatLng;
    final dest = _routeDestLatLng ?? _lastRouteDestLatLng;
    if (origin == null || dest == null) return;
    final newOrigin = dest;
    final newDest = origin;
    final prevOriginText = _routeOriginText.isNotEmpty
        ? _routeOriginText
        : _lastRouteOriginText;
    final prevDestText = _routeDestText.isNotEmpty
        ? _routeDestText
        : _lastRouteDestText;
    setState(() {
      _routeOriginLatLng = newOrigin;
      _routeDestLatLng = newDest;
      _routeOriginText = prevDestText;
      _routeDestText = prevOriginText;
      _activeRouteFromJadwal = false;
      _currentScheduleId = null;
      _currentRouteCategory = null;
    });
    // Ambil semua alternatif rute (dengan ETA lalu lintas jika layer aktif)
    final alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: newOrigin.latitude,
      originLng: newOrigin.longitude,
      destLat: newDest.latitude,
      destLng: newDest.longitude,
      trafficAware: _trafficEnabled,
    );
    if (mounted && alternatives.isNotEmpty) {
      // Tampilkan alternatif rute di map, tunggu driver pilih
      setState(() {
        _routeOriginLatLng = newOrigin;
        _routeDestLatLng = newDest;
        _routeOriginText = prevDestText;
        _routeDestText = prevOriginText;
        _alternativeRoutes = alternatives;
        _selectedRouteIndex = -1; // Belum dipilih
        _routeSelected = false; // Belum dipilih
        _isDriverWorking =
            false; // Tombol tetap "Siap Kerja" sampai rute dipilih
        _routePolyline = null; // Belum ada rute yang dipilih
        _routeDistanceText = '';
        _routeDurationText = '';
        _activeRouteFromJadwal = false;
        _currentScheduleId = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAlternativeRoutesBounds();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pilih rute yang diinginkan di map. Gunakan tombol di bawah peta atau tap garis rute.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _openRouteForm(
    RouteType routeType, {
    String? initialDest,
    String? initialOrigin,
    bool isDriverVerified = true,
  }) {
    if (!isDriverVerified) {
      _showDriverLengkapiVerifikasiDialog();
      return;
    }
    setState(() {
      _activeRouteFromJadwal = false;
      _currentScheduleId = null;
      _currentRouteCategory = null;
    });
    final sameProvinceOnly = routeType == RouteType.dalamProvinsi;
    final sameIslandOnly = routeType == RouteType.antarProvinsi;
    final provincesInIsland =
        sameIslandOnly && (_currentProvinsi ?? '').isNotEmpty
        ? ProvinceIsland.getProvincesInSameIsland(_currentProvinsi!)
        : null;
    final currentContext = context; // Capture context for use in callback
    showModalBottomSheet<void>(
      context: currentContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DriverRouteFormSheet(
        originText: _originLocationText,
        currentProvinsi: _currentProvinsi,
        sameProvinceOnly: sameProvinceOnly,
        sameIslandOnly: sameIslandOnly,
        provincesInIsland: provincesInIsland ?? [],
        driverLat: _currentPosition?.latitude,
        driverLng: _currentPosition?.longitude,
        initialDest: initialDest,
        initialOrigin: initialOrigin,
        mapController: _mapController,
        formDestMapModeNotifier: _formDestMapModeNotifier,
        formDestMapTapNotifier: _formDestMapTapNotifier,
        formDestPreviewNotifier: _formDestPreviewNotifier,
        onRouteRequest:
            (
              originLat,
              originLng,
              originText,
              destLat,
              destLng,
              destText,
            ) async {
              Navigator.pop(ctx);
              // Ambil semua alternatif rute (dengan ETA lalu lintas jika layer aktif)
              final alternatives = await DirectionsService.getAlternativeRoutes(
                originLat: originLat,
                originLng: originLng,
                destLat: destLat,
                destLng: destLng,
                trafficAware: _trafficEnabled,
              );
              if (!mounted) return;
              if (alternatives.isNotEmpty) {
                // Tampilkan alternatif rute di map, tunggu driver pilih
                setState(() {
                  _routeOriginLatLng = LatLng(originLat, originLng);
                  _routeDestLatLng = LatLng(destLat, destLng);
                  _routeOriginText = originText;
                  _routeDestText = destText;
                  _alternativeRoutes = alternatives;
                  _selectedRouteIndex = -1; // Belum dipilih
                  _routeSelected = false; // Belum dipilih
                  _isDriverWorking =
                      false; // Tombol tetap "Siap Kerja" sampai rute dipilih
                  _routePolyline = null; // Belum ada rute yang dipilih
                  _routeDistanceText = '';
                  _routeDurationText = '';
                });

                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fitAlternativeRoutesBounds();
                  });
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Pilih rute yang diinginkan di map. Gunakan tombol di bawah peta atau tap garis rute.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        TrakaL10n.of(currentContext).failedToLoadRouteDirections,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
      ),
    );
  }

  void _toggleMapType() {
    setState(() {
      // Toggle antara normal dan hybrid (satelit dengan label)
      _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  void _toggleTraffic() {
    setState(() => _trafficEnabled = !_trafficEnabled);
  }

  /// Zoom out peta agar seluruh rute alternatif terlihat.
  void _fitAlternativeRoutesBounds() {
    if (_mapController == null || _alternativeRoutes.isEmpty || !mounted)
      return;
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final route in _alternativeRoutes) {
      for (final p in route.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    if (_routeOriginLatLng != null) {
      minLat = minLat < _routeOriginLatLng!.latitude
          ? minLat
          : _routeOriginLatLng!.latitude;
      maxLat = maxLat > _routeOriginLatLng!.latitude
          ? maxLat
          : _routeOriginLatLng!.latitude;
      minLng = minLng < _routeOriginLatLng!.longitude
          ? minLng
          : _routeOriginLatLng!.longitude;
      maxLng = maxLng > _routeOriginLatLng!.longitude
          ? maxLng
          : _routeOriginLatLng!.longitude;
    }
    if (_routeDestLatLng != null) {
      minLat = minLat < _routeDestLatLng!.latitude
          ? minLat
          : _routeDestLatLng!.latitude;
      maxLat = maxLat > _routeDestLatLng!.latitude
          ? maxLat
          : _routeDestLatLng!.latitude;
      minLng = minLng < _routeDestLatLng!.longitude
          ? minLng
          : _routeDestLatLng!.longitude;
      maxLng = maxLng > _routeDestLatLng!.longitude
          ? maxLng
          : _routeDestLatLng!.longitude;
    }
    if (minLat != double.infinity && maxLat != -double.infinity && mounted) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          100,
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Jangan zoom otomatis sebelum driver klik "Mulai Rute ini"
    if (_alternativeRoutes.isNotEmpty && !_isDriverWorking) return;
    if (_pendingJadwalRouteLoad) return; // Akan load rute dari jadwal
    // Zoom ke driver hanya jika tidak ada rute atau sudah mulai bekerja
    if (_currentPosition != null && mounted) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          MapStyleService.defaultZoom,
        ),
      );
    }
  }

  /// Load titik biru untuk marker posisi driver saat !chaseCamActive.
  Future<void> _loadBlueDotOnce() async {
    if (_blueDotIcon != null) return;
    if (!mounted) return;
    try {
      final sizePx = context.responsive.iconSize(48).round().clamp(40, 56);
      final icon = await DriverLocationIconService.loadBlueDotDescriptor(
        sizePx: sizePx,
      );
      if (mounted) {
        _blueDotIcon = icon;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _blueDotIcon = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        );
        setState(() {});
      }
    }
  }

  /// Load icon mobil merah & hijau sekali (tanpa rotasi). Rotasi pakai Marker.rotation.
  /// Asset: mobil menghadap ke bawah (selatan). rotation = (bearing + 180) % 360.
  Future<void> _loadCarIconsOnce() async {
    if (_carIconRed != null && _carIconGreen != null) return;
    if (!mounted) return;
    try {
      final result = await CarIconService.loadCarIcons(
        context: context,
        baseSize: 16,
        padding: 0,
      );
      if (mounted) {
        _carIconRed = result.red;
        _carIconGreen = result.green;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        _carIconRed = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        );
        _carIconGreen = BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        );
        setState(() {});
      }
    }
  }

  Future<void> _loadDriverCarMarkerAsync(
    String cacheKey,
    String streetName,
    bool isMoving,
    double speedKmh,
  ) async {
    if (_driverCarMarkerCache.containsKey(cacheKey)) return;
    if (!mounted) return;
    try {
      final icon = await DriverCarMarkerService.createDriverCarMarker(
        isMoving: isMoving,
        streetName: streetName,
        speedKmh: speedKmh,
      );
      if (!mounted) return;
      if (_driverCarMarkerCache.length >= _maxDriverCarMarkerCache) {
        final first = _driverCarMarkerCache.keys.first;
        _driverCarMarkerCache.remove(first);
      }
      _driverCarMarkerCache[cacheKey] = icon;
      setState(() {});
    } catch (_) {}
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};
    final chaseCamActive =
        _isDriverWorking || _navigatingToOrderId != null;
    if (_currentPosition != null) {
      final displayLatLng =
          _displayedPosition ??
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

      if (chaseCamActive) {
        // Marker ala Grab: dot (idle) + arrow (moving). Debounce + adaptive speed.
        final isMoving = _isMovingStable;
        final speedKmh = _currentSpeedMps * 3.6;
        final tier = MarkerAssets.speedTier(speedKmh);
        final cacheKey = '${_currentStreetName}__${isMoving}__$tier';
        var icon = _driverCarMarkerCache[cacheKey];
        if (icon == null) {
          _loadDriverCarMarkerAsync(cacheKey, _currentStreetName, isMoving, speedKmh);
          icon = isMoving ? _carIconGreen : _carIconRed;
          icon ??= BitmapDescriptor.defaultMarkerWithHue(
            isMoving ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
          );
        }
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: displayLatLng,
            icon: icon,
            rotation: _smoothedBearing,
            flat: true,
            anchor: const Offset(0.5, 0.33),
          ),
        );
      } else {
        // Beranda driver: titik biru besar (rute dipilih, belum mulai).
        final icon = _blueDotIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: displayLatLng,
            icon: icon,
            flat: true,
            anchor: const Offset(0.5, 0.5),
          ),
        );
      }
    }
    // Pin asal: sembunyikan saat driver bekerja—icon mobil sudah penanda lokasi.
    // Jangan tampilkan jika origin dekat lokasi driver (hindari 2 pin bertumpuk).
    final originNearDriver = _routeOriginLatLng != null &&
        _currentPosition != null &&
        Geolocator.distanceBetween(
          _routeOriginLatLng!.latitude,
          _routeOriginLatLng!.longitude,
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ) < 100; // < 100m = sama lokasi
    if (_routeOriginLatLng != null &&
        !_isDriverWorking &&
        _navigatingToOrderId == null &&
        !originNearDriver) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _routeOriginLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }
    if (_routeDestLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _routeDestLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    // Preview tujuan dari form (saat isi form rute, sebelum submit).
    // Jangan tampilkan jika rute sudah punya destination—hindari 2 pin di tujuan.
    final formPreview = _formDestPreviewNotifier.value;
    if (formPreview != null && _routeDestLatLng == null) {
      markers.add(
        Marker(
          markerId: const MarkerId('form_dest_preview'),
          position: formPreview,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    // Pin pemesan (penumpang/barang): tampilkan SEMUA yang sesuai rute saat ini (multi penumpang).
    // Pickup (agreed): kuning. Dropoff (picked_up): hijau. Completed: tidak tampil.
    // Tampilkan saat driver bekerja, navigasi, atau punya rute + order (beranda dengan rute terjadwal).
    final hasRoute = _routeOriginLatLng != null && _routeDestLatLng != null;
    final todayYmd = _todayYmd();
    final visiblePickups = <OrderModel>[];
    final visibleDropoffs = <OrderModel>[];
    if (chaseCamActive || hasRoute) {
      for (final order in _driverOrders) {
        if (order.status == OrderService.statusCompleted) continue;
        if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
        if (order.orderType != OrderModel.typeTravel &&
            order.orderType != OrderModel.typeKirimBarang) continue;

        if (order.status == OrderService.statusAgreed && !order.hasDriverScannedPassenger) {
          final lat = order.passengerLat ?? order.originLat;
          final lng = order.passengerLng ?? order.originLng;
          if (lat != null && lng != null) visiblePickups.add(order);
        } else if (order.status == OrderService.statusPickedUp) {
          final (lat, lng) = _getOrderDestinationLatLng(order);
          if (lat != null && lng != null) visibleDropoffs.add(order);
        }
      }
    }
    final visibleOrders = [...visiblePickups, ...visibleDropoffs];
    // Urutan jemput: sort by posisi sepanjang rute (untuk pickup)
    final routePolyline =
        _routePolyline ??
        (_alternativeRoutes.isNotEmpty &&
                _selectedRouteIndex >= 0 &&
                _selectedRouteIndex < _alternativeRoutes.length
            ? _alternativeRoutes[_selectedRouteIndex].points
            : null);
    if (visiblePickups.length > 1 &&
        routePolyline != null &&
        routePolyline.isNotEmpty) {
      visiblePickups.sort((a, b) {
        final posA = LatLng(
          a.passengerLiveLat ?? a.passengerLat ?? a.originLat!,
          a.passengerLiveLng ?? a.passengerLng ?? a.originLng!,
        );
        final posB = LatLng(
          b.passengerLiveLat ?? b.passengerLat ?? b.originLat!,
          b.passengerLiveLng ?? b.passengerLng ?? b.originLng!,
        );
        final idxA = RouteUtils.getIndexAlongPolyline(
          posA,
          routePolyline,
          toleranceMeters: 50000,
        );
        final idxB = RouteUtils.getIndexAlongPolyline(
          posB,
          routePolyline,
          toleranceMeters: 50000,
        );
        if (idxA < 0 && idxB < 0) return 0;
        if (idxA < 0) return 1;
        if (idxB < 0) return -1;
        return idxA.compareTo(idxB);
      });
    }
    final visiblePassengerOrderIds = visibleOrders.map((o) => o.id).toSet();

    // Marker pickup (kuning) dan dropoff (hijau)
    int pickupIndex = 0;
    for (final order in visiblePickups) {
      pickupIndex++;
      final pos = LatLng(
        order.passengerLiveLat ?? order.passengerLat ?? order.originLat!,
        order.passengerLiveLng ?? order.passengerLng ?? order.originLng!,
      );
      final isNavigatingTo = order.id == _navigatingToOrderId && !_navigatingToDestination;
      final defaultIcon = order.isKirimBarang
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      final icon = isNavigatingTo
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : (_passengerMarkerIcons[order.id] ?? defaultIcon);
      final pickupOrder = visiblePickups.length > 1 ? pickupIndex : null;
      final snippet = order.isKirimBarang ? 'Kirim barang' : 'Penumpang';
      final snippetWithOrder = pickupOrder != null
          ? '$snippet • Jemput ke-$pickupOrder'
          : snippet;
      markers.add(
        Marker(
          markerId: MarkerId('passenger_pickup_${order.id}'),
          position: pos,
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: order.passengerName,
            snippet: snippetWithOrder,
          ),
          onTap: () => _onPassengerMarkerTap(order),
        ),
      );
    }
    for (final order in visibleDropoffs) {
      final (lat, lng) = _getOrderDestinationLatLng(order);
      if (lat == null || lng == null) continue;
      final pos = LatLng(lat, lng);
      final isNavigatingTo = order.id == _navigatingToOrderId && _navigatingToDestination;
      final defaultIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      final icon = isNavigatingTo
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : (_passengerMarkerIcons['${order.id}_drop'] ?? defaultIcon);
      final label = order.isKirimBarang ? 'Tujuan barang' : 'Tujuan';
      markers.add(
        Marker(
          markerId: MarkerId('passenger_drop_${order.id}'),
          position: pos,
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: order.destText.isNotEmpty
                ? order.destText
                : (order.isKirimBarang ? 'Lokasi penerima' : order.passengerName),
            snippet: label,
          ),
          onTap: () => _onDropoffMarkerTap(order),
        ),
      );
    }
    // Hapus cache icon untuk order yang tidak lagi ditampilkan
    _passengerMarkerIcons.removeWhere(
      (id, _) => !visiblePassengerOrderIds.contains(id),
    );
    // Marker tujuan saat pengantaran (oranye)
    if (_navigatingToDestination &&
        _navigatingToOrderId != null &&
        _lastDestinationLat != null &&
        _lastDestinationLng != null) {
      OrderModel? navOrder;
      for (final o in _driverOrders) {
        if (o.id == _navigatingToOrderId) {
          navOrder = o;
          break;
        }
      }
      if (navOrder != null) {
        final destPos = LatLng(_lastDestinationLat!, _lastDestinationLng!);
        markers.add(
          Marker(
            markerId: const MarkerId('destination_pengantaran'),
            position: destPos,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            anchor: const Offset(0.5, 1.0),
            infoWindow: InfoWindow(
              title: navOrder.destText.isNotEmpty
                  ? navOrder.destText
                  : (navOrder.isKirimBarang ? 'Lokasi penerima' : 'Tujuan'),
              snippet: 'Menuju tujuan',
            ),
          ),
        );
      }
    }
    return markers;
  }

  static String _todayYmd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Jumlah penumpang/barang yang menunggu (agreed, belum dijemput) - untuk badge.
  int get _waitingPassengerCount {
    return _waitingPassengerOrders.length;
  }

  /// Daftar penumpang/barang yang sudah dijemput dan menunggu diantar - untuk overlay "Menuju tujuan".
  List<OrderModel> get _pickedUpOrdersForDestination {
    final todayYmd = _todayYmd();
    final list = <OrderModel>[];
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusPickedUp) continue;
      if (order.orderType != OrderModel.typeTravel &&
          order.orderType != OrderModel.typeKirimBarang) continue;
      if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
      final (lat, lng) = _getOrderDestinationLatLng(order);
      if (lat == null || lng == null) continue;
      list.add(order);
    }
    return list;
  }

  /// Prioritas target: stop pertama dari _optimizedStops (#7 + #8 insert).
  /// Returns (order, isPickup). Null = tidak ada stop, driver ke tujuan utama.
  (OrderModel?, bool)? get _nextTargetForNavigation {
    final stops = _optimizedStops;
    if (stops.isEmpty) return null;
    final first = stops.first;
    return (first.order, first.isPickup);
  }

  /// Daftar stop dalam urutan greedy optimal (untuk panel list #7).
  /// #8: gunakan insert optimization saat order baru masuk (hanya tambah, tidak ada yang hilang).
  List<({OrderModel order, bool isPickup})> get _optimizedStops {
    if (_currentPosition == null) return [];
    final driverPos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final pickups = _waitingPassengerOrders;
    final dropoffs = _pickedUpOrdersForDestination;
    final currentPickupIds = pickups.map((o) => o.id).toSet();
    final currentDropoffIds = dropoffs.map((o) => o.id).toSet();
    final newPickupIds = currentPickupIds.difference(_lastPickupOrderIds);
    final removedPickupIds = _lastPickupOrderIds.difference(currentPickupIds);
    final removedDropoffIds = _lastDropoffOrderIds.difference(currentDropoffIds);

    final positionMoved = _lastPositionForOptimizedStops != null &&
        Geolocator.distanceBetween(
          _lastPositionForOptimizedStops!.latitude,
          _lastPositionForOptimizedStops!.longitude,
          driverPos.latitude,
          driverPos.longitude,
        ) > _invalidateCacheDistanceMeters;
    if (positionMoved) {
      _lastOptimizedStops = null;
      _lastPickupOrderIds.clear();
      _lastDropoffOrderIds.clear();
      _lastPositionForOptimizedStops = null;
    }

    final useInsert = _lastOptimizedStops != null &&
        !positionMoved &&
        newPickupIds.isNotEmpty &&
        removedPickupIds.isEmpty &&
        removedDropoffIds.isEmpty;

    if (useInsert) {
      var route = _lastOptimizedStops!;
      for (final order in pickups) {
        if (!newPickupIds.contains(order.id)) continue;
        final inserted = RouteOptimizationService.insertOrderOptimal(
          driverPos,
          route,
          order,
          maxCapacity: _cachedDriverMaxCapacity,
          kargoSlotPerOrder: _cachedKargoSlotPerOrder,
        );
        if (inserted == null || inserted.isEmpty) break;
        route = inserted;
      }
      _lastOptimizedStops = route;
      _lastPositionForOptimizedStops = driverPos;
      _lastPickupOrderIds.clear();
      _lastPickupOrderIds.addAll(currentPickupIds);
      _lastDropoffOrderIds.clear();
      _lastDropoffOrderIds.addAll(currentDropoffIds);
      return route;
    }

    final result = RouteOptimizationService.optimizeStops(
      driverPos,
      pickups,
      dropoffs,
      maxCapacity: _cachedDriverMaxCapacity,
      kargoSlotPerOrder: _cachedKargoSlotPerOrder,
    );
    _lastOptimizedStops = result;
    _lastPositionForOptimizedStops = driverPos;
    _lastPickupOrderIds.clear();
    _lastPickupOrderIds.addAll(currentPickupIds);
    _lastDropoffOrderIds.clear();
    _lastDropoffOrderIds.addAll(currentDropoffIds);
    return result;
  }

  static (double?, double?) _getOrderDestinationLatLng(OrderModel order) {
    if (order.isKirimBarang) {
      return (
        order.receiverLat ?? order.destLat,
        order.receiverLng ?? order.destLng,
      );
    }
    return (order.destLat, order.destLng);
  }

  /// Cek apakah order termasuk dalam rute aktif saat ini (untuk tampilan map).
  bool _isOrderForCurrentRoute(OrderModel order, String todayYmd) {
    if (order.isScheduledOrder) {
      if (_currentScheduleId == null ||
          _currentScheduleId != order.scheduleId ||
          (order.scheduledDate ?? '') != todayYmd) {
        return false;
      }
      return true;
    }
    if (_isDriverWorking && _routeJourneyNumber != null) {
      return order.routeJourneyNumber == _routeJourneyNumber;
    }
    if (_routeJourneyNumber != null && _routeJourneyNumber!.isNotEmpty) {
      return order.routeJourneyNumber == _routeJourneyNumber;
    }
    return false;
  }

  /// Daftar penumpang/barang yang menunggu (agreed, belum dijemput) - untuk daftar di bawah zoom.
  List<OrderModel> get _waitingPassengerOrders {
    final todayYmd = _todayYmd();
    final list = <OrderModel>[];
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger) continue;
      final lat = order.passengerLat ?? order.originLat;
      final lng = order.passengerLng ?? order.originLng;
      if (lat == null || lng == null) continue;
      if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
      list.add(order);
    }
    // Urutan jemput untuk pesanan terjadwal: sort by posisi sepanjang rute
    final routePolyline =
        _routePolyline ??
        (_alternativeRoutes.isNotEmpty &&
                _selectedRouteIndex >= 0 &&
                _selectedRouteIndex < _alternativeRoutes.length
            ? _alternativeRoutes[_selectedRouteIndex].points
            : null);
    if (list.length > 1 && routePolyline != null && routePolyline.isNotEmpty) {
      list.sort((a, b) {
        final posA = LatLng(
          a.passengerLat ?? a.originLat!,
          a.passengerLng ?? a.originLng!,
        );
        final posB = LatLng(
          b.passengerLat ?? b.originLat!,
          b.passengerLng ?? b.originLng!,
        );
        final idxA = RouteUtils.getIndexAlongPolyline(
          posA,
          routePolyline,
          toleranceMeters: 50000,
        );
        final idxB = RouteUtils.getIndexAlongPolyline(
          posB,
          routePolyline,
          toleranceMeters: 50000,
        );
        if (idxA < 0 && idxB < 0) return 0;
        if (idxA < 0) return 1;
        if (idxB < 0) return -1;
        return idxA.compareTo(idxB);
      });
    }
    return list;
  }

  /// Jumlah pesanan terjadwal untuk hari ini yang sudah kesepakatan dan belum dijemput (untuk banner pengingat).
  int get _scheduledAgreedCountForToday {
    final todayYmd = _todayYmd();
    return _driverOrders.where((o) {
      if (!o.isScheduledOrder || (o.scheduledDate ?? '') != todayYmd)
        return false;
      if (o.status != OrderService.statusAgreed &&
          o.status != OrderService.statusPickedUp)
        return false;
      return !o.hasDriverScannedPassenger;
    }).length;
  }

  Future<void> _loadPassengerMarkerIconsIfNeeded() async {
    // Load icon untuk semua penumpang pickup yang tampil di map (multi penumpang).
    final todayYmd = _todayYmd();
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger ||
          (order.passengerLat == null && order.originLat == null)) {
        continue;
      }
      if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
      if (_passengerMarkerIcons.containsKey(order.id)) continue;
      try {
        final icon = await MarkerIconService.createProfilePhotoMarker(
          name: order.passengerName.trim().isEmpty
              ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
              : order.passengerName,
          photoUrl: order.passengerPhotoUrl,
          ribbonColor: order.isKirimBarang ? Colors.blue : Colors.orange,
          fallbackCircleColor: order.isKirimBarang
              ? Colors.blue.shade300
              : Colors.orange.shade300,
        );
        if (!mounted) return;
        _passengerMarkerIcons[order.id] = icon;
        setState(() {});
      } catch (_) {
        // Tetap pakai pin oranye default
      }
    }
  }

  Future<void> _onPassengerMarkerTap(OrderModel order) async {
    final lat = order.passengerLat ?? order.originLat;
    final lng = order.passengerLng ?? order.originLng;
    if (lat == null || lng == null) return;
    final label = order.isKirimBarang ? 'barang' : 'penumpang';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ambil pemesan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  backgroundImage:
                      (order.passengerPhotoUrl != null &&
                          order.passengerPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                      : null,
                  child:
                      (order.passengerPhotoUrl == null ||
                          order.passengerPhotoUrl!.isEmpty)
                      ? Icon(
                          Icons.person,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          order.passengerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (order.isPassengerEnglish) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            TrakaL10n.of(ctx).touristBadge,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Apakah anda akan mengambil $label ini? Jika ya, anda akan diarahkan ke lokasi pemesan.',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, arahkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Tetap di Beranda: mode navigasi ke penumpang di dalam app (tidak buka Google Maps)
    await OrderService.setDriverNavigatingToPickup(order.id);
    if (!mounted) return;
    setState(() {
      _navigatingToOrderId = order.id;
      _lastPassengerLat = lat;
      _lastPassengerLng = lng;
    });
    await _fetchAndShowRouteToPassenger(order);
  }

  /// Prioritas #4: Navigasi ke stop terdekat (pickup atau dropoff).
  Future<void> _navigateToNextTarget() async {
    final next = _nextTargetForNavigation;
    if (next == null) return;
    final (order, isPickup) = next;
    if (order == null) return;

    if (isPickup) {
      await OrderService.setDriverNavigatingToPickup(order.id);
      if (!mounted) return;
      final lat = order.passengerLat ?? order.originLat;
      final lng = order.passengerLng ?? order.originLng;
      setState(() {
        _navigatingToOrderId = order.id;
        _navigatingToDestination = false;
        _lastPassengerLat = lat;
        _lastPassengerLng = lng;
      });
      _loadPassengerMarkerIconsIfNeeded();
      await _fetchAndShowRouteToPassenger(order);
    } else {
      if (!mounted) return;
      setState(() {
        _navigatingToOrderId = order.id;
        _navigatingToDestination = true;
        final (lat, lng) = _getOrderDestinationLatLng(order);
        _lastDestinationLat = lat;
        _lastDestinationLng = lng;
      });
      _fetchAndShowRouteToDestination(order);
    }
  }

  /// Saat driver klik marker tujuan (dropoff) → arahkan ke lokasi pengantaran.
  void _onDropoffMarkerTap(OrderModel order) {
    if (!mounted) return;
    setState(() {
      _navigatingToOrderId = order.id;
      _navigatingToDestination = true;
      final (lat, lng) = _getOrderDestinationLatLng(order);
      _lastDestinationLat = lat;
      _lastDestinationLng = lng;
    });
    _fetchAndShowRouteToDestination(order);
  }

  /// Re-routing saat keluar rute: garis biru ke jalan lain untuk kembali.
  Future<void> _maybeRerouteFromCurrentPosition(LatLng currentPos) async {
    if (_routeDestLatLng == null) return;
    final now = DateTime.now();
    if (_lastRerouteAt != null) {
      final secSince = now.difference(_lastRerouteAt!).inSeconds;
      if (secSince < _rerouteDebounceSeconds) return;
    }
    if (_lastReroutePosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastReroutePosition!.latitude,
        _lastReroutePosition!.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
      if (dist < _rerouteDebounceDistanceMeters) return;
    }

    final withSteps = await DirectionsService.getRouteWithSteps(
      originLat: currentPos.latitude,
      originLng: currentPos.longitude,
      destLat: _routeDestLatLng!.latitude,
      destLng: _routeDestLatLng!.longitude,
      trafficAware: _trafficEnabled,
    );
    if (!mounted) return;
    if (withSteps != null) {
      setState(() {
        _routePolyline = withSteps.result.points;
        _routeDistanceText = withSteps.result.distanceText;
        _routeDurationText = withSteps.result.durationText;
        _routeEstimatedDurationSeconds = withSteps.result.durationSeconds;
        _lastReroutePosition = currentPos;
        _lastRerouteAt = now;
        if (_alternativeRoutes.isNotEmpty && _selectedRouteIndex >= 0) {
          _alternativeRoutes = [
            ..._alternativeRoutes.sublist(0, _selectedRouteIndex),
            withSteps.result,
            ..._alternativeRoutes.sublist(_selectedRouteIndex + 1),
          ];
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rute diperbarui untuk kembali ke tujuan.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Ambil rute driver → penumpang dan tampilkan di peta. Dipanggil saat "Ya, arahkan", saat lokasi penumpang berubah, dan saat driver bergerak 2.5 km.
  Future<void> _fetchAndShowRouteToPassenger(OrderModel order) async {
    final destLat = order.passengerLiveLat ?? order.passengerLat ?? order.originLat;
    final destLng = order.passengerLiveLng ?? order.passengerLng ?? order.originLng;
    if (destLat == null || destLng == null) return;
    if (_currentPosition == null) return;
    final withSteps = await DirectionsService.getRouteWithSteps(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: destLat,
      destLng: destLng,
      trafficAware: _trafficEnabled,
    );
    if (!mounted) return;
      if (withSteps != null) {
      final result = withSteps.result;
      setState(() {
        _polylineToPassenger = result.points;
        _routeSteps = withSteps.steps;
        _currentStepIndex = _routeSteps.isNotEmpty ? 0 : -1;
        _routeToPassengerDistanceText = result.distanceText;
        _routeToPassengerDurationText = result.durationText;
        _routeToPassengerDistanceMeters = result.distanceKm * 1000;
        _routeToPassengerDurationSeconds = result.durationSeconds;
        _routeWarnings = result.warnings;
        _routeTollInfo = result.tollInfoText;
        _lastFetchRouteToPassengerPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      });
      _fitRouteToPassengerBounds();
      if (_currentPosition != null) {
        _updateCurrentStepFromPosition(_currentPosition!);
      }
      _speakCurrentStep();
      _startTrafficAlternativesCheck();
      // Fetch toll info (async, tidak blokir)
      RoutesTollService.getTollEstimate(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: order.passengerLat!,
        destLng: order.passengerLng!,
      ).then((toll) {
        if (mounted && toll != null && _navigatingToOrderId == order.id) {
          setState(() => _routeTollInfo = toll);
        }
      });
    } else {
      // Fallback: garis lurus jika API gagal
      final distM = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        order.passengerLat!,
        order.passengerLng!,
      );
      setState(() {
        _polylineToPassenger = [
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          LatLng(order.passengerLat!, order.passengerLng!),
        ];
        _routeSteps = [];
        _currentStepIndex = -1;
        _routeToPassengerDistanceText = distM < 1000
            ? '${distM.round()} m'
            : '${(distM / 1000).toStringAsFixed(1)} km';
        _routeToPassengerDurationText = '';
        _routeToPassengerDistanceMeters = distM;
        _lastFetchRouteToPassengerPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      });
      _fitRouteToPassengerBounds();
    }
  }

  /// Ambil rute driver → tujuan (destLat/destLng atau receiver) dan tampilkan di peta. Untuk pengantaran.
  Future<void> _fetchAndShowRouteToDestination(OrderModel order) async {
    final (destLat, destLng) = _getOrderDestinationLatLng(order);
    if (destLat == null || destLng == null) return;
    if (_currentPosition == null) return;
    final withSteps = await DirectionsService.getRouteWithSteps(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: destLat,
      destLng: destLng,
      trafficAware: _trafficEnabled,
    );
    if (!mounted) return;
    if (withSteps != null) {
      final result = withSteps.result;
      setState(() {
        _polylineToDestination = result.points;
        _routeSteps = withSteps.steps;
        _currentStepIndex = _routeSteps.isNotEmpty ? 0 : -1;
        _routeToPassengerDistanceText = result.distanceText;
        _routeToPassengerDurationText = result.durationText;
        _routeToPassengerDistanceMeters = result.distanceKm * 1000;
        _routeToPassengerDurationSeconds = result.durationSeconds;
        _routeWarnings = result.warnings;
        _routeTollInfo = result.tollInfoText;
        _lastDestinationLat = destLat;
        _lastDestinationLng = destLng;
        _lastFetchRouteToDestinationPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      });
      _fitRouteToDestinationBounds();
      if (_currentPosition != null) {
        _updateCurrentStepFromPosition(_currentPosition!);
      }
      _speakCurrentStep();
      _startTrafficAlternativesCheck();
      RoutesTollService.getTollEstimate(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
      ).then((toll) {
        if (mounted && toll != null &&
            _navigatingToOrderId == order.id &&
            _navigatingToDestination) {
          setState(() => _routeTollInfo = toll);
        }
      });
    } else {
      final distM = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        destLat,
        destLng,
      );
      setState(() {
        _polylineToDestination = [
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          LatLng(destLat, destLng),
        ];
        _routeSteps = [];
        _currentStepIndex = -1;
        _routeToPassengerDistanceText = distM < 1000
            ? '${distM.round()} m'
            : '${(distM / 1000).toStringAsFixed(1)} km';
        _routeToPassengerDurationText = '';
        _routeToPassengerDistanceMeters = distM;
        _lastDestinationLat = destLat;
        _lastDestinationLng = destLng;
        _lastFetchRouteToDestinationPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      });
      _fitRouteToDestinationBounds();
    }
  }

  void _fitRouteToDestinationBounds() {
    if (_mapController == null ||
        _polylineToDestination == null ||
        _polylineToDestination!.isEmpty ||
        !mounted) return;
    double minLat = _polylineToDestination!.first.latitude;
    double maxLat = minLat;
    double minLng = _polylineToDestination!.first.longitude;
    double maxLng = minLng;
    for (final p in _polylineToDestination!) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (mounted) {
      try {
        final spanLat = maxLat - minLat;
        final spanLng = maxLng - minLng;
        const minZoom = 12.0;
        if (spanLat > 0.05 || spanLng > 0.05) {
          final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(center, minZoom),
          );
        } else {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              100,
            ),
          );
        }
      } catch (_) {}
    }
  }

  /// Update jarak & ETA dinamis ke penumpang/tujuan (dari posisi driver saat ini). Ringan, tanpa API.
  void _updateRouteToPassengerDistance(Position position) {
    final navId = _navigatingToOrderId;
    if (navId == null) return;
    _updateCurrentStepFromPosition(position);
    OrderModel? navOrder;
    for (final o in _driverOrders) {
      if (o.id == navId) {
        navOrder = o;
        break;
      }
    }
    if (navOrder == null) return;
    double? destLat;
    double? destLng;
    if (_navigatingToDestination) {
      final d = _getOrderDestinationLatLng(navOrder);
      destLat = d.$1;
      destLng = d.$2;
    } else {
      destLat = navOrder.passengerLiveLat ?? navOrder.passengerLat;
      destLng = navOrder.passengerLiveLng ?? navOrder.passengerLng;
    }
    if (destLat == null || destLng == null) return;
    final distMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      destLat,
      destLng,
    );
    String distText;
    if (distMeters < 1000) {
      distText = '${distMeters.round()} m';
    } else {
      distText = '${(distMeters / 1000).toStringAsFixed(1)} km';
    }
    const avgSpeedKmh = 40.0;
    final durationSeconds = (distMeters / 1000) / avgSpeedKmh * 3600;
    final mins = (durationSeconds / 60).round();
    final durText = mins < 60 ? '$mins menit' : '${(mins / 60).round()} jam';
    if (_routeToPassengerDistanceText != distText ||
        _routeToPassengerDurationText != durText ||
        _routeToPassengerDistanceMeters != distMeters) {
      final wasNearArrival = (_routeToPassengerDistanceMeters ?? 999) < 100;
      final isNearArrival = distMeters < 100;
      if (mounted) {
        setState(() {
          _routeToPassengerDistanceText = distText;
          _routeToPassengerDurationText = durText;
          _routeToPassengerDistanceMeters = distMeters;
          _routeToPassengerDurationSeconds = durationSeconds.round();
        });
        if (isNearArrival && !wasNearArrival && !_hasSpokenNearArrival) {
          _hasSpokenNearArrival = true;
          HapticFeedback.mediumImpact();
          VoiceNavigationService.instance.speak(
            _navigatingToDestination
                ? 'Hampir sampai di lokasi tujuan'
                : 'Hampir sampai di lokasi penumpang',
            '${distMeters.round()} meter',
          );
        }
      }
    }
  }

  void _fitRouteToPassengerBounds() {
    if (_mapController == null ||
        _polylineToPassenger == null ||
        _polylineToPassenger!.isEmpty ||
        !mounted)
      return;
    double minLat = _polylineToPassenger!.first.latitude;
    double maxLat = minLat;
    double minLng = _polylineToPassenger!.first.longitude;
    double maxLng = minLng;
    for (final p in _polylineToPassenger!) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (mounted) {
      try {
        final spanLat = maxLat - minLat;
        final spanLng = maxLng - minLng;
        const minZoom = 12.0;
        if (spanLat > 0.05 || spanLng > 0.05) {
          final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(center, minZoom),
          );
        } else {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              100, // Padding agar mobil & penumpang terlihat jelas
            ),
          );
        }
      } catch (_) {
        // Abaikan jika map disposed saat widget sedang dispose
      }
    }
  }

  void _exitNavigatingToPassenger() {
    VoiceNavigationService.instance.stop();
    _stopTrafficAlternativesCheck();
    final orderId = _navigatingToOrderId;
    if (orderId != null && !_navigatingToDestination) {
      OrderService.clearDriverNavigatingToPickup(orderId);
    }
    setState(() {
      _navigatingToOrderId = null;
      _fasterAlternativeMinutesSaved = null;
      _navigatingToDestination = false;
      _polylineToPassenger = null;
      _isOffRoute = false;
      _polylineToDestination = null;
      _routeSteps = [];
      _currentStepIndex = -1;
      _routeToPassengerDistanceText = '';
      _routeToPassengerDurationText = '';
      _routeToPassengerDistanceMeters = null;
      _routeToPassengerDurationSeconds = null;
      _routeWarnings = [];
      _routeTollInfo = null;
      _hasSpokenNearArrival = false;
      _lastPassengerLat = null;
      _lastPassengerLng = null;
      _lastFetchRouteToPassengerPosition = null;
      _lastDestinationLat = null;
      _lastDestinationLng = null;
      _lastFetchRouteToDestinationPosition = null;
    });
    _fitMapToMainRoute();
  }

  void _exitNavigatingToDestination() {
    _exitNavigatingToPassenger();
  }

  void _startTrafficAlternativesCheck() {
    _trafficAlternativesCheckTimer?.cancel();
    if (!_trafficEnabled || _navigatingToOrderId == null) return;
    _trafficAlternativesCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkFasterAlternativeRoute(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(minutes: 2), () {
        if (mounted && _navigatingToOrderId != null) _checkFasterAlternativeRoute();
      });
    });
  }

  void _stopTrafficAlternativesCheck() {
    _trafficAlternativesCheckTimer?.cancel();
    _trafficAlternativesCheckTimer = null;
  }

  Future<void> _checkFasterAlternativeRoute() async {
    if (!mounted || _navigatingToOrderId == null || !_trafficEnabled) return;
    if (_currentPosition == null) return;
    final currentDuration = _routeToPassengerDurationSeconds ?? 0;
    if (currentDuration <= 0) return;
    OrderModel? navOrder;
    for (final o in _driverOrders) {
      if (o.id == _navigatingToOrderId) {
        navOrder = o;
        break;
      }
    }
    if (navOrder == null) return;
    double? destLat;
    double? destLng;
    if (_navigatingToDestination) {
      final t = _getOrderDestinationLatLng(navOrder);
      destLat = t.$1;
      destLng = t.$2;
    } else {
      destLat = navOrder.passengerLiveLat ?? navOrder.passengerLat;
      destLng = navOrder.passengerLiveLng ?? navOrder.passengerLng;
    }
    if (destLat == null || destLng == null) return;
    final alternatives = await DirectionsService.getAlternativeRoutesWithSteps(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: destLat,
      destLng: destLng,
      trafficAware: true,
    );
    if (!mounted || alternatives.length < 2) return;
    int? fastestDuration;
    for (final alt in alternatives) {
      if (alt.result.durationSeconds < currentDuration) {
        if (fastestDuration == null || alt.result.durationSeconds < fastestDuration) {
          fastestDuration = alt.result.durationSeconds;
        }
      }
    }
    if (fastestDuration != null) {
      final savedMin = (currentDuration - fastestDuration) ~/ 60;
      if (savedMin >= 2 && mounted) {
        setState(() => _fasterAlternativeMinutesSaved = savedMin);
      }
    }
  }

  /// Tampilkan rute alternatif saat navigasi ke penumpang/tujuan. Driver bisa pilih tanpa keluar navigasi.
  Future<void> _showAlternativeRoutesDuringNavigation() async {
    if (_currentPosition == null || _navigatingToOrderId == null) return;
    setState(() => _fasterAlternativeMinutesSaved = null);
    OrderModel? navOrder;
    for (final o in _driverOrders) {
      if (o.id == _navigatingToOrderId) {
        navOrder = o;
        break;
      }
    }
    if (navOrder == null) return;
    double? destLat;
    double? destLng;
    if (_navigatingToDestination) {
      final d = _getOrderDestinationLatLng(navOrder);
      destLat = d.$1;
      destLng = d.$2;
    } else {
      destLat = navOrder.passengerLiveLat ?? navOrder.passengerLat;
      destLng = navOrder.passengerLiveLng ?? navOrder.passengerLng;
    }
    if (destLat == null || destLng == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Memuat rute alternatif...'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    final alternatives = await DirectionsService.getAlternativeRoutesWithSteps(
      originLat: _currentPosition!.latitude,
      originLng: _currentPosition!.longitude,
      destLat: destLat,
      destLng: destLng,
      trafficAware: _trafficEnabled,
    );

    if (!mounted) return;
    if (alternatives.isEmpty || alternatives.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada rute alternatif tersedia'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Pilih rute alternatif',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...alternatives.asMap().entries.map((e) {
                final i = e.key;
                final alt = e.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF00B14F).withValues(alpha: 0.2),
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text('${alt.result.distanceText} • ${alt.result.durationText}'),
                  subtitle: alt.result.warnings.isNotEmpty
                      ? Text(alt.result.warnings.first, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(i),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected == null || !mounted) return;

    final chosen = alternatives[selected];
    setState(() {
      if (_navigatingToDestination) {
        _polylineToDestination = chosen.result.points;
        _lastFetchRouteToDestinationPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } else {
        _polylineToPassenger = chosen.result.points;
        _lastFetchRouteToPassengerPosition = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
      _routeSteps = chosen.steps;
      _currentStepIndex = _routeSteps.isNotEmpty ? 0 : -1;
      _routeToPassengerDistanceText = chosen.result.distanceText;
      _routeToPassengerDurationText = chosen.result.durationText;
      _routeToPassengerDistanceMeters = chosen.result.distanceKm * 1000;
      _routeToPassengerDurationSeconds = chosen.result.durationSeconds;
      _routeWarnings = chosen.result.warnings;
      _routeTollInfo = chosen.result.tollInfoText;
    });
    if (_navigatingToDestination) {
      _fitRouteToDestinationBounds();
    } else {
      _fitRouteToPassengerBounds();
    }
    _updateCurrentStepFromPosition(_currentPosition!);
    _speakCurrentStep();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rute ${selected + 1} dipilih: ${chosen.result.distanceText} • ${chosen.result.durationText}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Update step aktif saat turn-by-turn dari posisi driver di polyline.
  void _updateCurrentStepFromPosition(Position position) {
    final poly = _activeNavigationPolyline;
    final steps = _routeSteps;
    if (poly == null || poly.isEmpty || steps.isEmpty) return;
    final pos = LatLng(position.latitude, position.longitude);
    final (_, segmentIndex, ratio) = RouteUtils.projectPointOntoPolyline(
      pos,
      poly,
      maxDistanceMeters: 250,
    );
    if (segmentIndex < 0) return;
    final distM = RouteUtils.distanceAlongPolyline(poly, segmentIndex, ratio);
    int stepIdx = -1;
    for (int i = 0; i < steps.length; i++) {
      if (distM >= steps[i].startDistanceMeters &&
          distM < steps[i].endDistanceMeters) {
        stepIdx = i;
        break;
      }
    }
    if (stepIdx < 0 && distM >= steps.last.endDistanceMeters) {
      stepIdx = steps.length - 1;
    } else if (stepIdx < 0 && steps.isNotEmpty) {
      stepIdx = 0;
    }
    if (stepIdx != _currentStepIndex && mounted) {
      setState(() => _currentStepIndex = stepIdx);
      _speakCurrentStep();
      HapticFeedback.mediumImpact();
    }
  }

  /// Bicara instruksi turn-by-turn saat step berubah (jika suara tidak dimatikan).
  void _speakCurrentStep() {
    if (_routeSteps.isEmpty ||
        _currentStepIndex < 0 ||
        _currentStepIndex >= _routeSteps.length) return;
    final step = _routeSteps[_currentStepIndex];
    final formatted = InstructionFormatter.formatStep(step);
    VoiceNavigationService.instance.speak(formatted, step.distanceText);
  }

  /// Kembalikan tampilan map ke rute utama (setelah penumpang dijemput atau driver klik Kembali).
  void _fitMapToMainRoute() {
    if (_mapController == null || !mounted) return;
    if (_currentPosition != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          MapStyleService.defaultZoom,
        ),
      );
    }
  }

  /// Split polyline: (sudah dilewati, sisa perjalanan). Untuk warna: kuning=lewat, biru=sisa.
  (List<LatLng> passed, List<LatLng> remaining) _splitPolylineAtDriver(
    List<LatLng> route,
  ) {
    if (route.length < 2) return (<LatLng>[], route);
    final driverPos =
        _displayedPosition ??
        _targetPosition ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : null);
    if (driverPos == null) return (<LatLng>[], route);

    final (
      projPoint,
      segmentIndex,
      ratio,
    ) = RouteUtils.projectPointOntoPolyline(
      driverPos,
      route,
      maxDistanceMeters: 250,
    );

    if (segmentIndex >= 0) {
      final passed = <LatLng>[];
      for (int i = 0; i <= segmentIndex; i++) {
        passed.add(route[i]);
      }
      passed.add(projPoint);

      final remaining = <LatLng>[projPoint];
      for (int i = segmentIndex + 1; i < route.length; i++) {
        remaining.add(route[i]);
      }
      return (passed, remaining);
    }
    return (<LatLng>[], route);
  }

  /// Trim polyline: hanya sisa perjalanan (untuk mode navigasi ke penumpang).
  List<LatLng> _trimPolylineFromDriver(List<LatLng> route) {
    final (_, remaining) = _splitPolylineAtDriver(route);
    return remaining.length >= 2 ? remaining : route;
  }

  List<LatLng>? get _activeNavigationPolyline {
    if (_navigatingToOrderId == null) return null;
    if (_navigatingToDestination) return _polylineToDestination;
    return _polylineToPassenger;
  }

  static const Color _polylinePenjemputanColor = Color(0xFF00B14F); // Grab green
  static const Color _polylinePengantaranColor = Color(0xFFE65100); // Oranye

  Set<Polyline> _buildPolylines() {
    final Set<Polyline> polylines = {};

    // Mode navigasi ke penumpang atau tujuan: tampilkan rute (hijau/oranye) + rute utama (abu-abu)
    final navPolyline = _activeNavigationPolyline;
    if (_navigatingToOrderId != null &&
        navPolyline != null &&
        navPolyline.isNotEmpty) {
      final routeColor = _navigatingToDestination
          ? _polylinePengantaranColor
          : _polylinePenjemputanColor;
      // Rute utama (origin→dest) dengan trim: hanya sisa perjalanan
      List<LatLng>? mainRoute = _routePolyline;
      if ((mainRoute == null || mainRoute.isEmpty) &&
          _alternativeRoutes.isNotEmpty &&
          _selectedRouteIndex >= 0 &&
          _selectedRouteIndex < _alternativeRoutes.length) {
        mainRoute = _alternativeRoutes[_selectedRouteIndex].points;
      }
      if (mainRoute != null && mainRoute.isNotEmpty) {
        final (passed, remaining) = _splitPolylineAtDriver(mainRoute);
        if (passed.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route_main_passed'),
              points: passed,
              color: Colors.amber.shade300,
              width: 4,
            ),
          );
        }
        if (remaining.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route_main_faded'),
              points: remaining,
              color: Colors.grey.shade400,
              width: 4,
            ),
          );
        }
      }
      // Rute ke penumpang/tujuan: sudah dilewati kuning, sisa hijau/oranye
      final (passed, remaining) = _splitPolylineAtDriver(navPolyline);
      if (passed.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route_to_passenger_passed'),
            points: passed,
            color: Colors.amber.shade300,
            width: 6,
          ),
        );
      }
      if (remaining.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route_to_passenger'),
            points: remaining,
            color: routeColor,
            width: 6,
          ),
        );
      }
      return polylines;
    }

    // Tampilkan semua alternatif rute jika ada (warna per rute: biru, hijau, oranye, ungu)
    if (_alternativeRoutes.isNotEmpty) {
      for (int i = 0; i < _alternativeRoutes.length; i++) {
        final route = _alternativeRoutes[i];
        final routeColor = routeColorForIndex(i);
        final isSelected = i == _selectedRouteIndex && _routeSelected;
        if (isSelected && _isDriverWorking) {
          final (passed, remaining) = _splitPolylineAtDriver(route.points);
          if (passed.length >= 2) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_${i}_passed'),
                points: passed,
                color: routeColor.withValues(alpha: 0.5),
                width: 5,
                patterns: [],
              ),
            );
          }
          if (remaining.length >= 2) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_$i'),
                points: remaining,
                color: routeColor,
                width: 9,
                patterns: [],
              ),
            );
          }
        } else {
          final points = isSelected
              ? _trimPolylineFromDriver(route.points)
              : route.points;
          if (points.length >= 2) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_$i'),
                points: points,
                color: routeColor,
                width: isSelected ? 9 : 4,
                patterns: [],
              ),
            );
          }
        }
      }
    } else if (_routePolyline != null && _routePolyline!.isNotEmpty) {
      final (passed, remaining) = _splitPolylineAtDriver(_routePolyline!);
      if (passed.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route_passed'),
            points: passed,
            color: Colors.amber.shade300,
            width: 5,
          ),
        );
      }
      if (remaining.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: remaining,
            color: Theme.of(context).colorScheme.primary,
            width: 5,
          ),
        );
      }
    }

    return polylines;
  }

  /// Hitung jarak dari titik ke segmen garis (dalam meter).
  double _distanceToSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    // Hitung jarak menggunakan formula haversine untuk segmen pendek
    final distToStart = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      segmentStart.latitude,
      segmentStart.longitude,
    );
    final distToEnd = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      segmentEnd.latitude,
      segmentEnd.longitude,
    );
    final distSegment = Geolocator.distanceBetween(
      segmentStart.latitude,
      segmentStart.longitude,
      segmentEnd.latitude,
      segmentEnd.longitude,
    );

    // Jika segmen sangat pendek, return jarak terdekat ke titik ujung
    if (distSegment < 1) {
      return distToStart < distToEnd ? distToStart : distToEnd;
    }

    // Hitung jarak ke segmen menggunakan proyeksi
    // Untuk segmen pendek, gunakan pendekatan sederhana
    final ratio = distToStart / (distToStart + distToEnd);
    final projectedLat =
        segmentStart.latitude +
        (segmentEnd.latitude - segmentStart.latitude) * ratio;
    final projectedLng =
        segmentStart.longitude +
        (segmentEnd.longitude - segmentStart.longitude) * ratio;

    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      projectedLat,
      projectedLng,
    );
  }

  /// Handle tap pada map untuk memilih rute alternatif.
  /// Gunakan posisi tap (bukan posisi driver) agar tap di garis kuning langsung memilih rute.
  /// Bisa memilih rute lain sebelum klik "Mulai", setelah "Mulai" tidak bisa lagi.
  void _onMapTap(LatLng position) {
    if (_alternativeRoutes.isEmpty || _isDriverWorking) {
      return; // Tidak bisa pilih jika sudah mulai bekerja
    }

    // Referensi: posisi tap agar driver bisa tap langsung di garis kuning untuk memilih
    final LatLng referencePoint = position;

    // Hitung jarak dari referencePoint ke setiap alternatif rute dengan optimasi
    double minDistance = double.infinity;
    int closestRouteIndex = -1;

    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      // Optimasi: gunakan sampling setiap beberapa titik untuk performa lebih baik
      final distance =
          _distanceToPolylineOptimized(referencePoint, route.points);
      if (distance < minDistance) {
        minDistance = distance;
        closestRouteIndex = i;
      }
    }

    // Threshold besar untuk rute antar pulau/nasional (bisa 500km+).
    final threshold = _alternativeRoutes.length <= 3 ? 500000.0 : 250000.0;

    if (closestRouteIndex >= 0 && minDistance < threshold) {
      // Generate journey number dan mulai rute
      _selectRouteAndStart(closestRouteIndex);
      // Info rute dipilih tampil via tombol "Mulai Rute ini" (garis sudah biru)
    } else if (_alternativeRoutes.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tap pada area garis kuning untuk memilih. Jarak terdekat: ${(minDistance / 1000).toStringAsFixed(1)}km',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// Versi optimasi dari _distanceToPolyline dengan sampling untuk performa lebih baik.
  double _distanceToPolylineOptimized(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        polyline[0].latitude,
        polyline[0].longitude,
      );
    }

    double minDistance = double.infinity;

    // Optimasi: step 2 agar tap di garis kuning lebih akurat (step 5 bisa melewatkan segmen)
    final step = polyline.length > 500 ? 3 : (polyline.length > 200 ? 2 : 1);

    for (int i = 0; i < polyline.length - 1; i += step) {
      final nextIndex = (i + step < polyline.length)
          ? i + step
          : polyline.length - 1;
      final segmentStart = polyline[i];
      final segmentEnd = polyline[nextIndex];
      final distance = _distanceToSegment(point, segmentStart, segmentEnd);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    // Pastikan cek segmen terakhir jika step > 1
    if (step > 1 && polyline.length > 1) {
      final lastIndex = polyline.length - 1;
      if (lastIndex - step >= 0) {
        final distance = _distanceToSegment(
          point,
          polyline[lastIndex - step],
          polyline[lastIndex],
        );
        if (distance < minDistance) {
          minDistance = distance;
        }
      }
      // Cek segmen terakhir langsung
      final distance = _distanceToSegment(
        point,
        polyline[lastIndex - 1],
        polyline[lastIndex],
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    return minDistance;
  }

  /// Pilih rute dan siapkan untuk mulai bekerja (tapi belum aktif sampai tombol diklik).
  Future<void> _selectRouteAndStart(int routeIndex) async {
    if (routeIndex < 0 || routeIndex >= _alternativeRoutes.length) return;

    final selectedRoute = _alternativeRoutes[routeIndex];
    final startedAt = DateTime.now();

    // Set UI segera agar tombol "Mulai Rute ini" langsung muncul
    String? journeyNumber;
    if (_activeRouteFromJadwal &&
        _currentScheduleId != null &&
        _currentScheduleId!.isNotEmpty) {
      journeyNumber = OrderService.routeJourneyNumberScheduled;
    }
    setState(() {
      _selectedRouteIndex = routeIndex;
      _routePolyline = selectedRoute.points;
      _routeDistanceText = selectedRoute.distanceText;
      _routeDurationText = selectedRoute.durationText;
      _routeEstimatedDurationSeconds = selectedRoute.durationSeconds;
      _routeSelected = true;
      _routeJourneyNumber = journeyNumber;
      _routeStartedAt = startedAt;
    });

    // Generate journey number di background (untuk rute dari form, bukan Jadwal)
    if (journeyNumber == null && mounted) {
      if (FirebaseAuth.instance.currentUser == null) {
        if (mounted) {
          _showSessionInvalidSnackBar();
        }
      } else {
        try {
          final generated =
              await RouteJourneyNumberService.generateRouteJourneyNumber();
          if (mounted) {
            setState(() => _routeJourneyNumber = generated);
          }
        } on FirebaseFunctionsException catch (e) {
          if (mounted) {
            final msg = e.code == 'unauthenticated'
                ? 'Sesi tidak valid. Silakan login ulang untuk melanjutkan.'
                : 'Gagal generate nomor rute: ${e.message}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red,
                action: e.code == 'unauthenticated'
                    ? SnackBarAction(
                        label: 'Ke Profil',
                        textColor: Colors.white,
                        onPressed: () => setState(() => _currentIndex = 4),
                      )
                    : null,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal generate nomor rute: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }

    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      _displayedBearing = _currentPosition!.heading;
      _smoothedBearing = _displayedBearing;
    }
    await _loadCarIconsOnce();
  }

  void _showDriverLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TrakaL10n.of(context).completeVerification),
        content: Text(
          TrakaL10n.of(context).completeDataVerificationPromptDriver,
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _currentIndex = 4); // Tab Saya (Profil)
            },
            child: const Text('Lengkapi Sekarang'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverMapScreen({required bool isDriverVerified}) {
    return Stack(
      children: [
        RepaintBoundary(
          child: StyledGoogleMapBuilder(
            builder: (style, useDark) {
              // Mode gelap: pakai normal agar style gelap berlaku (style tidak berlaku di hybrid)
              final effectiveMapType = useDark ? MapType.normal : _mapType;
              return GoogleMap(
                padding: EdgeInsets.zero,
                buildingsEnabled: true,
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: () {
                  if (_suppressNextCameraMoveStarted) {
                    _suppressNextCameraMoveStarted = false;
                    return;
                  }
                  if (_isDriverWorking || _navigatingToOrderId != null) {
                    setState(() => _cameraTrackingEnabled = false);
                  }
                },
                initialCameraPosition: CameraPosition(
                  target: _currentPosition != null
                      ? LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        )
                      : const LatLng(-3.3194, 114.5907),
                  zoom: MapStyleService.defaultZoom,
                  tilt: MapStyleService.defaultTilt,
                ),
                mapType: effectiveMapType,
                style: style,
                trafficEnabled: _trafficEnabled,
                myLocationEnabled:
                    false, // Disable untuk menghilangkan pin hijau default
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: true, // Enable zoom dengan gesture 2 jari
                scrollGesturesEnabled: true, // Enable scroll/pan
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                markers: _buildMarkers(),
                polylines: _buildPolylines(),
                onTap: (LatLng position) {
                  if (_formDestMapModeNotifier.value) {
                    _formDestMapTapNotifier.value = position;
                  } else if (_alternativeRoutes.isNotEmpty &&
                      !_isDriverWorking) {
                    _onMapTap(position);
                  }
                },
              );
            },
          ),
        ),
        // Overlay tap: bypass Polyline.onTap yang bermasalah di Android/iOS
        if (_alternativeRoutes.isNotEmpty &&
            !_isDriverWorking &&
            _mapController != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) async {
                if (_mapController == null || !mounted) return;
                try {
                  final latLng = await _mapController!.getLatLng(
                    ScreenCoordinate(
                      x: details.localPosition.dx.toInt(),
                      y: details.localPosition.dy.toInt(),
                    ),
                  );
                  if (mounted) _onMapTap(latLng);
                } catch (_) {}
              },
            ),
          ),
        const PromotionBannerWidget(role: 'driver'),
        DriverRouteSelectionButtons(
          routeCount: _alternativeRoutes.length,
          selectedIndex: _selectedRouteIndex,
          routeDistanceTexts: _alternativeRoutes
              .map((r) => r.distanceText)
              .toList(),
          onSelectRoute: (i) => _selectRouteAndStart(i),
          visible: _alternativeRoutes.isNotEmpty && !_isDriverWorking,
          routeSelected: _routeSelected,
        ),
        DriverRouteTapHint(
          routeSelected: _routeSelected,
          visible: _alternativeRoutes.isNotEmpty && !_isDriverWorking,
        ),
        DriverScheduledReminder(
          scheduledCount: _scheduledAgreedCountForToday,
          onOpenJadwal: () => setState(() => _currentIndex = 1),
          visible:
              _currentScheduleId == null && _scheduledAgreedCountForToday > 0,
        ),
        DriverWorkToggleButton(
          isDriverWorking: _isDriverWorking,
          routeSelected: _routeSelected,
          hasActiveOrder: _hasActiveOrder,
          onTap: () => _onToggleButtonTap(isDriverVerified: isDriverVerified),
        ),
        DriverStartRouteButton(
          visible: _routeSelected && !_isDriverWorking,
          isLoading: _isStartRouteLoading,
          onTap: _onStartButtonTap,
        ),
        DriverRouteInfoIconButton(
          visible: _isDriverWorking &&
              _routePolyline != null &&
              _routePolyline!.isNotEmpty &&
              _navigatingToOrderId == null,
          hasOperDriverAvailable: _jumlahPenumpangPickedUp > 0,
          onTap: _showRouteInfoBottomSheet,
        ),
        ListenableBuilder(
          listenable: MapStyleService.themeNotifier,
          builder: (context, _) {
            final useDark = MapStyleService.themeNotifier.value == ThemeMode.dark;
            final effectiveMapType = useDark ? MapType.normal : _mapType;
            return MapTypeZoomControls(
              mapType: effectiveMapType,
              onToggleMapType: _toggleMapType,
              trafficEnabled: _trafficEnabled,
              onToggleTraffic: _toggleTraffic,
              onZoomIn: () {
                if (mounted)
                  _mapController?.animateCamera(CameraUpdate.zoomIn());
              },
              onZoomOut: () {
                if (mounted)
                  _mapController?.animateCamera(CameraUpdate.zoomOut());
              },
              onThemeToggle: () => ThemeService.toggle(),
            );
          },
        ),
        // Prioritas #4: Tombol "Arahkan ke stop terdekat" (pickup → dropoff → tujuan)
        if (_navigatingToOrderId == null &&
            _nextTargetForNavigation != null) ...[
          _NextStopBanner(
            target: _nextTargetForNavigation!.$1!,
            isPickup: _nextTargetForNavigation!.$2,
            onTap: () => _navigateToNextTarget(),
          ),
        ],
        // #6: Panel list penumpang gabungan (Penjemputan + Pengantaran) - tap → fokus map + navigasi
        if ((_waitingPassengerCount > 0 || _pickedUpOrdersForDestination.isNotEmpty) &&
            _navigatingToOrderId == null)
          DriverStopsListOverlay(
            pickupOrders: _waitingPassengerOrders,
            dropoffOrders: _pickedUpOrdersForDestination,
            optimizedStops: _optimizedStops,
            driverPosition: _currentPosition != null
                ? LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  )
                : null,
            onSelectPickup: (order) async {
              await OrderService.setDriverNavigatingToPickup(order.id);
              if (!mounted) return;
              final lat = order.passengerLat ?? order.originLat;
              final lng = order.passengerLng ?? order.originLng;
              setState(() {
                _navigatingToOrderId = order.id;
                _navigatingToDestination = false;
                _lastPassengerLat = lat;
                _lastPassengerLng = lng;
              });
              _loadPassengerMarkerIconsIfNeeded();
              _fetchAndShowRouteToPassenger(order);
            },
            onSelectDropoff: (order) {
              if (!mounted) return;
              setState(() {
                _navigatingToOrderId = order.id;
                _navigatingToDestination = true;
                final (lat, lng) = _getOrderDestinationLatLng(order);
                _lastDestinationLat = lat;
                _lastDestinationLng = lng;
              });
              _fetchAndShowRouteToDestination(order);
            },
          ),
        // Overlay "Menuju penumpang" (hijau) saat diarahkan ke penjemputan
        if (_navigatingToOrderId != null && !_navigatingToDestination)
          NavigatingToPassengerOverlay(
            routeToPassengerDistanceText: _routeToPassengerDistanceText,
            routeToPassengerDurationText: _routeToPassengerDurationText,
            routeToPassengerDistanceMeters: _routeToPassengerDistanceMeters,
            waitingPassengerCount: _waitingPassengerCount,
            navigatingToOrderId: _navigatingToOrderId,
            onExitNavigating: _exitNavigatingToPassenger,
            voiceMuted: VoiceNavigationService.instance.muted,
            onVoiceMuteToggle: () async {
              await VoiceNavigationService.instance.toggleMuted();
              if (mounted) setState(() {});
            },
            onAlternativeRoutes: _showAlternativeRoutesDuringNavigation,
          ),
        // Overlay "Menuju tujuan" (oranye) saat diarahkan ke pengantaran
        if (_navigatingToOrderId != null && _navigatingToDestination)
          NavigatingToDestinationOverlay(
            routeDistanceText: _routeToPassengerDistanceText,
            routeDurationText: _routeToPassengerDurationText,
            routeDistanceMeters: _routeToPassengerDistanceMeters,
            navigatingToOrderId: _navigatingToOrderId,
            onExitNavigating: _exitNavigatingToDestination,
            voiceMuted: VoiceNavigationService.instance.muted,
            onVoiceMuteToggle: () async {
              await VoiceNavigationService.instance.toggleMuted();
              if (mounted) setState(() {});
            },
            onAlternativeRoutes: _showAlternativeRoutesDuringNavigation,
          ),
        // Banner rekomendasi rute alternatif saat macet (seperti Grab)
        if (_fasterAlternativeMinutesSaved != null &&
            _fasterAlternativeMinutesSaved! >= 2)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 260,
            left: 20,
            right: 20,
            child: Center(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF00B14F),
                child: InkWell(
                  onTap: _showAlternativeRoutesDuringNavigation,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.route,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Rute alternatif $_fasterAlternativeMinutesSaved menit lebih cepat tersedia. Ketuk untuk pilih.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Banner off-route: Anda keluar dari rute
        if (_isOffRoute)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 200,
            left: 20,
            right: 20,
            child: Center(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.amber.shade700,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Anda keluar dari rute. Ikuti garis untuk kembali.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Banner petunjuk belok turn-by-turn di bawah peta
        if (_navigatingToOrderId != null && _routeSteps.isNotEmpty)
          TurnByTurnBanner(
            steps: _routeSteps,
            currentStepIndex: _currentStepIndex >= 0 ? _currentStepIndex : 0,
            etaArrival: _routeToPassengerDurationSeconds != null
                ? DateTime.now().add(Duration(seconds: _routeToPassengerDurationSeconds!))
                : null,
            tollInfoText: _routeTollInfo,
            routeWarnings: _routeWarnings,
          ),
        // Mobil = marker di peta (posisi geografis akurat). Tidak pakai overlay tetap.
        // Tombol Fokus: recenter ke mobil saat driver geser/zoom manual
        if (!_cameraTrackingEnabled &&
            (_isDriverWorking || _navigatingToOrderId != null))
          DriverFocusButton(onTap: _focusOnCar),
        // Nama jalan sudah jadi bagian marker (Opsi C) — overlay terpisah dihapus.
        // Arrow besar arah belok (HUD) di atas peta - hanya saat jemput penumpang
        if (_navigatingToOrderId != null &&
            _routeSteps.isNotEmpty &&
            _currentStepIndex >= 0 &&
            _currentStepIndex < _routeSteps.length)
          DriverTurnDirectionOverlay(
            step: _routeSteps[_currentStepIndex],
            currentStreetName: _currentStreetName,
            remainingDistanceText: _routeToPassengerDistanceText.isNotEmpty
                ? _routeToPassengerDistanceText
                : null,
          ),
      ],
    );
  }

  /// Cek apakah ada active order (agreed/picked_up) - travel atau kirim_barang.
  void _checkActiveOrder() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    OrderService.getOrdersForDriver(uid)
        .then((orders) {
          if (!mounted) return;
          final hasActive = orders.any(
            (o) =>
                (o.orderType == OrderModel.typeTravel ||
                    o.orderType == OrderModel.typeKirimBarang) &&
                (o.status == OrderService.statusAgreed ||
                    o.status == OrderService.statusPickedUp),
          );
          if (mounted) {
            setState(() {
              _hasActiveOrder = hasActive;
            });
          }
        })
        .catchError((e, st) {
          logError('DriverScreen._checkActiveOrder', e, st);
        });
  }

  Widget _buildOtherScreens({required bool isDriverVerified}) {
      // Lazy IndexedStack: hanya build tab saat pertama dikunjungi (lebih responsif)
      final idx = _currentIndex - 1;
      if (idx >= 0 && idx < 4) _visitedTabIndices.add(_currentIndex);

      return IndexedStack(
        index: idx,
        children: [
          _visitedTabIndices.contains(1)
              ? RepaintBoundary(
                  child: KeyedSubtree(
                    key: const ValueKey('jadwal'),
                    child: DriverJadwalRuteScreen(
                      isDriverVerified: isDriverVerified,
                      onVerificationRequired: _showDriverLengkapiVerifikasiDialog,
                      onOpenRuteFromJadwal: (origin, dest, scheduleId, routePolyline, routeCategory) {
                        if (!isDriverVerified) {
                          _showDriverLengkapiVerifikasiDialog();
                          return;
                        }
                        setState(() {
                          _currentIndex = 0;
                          _pendingJadwalRouteLoad = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _loadRouteFromJadwal(origin, dest, scheduleId, routePolyline, routeCategory);
                        });
                      },
                      disableRouteIconForToday:
                          _isDriverWorking && !_activeRouteFromJadwal,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          _visitedTabIndices.contains(2)
              ? RepaintBoundary(
                  child: KeyedSubtree(
                    key: const ValueKey('chat_driver'),
                    child: const ChatListDriverScreen(),
                  ),
                )
              : const SizedBox.shrink(),
          _visitedTabIndices.contains(3)
              ? RepaintBoundary(
                  child: KeyedSubtree(
                    key: ValueKey('data_order_$_dataOrderRefreshKey'),
                    child: DataOrderDriverScreen(
                      onNavigateToPassenger: (order) async {
                        await OrderService.setDriverNavigatingToPickup(order.id);
                        if (!mounted) return;
                        setState(() {
                          _currentIndex = 0;
                          _navigatingToOrderId = order.id;
                          _lastPassengerLat = order.passengerLat;
                          _lastPassengerLng = order.passengerLng;
                        });
                        _loadPassengerMarkerIconsIfNeeded();
                        _fetchAndShowRouteToPassenger(order);
                      },
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          _visitedTabIndices.contains(4)
              ? RepaintBoundary(
                  child: KeyedSubtree(
                    key: const ValueKey('profile_driver'),
                    child: const ProfileDriverScreen(),
                  ),
                )
              : const SizedBox.shrink(),
        ],
      );
    }

    /// Driver profil lengkap & terverifikasi: Data Kendaraan + Verifikasi Driver (SIM) + Email & No.Telp.
    @override
    Widget build(BuildContext context) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Tunggu 3 detik sebelum tampilkan "Sesi tidak valid" — hindari logout palsu saat
        // token refresh (mis. setelah telpon WA, app resume dari background).
        if (!_sessionInvalidConfirmed) {
          _sessionInvalidCheckTimer?.cancel();
          _sessionInvalidCheckTimer = Timer(const Duration(milliseconds: 3000), () {
            if (!mounted) return;
            final now = FirebaseAuth.instance.currentUser;
            if (now == null) {
              setState(() => _sessionInvalidConfirmed = true);
            } else {
              setState(() => _sessionInvalidConfirmed = false);
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange.shade700),
                  const SizedBox(height: 16),
                  Text(
                    'Sesi tidak valid. Silakan login ulang.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Ke Login'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      _sessionInvalidConfirmed = false;

      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, profileSnap) {
          if (!profileSnap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final data =
              profileSnap.data!.data() as Map<String, dynamic>? ??
              <String, dynamic>{};
          final isDriverVerified = VerificationService.isDriverVerified(data);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateWakelock();
          });

          return Scaffold(
            // Pembatasan "Pesanan Aktif" hanya untuk penumpang; driver tetap bisa akses Beranda/rute.
            body: _currentIndex == 0
                ? StreamBuilder<DriverContributionStatus>(
                    stream:
                        DriverContributionService.streamContributionStatus(),
                    builder: (context, contribSnap) {
                      final status = contribSnap.data;
                      final mustPay = status?.mustPayContribution ?? false;
                      final total = status?.totalRupiah ?? 0;
                      final fmt = (int n) => n.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
                      final t = status?.contributionTravelRupiah ?? 0;
                      final b = status?.contributionBarangRupiah ?? 0;
                      final v = (status?.outstandingViolationFee ?? 0).round();
                      return Column(
                        children: [
                          if (mustPay)
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: context.responsive.spacing(16),
                                vertical: context.responsive.spacing(12),
                              ),
                              color: Colors.orange.shade50,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange.shade800,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          total > 0
                                              ? 'Estimasi bayar: Rp ${fmt(total)}'
                                              : 'Bayar kontribusi untuk menerima order dan balas chat.',
                                          style: TextStyle(
                                            color: Colors.orange.shade900,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (total > 0 && (t > 0 || b > 0 || v > 0)) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              if (t > 0) 'Travel: Rp ${fmt(t)}',
                                              if (b > 0) 'Kirim barang: Rp ${fmt(b)}',
                                              if (v > 0) 'Denda pelanggaran: Rp ${fmt(v)}',
                                            ].join('  •  '),
                                            style: TextStyle(
                                              color: Colors.orange.shade800,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          'Bayar via Google Play untuk menerima order dan balas chat.',
                                          style: TextStyle(
                                            color: Colors.orange.shade800,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final ok = await Navigator.of(context)
                                          .push<bool>(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ContributionDriverScreen(),
                                            ),
                                          );
                                      if (ok == true && mounted)
                                        setState(() {});
                                    },
                                    child: const Text('Bayar'),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: _buildDriverMapScreen(
                              isDriverVerified: isDriverVerified,
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : _buildOtherScreens(isDriverVerified: isDriverVerified),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                HapticFeedback.selectionClick();
                setState(() {
                  // Hanya refresh Data Order saat pindah dari Chat (tab 2), bukan tiap tap (cegah kedip)
                  if (index == 3 && _currentIndex == 2) _dataOrderRefreshKey++;
                  _currentIndex = index;
                });
                // Jika kembali ke halaman beranda, cek ulang active order
                if (index == 0) {
                  _checkActiveOrder();
                }
              },
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              backgroundColor: Theme.of(context).colorScheme.surface,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              items: [
                BottomNavigationBarItem(
                  icon: Icon(
                    _currentIndex == 0 ? Icons.home : Icons.home_outlined,
                    color: _currentIndex == 0
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: TrakaL10n.of(context).navHome,
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    _currentIndex == 1
                        ? Icons.schedule
                        : Icons.schedule_outlined,
                    color: _currentIndex == 1
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: TrakaL10n.of(context).navSchedule,
                ),
                BottomNavigationBarItem(
                  icon: _chatUnreadCount > 0
                      ? Badge(
                          label: Text('$_chatUnreadCount'),
                          child: Icon(
                            _currentIndex == 2
                                ? Icons.chat_bubble
                                : Icons.chat_bubble_outline,
                            color: _currentIndex == 2
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Icon(
                          _currentIndex == 2
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                          color: _currentIndex == 2
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  label: TrakaL10n.of(context).navChat,
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    _currentIndex == 3
                        ? Icons.receipt_long
                        : Icons.receipt_long_outlined,
                    color: _currentIndex == 3
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: TrakaL10n.of(context).navOrders,
                ),
                BottomNavigationBarItem(
                  icon: Icon(
                    _currentIndex == 4 ? Icons.person : Icons.person_outline,
                    color: _currentIndex == 4
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: TrakaL10n.of(context).navProfile,
                ),
              ],
            ),
          );
        },
      );
    }
}

/// Banner "Arahkan ke stop terdekat" - prioritas pickup → dropoff.
class _NextStopBanner extends StatelessWidget {
  const _NextStopBanner({
    required this.target,
    required this.isPickup,
    required this.onTap,
  });

  final OrderModel target;
  final bool isPickup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isPickup
        ? const Color(0xFF00B14F) // hijau penjemputan
        : const Color(0xFFE65100); // oranye pengantaran
    final label = isPickup ? 'Jemput' : 'Antar';
    final name = target.passengerName.trim().isEmpty
        ? (target.isKirimBarang ? 'Barang' : 'Penumpang')
        : target.passengerName;

    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.95),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isPickup ? Icons.person_pin_circle : Icons.flag,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$label: $name',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Tap untuk arahkan ke stop terdekat',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.navigation, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

