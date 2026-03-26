import 'dart:async';
import 'dart:math' as math;

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

import '../config/app_constants.dart';
import '../config/province_island.dart';
import '../theme/app_theme.dart';
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
import '../services/camera_follow_engine.dart';
import '../services/route_utils.dart';
import '../services/route_optimization_service.dart';
import '../services/route_session_service.dart';
import '../services/driver_contribution_service.dart';
import '../services/user_shell_profile_stream.dart';
import '../services/verification_service.dart';
import '../services/pending_purchase_recovery_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/app_analytics_service.dart';
import '../services/performance_trace_service.dart';
import '../services/auth_session_service.dart';
import '../services/hybrid_foreground_recovery.dart';
import '../services/low_ram_warning_service.dart';
import '../services/trip_service.dart';
import '../services/voice_navigation_service.dart';
import '../services/routes_toll_service.dart';
import '../widgets/driver_map_overlays.dart';
import '../widgets/driver_route_form_sheet.dart';
import '../widgets/driver_focus_button.dart';
import '../widgets/oper_driver_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/driver_route_info_panel.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/navigating_to_destination_overlay.dart';
import '../widgets/navigating_to_passenger_overlay.dart';
import '../widgets/turn_by_turn_banner.dart';
import '../widgets/driver_stops_list_overlay.dart';
import '../widgets/promotion_banner_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'chat_list_driver_screen.dart';
import 'contribution_driver_screen.dart';
import 'data_order_driver_screen.dart';
import 'driver_jadwal_rute_screen.dart';
import 'login_screen.dart';
import 'profile_driver_screen.dart';
import '../widgets/traka_main_bottom_navigation_bar.dart';

/// Tipe rute: dalam provinsi, antar provinsi, dalam negara.
enum RouteType { dalamProvinsi, antarProvinsi, dalamNegara }

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Diset dari stream `users/{uid}` — gate mulai kerja & dialog admin vs lengkapi data.
  bool _driverProfileComplete = true;
  bool _canStartDriverWork = true;

  int _currentIndex = 0;
  /// Tab 0 = peta; saat false, kurangi setState/animateCamera agar tab lain (order/chat) responsif.
  bool get _mapTabVisible => _currentIndex == 0;

  /// Tab yang sudah pernah dikunjungi (lazy build: hanya build saat pertama kali).
  final Set<int> _visitedTabIndices = {};
  /// Tab 1–4 lazy; panggil dari setState — jangan mutasi [Set] ini di dalam build().
  void _registerTabVisit(int index) {
    if (index >= 1 && index <= 4) {
      _visitedTabIndices.add(index);
    }
  }
  /// Increment saat tab Data Order dipilih agar Data Order refresh (mis. setelah kesepakatan di chat).
  int _dataOrderRefreshKey = 0;
  GoogleMapController? _mapController;
  final CameraFollowEngine _cameraFollowEngine = CameraFollowEngine();

  /// Denyut lingkaran akurasi di sekitar titik biru (gaya Google Maps).
  late final AnimationController _locationPulseController;
  int _locationPulseBucket = -1;
  MapType _mapType = MapType.normal; // Default: peta jalan
  /// Layer kemacetan lalu lintas (seperti Grab). Default on saat navigasi.
  bool _trafficEnabled = true;
  /// Rekomendasi rute alternatif saat macet: menit lebih cepat (null = tidak ada).
  int? _fasterAlternativeMinutesSaved;
  Timer? _trafficAlternativesCheckTimer;
  /// Zoom ringan sekali per step belokan (tahap 4).
  int _lastContextualZoomStepIndex = -999;
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
  /// Throttle Directions API (jarak/ETA) — hemat baterai & kuota; peta tetap live lewat interpolasi.
  LatLng? _lastEtaThrottleDest;
  DateTime? _lastDirectionsEtaFetchAt;
  LatLng? _lastDirectionsEtaFetchPosition;
  static const int _directionsEtaMinIntervalSeconds = 72;
  static const double _directionsEtaMinDistanceMeters = 450;
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
  Timer? _pendingJadwalSafetyTimer;
  DateTime? _driverPausedAt;
  /// Mencegah `finally` muat rute lawas meng-clear flag saat sudah ada permintaan muat baru.
  int _loadRouteFromJadwalGen = 0;
  /// True saat restore rute: UI sudah "aktif" tapi polyline Directions belum siap.
  bool _routeRestoreAwaitingPolyline = false;
  /// ID jadwal yang dijalankan (untuk sinkron pesanan terjadwal dengan Data Order).
  String? _currentScheduleId;
  /// Satu operasi cek jadwal + sheet rute: tap ganda / postFrame + tap menunggu future ini (bukan jalan paralel).
  Future<void>? _driverStartWorkCheckFuture;
  /// Snackbar "Memeriksa pesanan terjadwal…" — dibatalkan saat pindah tab / selesai, supaya tidak muncul lagi terlambat.
  Timer? _startWorkLoadingSnackTimer;
  /// Membataskan hasil [ _checkScheduledOrdersThenShowRouteSheetBody ] jika alur kehabisan waktu / diganti tap baru.
  int _startWorkCheckGen = 0;
  /// Cegah beberapa bottom sheet "Pilih jenis rute" terbuka bersamaan.
  bool _routeTypeSheetOpen = false;
  /// Cegah sheet "jenis rute" dipicu dua kali beruntun (race sangat singkat).
  DateTime? _lastRouteTypeSheetOpenedAt;
  // Tracking untuk auto-switch rute
  DateTime? _lastRouteSwitchTime; // Waktu terakhir switch rute
  int _originalRouteIndex = -1; // Index rute awal sebelum auto-switch
  /// Jarak tegak maks. GPS ke polyline agar masuk koridor rute itu (pilih rute terdekat).
  /// Produksi: 500 m — bedakan jalur paralel umum; longgar vs noise GPS (~10–50 m).
  static const double _autoSwitchNearestRouteToleranceMeters = 500.0;
  /// Jeda minimum antar pergantian indeks rute (mencegah flip-flop bearing/Firestore).
  /// Cukup panjang untuk cegah flip-flop, tapi masih seperti Maps (bukan 10 menit).
  static const Duration _autoSwitchRouteCooldown = Duration(seconds: 15);
  DateTime? _destinationReachedAt;
  static const Duration _autoEndDuration = Duration(hours: 1, minutes: 30);
  static const double _atDestinationMeters = 500;
  /// Throttle SnackBar: sampai tujuan rute utama tapi masih ada order aktif.
  DateTime? _lastSnackAtRouteDestWithActiveOrders;
  // Nomor rute perjalanan (unik), waktu mulai rute, estimasi durasi untuk auto-end
  String? _routeJourneyNumber;
  /// Prefetch paralel: Cloud Function nomor rute dimulai saat alternatif rute sudah dimuat.
  Future<String>? _journeyNumberPrefetchFuture;
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
  /// Kunci sedang di-build async — hindari spam [DriverCarMarkerService] tiap frame.
  final Set<String> _driverCarMarkerLoadingKeys = {};
  static const Duration _driverCarMarkerBuildTimeout = Duration(milliseconds: 2800);

  /// Titik biru untuk posisi driver saat !chaseCamActive (rute dipilih, belum mulai).
  BitmapDescriptor? _blueDotIcon;

  /// Panah biru ringan saat beranda non-aktif + kecepatan cukup (bukan cone mode kerja).
  BitmapDescriptor? _homeBrowsingArrowIcon;

  /// Di atas ini (km/j): panah + arah; di bawah: titik biru saja.
  static const double _homeBrowsingHeadingMinKmh = 5.0;

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
  /// Sampel lokasi sebelumnya untuk turunan kecepatan (selalu di-update; tidak hanya saat kerja).
  Position? _lastPositionForSpeed;

  /// Kecepatan terakhir (m/s) untuk offset kamera dinamis.
  double _currentSpeedMps = 0.0;

  // Long press detection untuk pilih rute alternatif
  // Badge chat: jumlah order dengan pesan belum dibaca driver
  StreamSubscription<List<OrderModel>>? _driverOrdersSub;
  List<OrderModel> _driverOrders = [];
  /// Gabungkan snapshot order cepat dari Firestore → satu setState (~180ms) agar UI tidak macet.
  Timer? _driverOrdersUiDebounce;
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

  /// Preview pin tujuan di peta saat memilih dari autocomplete form rute.
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

  bool _manualRerouteInProgress = false;

  /// Re-routing saat keluar rute: debounce (otomatis + manual pakai fungsi yang sama).
  LatLng? _lastReroutePosition;
  DateTime? _lastRerouteAt;
  /// Throttle snackbar "rute dari cache" (Directions snapshot).
  DateTime? _lastDirectionsStaleSnackAt;
  /// Cooldown reroute karena deteksi belokan terlewat.
  DateTime? _lastMissedTurnRerouteAt;
  /// Satu kali ambil steps untuk rute utama (turn-by-turn + missed-turn).
  bool _routeStepsHydrateRequested = false;

  /// Indikator "menyesuaikan rute" saat Directions API berjalan (bisa >1 fetch paralel).
  int _routeRecalculateDepth = 0;

  void _pushRouteRecalculate() {
    _routeRecalculateDepth++;
    if (_routeRecalculateDepth == 1 && mounted) setState(() {});
  }

  void _popRouteRecalculate() {
    if (_routeRecalculateDepth <= 0) return;
    _routeRecalculateDepth--;
    if (mounted) setState(() {});
  }

  void _notifyDirectionsStaleFromOutcome(
    DirectionsWithStepsOutcome outcome, {
    required bool showSnackBar,
  }) {
    if (!outcome.usedStaleCache || !mounted) return;
    AppAnalyticsService.logDriverNavigationDirectionsStale();
    if (!showSnackBar) return;
    final now = DateTime.now();
    if (_lastDirectionsStaleSnackAt != null &&
        now.difference(_lastDirectionsStaleSnackAt!) <
            const Duration(seconds: 45)) {
      return;
    }
    _lastDirectionsStaleSnackAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(TrakaL10n.of(context).routeFromCacheNavHint),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Auto reroute: jangan terlalu sering panggil Directions API.
  static const int _rerouteDebounceSeconds = 12;
  /// Jarak minimum sejak reroute terakhir / posisi referensi agar boleh reroute lagi.
  static const double _rerouteDebounceDistanceMeters = 40.0;
  /// GPS mentah menyimpang ≥ ini dari polyline → coba reroute otomatis (beda jalur tanpa klik).
  static const double _autoRerouteMinDeviationMeters = 50.0;

  /// Belokan terlewat (lurus padahal harus belok): setelah titik belokan + [past], dalam jendela [window].
  static const double _missedTurnPastMeters = 42.0;
  static const double _missedTurnWindowMeters = 380.0;
  static const double _missedTurnMinDeviationMeters = 36.0;
  static const int _missedTurnRerouteCooldownSeconds = 10;

  /// Abaikan onCameraMoveStarted berikutnya (dari animateCamera programatik).
  bool _suppressNextCameraMoveStarted = false;

  /// Titik GPS saat user geser peta (tracking mati) — untuk auto-resume kamera.
  LatLng? _gpsWhenCameraManualDisabled;

  /// Lewati satu tick follow kamera setelah auto-resume agar tidak double animateCamera.
  bool _suppressCameraFollowAfterResume = false;

  /// Jarak minimum pergerakan GPS dari titik saat geser → kamera ikuti lagi (Grab-style).
  static const double _resumeCameraAfterManualPanMeters = 90.0;

  /// Sudah bicara "Hampir sampai" sekali (jangan ulang).
  bool _hasSpokenNearArrival = false;

  /// Nama jalan saat ini (reverse geocode, throttle).
  String _currentStreetName = '';

  /// Slug kota/kabupaten untuk GEO matching (#9). Dari subAdministrativeArea.
  String? _currentCitySlug;

  /// Posisi terakhir untuk throttle reverse geocode nama jalan (meter).
  static const double _streetNameGeocodeMinDistanceMeters = 80;
  /// Reverse geocode untuk teks asal/provinsi: jangan tiap tick GPS (~1,3s) — duplikat beban dengan [_updateStreetName].
  static const double _originPlacemarkGeocodeMinDistanceMeters = 500;
  static const int _originPlacemarkGeocodeMaxIntervalMinutes = 12;
  LatLng? _lastOriginPlacemarkGeocodePosition;
  DateTime? _lastOriginPlacemarkGeocodeAt;

  /// Hanya satu `_getCurrentLocation(forTracking: true)` pada satu waktu — cegah tumpukan async (ANR, tidak merespons).
  bool _getCurrentLocationTrackingInFlight = false;

  /// Auto-switch rute bisa menunggu Firestore; jangan jalankan dua kali bersamaan (timer berikutnya bisa overlap).
  bool _autoSwitchRouteCheckInFlight = false;
  LatLng? _lastStreetNameGeocodePosition;

  /// Request ID untuk debounce: abaikan hasil geocode jika posisi sudah berubah.
  int _streetNameGeocodeRequestId = 0;

  /// Throttle setState posisi: rebuild peta hanya jika marker pindah cukup jauh (hindari jank saat geser).
  LatLng? _lastUiEmittedLocationForPosition;
  static const double _minMetersForLocationPositionSetState = 2.5;
  /// Saat driver geser peta (tracking mati): jarangkan rebuild marker — ikon tetap diperbarui lewat interpolasi.
  static const double _minMetersForLocationPositionSetStateWhilePanning = 16.0;

  @override
  void initState() {
    super.initState();
    _locationPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _locationPulseController.addListener(_onLocationPulseTick);
    NotificationNavigationService.registerOpenProfileTab(() {
      if (!mounted) return;
      setState(() {
        _registerTabVisit(4);
        _currentIndex = 4;
      });
    });
    unawaited(PerformanceTraceService.stopStartupToInteractive());
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
    _loadHomeBrowsingArrowOnce();
    _startAuthTokenRefreshTimer();
    HybridForegroundRecovery.manualSyncAllTick.addListener(
      _onManualDriverSyncAllTick,
    );
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
      if (mounted && _homeBrowsingArrowIcon == null) {
        unawaited(_loadHomeBrowsingArrowOnce());
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
          if (o.isCompleted || o.status == OrderService.statusCancelled) {
            continue;
          }
          if (!badgeService.isOptimisticRead(o.id) &&
              o.hasUnreadChatForDriver(uid)) {
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
        _scheduleDriverOrdersUi(
          orders: orders,
          count: count,
          hasActive: hasActive,
          penumpang: penumpang,
          barang: barang,
          penumpangPickedUp: penumpangPickedUp,
        );
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
          o.hasUnreadChatForDriver(uid)) {
        count++;
      }
    }
    setState(() => _chatUnreadCount = count);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _driverPausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _refreshAuthTokenSilently();
      final pausedAt = _driverPausedAt;
      _driverPausedAt = null;
      if (pausedAt != null) {
        final bg = DateTime.now().difference(pausedAt);
        HybridForegroundRecovery.signalAfterBackground(backgroundDuration: bg);
        // Setelah cukup lama di background, snackbar "Memeriksa…" / alur Siap Kerja bisa tertahan — reset agar tidak perlu tutup app.
        if (bg >= const Duration(seconds: 3)) {
          _startWorkLoadingSnackTimer?.cancel();
          _startWorkLoadingSnackTimer = null;
          _startWorkCheckGen++;
          _driverStartWorkCheckFuture = null;
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
        }
      }
      // Lokasi HP bisa jauh dari titik di peta setelah background / multitasking.
      if (mounted) {
        unawaited(_getCurrentLocation(forTracking: true));
        _updateWakelock();
        _checkActiveOrder();
      }
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

  /// Satu setState untuk daftar order + badge (stream bisa spam saat ada kesepakatan / chat).
  void _scheduleDriverOrdersUi({
    required List<OrderModel> orders,
    required int count,
    required bool hasActive,
    required int penumpang,
    required int barang,
    required int penumpangPickedUp,
  }) {
    void apply() {
      if (!mounted) return;
      setState(() {
        _driverOrders = orders;
        _chatUnreadCount = count;
        _hasActiveOrder = hasActive;
        _jumlahPenumpang = penumpang;
        _jumlahBarang = barang;
        _jumlahPenumpangPickedUp = penumpangPickedUp;
      });
      _loadPassengerMarkerIconsIfNeeded();
    }

    _driverOrdersUiDebounce?.cancel();
    // Pertama kali: langsung (hindari blank); berikutnya: debounce lawan spam stream.
    if (_driverOrders.isEmpty) {
      apply();
      return;
    }
    _driverOrdersUiDebounce = Timer(const Duration(milliseconds: 180), apply);
  }

  /// Timer lokasi: saat bekerja pakai interval adaptif (lihat [_restartLocationTimer]);
  /// saat tidak bekerja 30 detik.

  /// Throttle setState interpolasi: ~8 fps agar rebuild tidak membebani UI thread.
  DateTime? _lastInterpolationSetStateTime;
  static const int _interpolationSetStateMinMs = 120;
  /// Saat driver geser peta manual (tracking off), jangan rebuild sekeras saat ikuti kamera.
  static const int _interpolationSetStateMinMsPanning = 380;

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

  /// Durasi animasi: min 200ms, max 3000ms (proporsional dengan waktu gerak nyata).
  static const int _animDurationMinMs = 200;
  static const int _animDurationMaxMs = 3000;
  static const int _animTickMs = 120;

  /// Ikut kamera: [CameraFollowEngine] throttle ~380 ms + durasi dibatasi agar tidak
  /// bertumpuk dengan animasi panjang (marker tetap halus tiap [_animTickMs]).

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
        maxDistanceMeters: _snapToRoutePolylineMaxMeters,
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
      if (mounted &&
          _displayedPosition != null &&
          _currentIndex == 0 &&
          _cameraTrackingEnabled) {
        _animateCameraToDisplayed(_smoothedBearing);
      }
      if (mounted && _currentIndex == 0) {
        final now = DateTime.now();
        final minInterval = (!_cameraTrackingEnabled &&
                (_isDriverWorking || _navigatingToOrderId != null))
            ? _interpolationSetStateMinMsPanning
            : _interpolationSetStateMinMs;
        if (_lastInterpolationSetStateTime == null ||
            now.difference(_lastInterpolationSetStateTime!).inMilliseconds >=
                minInterval) {
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
    if (mounted && _mapTabVisible) setState(() {});
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

  /// Snap ikon ke polyline biru hanya jika GPS dalam radius ini. Di luar itu pakai
  /// koordinat GPS mentah — jalan baru / perkampungan yang belum ada di basemap
  /// Google (polyline mengikuti graf jaringan, bukan jalan fisik di lapangan).
  static const double _snapToRoutePolylineMaxMeters = 95.0;

  /// GPS [Position.speed] sering 0 atau tidak diisi di Android — pakai turunan jarak
  /// ([_currentSpeedMps]) bila kecepatan OS tidak meyakinkan.
  double _effectiveSpeedMps(Position position) {
    final g = position.speed;
    if (g.isFinite && g >= 1.0) return g;
    return _currentSpeedMps;
  }

  double _smoothBearing(
    double current,
    double newBearing, {
    double alpha = _bearingSmoothAlpha,
    double hysteresis = _bearingHysteresisDeg,
  }) {
    double diff = newBearing - current;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    if (diff.abs() < hysteresis) return current; // Hysteresis: abaikan getar
    final effectiveAlpha = diff.abs() > _bearingTurnThresholdDeg
        ? _bearingSmoothAlphaTurn
        : alpha;
    return (current + diff * effectiveAlpha) % 360;
  }

  /// Animate kamera: target di depan, bearing dari rute atau GPS (heading-up). Saat diam: utara ke atas.
  /// [force] lewati throttle (tombol fokus, rotasi layar).
  /// [snapFocus] — dari tombol fokus: jangan skip animasi karena jarak <5 m (user bisa baru saja geser peta).
  void _animateCameraToDisplayed(
    double bearing, {
    bool force = false,
    bool snapFocus = false,
  }) {
    if (_mapController == null || !mounted || _displayedPosition == null) {
      return;
    }
    if (!_mapTabVisible) return;
    if (!_isDriverWorking && _navigatingToOrderId == null) return;
    try {
      final polyline = _activeNavigationPolyline ?? _routePolyline;
      final hasPoly = polyline != null && polyline.length >= 2;
      final pos = _displayedPosition!;
      final isStationary = _currentSpeedMps < _stationarySpeedMps;
      final LatLng target;
      if (isStationary) {
        target = pos;
      } else if (hasPoly) {
        final cameraTarget = RouteUtils.pointAheadOnPolyline(
          pos,
          polyline,
          _getCameraOffsetAheadMeters(),
          maxDistanceMeters: 320,
        );
        target = cameraTarget ?? pos;
      } else {
        // Tanpa garis rute: ikut heading GPS (mode mengemudi) + titik pandang sedikit ke depan — mirip Maps.
        final aheadM = _getCameraOffsetAheadMeters().clamp(70.0, 180.0);
        target = !isStationary && bearing.isFinite
            ? RouteUtils.offsetPoint(pos, bearing, aheadM)
            : pos;
      }
      // Bearing kamera: dari rute/GPS saat jalan; utara ke atas saat berhenti tanpa rute.
      final double camBearing;
      if (hasPoly) {
        camBearing = bearing;
      } else if (!isStationary && bearing.isFinite) {
        camBearing = bearing % 360;
      } else {
        camBearing = 0.0;
      }
      final distanceMeters = _lastCameraTarget != null
          ? Geolocator.distanceBetween(
              _lastCameraTarget!.latitude,
              _lastCameraTarget!.longitude,
              target.latitude,
              target.longitude,
            )
          : 0.0;
      // Saat berhenti: target kamera hampir sama, skip animasi agar stabil.
      // Jangan pakai aturan ini untuk tombol fokus — _lastCameraTarget bisa masih dari sebelum user geser peta.
      // Jika jarak kecil tapi bearing berubah (belokan), tetap animasi — jangan membekukan rotasi.
      if (!snapFocus && distanceMeters < 5) {
        double bearingDiff = 180.0;
        if (_lastCameraBearing != null) {
          var d = camBearing - _lastCameraBearing!;
          while (d > 180) {
            d -= 360;
          }
          while (d < -180) {
            d += 360;
          }
          bearingDiff = d.abs();
        }
        if (bearingDiff < 12.0) {
          _lastCameraTarget = target;
          _lastCameraBearing = camBearing;
          return;
        }
      }
      final duration = snapFocus
          ? const Duration(milliseconds: 320)
          : _cameraDurationForMovement(
              distanceMeters: distanceMeters,
              newBearing: camBearing,
              lastBearing: _lastCameraBearing,
            );
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      final scheduled = _cameraFollowEngine.tryAnimateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            bearing: camBearing,
            tilt: _displayedTilt,
            zoom: _displayedZoom,
          ),
        ),
        duration: duration,
        force: force,
      );
      if (scheduled) {
        _lastCameraTarget = target;
        _lastCameraBearing = camBearing;
      }
    } catch (_) {}
  }

  /// Intro cinematic: center + zoom ke driver saat pertama kali mulai kerja (ala Grab).
  void _animateCameraIntroOnStart() {
    if (_mapController == null || !mounted || !_mapTabVisible) return;
    final pos = _displayedPosition ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : null);
    if (pos == null) return;
    try {
      setState(() {
        _cameraTrackingEnabled = true;
        _gpsWhenCameraManualDisabled = null;
      });
      _lastCameraTarget = pos;
      _lastCameraBearing = _smoothedBearing;
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      _cameraFollowEngine.tryAnimateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            bearing: _smoothedBearing,
            tilt: _displayedTilt,
            zoom: _displayedZoom,
          ),
        ),
        duration: const Duration(milliseconds: 450),
        force: true,
      );
    } catch (_) {}
  }

  /// Tombol Fokus: recenter ke mobil, kembali ke mode ikuti (Grab/Google Maps style).
  void _focusOnCar() {
    // Reset supaya jarak ke target tidak dianggap "0 m" vs titik lama sebelum user geser peta.
    _gpsWhenCameraManualDisabled = null;
    _lastCameraTarget = null;
    _lastCameraBearing = null;
    _cameraFollowEngine.resetThrottle();
    setState(() => _cameraTrackingEnabled = true);
    if (_displayedPosition != null) {
      _animateCameraToDisplayed(
        _smoothedBearing,
        force: true,
        snapFocus: true,
      );
    }
  }

  /// Setelah user geser peta, nyalakan lagi ikuti kamera bila mobil bergerak cukup jauh (bukan tiap meter).
  void _maybeResumeCameraTrackingAfterMovement(Position position) {
    if (_cameraTrackingEnabled) return;
    if (!_isDriverWorking && _navigatingToOrderId == null) return;
    final anchor = _gpsWhenCameraManualDisabled;
    if (anchor == null) return;
    final dist = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );
    if (dist < _resumeCameraAfterManualPanMeters) return;
    _gpsWhenCameraManualDisabled = null;
    _lastCameraTarget = null;
    _lastCameraBearing = null;
    _cameraFollowEngine.resetThrottle();
    if (!mounted) return;
    setState(() => _cameraTrackingEnabled = true);
    if (_displayedPosition != null) {
      _suppressCameraFollowAfterResume = true;
      _animateCameraToDisplayed(
        _smoothedBearing,
        force: true,
        snapFocus: true,
      );
    }
  }

  void _restartLocationTimer() {
    _locationRefreshTimer?.cancel();
    // Saat bekerja: ~1,6s bergerak / 2,8s diam — sedikit lebih jarang dari 1,3s agar HP lemah tidak kejaran timer.
    final interval = _isDriverWorking
        ? (_hasMovedAfterStart
            ? const Duration(milliseconds: 1600)
            : const Duration(milliseconds: 2800))
        : const Duration(seconds: 15);
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
        _mapTabVisible &&
        _cameraTrackingEnabled &&
        (_isDriverWorking || _navigatingToOrderId != null) &&
        _displayedPosition != null) {
      _cameraFollowEngine.resetThrottle();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateCameraToDisplayed(_smoothedBearing, force: true);
      });
    }
  }

  void _onFormDestPreviewChanged() {
    if (mounted) setState(() {});
  }

  /// Layar tetap menyala selama mode driver aktif (rute jalan), di semua tab Beranda driver.
  /// Tanpa ini, beberapa OEM melepaskan wakelock setelah app di-background.
  void _updateWakelock() {
    if (_isDriverWorking) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _onManualDriverSyncAllTick() {
    if (!mounted) return;
    setState(() => _dataOrderRefreshKey++);
    _checkActiveOrder();
  }

  @override
  void dispose() {
    HybridForegroundRecovery.manualSyncAllTick.removeListener(
      _onManualDriverSyncAllTick,
    );
    _locationPulseController
      ..removeListener(_onLocationPulseTick)
      ..dispose();
    NotificationNavigationService.unregisterOpenProfileTab();
    WidgetsBinding.instance.removeObserver(this);
    _authTokenRefreshTimer?.cancel();
    _sessionInvalidCheckTimer?.cancel();
    _authStateSub?.cancel();
    WakelockPlus.disable();
    _formDestPreviewNotifier.removeListener(_onFormDestPreviewChanged);
    _disposeDriverOrdersSub();
    _locationRefreshTimer?.cancel();
    _interpolationTimer?.cancel();
    _movementDebounceTimer?.cancel();
    _trafficAlternativesCheckTimer?.cancel();
    _driverOrdersUiDebounce?.cancel();
    _pendingJadwalSafetyTimer?.cancel();
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

  /// Mengembalikan state setelah [getAlternativeRoutes] gagal — jangan biarkan UI "aktif" tanpa polyline.
  void _revertOptimisticRouteRestoreFailure() {
    if (!mounted) return;
    setState(() {
      _isDriverWorking = false;
      _routePolyline = null;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
      _routeDistanceText = '';
      _routeDurationText = '';
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routeSelected = false;
      _originalRouteIndex = -1;
      _routeJourneyNumber = null;
      _routeStartedAt = null;
      _routeEstimatedDurationSeconds = null;
      _activeRouteFromJadwal = false;
      _hasMovedAfterStart = false;
      _positionWhenStarted = null;
      _destinationReachedAt = null;
      _currentScheduleId = null;
      _routeRestoreAwaitingPolyline = false;
    });
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

    // UI optimistik: tombol / status "sedang aktif" sebelum Directions API selesai (sering jadi bottleneck).
    setState(() {
      _routeRestoreAwaitingPolyline = true;
      _isDriverWorking = true;
      _routeOriginLatLng = LatLng(oLat, oLng);
      _routeDestLatLng = LatLng(dLat, dLng);
      _routeOriginText = originText;
      _routeDestText = destText;
      _activeRouteFromJadwal = fromJadwal ?? false;
      _routeSelected = true;
      if (firestoreRoute != null) {
        _routeJourneyNumber = firestoreRoute.routeJourneyNumber;
        _routeStartedAt = firestoreRoute.routeStartedAt;
        _routeEstimatedDurationSeconds = firestoreRoute.estimatedDurationSeconds;
        final sid = firestoreRoute.scheduleId;
        if (sid != null && sid.isNotEmpty) {
          _currentScheduleId = sid;
        }
      }
      _hasMovedAfterStart = true;
      _positionWhenStarted = _currentPosition;
      if (_currentPosition != null) {
        final raw = LatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        _displayedPosition = raw;
        _targetPosition = raw;
      }
    });
    if (_currentPosition != null) {
      unawaited(_updateDriverStatusToFirestore(_currentPosition!));
    }

    // Alternatif rute: coba sekali lagi tanpa traffic jika kosong (jaringan / quota).
    var alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      trafficAware: _trafficEnabled,
    );
    if (!mounted) return;
    if (alternatives.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      alternatives = await DirectionsService.getAlternativeRoutes(
        originLat: oLat,
        originLng: oLng,
        destLat: dLat,
        destLng: dLng,
        trafficAware: false,
      );
    }
    if (!mounted) return;
    if (alternatives.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gagal memuat rute. Periksa koneksi, lalu buka lagi dari beranda.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      }
      _revertOptimisticRouteRestoreFailure();
      return;
    }

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
      _routeRestoreAwaitingPolyline = false;
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
    if (forTracking) {
      if (_getCurrentLocationTrackingInFlight) return;
      _getCurrentLocationTrackingInFlight = true;
    }
    try {
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
          highAccuracyWhenTracking:
              AppConstants.useHighAccuracyLocationForActiveDriverNavigation(
            forTracking: forTracking,
            isDriverWorking: _isDriverWorking,
            hasNavigatingToOrder: _navigatingToOrderId != null,
          ),
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
          highAccuracyWhenTracking:
              AppConstants.useHighAccuracyLocationForActiveDriverNavigation(
            forTracking: forTracking,
            isDriverWorking: _isDriverWorking,
            hasNavigatingToOrder: _navigatingToOrderId != null,
          ),
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
        _currentPosition = position;
        final rawLatLng = LatLng(position.latitude, position.longitude);
        final panningMap = !_cameraTrackingEnabled &&
            (_isDriverWorking || _navigatingToOrderId != null);
        final minMetersForPositionUi = panningMap
            ? _minMetersForLocationPositionSetStateWhilePanning
            : _minMetersForLocationPositionSetState;
        final needPositionUi =
            _lastUiEmittedLocationForPosition == null ||
                Geolocator.distanceBetween(
                      _lastUiEmittedLocationForPosition!.latitude,
                      _lastUiEmittedLocationForPosition!.longitude,
                      rawLatLng.latitude,
                      rawLatLng.longitude,
                    ) >=
                    minMetersForPositionUi;
        if (needPositionUi) {
          if (_mapTabVisible) {
            _lastUiEmittedLocationForPosition = rawLatLng;
            setState(() {});
          }
        }

        // Posisi: GPS mentah kecuali cukup dekat polyline (lihat [_snapToRoutePolylineMaxMeters]).
        int targetSeg = -1;
        double targetRatio = 0;
        LatLng targetPos = rawLatLng;
        final polyline = _routePolyline ?? _activeNavigationPolyline;
        if (polyline != null && polyline.length >= 2) {
          final projected = RouteUtils.projectPointOntoPolyline(
            rawLatLng,
            polyline,
            maxDistanceMeters: _snapToRoutePolylineMaxMeters,
          );
          targetSeg = projected.$2;
          targetRatio = projected.$3;
          // Snap ke garis biru hanya jika proyeksi dalam radius; jika tidak = ikut HP.
          if (targetSeg >= 0) targetPos = projected.$1;
        }

        final routeDeviationMeters =
            (polyline != null && polyline.length >= 2)
                ? RouteUtils.distanceToPolyline(rawLatLng, polyline)
                : 0.0;

        // Prediction engine: blend GPS dengan prediksi untuk pergerakan lebih halus (bukan hanya saat data telat)
        if (_positionBeforeLast != null && _lastReceivedTarget != null) {
          final predicted = _predictPosition(_positionBeforeLast!, _lastReceivedTarget!);
          targetPos = LatLng(
            targetPos.latitude * 0.88 + predicted.latitude * 0.12,
            targetPos.longitude * 0.88 + predicted.longitude * 0.12,
          );
        }

        // Hitung kecepatan untuk offset kamera dinamis (smoothing + outlier filter).
        // Pakai [_lastPositionForSpeed] (bukan hanya saat kerja) agar turunan jarak
        // tetap ada saat GPS [speed] = 0.
        if (_lastPositionForSpeed != null && _lastPositionTimestamp != null) {
          final distM = Geolocator.distanceBetween(
            _lastPositionForSpeed!.latitude,
            _lastPositionForSpeed!.longitude,
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

        _maybeResumeCameraTrackingAfterMovement(position);

        // Langkah navigasi untuk rute utama (setelah hydrate) — suara + indeks step.
        if (_isDriverWorking &&
            _navigatingToOrderId == null &&
            polyline != null &&
            polyline.length >= 2 &&
            _routeSteps.isEmpty &&
            _routeDestLatLng != null &&
            !_routeStepsHydrateRequested) {
          _routeStepsHydrateRequested = true;
          unawaited(_hydrateMainRouteSteps());
        }

        var missedTurnRerouteScheduled = false;
        if (_isDriverWorking &&
            polyline != null &&
            polyline.length >= 2 &&
            _routeSteps.isNotEmpty) {
          missedTurnRerouteScheduled = _checkMissedTurnAndScheduleReroute(
            rawLatLng,
            polyline,
            routeDeviationMeters,
          );
        }

        if (_isDriverWorking &&
            _routeSteps.isNotEmpty &&
            _navigatingToOrderId == null) {
          _updateCurrentStepFromPosition(position);
        }

        // Auto reroute ala Google Maps: beda jalur / menyimpang dari garis biru → rute baru dari GPS sekarang.
        final shouldAutoReroute = _isDriverWorking &&
            !missedTurnRerouteScheduled &&
            _currentPosition != null &&
            polyline != null &&
            polyline.length >= 2 &&
            routeDeviationMeters >= _autoRerouteMinDeviationMeters;

        if (shouldAutoReroute) {
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
                  _fetchAndShowRouteToDestination(navOrder, quiet: true);
                } else {
                  _fetchAndShowRouteToPassenger(navOrder, quiet: true);
                }
              }
            }
          } else if (_routeDestLatLng != null) {
            unawaited(
              _maybeRerouteFromCurrentPosition(
                rawLatLng,
                quiet: true,
              ),
            );
          }
        }

        if (forTracking) {
          final now = DateTime.now();
          final movedFar = _lastOriginPlacemarkGeocodePosition == null ||
              Geolocator.distanceBetween(
                    _lastOriginPlacemarkGeocodePosition!.latitude,
                    _lastOriginPlacemarkGeocodePosition!.longitude,
                    rawLatLng.latitude,
                    rawLatLng.longitude,
                  ) >=
                  _originPlacemarkGeocodeMinDistanceMeters;
          final stale = _lastOriginPlacemarkGeocodeAt == null ||
              now.difference(_lastOriginPlacemarkGeocodeAt!).inMinutes >=
                  _originPlacemarkGeocodeMaxIntervalMinutes;
          if (movedFar || stale) {
            _lastOriginPlacemarkGeocodePosition = rawLatLng;
            _lastOriginPlacemarkGeocodeAt = now;
            unawaited(_updateLocationText(position));
          }
        } else {
          await _updateLocationText(position);
        }

        // Nama jalan (reverse geocode, throttle ~80m)
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
          // Saat diam: bekukan bearing agar kamera tidak kemana-mana.
          // Jangan pakai raw [position.speed] saja — di Android sering 0 → bearing membeku.
          double rawBearing = 0.0;
          bool skipBearingUpdate = false;
          final speedMps = _effectiveSpeedMps(position);
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
              if (!mounted || _isMovingStable == capturedMoving) return;
              _isMovingStable = capturedMoving;
              if (_mapTabVisible) setState(() {});
            });
            _restartLocationTimer(); // ~1,3s bergerak / 2,5s diam
          } else if (_needsBearingSetState) {
            _needsBearingSetState = false;
            // Saat user geser peta, hindari rebuild hanya untuk rotasi — geser tetap halus di thread peta.
            if (_cameraTrackingEnabled && _mapTabVisible) {
              setState(() {}); // Update bearing untuk Marker.rotation
            }
          }

          // Update posisi terakhir untuk deteksi pergerakan berikutnya
          _lastPositionForMovement = position;
        } else {
          // Idle: update bearing untuk rotasi icon (smooth)
          if (position.heading.isFinite) {
            final speedMps = _effectiveSpeedMps(position);
            if (speedMps.isFinite && speedMps >= _bearingMinSpeedMps) {
              _displayedBearing = position.heading;
              final prevSmoothed = _smoothedBearing;
              _smoothedBearing = _smoothBearing(
                _smoothedBearing,
                position.heading,
              );
              final rotDiff = ((_smoothedBearing - prevSmoothed + 180) % 360 - 180).abs();
              if (rotDiff > 3 && _mapTabVisible) setState(() {});
            }
          }
        }

        // Update jarak/ETA: Directions API di-throttle; antar fetch pakai garis lurus (ringan).
        if (_isDriverWorking && _routeDestLatLng != null) {
          await _refreshDistanceDurationThrottled(position);
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
                  _fetchAndShowRouteToDestination(navOrder, quiet: true);
                } else {
                  _fetchAndShowRouteToPassenger(navOrder, quiet: true);
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
          unawaited(_checkAndAutoSwitchRoute(position));
        }

        // Update status & lokasi ke Firestore agar penumpang bisa menemukan driver.
        // Saat menuju jemput: update sering (50m/5s) untuk Lacak Driver.
        // Saat rute biasa: update hemat (2km/15min).
        if (_isDriverWorking &&
            (_lastUpdatedTime == null || _shouldUpdateFirestore(position))) {
          await _updateDriverStatusToFirestore(position);
        }

        // Kamera: satu jalur dengan [_animateCameraToDisplayed] (sumber = posisi visual / interpolasi).
        // Hindari animateCamera ganda di sini — itu bikin kamera vs marker tidak sinkron.
        if (_mapController != null &&
            mounted &&
            _mapTabVisible &&
            _cameraTrackingEnabled) {
          if (_suppressCameraFollowAfterResume) {
            _suppressCameraFollowAfterResume = false;
          } else {
            final interpolationActive = _interpolationTimer?.isActive ?? false;
            final hasPolylineRoute = (_isDriverWorking ||
                    _navigatingToOrderId != null) &&
                (polyline != null && polyline.length >= 2);
            if (!hasPolylineRoute || !interpolationActive) {
              _animateCameraToDisplayed(_smoothedBearing);
            }
          }
        }

        _lastPositionForSpeed = position;
      }
      } catch (_) {}
    } finally {
      if (forTracking) {
        _getCurrentLocationTrackingInFlight = false;
      }
    }
  }

  bool _shouldFetchDirectionsEta(Position position) {
    final dest = _routeDestLatLng;
    if (dest == null) return false;
    if (_lastEtaThrottleDest == null ||
        (dest.latitude - _lastEtaThrottleDest!.latitude).abs() > 1e-5 ||
        (dest.longitude - _lastEtaThrottleDest!.longitude).abs() > 1e-5) {
      _lastEtaThrottleDest = LatLng(dest.latitude, dest.longitude);
      return true;
    }
    if (_lastDirectionsEtaFetchAt == null) return true;
    if (DateTime.now().difference(_lastDirectionsEtaFetchAt!).inSeconds >=
        _directionsEtaMinIntervalSeconds) {
      return true;
    }
    if (_lastDirectionsEtaFetchPosition != null) {
      final moved = Geolocator.distanceBetween(
        _lastDirectionsEtaFetchPosition!.latitude,
        _lastDirectionsEtaFetchPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (moved >= _directionsEtaMinDistanceMeters) return true;
    }
    return false;
  }

  /// Antara fetch Directions: perkiraan garis lurus (tanpa jaringan), teks ikut bergerak.
  void _updateDistanceDurationStraightLine(Position position) {
    if (_routeDestLatLng == null || !mounted) return;
    final distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _routeDestLatLng!.latitude,
      _routeDestLatLng!.longitude,
    );
    final distanceKm = distanceMeters / 1000;
    final newDistText = '${distanceKm.toStringAsFixed(1)} km';
    final estimatedHours = distanceKm / 60;
    final String newDurText;
    if (estimatedHours < 1) {
      final minutes = (estimatedHours * 60).round();
      newDurText = '$minutes mins';
    } else {
      final hours = estimatedHours.floor();
      final minutes = ((estimatedHours - hours) * 60).round();
      newDurText = hours > 0 && minutes > 0
          ? '$hours hours $minutes mins'
          : hours > 0
          ? '$hours hours'
          : '$minutes mins';
    }
    if (_currentDistanceText != newDistText ||
        _currentDurationText != newDurText) {
      setState(() {
        _currentDistanceText = newDistText;
        _currentDurationText = newDurText;
      });
    }
  }

  Future<void> _refreshDistanceDurationThrottled(Position position) async {
    if (_routeDestLatLng == null) return;
    if (_shouldFetchDirectionsEta(position)) {
      await _updateCurrentDistanceAndDuration(position);
    } else {
      _updateDistanceDurationStraightLine(position);
    }
  }

  /// Update jarak dan estimasi waktu dari posisi driver saat ini ke tujuan (Directions API).
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
        _lastDirectionsEtaFetchAt = DateTime.now();
        _lastDirectionsEtaFetchPosition =
            LatLng(position.latitude, position.longitude);
        if (_currentDistanceText != result.distanceText ||
            _currentDurationText != result.durationText) {
          setState(() {
            _currentDistanceText = result.distanceText;
            _currentDurationText = result.durationText;
          });
        }
      } else if (mounted) {
        _lastDirectionsEtaFetchAt = DateTime.now();
        _lastDirectionsEtaFetchPosition =
            LatLng(position.latitude, position.longitude);
        _updateDistanceDurationStraightLine(position);
      }
    } catch (_) {
      // Jangan spam API saat error; tampilkan garis lurus dulu.
      _lastDirectionsEtaFetchAt = DateTime.now();
      _lastDirectionsEtaFetchPosition =
          LatLng(position.latitude, position.longitude);
      if (mounted) _updateDistanceDurationStraightLine(position);
    }
  }

  /// Cek dan auto-switch rute jika driver berada di rute alternatif lain.
  /// Syarat: GPS dalam [_autoSwitchNearestRouteToleranceMeters] ke polyline terdekat;
  /// jeda antar switch ≥ [_autoSwitchRouteCooldown]. Switch balik ke rute awal aturan sama.
  Future<void> _checkAndAutoSwitchRoute(Position position) async {
    if (_alternativeRoutes.isEmpty || _selectedRouteIndex < 0) return;
    if (_autoSwitchRouteCheckInFlight) return;
    _autoSwitchRouteCheckInFlight = true;
    try {
      final driverPos = LatLng(position.latitude, position.longitude);
      final now = DateTime.now();

      // Konversi alternatif rute ke List<List<LatLng>> untuk RouteUtils
      final alternativePolylines = _alternativeRoutes
          .map((r) => r.points)
          .toList();

      // Cari rute terdekat dari posisi driver saat ini (isolate jika polyline besar).
      final nearestRouteIndex = await RouteUtils.findNearestRouteIndexAsync(
        driverPos,
        alternativePolylines,
        toleranceMeters: _autoSwitchNearestRouteToleranceMeters,
      );

      if (!mounted) return;

      // Jika tidak ada rute dalam toleransi, tidak perlu switch
      if (nearestRouteIndex < 0) return;

      // Jika rute terdekat berbeda dengan rute yang dipilih saat ini
      if (nearestRouteIndex != _selectedRouteIndex) {
        final canSwitch =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >= _autoSwitchRouteCooldown;

        if (canSwitch) {
          // Simpan index rute awal jika belum pernah switch
          if (_originalRouteIndex < 0) {
            _originalRouteIndex = _selectedRouteIndex;
          }

          // Switch ke rute terdekat
          if (mounted) {
            final sel = _alternativeRoutes[nearestRouteIndex];
            setState(() {
              _selectedRouteIndex = nearestRouteIndex;
              _routePolyline = sel.points;
              _routeDistanceText = sel.distanceText;
              _routeDurationText = sel.durationText;
              _routeEstimatedDurationSeconds = sel.durationSeconds;
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

            if (kDebugMode) {
              debugPrint(
                'DriverScreen: Auto-switch ke rute index $nearestRouteIndex',
              );
            }
          }
        }
      } else if (_originalRouteIndex >= 0 &&
          nearestRouteIndex == _originalRouteIndex &&
          _selectedRouteIndex != _originalRouteIndex) {
        final canSwitchBack =
            _lastRouteSwitchTime == null ||
            now.difference(_lastRouteSwitchTime!) >= _autoSwitchRouteCooldown;

        if (canSwitchBack) {
          final backIdx = _originalRouteIndex;
          final selBack = _alternativeRoutes[backIdx];
          // Switch kembali ke rute awal
          if (mounted) {
            setState(() {
              _selectedRouteIndex = backIdx;
              _routePolyline = selBack.points;
              _routeDistanceText = selBack.distanceText;
              _routeDurationText = selBack.durationText;
              _routeEstimatedDurationSeconds = selBack.durationSeconds;
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

            if (kDebugMode) {
              debugPrint(
                'DriverScreen: Auto-switch kembali ke rute awal index $backIdx',
              );
            }
          }
        }
      }
    } catch (e, st) {
      logError('DriverScreen._checkAndAutoSwitchRoute', e, st);
    } finally {
      _autoSwitchRouteCheckInFlight = false;
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
        final newProv = prov.isNotEmpty ? prov : null;
        final newOrigin = _formatPlacemarkShort(place);
        if (_currentProvinsi != newProv || _originLocationText != newOrigin) {
          setState(() {
            _currentProvinsi = newProv;
            _originLocationText = newOrigin;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        final fallback =
            '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        if (_originLocationText != fallback) {
          setState(() => _originLocationText = fallback);
        }
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
          citySlug = PlacemarkFormatter.citySlugForGeoMatching(subAdmin);
        }
      }
      final slugChanged =
          citySlug != null && citySlug != _currentCitySlug;
      if (name != _currentStreetName || slugChanged) {
        setState(() {
          _currentStreetName = name;
          if (citySlug != null) _currentCitySlug = citySlug;
        });
      }
    } catch (_) {
      if (mounted && requestId == _streetNameGeocodeRequestId) {
        final offline = TrakaL10n.of(context).offline;
        if (_currentStreetName != offline) {
          setState(() => _currentStreetName = offline);
        }
      }
    }
  }

  String _formatPlacemarkShort(Placemark place) =>
      PlacemarkFormatter.formatShort(place);

  /// Cek apakah perlu update lokasi ke Firestore (default 2 km / 15 menit, atau tier lebih sering).
  bool _shouldUpdateFirestore(Position currentPosition) {
    final fullLiveTracking = _navigatingToOrderId != null ||
        _jumlahPenumpangPickedUp > 0 ||
        _jumlahBarang > 0;
    if (fullLiveTracking) {
      return DriverStatusService.shouldUpdateLocationForLiveTracking(
        currentPosition: currentPosition,
        lastUpdatedPosition: _lastUpdatedPosition,
        lastUpdatedTime: _lastUpdatedTime,
      );
    }
    // Agreed menunggu jemput, belum tap arahkan: hemat write vs live 50 m — tetap cukup untuk notifikasi 1 km / 500 m
    if (_waitingPassengerCount > 0) {
      return DriverStatusService.shouldUpdateLocationForPickupProximity(
        currentPosition: currentPosition,
        lastUpdatedPosition: _lastUpdatedPosition,
        lastUpdatedTime: _lastUpdatedTime,
      );
    }
    return DriverStatusService.shouldUpdateLocation(
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
      // Jangan hitung auto-end / jangan akhiri kerja otomatis selagi masih ada travel/barang aktif.
      if (_hasActiveOrder) {
        _destinationReachedAt = null;
        _maybeShowAtMainRouteDestinationWithOrdersHint();
        return;
      }
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

  /// Nilai `bucket` untuk [AppAnalyticsService.logDriverFinishWorkBlocked].
  String _finishWorkBlockedAnalyticsBucket() {
    if (_jumlahPenumpang > 0 && _jumlahBarang > 0) return 'both';
    if (_jumlahPenumpang > 0) return 'passengers';
    if (_jumlahBarang > 0) return 'goods';
    return 'pending_unknown';
  }

  void _showSnackBarCannotEndWorkDueToActiveOrders() {
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    final label = l10n.finishWork;
    final String msg;
    if (_jumlahPenumpang > 0 && _jumlahBarang > 0) {
      msg = l10n.driverCannotFinishWorkBoth(
        _jumlahPenumpang,
        _jumlahBarang,
        label,
      );
    } else if (_jumlahPenumpang > 0) {
      msg = l10n.driverCannotFinishWorkPassengersOnly(_jumlahPenumpang, label);
    } else if (_jumlahBarang > 0) {
      msg = l10n.driverCannotFinishWorkGoodsOnly(_jumlahBarang, label);
    } else {
      msg = l10n.driverCannotFinishWorkPendingGeneric(label);
    }
    AppAnalyticsService.logDriverFinishWorkBlocked(
      surface: 'snackbar',
      bucket: _finishWorkBlockedAnalyticsBucket(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _maybeShowAtMainRouteDestinationWithOrdersHint() {
    if (!_hasActiveOrder) return;
    final now = DateTime.now();
    if (_lastSnackAtRouteDestWithActiveOrders != null &&
        now.difference(_lastSnackAtRouteDestWithActiveOrders!) <
            const Duration(minutes: 10)) {
      return;
    }
    _lastSnackAtRouteDestWithActiveOrders = now;
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    AppAnalyticsService.logDriverFinishWorkBlocked(
      surface: 'near_dest',
      bucket: _finishWorkBlockedAnalyticsBucket(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.driverNearMainRouteDestFinishWorkBlockedHint(l10n.finishWork),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _endWork() async {
    if (_hasActiveOrder) {
      _showSnackBarCannotEndWorkDueToActiveOrders();
      return;
    }
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
    _resetJourneyNumberPrefetch();
    setState(() {
      if (_routeOriginLatLng != null && _routeDestLatLng != null) {
        _lastRouteOriginLatLng = _routeOriginLatLng;
        _lastRouteDestLatLng = _routeDestLatLng;
        _lastRouteOriginText = _routeOriginText;
        _lastRouteDestText = _routeDestText;
      }
      _isDriverWorking = false;
      _routePolyline = null;
      _routeSteps = [];
      _currentStepIndex = -1;
      _routeStepsHydrateRequested = false;
      _lastMissedTurnRerouteAt = null;
      _routeRecalculateDepth = 0;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
      _routeDistanceText = '';
      _currentScheduleId = null;
      _routeDurationText = '';
      _destinationReachedAt = null;
      _lastSnackAtRouteDestWithActiveOrders = null;
      _routeJourneyNumber = null;
      _routeStartedAt = null;
      _routeEstimatedDurationSeconds = null;
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routeSelected = false;
      _lastReroutePosition = null;
      _lastRerouteAt = null;
      _manualRerouteInProgress = false;
      _originalRouteIndex = -1;
      _lastRouteSwitchTime = null;
      _carIconRed = null;
      _carIconGreen = null;
      _positionWhenStarted = null;
      _hasMovedAfterStart = false;
      _isMovingStable = false;
      _movementDebounceTimer?.cancel();
      _lastPositionForMovement = null;
      _lastPositionForSpeed = null;
      _activeRouteFromJadwal = false;
      _routeRestoreAwaitingPolyline = false;
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
      _gpsWhenCameraManualDisabled = null;
      _suppressCameraFollowAfterResume = false;
      _displayedZoom = 17.0;
      _displayedTilt = 40.0;
      _currentSpeedMps = 0.0;
      _lastEtaThrottleDest = null;
      _lastDirectionsEtaFetchAt = null;
      _lastDirectionsEtaFetchPosition = null;
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

  /// Tombol pill kiri: jika rute sudah dipilih, sama dengan "Mulai Rute ini" (bukan mati / tidak responsif).
  Future<void> _onDriverWorkPillTap() async {
    if (!_isDriverWorking &&
        _routeSelected &&
        _selectedRouteIndex >= 0 &&
        _alternativeRoutes.isNotEmpty) {
      await _onStartButtonTap();
      return;
    }
    await _onToggleButtonTap();
  }

  Future<void> _onToggleButtonTap() async {
    HapticFeedback.mediumImpact();
    // Draf alternatif tanpa pilihan memblokir alur; setelah dari Jadwal sering tertinggal — bersihkan dan lanjut Siap Kerja.
    if (_alternativeRoutes.isNotEmpty && !_routeSelected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Draf rute di peta dihapus. Lanjut pilih jenis rute / jadwal.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
      _clearDraftRoutesAndOpenStartFlow();
      return;
    }

    // Tombol "Mulai" akan menangani mulai bekerja (lihat method _onStartButtonTap)

    if (_isDriverWorking) {
      // Jika masih ada penumpang/barang (agreed atau picked_up), tidak boleh berhenti bekerja
      if (_hasActiveOrder) {
        _showSnackBarCannotEndWorkDueToActiveOrders();
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
      await _checkScheduledOrdersThenShowRouteSheet();
    }
  }

  /// Jika driver punya pesanan terjadwal (agreed/picked_up), tawarkan gunakan rute jadwal; else tampilkan sheet pilih jenis rute.
  Future<void> _checkScheduledOrdersThenShowRouteSheet() async {
    final existing = _driverStartWorkCheckFuture;
    if (existing != null) {
      // Jangan `await` tanpa batas lalu `return` — pengguna menganggap tombol mati. Lepaskan future macet.
      try {
        await existing.timeout(const Duration(seconds: 26));
      } catch (_) {}
      if (identical(_driverStartWorkCheckFuture, existing)) {
        _driverStartWorkCheckFuture = null;
      }
    }

    Future<void> guardedRun() async {
      try {
        await _checkScheduledOrdersThenShowRouteSheetBody()
            .timeout(const Duration(seconds: 22));
      } on TimeoutException {
        _startWorkCheckGen++;
        _startWorkLoadingSnackTimer?.cancel();
        _startWorkLoadingSnackTimer = null;
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Memeriksa jadwal terlalu lama. Periksa sinyal lalu ketuk Siap Kerja lagi.',
              ),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    }

    final run = guardedRun();
    _driverStartWorkCheckFuture = run;
    try {
      await run;
    } finally {
      if (identical(_driverStartWorkCheckFuture, run)) {
        _driverStartWorkCheckFuture = null;
      }
    }
  }

  Future<void> _checkScheduledOrdersThenShowRouteSheetBody() async {
    if (!_canStartDriverWork) {
      _showDriverVerificationGateDialog();
      return;
    }
    final gen = _startWorkCheckGen;
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    // SnackBar baru setelah jeda: cek Firestore sering selesai cepat — tanpa ini
    // tap Siap Kerja terasa "memuat pesan terjadwal" setiap kali (mengganggu).
    _startWorkLoadingSnackTimer?.cancel();
    if (mounted) {
      _startWorkLoadingSnackTimer = Timer(const Duration(milliseconds: 450), () {
        _startWorkLoadingSnackTimer = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memeriksa pesanan terjadwal…'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 25),
          ),
        );
      });
    }
    try {
      final orders = await OrderService.getDriverScheduledOrdersWithAgreed();
      if (!mounted) return;
      if (gen != _startWorkCheckGen) {
        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
        return;
      }
      ScaffoldMessenger.of(context).clearSnackBars();
      if (_currentIndex != 0) {
        return;
      }
      if (orders.isEmpty) {
        if (gen == _startWorkCheckGen) _showRouteTypeSheet();
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
      if (gen != _startWorkCheckGen) {
        if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
        return;
      }
      if (useJadwal == true &&
          scheduleId != null &&
          originText.isNotEmpty &&
          destText.isNotEmpty) {
        setState(() {
          _currentIndex = 0;
          _pendingJadwalRouteLoad = true;
          _isStartRouteLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _canStartDriverWork) {
            _loadRouteFromJadwal(originText, destText, scheduleId);
          }
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
        if (gen == _startWorkCheckGen) _showRouteTypeSheet();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('_checkScheduledOrdersThenShowRouteSheetBody: $e\n$st');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    } finally {
      _startWorkLoadingSnackTimer?.cancel();
      _startWorkLoadingSnackTimer = null;
    }
  }

  /// Bersihkan rute draf (alternatif ada tapi belum dipilih / state setengah dari jadwal), lalu alur Siap Kerja dari awal.
  void _clearDraftRoutesAndOpenStartFlow() {
    if (!_canStartDriverWork) {
      _showDriverVerificationGateDialog();
      return;
    }
    _resetJourneyNumberPrefetch();
    setState(() {
      _pendingJadwalRouteLoad = false;
      _isStartRouteLoading = false;
      _routeRestoreAwaitingPolyline = false;
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routePolyline = null;
      _routeDistanceText = '';
      _routeDurationText = '';
      _currentDistanceText = '';
      _currentDurationText = '';
      _routeSelected = false;
      _activeRouteFromJadwal = false;
      _currentScheduleId = null;
      _currentRouteCategory = null;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkScheduledOrdersThenShowRouteSheet();
    });
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
          onPressed: () => setState(() {
            _registerTabVisit(4);
            _currentIndex = 4;
          }),
        ),
      ),
    );
  }

  void _resetJourneyNumberPrefetch() {
    _journeyNumberPrefetchFuture = null;
  }

  /// Mulai memanggil Cloud Function di background begitu alternatif rute tersedia (bukan jadwal terjadwal).
  void _startJourneyNumberPrefetch() {
    if (_routeJourneyNumber != null && _routeJourneyNumber!.isNotEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_activeRouteFromJadwal &&
        _currentScheduleId != null &&
        _currentScheduleId!.isNotEmpty) {
      return;
    }
    _journeyNumberPrefetchFuture ??=
        RouteJourneyNumberService.generateRouteJourneyNumber().then((jn) {
          if (mounted) setState(() => _routeJourneyNumber = jn);
          return jn;
        });
  }

  Future<void> _awaitJourneyNumberAfterSelect() async {
    if (_routeJourneyNumber != null && _routeJourneyNumber!.isNotEmpty) return;
    if (_journeyNumberPrefetchFuture != null) {
      try {
        await _journeyNumberPrefetchFuture!;
        return;
      } catch (_) {
        _resetJourneyNumberPrefetch();
      }
    }
    final jn = await RouteJourneyNumberService.generateRouteJourneyNumber();
    if (mounted) setState(() => _routeJourneyNumber = jn);
  }

  /// Generate nomor rute setelah tap alternatif — jangan blokir frame UI (unawaited).
  Future<void> _awaitJourneyNumberAfterSelectWithSnacks() async {
    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) _showSessionInvalidSnackBar();
      return;
    }
    try {
      await _awaitJourneyNumberAfterSelect();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
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
                  onPressed: () => setState(() {
                    _registerTabVisit(4);
                    _currentIndex = 4;
                  }),
                )
              : null,
        ),
      );
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

  Future<String> _ensureJourneyNumberReadyForStartWork() async {
    if (_routeJourneyNumber != null && _routeJourneyNumber!.isNotEmpty) {
      return _routeJourneyNumber!;
    }
    if (_journeyNumberPrefetchFuture != null) {
      try {
        final jn = await _journeyNumberPrefetchFuture!;
        if (_routeJourneyNumber != null && _routeJourneyNumber!.isNotEmpty) {
          return _routeJourneyNumber!;
        }
        return jn;
      } catch (_) {
        _resetJourneyNumberPrefetch();
      }
    }
    final jn = await RouteJourneyNumberService.generateRouteJourneyNumber();
    if (mounted) setState(() => _routeJourneyNumber = jn);
    return jn;
  }

  /// Handler untuk tombol "Mulai" - mulai bekerja setelah rute dipilih
  Future<void> _onStartButtonTap() async {
    HapticFeedback.mediumImpact();
    if (!_routeSelected || _selectedRouteIndex < 0) return;
    if (_isStartRouteLoading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Masih memproses rute. Tunggu sebentar atau coba lagi.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _isStartRouteLoading = true);
    try {
      await _onStartButtonTapImpl();
    } finally {
      _isStartRouteLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _onStartButtonTapImpl() async {
    // Pastikan journey number (prefetch paralel saat alternatif dimuat, atau fallback)
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      if (FirebaseAuth.instance.currentUser == null) {
        if (mounted) {
          _showSessionInvalidSnackBar();
        }
        return;
      }
      try {
        await _ensureJourneyNumberReadyForStartWork();
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
                      onPressed: () => setState(() {
                        _registerTabVisit(4);
                        _currentIndex = 4;
                      }),
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
      // ETA/jarak dari rute yang sudah dipilih dulu — hindari round-trip Directions API
      // yang memblokir tombol "Mulai". Refresh di background di bawah.
      if (_selectedRouteIndex >= 0 &&
          _selectedRouteIndex < _alternativeRoutes.length) {
        final sel = _alternativeRoutes[_selectedRouteIndex];
        _currentDistanceText = sel.distanceText;
        _currentDurationText = sel.durationText;
      } else {
        _currentDistanceText = _routeDistanceText;
        _currentDurationText = _routeDurationText;
      }
    });
    _restartLocationTimer();

    // Load icon mobil MERAH saat mulai bekerja (belum bergerak)
    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      _displayedBearing = _currentPosition!.heading;
      _smoothedBearing = _displayedBearing;
    }
    await _loadCarIconsOnce();

    // Segarkan jarak/ETA dari posisi terkini ke tujuan tanpa memblokir UI.
    if (_currentPosition != null && _routeDestLatLng != null) {
      unawaited(_updateCurrentDistanceAndDuration(_currentPosition!));
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
      // Suara arahan langsung seperti Google Maps (TTS langkah pertama setelah hydrate).
      unawaited(VoiceNavigationService.instance.init());
      if (_routeDestLatLng != null && _currentPosition != null) {
        unawaited(_hydrateMainRouteSteps());
      }
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

  Widget _routeTypeSheetCard({
    required BuildContext sheetContext,
    required IconData icon,
    required Color iconBackground,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    final theme = Theme.of(sheetContext);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (badge != null && badge.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: iconColor.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: iconColor,
                                  height: 1.1,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.outline,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRouteTypeSheet() {
    if (!_canStartDriverWork) {
      _showDriverVerificationGateDialog();
      return;
    }
    final now = DateTime.now();
    if (_lastRouteTypeSheetOpenedAt != null &&
        now.difference(_lastRouteTypeSheetOpenedAt!) <
            const Duration(milliseconds: 1700)) {
      return;
    }
    if (_routeTypeSheetOpen) return;
    _routeTypeSheetOpen = true;
    _lastRouteTypeSheetOpenedAt = now;
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih jenis rute',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sesuaikan area tujuan dengan perjalanan Anda',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
            _routeTypeSheetCard(
              sheetContext: ctx,
              icon: Icons.location_city_rounded,
              iconBackground: AppTheme.primary.withValues(alpha: 0.14),
              iconColor: AppTheme.primary,
              title: 'Dalam provinsi',
              badge: 'Satu provinsi',
              subtitle: 'Tujuan hanya di provinsi lokasi Anda saat ini',
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.dalamProvinsi,
                );
              },
            ),
            _routeTypeSheetCard(
              sheetContext: ctx,
              icon: Icons.alt_route_rounded,
              iconBackground: AppTheme.secondary.withValues(alpha: 0.18),
              iconColor: AppTheme.secondary,
              title: 'Antar provinsi (satu pulau)',
              badge: 'Satu pulau',
              subtitle: 'Ke provinsi lain di pulau yang sama',
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.antarProvinsi,
                );
              },
            ),
            _routeTypeSheetCard(
              sheetContext: ctx,
              icon: Icons.travel_explore_rounded,
              iconBackground: AppTheme.primaryDark.withValues(alpha: 0.12),
              iconColor: AppTheme.primaryDark,
              title: 'Seluruh Indonesia',
              badge: 'Lintas pulau',
              subtitle: 'Ke mana saja di Indonesia (termasuk lintas pulau)',
              onTap: () {
                Navigator.pop(ctx);
                _openRouteForm(
                  RouteType.dalamNegara,
                );
              },
            ),
            if (hasPreviousRoute && atDestination) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Divider(
                  height: 1,
                  color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.35),
                ),
              ),
              _routeTypeSheetCard(
                sheetContext: ctx,
                icon: Icons.swap_horiz_rounded,
                iconBackground: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                iconColor: const Color(0xFF2E7D32),
                title: 'Putar arah rute sebelumnya',
                badge: 'Balik',
                subtitle:
                    'Tujuan dan asal rute terakhir ditukar (pulang pergi)',
                onTap: () {
                  Navigator.pop(ctx);
                  _reversePreviousRoute();
                },
              ),
            ],
            const SizedBox(height: 14),
          ],
        ),
      ),
    ).whenComplete(() {
      _routeTypeSheetOpen = false;
    });
  }

  /// Buang hanya rute API yang geometrinya hampir sama dengan rute tersimpan
  /// (garis bertumpuk). Alternatif dengan panjang mirip Google tapi jalur beda tetap tampil.
  List<DirectionsResult> _filterApiRoutesDuplicateOfSaved(
    DirectionsResult saved,
    List<DirectionsResult> api,
  ) {
    if (api.isEmpty) return api;
    return api
        .where(
          (r) => !RouteUtils.polylinesLikelyDuplicate(saved.points, r.points),
        )
        .toList();
  }

  /// Dari Jadwal & Rute (icon rute): muat rute dari tujuan awal/akhir jadwal.
  /// [routePolyline] dari Firestore dipangkas — dipakai hanya untuk menyaring duplikat Directions; garis di peta utamanya dari API.
  Future<void> _loadRouteFromJadwal(
    String originText,
    String destText, [
    String? scheduleId,
    List<LatLng>? routePolyline,
    String? routeCategory,
  ]) async {
    final loadGen = ++_loadRouteFromJadwalGen;
    _pendingJadwalSafetyTimer?.cancel();
    _pendingJadwalSafetyTimer = Timer(const Duration(seconds: 50), () {
      if (!mounted) return;
      if (loadGen != _loadRouteFromJadwalGen) return;
      if (_pendingJadwalRouteLoad) {
        setState(() => _pendingJadwalRouteLoad = false);
      }
    });
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
          setState(() => _pendingJadwalRouteLoad = false);
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

      DirectionsResult? savedFromPolyline;
      if (routePolyline != null && routePolyline.length >= 2) {
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
        savedFromPolyline = DirectionsResult(
          points: routePolyline,
          distanceKm: km,
          distanceText: '${km.toStringAsFixed(1)} km',
          durationSeconds: durSec,
          durationText: durSec >= 3600
              ? '${durSec ~/ 3600} jam ${(durSec % 3600) ~/ 60} mnt'
              : '${durSec ~/ 60} menit',
        );
      }

      var apiAlternatives = await DirectionsService.getAlternativeRoutes(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _trafficEnabled,
      );
      if (!mounted) return;
      if (apiAlternatives.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        apiAlternatives = await DirectionsService.getAlternativeRoutes(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          trafficAware: false,
        );
      }

      // Polyline di Firestore wajib dipangkas agar dokumen muat — jangan jadikan garis utama di peta
      // (titik sedikit = tampak patah memotong blok). Bila ada hasil Directions, pakai geometri API (halus).
      if (savedFromPolyline != null && apiAlternatives.isNotEmpty) {
        final extra = _filterApiRoutesDuplicateOfSaved(
          savedFromPolyline,
          apiAlternatives,
        );
        alternatives = extra.isNotEmpty
            ? extra
            : List<DirectionsResult>.from(apiAlternatives);
        preSelectedIndex = 0;
        preSelected = true;
      } else if (savedFromPolyline != null) {
        alternatives = [savedFromPolyline];
        preSelectedIndex = 0;
        preSelected = true;
      } else {
        alternatives = apiAlternatives;
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

      if (alternatives.length > 1) {
        _startJourneyNumberPrefetch();
      }

      if (mounted) {
        if (preSelected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                alternatives.length > 1
                    ? 'Garis rute mengikuti jalan (dari peta). Tap garis lain untuk alternatif, lalu Mulai Rute ini.'
                    : 'Rute sudah dipilih. Tap Mulai Rute ini untuk mulai bekerja.',
              ),
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
    } finally {
      _pendingJadwalSafetyTimer?.cancel();
      _pendingJadwalSafetyTimer = null;
      // Jangan biarkan flag ini true setelah async selesai / widget tidak mounted
      // (kasus: driver pindah tab saat geocode — `if (!mounted) return` tanpa clear → Siap Kerja terasa mati).
      if (loadGen != _loadRouteFromJadwalGen) return;
      if (_pendingJadwalRouteLoad) {
        if (mounted) {
          setState(() => _pendingJadwalRouteLoad = false);
        } else {
          _pendingJadwalRouteLoad = false;
        }
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
      _resetJourneyNumberPrefetch();
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
        _routeJourneyNumber = null;
      });
      _startJourneyNumberPrefetch();

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
  }) {
    if (!_canStartDriverWork) {
      _showDriverVerificationGateDialog();
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
    final routeScopeSubtitle = switch (routeType) {
      RouteType.dalamProvinsi => (_currentProvinsi ?? '').isNotEmpty
          ? 'Saran tujuan hanya di provinsi $_currentProvinsi. '
                'Hasil di luar provinsi disembunyikan.'
          : 'Provinsi lokasi belum terdeteksi; saran tujuan mungkin kurang tepat.',
      RouteType.antarProvinsi =>
        'Saran tujuan di provinsi lain di pulau yang sama dengan lokasi Anda '
            '(bukan provinsi yang sama). Hasil di pulau lain disembunyikan.',
      RouteType.dalamNegara =>
        'Tujuan bisa di seluruh Indonesia (lintas pulau).',
    };
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
        formDestPreviewNotifier: _formDestPreviewNotifier,
        routeScopeSubtitle: routeScopeSubtitle,
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
                _resetJourneyNumberPrefetch();
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
                  _routeJourneyNumber = null;
                });
                _startJourneyNumberPrefetch();

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
    if (_mapController == null || _alternativeRoutes.isEmpty || !mounted) {
      return;
    }
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
    unawaited(_onMapCreatedTraced(controller));
  }

  Future<void> _onMapCreatedTraced(GoogleMapController controller) async {
    await PerformanceTraceService.startDriverMapReadyTrace();
    if (!mounted) {
      await PerformanceTraceService.stopDriverMapReadyTrace();
      return;
    }
    _mapController = controller;
    _cameraFollowEngine.attach(controller);
    void scheduleStopTrace() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(PerformanceTraceService.stopDriverMapReadyTrace());
      });
    }

    // Jangan zoom otomatis sebelum driver klik "Mulai Rute ini"
    if (_alternativeRoutes.isNotEmpty && !_isDriverWorking) {
      scheduleStopTrace();
      return;
    }
    if (_pendingJadwalRouteLoad) {
      scheduleStopTrace();
      return;
    }
    // Zoom ke driver hanya jika tidak ada rute atau sudah mulai bekerja
    if (_currentPosition != null && mounted) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          MapStyleService.defaultZoom,
        ),
      );
    }
    scheduleStopTrace();
  }

  /// Rotasi marker beranda (non-aktif): heading GPS jika ada, else bearing yang sudah di-smooth.
  double _bearingForHomeBrowsingMarker() {
    final p = _currentPosition;
    if (p != null && p.heading.isFinite) {
      final h = p.heading;
      if (h >= 0 && h < 360) return h;
    }
    return _smoothedBearing;
  }

  /// Panah biru [MarkerAssets.movingBasic] untuk “sedang jalan” di beranda tanpa mode aktif.
  Future<void> _loadHomeBrowsingArrowOnce() async {
    if (_homeBrowsingArrowIcon != null) return;
    if (!mounted) return;
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final canvasPx = (96 * dpr).round().clamp(96, 160);
      _homeBrowsingArrowIcon =
          await DriverCarMarkerService.createArrowAssetWithShadow(
        assetPath: MarkerAssets.movingBasic,
        canvasSize: canvasPx.toDouble(),
      );
      if (mounted) setState(() {});
    } catch (_) {
      // Tetap pakai titik biru.
    }
  }

  /// Load titik biru untuk marker posisi driver saat !chaseCamActive.
  Future<void> _loadBlueDotOnce() async {
    if (_blueDotIcon != null) return;
    if (!mounted) return;
    try {
      final sizePx = context.responsive.iconSize(34).round().clamp(28, 40);
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
    if (_driverCarMarkerLoadingKeys.contains(cacheKey)) return;
    if (!mounted) return;
    _driverCarMarkerLoadingKeys.add(cacheKey);
    try {
      BitmapDescriptor icon;
      try {
        icon = await DriverCarMarkerService.createDriverCarMarker(
          isMoving: isMoving,
          streetName: streetName,
          speedKmh: speedKmh,
        ).timeout(_driverCarMarkerBuildTimeout);
      } catch (_) {
        final fallback = isMoving ? _carIconGreen : _carIconRed;
        icon = fallback ??
            BitmapDescriptor.defaultMarkerWithHue(
              isMoving ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
            );
      }
      if (!mounted) return;
      if (_driverCarMarkerCache.length >= _maxDriverCarMarkerCache) {
        final first = _driverCarMarkerCache.keys.first;
        _driverCarMarkerCache.remove(first);
      }
      _driverCarMarkerCache[cacheKey] = icon;
      setState(() {});
    } finally {
      _driverCarMarkerLoadingKeys.remove(cacheKey);
    }
  }

  /// Titik biru beranda (bukan panah, bukan marker Grab saat kerja).
  bool _shouldShowLocationPulse() {
    if (_currentPosition == null) return false;
    final chaseCamActive =
        _isDriverWorking || _navigatingToOrderId != null;
    if (chaseCamActive) return false;
    final speedKmh = _currentSpeedMps * 3.6;
    final showHeading = speedKmh >= _homeBrowsingHeadingMinKmh;
    if (showHeading && _homeBrowsingArrowIcon != null) return false;
    return true;
  }

  void _onLocationPulseTick() {
    if (!mounted) return;
    if (!_mapTabVisible || !_shouldShowLocationPulse()) {
      if (_locationPulseBucket != -1) {
        _locationPulseBucket = -1;
        setState(() {});
      }
      return;
    }
    final bucket =
        (_locationPulseController.value * 18).floor().clamp(0, 17);
    if (bucket == _locationPulseBucket) return;
    _locationPulseBucket = bucket;
    setState(() {});
  }

  /// Lingkaran halus membesar-mengecil seperti "akurasi" di Google Maps.
  Set<Circle> _buildLocationPulseCircles() {
    if (!_mapTabVisible || !_shouldShowLocationPulse()) {
      return {};
    }
    final displayLatLng =
        _displayedPosition ??
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final t = _locationPulseController.value;
    final pulse = math.sin(t * math.pi * 2) * 0.5 + 0.5;
    final radiusM = 12.0 + pulse * 32.0;
    final strokeA = (70 + pulse * 160).round().clamp(0, 255);
    final fillA = (10 + pulse * 36).round().clamp(0, 255);
    return {
      Circle(
        circleId: const CircleId('driver_blue_dot_pulse'),
        center: displayLatLng,
        radius: radiusM,
        fillColor: Color.fromARGB(fillA, 66, 133, 244),
        strokeColor: Color.fromARGB(strokeA, 255, 255, 255),
        strokeWidth: 2,
        zIndex: 0,
      ),
    };
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
        final cacheKey =
            '${_currentStreetName}__${isMoving}__${tier}__v${DriverCarMarkerService.layoutVersion}';
        final grabIcon = _driverCarMarkerCache[cacheKey];
        if (grabIcon == null) {
          // Jangan tampilkan placeholder mobil → hindari kedip mobil lalu dot/arrow Grab.
          unawaited(
            _loadDriverCarMarkerAsync(
              cacheKey,
              _currentStreetName,
              isMoving,
              speedKmh,
            ),
          );
        } else {
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: displayLatLng,
            icon: grabIcon,
            rotation: _smoothedBearing,
            flat: true,
            anchor: const Offset(0.5, 0.33),
            zIndex: 4,
          ),
        );
        }
      } else {
        // Beranda non-aktif: titik biru saat pelan; panah biru + arah saat sedang bergerak (bukan cone).
        final speedKmh = _currentSpeedMps * 3.6;
        final showHeading = speedKmh >= _homeBrowsingHeadingMinKmh;
        final arrow = _homeBrowsingArrowIcon;
        final useArrow = showHeading && arrow != null;
        final icon = useArrow
            ? arrow
            : (_blueDotIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure));
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: displayLatLng,
            icon: icon,
            rotation: useArrow ? _bearingForHomeBrowsingMarker() : 0.0,
            flat: useArrow,
            // Selaraskan dengan marker cone/arrow mode aktif: ujung panah ~posisi GPS.
            anchor: Offset(0.5, useArrow ? 0.33 : 0.5),
            zIndex: 4,
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
    // Warna: jemput travel kuning (beranda) / biru saat rute aktif; barang biru; pengantaran ungu; navigasi = hijau.
    // Urutan nomor = terdekat dari driver. Tap → sheet daftar + fokus peta / arahkan.
    final visiblePickups = _ordersForMapPickupsSorted();
    final visibleDropoffs = _ordersForMapDropoffsSorted();
    final visibleOrders = [...visiblePickups, ...visibleDropoffs];
    final visiblePassengerOrderIds = visibleOrders.map((o) => o.id).toSet();

    if (_routeDestLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _routeDestLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: 'Tujuan rute',
            snippet: _isDriverWorking && visibleDropoffs.isEmpty
                ? 'Ketuk pin untuk info pengantaran'
                : null,
          ),
          onTap: _isDriverWorking && visibleDropoffs.isEmpty
              ? () {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Belum ada titik pengantaran aktif. Setelah penjemputan, '
                        'marker pengantaran akan muncul sesuai lokasi tujuan pemesan atau penerima barang.',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              : null,
        ),
      );
    }

    // Marker penjemputan / pengantaran
    int pickupIndex = 0;
    for (final order in visiblePickups) {
      pickupIndex++;
      final pos = LatLng(
        order.passengerLiveLat ?? order.passengerLat ?? order.originLat!,
        order.passengerLiveLng ?? order.passengerLng ?? order.originLng!,
      );
      final isNavigatingTo = order.id == _navigatingToOrderId && !_navigatingToDestination;
      // Saat rute aktif: tanpa pin kuning (hindari tabrakan visual dengan garis/jalur); biru = jemput travel.
      final defaultIcon = order.isKirimBarang
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
          : BitmapDescriptor.defaultMarkerWithHue(
              _isDriverWorking
                  ? BitmapDescriptor.hueAzure
                  : BitmapDescriptor.hueYellow,
            );
      final icon = isNavigatingTo
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : (_passengerMarkerIcons[order.id] ?? defaultIcon);
      final pickupOrder = visiblePickups.length > 1 ? pickupIndex : null;
      final snippet = order.isKirimBarang ? 'Kirim barang • Jemput' : 'Penjemputan';
      double? distM;
      if (_currentPosition != null) {
        distM = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      final distPart = distM == null
          ? ''
          : (distM < 1000
              ? '${distM.round()} m'
              : '${(distM / 1000).toStringAsFixed(1)} km');
      final snippetWithOrder = [
        if (pickupOrder != null) 'Ke-$pickupOrder',
        if (distPart.isNotEmpty) distPart,
        snippet,
      ].join(' · ');
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
          onTap: () {
            unawaited(_showPickupStopsOnMapSheet());
          },
        ),
      );
    }
    for (final order in visibleDropoffs) {
      final (lat, lng) = _getOrderDestinationLatLng(order);
      if (lat == null || lng == null) continue;
      final pos = LatLng(lat, lng);
      final isNavigatingTo = order.id == _navigatingToOrderId && _navigatingToDestination;
      final defaultIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      final icon = isNavigatingTo
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
          : (_passengerMarkerIcons['${order.id}_drop'] ?? defaultIcon);
      final label = order.isKirimBarang ? 'Pengantaran barang' : 'Pengantaran';
      double? distDropM;
      if (_currentPosition != null) {
        distDropM = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      final distDropPart = distDropM == null
          ? ''
          : (distDropM < 1000
              ? '${distDropM.round()} m'
              : '${(distDropM / 1000).toStringAsFixed(1)} km');
      final snippetDrop = [if (distDropPart.isNotEmpty) distDropPart, label]
          .join(' · ');
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
            snippet: snippetDrop,
          ),
          onTap: () {
            unawaited(_showDropoffStopsOnMapSheet());
          },
        ),
      );
    }
    // Hapus cache icon untuk order yang tidak lagi ditampilkan (key = id atau id_drop).
    _passengerMarkerIcons.removeWhere((id, _) {
      final base =
          id.endsWith('_drop') ? id.substring(0, id.length - 5) : id;
      return !visiblePassengerOrderIds.contains(base);
    });
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

  /// Sama filter pin [_buildMarkers] — urut **terdekat dari posisi driver** (bukan sepanjang polyline utama).
  List<OrderModel> _ordersForMapPickupsSorted() {
    final chaseCamActive = _isDriverWorking || _navigatingToOrderId != null;
    final hasRoute = _routeOriginLatLng != null && _routeDestLatLng != null;
    final todayYmd = _todayYmd();
    final list = <OrderModel>[];
    if (chaseCamActive || hasRoute) {
      for (final order in _driverOrders) {
        if (order.status == OrderService.statusCompleted) continue;
        if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
        if (order.orderType != OrderModel.typeTravel &&
            order.orderType != OrderModel.typeKirimBarang) {
          continue;
        }
        if (order.status == OrderService.statusAgreed &&
            !order.hasDriverScannedPassenger) {
          final lat = order.passengerLat ?? order.originLat;
          final lng = order.passengerLng ?? order.originLng;
          if (lat != null && lng != null) list.add(order);
        }
      }
    }
    if (list.length <= 1 || _currentPosition == null) return list;
    final dLat = _currentPosition!.latitude;
    final dLng = _currentPosition!.longitude;
    final scored = list.map((o) {
      final lat = o.passengerLiveLat ?? o.passengerLat ?? o.originLat!;
      final lng = o.passengerLiveLng ?? o.passengerLng ?? o.originLng!;
      final d = Geolocator.distanceBetween(dLat, dLng, lat, lng);
      return (order: o, d: d);
    }).toList();
    scored.sort((a, b) => a.d.compareTo(b.d));
    return scored.map((e) => e.order).toList();
  }

  List<OrderModel> _ordersForMapDropoffsSorted() {
    final chaseCamActive = _isDriverWorking || _navigatingToOrderId != null;
    final hasRoute = _routeOriginLatLng != null && _routeDestLatLng != null;
    final todayYmd = _todayYmd();
    final list = <OrderModel>[];
    if (chaseCamActive || hasRoute) {
      for (final order in _driverOrders) {
        if (order.status == OrderService.statusCompleted) continue;
        if (!_isOrderForCurrentRoute(order, todayYmd)) continue;
        if (order.orderType != OrderModel.typeTravel &&
            order.orderType != OrderModel.typeKirimBarang) {
          continue;
        }
        if (order.status == OrderService.statusPickedUp) {
          final (lat, lng) = _getOrderDestinationLatLng(order);
          if (lat != null && lng != null) list.add(order);
        }
      }
    }
    if (list.length <= 1 || _currentPosition == null) return list;
    final dLat = _currentPosition!.latitude;
    final dLng = _currentPosition!.longitude;
    final scored = <({OrderModel order, double d})>[];
    for (final o in list) {
      final (lat, lng) = _getOrderDestinationLatLng(o);
      if (lat == null || lng == null) continue;
      final d = Geolocator.distanceBetween(dLat, dLng, lat, lng);
      scored.add((order: o, d: d));
    }
    scored.sort((a, b) => a.d.compareTo(b.d));
    return scored.map((e) => e.order).toList();
  }

  void _focusCameraOnLatLng(LatLng target, {double zoom = 15}) {
    if (_mapController == null || !mounted) return;
    try {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } catch (_) {}
  }

  Future<void> _startNavigateToPickupFromSheet(OrderModel order) async {
    final lat = order.passengerLat ?? order.originLat;
    final lng = order.passengerLng ?? order.originLng;
    if (lat == null || lng == null) return;
    await OrderService.setDriverNavigatingToPickup(order.id);
    if (!mounted) return;
    setState(() {
      _navigatingToOrderId = order.id;
      _navigatingToDestination = false;
      _lastPassengerLat = lat;
      _lastPassengerLng = lng;
    });
    _loadPassengerMarkerIconsIfNeeded();
    await _fetchAndShowRouteToPassenger(order);
  }

  Future<void> _startNavigateToDropoffFromSheet(OrderModel order) async {
    if (!mounted) return;
    final (lat, lng) = _getOrderDestinationLatLng(order);
    if (lat == null || lng == null) return;
    setState(() {
      _navigatingToOrderId = order.id;
      _navigatingToDestination = true;
      _lastDestinationLat = lat;
      _lastDestinationLng = lng;
    });
    await _fetchAndShowRouteToDestination(order);
  }

  Future<void> _showPickupStopsOnMapSheet() async {
    final orders = _ordersForMapPickupsSorted();
    if (orders.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.person_pin_circle,
                        color: const Color(0xFF00B14F), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Penjemputan (terdekat di atas)',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Ketuk peta untuk fokus lokasi, atau Arahkan untuk navigasi.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.42,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    final lat = order.passengerLiveLat ??
                        order.passengerLat ??
                        order.originLat;
                    final lng = order.passengerLiveLng ??
                        order.passengerLng ??
                        order.originLng;
                    double? distM;
                    if (_currentPosition != null &&
                        lat != null &&
                        lng != null) {
                      distM = Geolocator.distanceBetween(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        lat,
                        lng,
                      );
                    }
                    final distLabel = distM == null
                        ? ''
                        : (distM < 1000
                            ? '${distM.round()} m dari Anda'
                            : '${(distM / 1000).toStringAsFixed(1)} km dari Anda');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: order.isKirimBarang
                            ? Colors.blue.shade100
                            : Colors.amber.shade100,
                        child: Icon(
                          order.isKirimBarang
                              ? Icons.local_shipping
                              : Icons.person,
                          color: order.isKirimBarang
                              ? Colors.blue.shade800
                              : Colors.amber.shade900,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        order.passengerName.isEmpty
                            ? (order.isKirimBarang ? 'Kirim barang' : 'Penumpang')
                            : order.passengerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (orders.length > 1) 'Urutan ${i + 1}',
                          if (distLabel.isNotEmpty) distLabel,
                          if (order.isKirimBarang) 'Kirim barang',
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'Lihat di peta',
                            icon: const Icon(Icons.map_outlined),
                            onPressed: lat != null && lng != null
                                ? () {
                                    Navigator.of(ctx).pop();
                                    _focusCameraOnLatLng(LatLng(lat, lng));
                                  }
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Arahkan',
                            icon: const Icon(Icons.navigation),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              unawaited(_startNavigateToPickupFromSheet(order));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDropoffStopsOnMapSheet() async {
    final orders = _ordersForMapDropoffsSorted();
    if (orders.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.flag, color: const Color(0xFFE65100), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pengantaran (terdekat di atas)',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Ketuk peta untuk fokus lokasi, atau Arahkan untuk navigasi.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.42,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    final (lat, lng) = _getOrderDestinationLatLng(order);
                    double? distM;
                    if (_currentPosition != null &&
                        lat != null &&
                        lng != null) {
                      distM = Geolocator.distanceBetween(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        lat,
                        lng,
                      );
                    }
                    final distLabel = distM == null
                        ? ''
                        : (distM < 1000
                            ? '${distM.round()} m dari Anda'
                            : '${(distM / 1000).toStringAsFixed(1)} km dari Anda');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepOrange.shade100,
                        child: Icon(
                          Icons.flag,
                          color: Colors.deepOrange.shade900,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        order.destText.isNotEmpty
                            ? order.destText
                            : (order.isKirimBarang
                                ? 'Lokasi penerima'
                                : order.passengerName),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (orders.length > 1) 'Urutan ${i + 1}',
                          if (distLabel.isNotEmpty) distLabel,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'Lihat di peta',
                            icon: const Icon(Icons.map_outlined),
                            onPressed: lat != null && lng != null
                                ? () {
                                    Navigator.of(ctx).pop();
                                    _focusCameraOnLatLng(LatLng(lat, lng));
                                  }
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Arahkan',
                            icon: const Icon(Icons.navigation),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              unawaited(_startNavigateToDropoffFromSheet(order));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          order.orderType != OrderModel.typeKirimBarang) {
        continue;
      }
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
          order.hasDriverScannedPassenger) {
        continue;
      }
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
      if (!o.isScheduledOrder || (o.scheduledDate ?? '') != todayYmd) {
        return false;
      }
      if (o.status != OrderService.statusAgreed &&
          o.status != OrderService.statusPickedUp) {
        return false;
      }
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

  /// Tombol kuning di samping zoom: fokus / mulai navigasi penjemputan (urutan stop optimal).
  Future<void> _onPickupStopShortcutTap() async {
    unawaited(VoiceNavigationService.instance.init());
    if (!_isDriverWorking || !mounted) return;
    final pickups = _waitingPassengerOrders;
    if (pickups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada penjemputan dalam rute ini'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_navigatingToOrderId != null && !_navigatingToDestination) {
      _cameraFollowEngine.resetThrottle();
      setState(() => _cameraTrackingEnabled = true);
      _fitRouteToPassengerBounds();
      return;
    }
    OrderModel? order;
    for (final s in _optimizedStops) {
      if (s.isPickup) {
        order = s.order;
        break;
      }
    }
    order ??= pickups.first;
    await OrderService.setDriverNavigatingToPickup(order.id);
    if (!mounted) return;
    final lat = order.passengerLat ?? order.originLat;
    final lng = order.passengerLng ?? order.originLng;
    setState(() {
      _navigatingToOrderId = order!.id;
      _navigatingToDestination = false;
      _lastPassengerLat = lat;
      _lastPassengerLng = lng;
    });
    _loadPassengerMarkerIconsIfNeeded();
    await _fetchAndShowRouteToPassenger(order);
  }

  /// Tombol hijau di samping zoom: fokus / mulai navigasi pengantaran.
  Future<void> _onDropoffStopShortcutTap() async {
    unawaited(VoiceNavigationService.instance.init());
    if (!_isDriverWorking || !mounted) return;
    final dropoffs = _pickedUpOrdersForDestination;
    if (dropoffs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada pengantaran dalam rute ini'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_navigatingToOrderId != null && _navigatingToDestination) {
      _cameraFollowEngine.resetThrottle();
      setState(() => _cameraTrackingEnabled = true);
      _fitRouteToDestinationBounds();
      return;
    }
    OrderModel? order;
    for (final s in _optimizedStops) {
      if (!s.isPickup) {
        order = s.order;
        break;
      }
    }
    order ??= dropoffs.first;
    if (!mounted) return;
    setState(() {
      _navigatingToOrderId = order!.id;
      _navigatingToDestination = true;
      final (lat, lng) = _getOrderDestinationLatLng(order);
      _lastDestinationLat = lat;
      _lastDestinationLng = lng;
    });
    _fetchAndShowRouteToDestination(order);
  }

  /// Instruksi yang mengandung manuver belok / putar (bukan sekadar lurus).
  bool _stepLooksLikeTurn(RouteStep s) {
    final t = s.instruction.toLowerCase();
    final compact = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact == 'lanjutkan' || compact.startsWith('lanjutkan ')) {
      return false;
    }
    return t.contains('belok') ||
        t.contains('tikung') ||
        t.contains(' putar') ||
        t.contains('putar ') ||
        t.contains('u-turn') ||
        t.contains('bundar') ||
        t.contains('roundabout') ||
        t.contains('ramp') ||
        t.contains('merge') ||
        t.contains('ambil jalan') ||
        t.contains('take the') ||
        t.contains('exit') ||
        t.contains('keluar') ||
        t.contains('slight left') ||
        t.contains('slight right') ||
        t.contains('sharp') ||
        (t.contains('kiri') && (t.contains('belok') || t.contains('ke'))) ||
        (t.contains('kanan') && (t.contains('belok') || t.contains('ke'))) ||
        t.contains(' turn left') ||
        t.contains(' turn right') ||
        t.contains('turn left') ||
        t.contains('turn right');
  }

  /// Ambil langkah turn-by-turn untuk rute utama (bukan navigasi order) sekali per sesi.
  Future<void> _hydrateMainRouteSteps() async {
    if (!mounted) return;
    if (_navigatingToOrderId != null) return;
    if (_currentPosition == null || _routeDestLatLng == null) return;
    _routeStepsHydrateRequested = true;
    _pushRouteRecalculate();
    try {
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
        trafficAware: _trafficEnabled,
      );
      if (!mounted) return;
      final withSteps = outcome.data;
      if (withSteps == null) return;
      _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: false);
      setState(() {
        // Polyline + steps harus dari respons yang sama (jarak kumulatif step konsisten).
        _routePolyline = withSteps.result.points;
        _routeDistanceText = withSteps.result.distanceText;
        _routeDurationText = withSteps.result.durationText;
        _routeEstimatedDurationSeconds = withSteps.result.durationSeconds;
        _routeSteps = withSteps.steps;
        _currentStepIndex = withSteps.steps.isNotEmpty ? 0 : -1;
      });
      var spokeFromStepChange = false;
      if (_currentPosition != null) {
        spokeFromStepChange = _updateCurrentStepFromPosition(_currentPosition!);
      }
      if (!spokeFromStepChange &&
          mounted &&
          _routeSteps.isNotEmpty &&
          _currentStepIndex >= 0) {
        _speakCurrentStep();
      }
    } catch (_) {
    } finally {
      _popRouteRecalculate();
    }
  }

  /// Belokan terlewat: sudah melewati titik manuver tapi GPS jauh dari polyline → rute baru (paksa).
  /// Mengembalikan true jika reroute dijadwalkan (supaya tidak double dengan auto simpang saat tick sama).
  bool _checkMissedTurnAndScheduleReroute(
    LatLng raw,
    List<LatLng> poly,
    double routeDeviationMeters,
  ) {
    if (_routeSteps.isEmpty || poly.length < 2) return false;
    if (routeDeviationMeters < _missedTurnMinDeviationMeters) return false;
    if (_lastMissedTurnRerouteAt != null) {
      final sec = DateTime.now().difference(_lastMissedTurnRerouteAt!).inSeconds;
      if (sec < _missedTurnRerouteCooldownSeconds) return false;
    }

    final (_, seg, ratio) = RouteUtils.projectPointOntoPolyline(
      raw,
      poly,
      maxDistanceMeters: 140,
    );
    if (seg < 0) return false;
    final distM = RouteUtils.distanceAlongPolyline(poly, seg, ratio);

    for (var i = 0; i < _routeSteps.length; i++) {
      final step = _routeSteps[i];
      if (!_stepLooksLikeTurn(step)) continue;
      final end = step.endDistanceMeters;
      if (distM <= end + _missedTurnPastMeters) continue;
      if (distM >= end + _missedTurnPastMeters + _missedTurnWindowMeters) {
        continue;
      }

      _lastMissedTurnRerouteAt = DateTime.now();

      if (_navigatingToOrderId != null) {
        OrderModel? navOrder;
        for (final o in _driverOrders) {
          if (o.id == _navigatingToOrderId) {
            navOrder = o;
            break;
          }
        }
        if (navOrder != null) {
          if (_navigatingToDestination) {
            unawaited(
              _fetchAndShowRouteToDestination(navOrder, quiet: true),
            );
          } else {
            unawaited(
              _fetchAndShowRouteToPassenger(navOrder, quiet: true),
            );
          }
        }
      } else if (_routeDestLatLng != null) {
        unawaited(_maybeRerouteFromCurrentPosition(raw, force: true, quiet: true));
      }
      return true;
    }
    return false;
  }

  /// Re-routing saat keluar rute: garis biru ke jalan lain untuk kembali.
  /// [force] — dari tombol "Perbarui rute dari sini": lewati debounce waktu/jarak.
  /// [quiet] — pembaruan otomatis: tanpa SnackBar (mengemudi).
  /// Mengembalikan `true` jika polyline berhasil diperbarui.
  Future<bool> _maybeRerouteFromCurrentPosition(
    LatLng currentPos, {
    bool force = false,
    bool quiet = false,
  }) async {
    if (_routeDestLatLng == null) return false;
    final now = DateTime.now();
    if (!force) {
      if (_lastRerouteAt != null) {
        final secSince = now.difference(_lastRerouteAt!).inSeconds;
        if (secSince < _rerouteDebounceSeconds) return false;
      }
      if (_lastReroutePosition != null) {
        final dist = Geolocator.distanceBetween(
          _lastReroutePosition!.latitude,
          _lastReroutePosition!.longitude,
          currentPos.latitude,
          currentPos.longitude,
        );
        if (dist < _rerouteDebounceDistanceMeters) return false;
      }
    }

    _pushRouteRecalculate();
    try {
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: currentPos.latitude,
        originLng: currentPos.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
        trafficAware: _trafficEnabled,
      );
      if (!mounted) return false;
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
        setState(() {
          _routePolyline = withSteps.result.points;
          _routeDistanceText = withSteps.result.distanceText;
          _routeDurationText = withSteps.result.durationText;
          _routeEstimatedDurationSeconds = withSteps.result.durationSeconds;
          _routeSteps = withSteps.steps;
          _currentStepIndex = withSteps.steps.isNotEmpty ? 0 : -1;
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
        if (_currentPosition != null) {
          _updateCurrentStepFromPosition(_currentPosition!);
        }
        if (mounted && !quiet) {
          final l10n = TrakaL10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.routeUpdated),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      }
      return false;
    } finally {
      _popRouteRecalculate();
    }
  }

  Future<void> _onRefreshRouteFromHerePressed() async {
    if (_manualRerouteInProgress) return;
    if (_routeDestLatLng == null || _currentPosition == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).failedToGetLocation),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _manualRerouteInProgress = true);
    try {
      final pos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final ok = await _maybeRerouteFromCurrentPosition(pos, force: true, quiet: false);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).failedToLoadRoute),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _manualRerouteInProgress = false);
    }
  }

  /// Ambil rute driver → penumpang dan tampilkan di peta. Dipanggil saat "Ya, arahkan", saat lokasi penumpang berubah, dan saat driver bergerak 2.5 km.
  /// [quiet]: recalculate otomatis (simpang jalan) — tanpa SnackBar / suara ulang.
  Future<void> _fetchAndShowRouteToPassenger(
    OrderModel order, {
    bool quiet = false,
  }) async {
    final destLat = order.passengerLiveLat ?? order.passengerLat ?? order.originLat;
    final destLng = order.passengerLiveLng ?? order.passengerLng ?? order.originLng;
    if (destLat == null || destLng == null) return;
    if (_currentPosition == null) return;
    _pushRouteRecalculate();
    try {
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _trafficEnabled,
      );
      if (!mounted) return;
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
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
          if (!_updateCurrentStepFromPosition(_currentPosition!)) {
            if (!quiet) _speakCurrentStep();
          }
        } else {
          if (!quiet) _speakCurrentStep();
        }
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
        if (!quiet) {
          unawaited(
            VoiceNavigationService.instance.speakSummary(
              'Menuju titik penjemputan. Ikuti garis hijau di peta.',
            ),
          );
        }
      }
    } finally {
      _popRouteRecalculate();
    }
  }

  /// Ambil rute driver → tujuan (destLat/destLng atau receiver) dan tampilkan di peta. Untuk pengantaran.
  /// [quiet]: recalculate otomatis — tanpa SnackBar / suara ulang.
  Future<void> _fetchAndShowRouteToDestination(
    OrderModel order, {
    bool quiet = false,
  }) async {
    final (destLat, destLng) = _getOrderDestinationLatLng(order);
    if (destLat == null || destLng == null) return;
    if (_currentPosition == null) return;
    _pushRouteRecalculate();
    try {
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _trafficEnabled,
      );
      if (!mounted) return;
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
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
          if (!_updateCurrentStepFromPosition(_currentPosition!)) {
            if (!quiet) _speakCurrentStep();
          }
        } else {
          if (!quiet) _speakCurrentStep();
        }
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
        if (!quiet) {
          unawaited(
            VoiceNavigationService.instance.speakSummary(
              'Menuju titik pengantaran. Ikuti garis oranye di peta.',
            ),
          );
        }
      }
    } finally {
      _popRouteRecalculate();
    }
  }

  void _fitRouteToDestinationBounds() {
    if (_mapController == null ||
        _polylineToDestination == null ||
        _polylineToDestination!.isEmpty ||
        !mounted) {
      return;
    }
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
          VoiceNavigationService.instance.speakWithLead(
            '${distMeters.round()} meter',
            _navigatingToDestination
                ? 'Hampir sampai di lokasi tujuan'
                : 'Hampir sampai di lokasi penumpang',
          );
        }
      }
    }
  }

  void _fitRouteToPassengerBounds() {
    if (_mapController == null ||
        _polylineToPassenger == null ||
        _polylineToPassenger!.isEmpty ||
        !mounted) {
      return;
    }
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
      _lastContextualZoomStepIndex = -999;
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

    ScaffoldMessenger.of(context).clearSnackBars();

    final origin = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final destination = LatLng(destLat, destLng);

    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.88,
          child: _AlternativeRoutesPickerSheet(
            alternatives: alternatives,
            origin: origin,
            destination: destination,
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
    _lastContextualZoomStepIndex = -999;
    if (_navigatingToDestination) {
      _fitRouteToDestinationBounds();
    } else {
      _fitRouteToPassengerBounds();
    }
    if (!_updateCurrentStepFromPosition(_currentPosition!)) {
      _speakCurrentStep();
    }
  }

  /// Update step aktif saat turn-by-turn dari posisi driver di polyline.
  /// Mengembalikan `true` jika indeks step berubah (TTS + haptik sudah dipicu).
  bool _updateCurrentStepFromPosition(Position position) {
    final poly = _activeNavigationPolyline ??
        ((_routePolyline != null && _routePolyline!.length >= 2)
            ? _routePolyline
            : null);
    final steps = _routeSteps;
    if (poly == null || poly.isEmpty || steps.isEmpty) return false;
    final pos = LatLng(position.latitude, position.longitude);
    final (_, segmentIndex, ratio) = RouteUtils.projectPointOntoPolyline(
      pos,
      poly,
      maxDistanceMeters: 250,
    );
    if (segmentIndex < 0) return false;
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
      _bumpZoomForTurnStepIfNeeded(stepIdx);
      _speakCurrentStep();
      HapticFeedback.mediumImpact();
      return true;
    }
    return false;
  }

  /// Bicara instruksi turn-by-turn saat step berubah (jika suara tidak dimatikan).
  void _speakCurrentStep() {
    if (_routeSteps.isEmpty ||
        _currentStepIndex < 0 ||
        _currentStepIndex >= _routeSteps.length) {
      return;
    }
    final step = _routeSteps[_currentStepIndex];
    final formatted = InstructionFormatter.formatStep(step);
    VoiceNavigationService.instance.speakCue(formatted);
  }

  /// Kembalikan tampilan map ke rute utama (setelah penumpang dijemput atau driver klik Kembali).
  void _fitMapToMainRoute() {
    if (_mapController == null || !mounted) return;
    List<LatLng>? main = _routePolyline;
    if ((main == null || main.length < 2) &&
        _alternativeRoutes.isNotEmpty &&
        _selectedRouteIndex >= 0 &&
        _selectedRouteIndex < _alternativeRoutes.length) {
      main = _alternativeRoutes[_selectedRouteIndex].points;
    }
    if (main != null && main.length >= 2) {
      var minLat = main.first.latitude;
      var maxLat = minLat;
      var minLng = main.first.longitude;
      var maxLng = minLng;
      for (final p in main) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      if (_currentPosition != null) {
        final clat = _currentPosition!.latitude;
        final clng = _currentPosition!.longitude;
        if (clat < minLat) minLat = clat;
        if (clat > maxLat) maxLat = clat;
        if (clng < minLng) minLng = clng;
        if (clng > maxLng) maxLng = clng;
      }
      try {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            72,
          ),
        );
      } catch (_) {
        if (_currentPosition != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              MapStyleService.defaultZoom,
            ),
          );
        }
      }
      return;
    }
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
            consumeTapEvents: true,
            onTap: () {
              unawaited(_showAlternativeRoutesDuringNavigation());
            },
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

  /// Handle tap pada map untuk memilih rute alternatif.
  /// Gunakan posisi tap (bukan posisi driver) agar tap di garis kuning langsung memilih rute.
  /// Bisa memilih rute lain sebelum klik "Mulai", setelah "Mulai" tidak bisa lagi.
  void _onMapTap(LatLng position) {
    if (_alternativeRoutes.isEmpty || _isDriverWorking) {
      return; // Tidak bisa pilih jika sudah mulai bekerja
    }

    // Referensi: posisi tap agar driver bisa tap langsung di garis kuning untuk memilih
    final LatLng referencePoint = position;

    // Hitung jarak dari referencePoint ke setiap alternatif rute (semua segmen).
    double minDistance = double.infinity;
    int closestRouteIndex = -1;

    for (int i = 0; i < _alternativeRoutes.length; i++) {
      final route = _alternativeRoutes[i];
      // Jarak penuh ke setiap segmen agar tap di polyline rapat (mis. bandara) tidak meleset.
      final distance = RouteUtils.distanceToPolyline(referencePoint, route.points);
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

    // Sinkronkan nomor rute di background — jangan await agar tap pilih rute langsung responsif.
    if (journeyNumber == null && mounted) {
      unawaited(_awaitJourneyNumberAfterSelectWithSnacks());
    }

    if (_currentPosition != null && _currentPosition!.heading.isFinite) {
      _displayedBearing = _currentPosition!.heading;
      _smoothedBearing = _displayedBearing;
    }
    unawaited(_loadCarIconsOnce());
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
              setState(() {
                _registerTabVisit(4);
                _currentIndex = 4; // Tab Saya (Profil)
              });
            },
            child: const Text('Lengkapi Sekarang'),
          ),
        ],
      ),
    );
  }

  void _showDriverAdminVerificationDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verifikasi dari admin'),
        content: Text(
          VerificationService.adminVerificationBlockingHintId,
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _registerTabVisit(4);
                _currentIndex = 4;
              });
            },
            child: const Text('Ke Profil'),
          ),
        ],
      ),
    );
  }

  void _showDriverVerificationGateDialog() {
    if (!_driverProfileComplete) {
      _showDriverLengkapiVerifikasiDialog();
    } else {
      _showDriverAdminVerificationDialog();
    }
  }

  /// Padding isi peta: jalan & manuver tidak tertutup instruksi/kontrol (tahap 1, gaya Google Maps).
  EdgeInsets _driverMapContentPadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeTop = mq.padding.top;
    final safeBottom = mq.padding.bottom;
    final landscape = mq.orientation == Orientation.landscape;

    double top = safeTop + 10;
    if (_navigatingToOrderId != null && _routeSteps.isNotEmpty) {
      top = safeTop + (landscape ? 120 : 172);
    } else if (_navigatingToOrderId == null &&
        _nextTargetForNavigation != null) {
      top = safeTop + (landscape ? 60 : 92);
    } else if (_routeRecalculateDepth > 0) {
      top = safeTop + 52;
    }

    const double rightRail = 72;
    double bottom = safeBottom + 20;
    if (_navigatingToOrderId != null) {
      bottom = safeBottom + (landscape ? 132 : 184);
    }
    if (_fasterAlternativeMinutesSaved != null &&
        _fasterAlternativeMinutesSaved! >= 2) {
      final altBottom = safeBottom + 268;
      if (altBottom > bottom) bottom = altBottom;
    }

    double left = 8;
    final muteBottomLeft = (_isDriverWorking || _navigatingToOrderId != null) &&
        !(_navigatingToOrderId != null && _routeSteps.isNotEmpty);
    if (muteBottomLeft) {
      left = 52;
    }

    return EdgeInsets.only(
      top: top,
      left: left,
      right: rightRail,
      bottom: bottom,
    );
  }

  void _bumpZoomForTurnStepIfNeeded(int stepIndex) {
    if (_navigatingToOrderId == null) return;
    if (!_cameraTrackingEnabled) return;
    if (_lastContextualZoomStepIndex == stepIndex) return;
    if (stepIndex < 0 || stepIndex >= _routeSteps.length) return;
    final s = _routeSteps[stepIndex];
    if (!_stepLooksLikeTurn(s)) return;
    _lastContextualZoomStepIndex = stepIndex;
    final c = _mapController;
    if (c == null || !mounted) return;
    try {
      c.animateCamera(CameraUpdate.zoomBy(0.38));
    } catch (_) {}
  }

  Widget _buildDriverMapScreen() {
    final l10nMap = TrakaL10n.of(context);
    return Stack(
      children: [
        RepaintBoundary(
          child: StyledGoogleMapBuilder(
            builder: (style, useDark) {
              // Mode gelap: pakai normal agar style gelap berlaku (style tidak berlaku di hybrid)
              final effectiveMapType = useDark ? MapType.normal : _mapType;
              return GoogleMap(
                padding: _driverMapContentPadding(context),
                buildingsEnabled: true,
                indoorViewEnabled: true,
                mapToolbarEnabled: false,
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: () {
                  if (_suppressNextCameraMoveStarted) {
                    _suppressNextCameraMoveStarted = false;
                    return;
                  }
                  if (_isDriverWorking || _navigatingToOrderId != null) {
                    setState(() {
                      _cameraTrackingEnabled = false;
                      _gpsWhenCameraManualDisabled = _currentPosition != null
                          ? LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            )
                          : _displayedPosition;
                    });
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
                circles: _buildLocationPulseCircles(),
                polylines: _buildPolylines(),
                // Saat overlay aktif, tap hanya lewat getLatLng (fisik px) agar tidak dobel.
                onTap: (_alternativeRoutes.isNotEmpty &&
                        !_isDriverWorking &&
                        _mapController != null)
                    ? null
                    : (LatLng position) {
                        if (_alternativeRoutes.isNotEmpty && !_isDriverWorking) {
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
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final latLng = await _mapController!.getLatLng(
                    ScreenCoordinate(
                      x: (details.localPosition.dx * dpr).round(),
                      y: (details.localPosition.dy * dpr).round(),
                    ),
                  );
                  if (mounted) _onMapTap(latLng);
                } catch (_) {}
              },
            ),
          ),
        const PromotionBannerWidget(role: 'driver'),
        if (_routeRecalculateDepth > 0)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: RepaintBoundary(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10nMap.routeRecalculating,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_routeRestoreAwaitingPolyline)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 96,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Memuat rute di peta…',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          onOpenJadwal: () => setState(() {
            _registerTabVisit(1);
            _currentIndex = 1;
          }),
          visible:
              _currentScheduleId == null && _scheduledAgreedCountForToday > 0,
        ),
        DriverWorkToggleButton(
          isDriverWorking: _isDriverWorking,
          routeSelected: _routeSelected,
          hasActiveOrder: _hasActiveOrder,
          onTap: _onDriverWorkPillTap,
        ),
        DriverStartRouteButton(
          visible: _routeSelected && !_isDriverWorking,
          isLoading: _isStartRouteLoading,
          onTap: _onStartButtonTap,
        ),
        ListenableBuilder(
          listenable: MapStyleService.themeNotifier,
          builder: (context, _) {
            final useDark = MapStyleService.themeNotifier.value == ThemeMode.dark;
            final effectiveMapType = useDark ? MapType.normal : _mapType;
            final mq = MediaQuery.of(context);
            final zoomTop = mq.orientation == Orientation.landscape
                ? mq.padding.top + 4
                : mq.padding.top + 44;
            final showStopsShortcuts = _isDriverWorking &&
                (_waitingPassengerCount > 0 ||
                    _pickedUpOrdersForDestination.isNotEmpty);
            return MapTypeZoomControls(
              mapType: effectiveMapType,
              topOffset: zoomTop,
              onToggleMapType: _toggleMapType,
              trafficEnabled: _trafficEnabled,
              onToggleTraffic: _toggleTraffic,
              onZoomIn: () {
                if (mounted) {
                  _mapController?.animateCamera(CameraUpdate.zoomIn());
                }
              },
              onZoomOut: () {
                if (mounted) {
                  _mapController?.animateCamera(CameraUpdate.zoomOut());
                }
              },
              onThemeToggle: () => ThemeService.toggle(),
              showPickupDropoffShortcuts: showStopsShortcuts,
              onPickupShortcutTap: showStopsShortcuts
                  ? () => unawaited(_onPickupStopShortcutTap())
                  : null,
              onDropoffShortcutTap: showStopsShortcuts
                  ? () => unawaited(_onDropoffStopShortcutTap())
                  : null,
              pickupShortcutEnabled: _waitingPassengerCount > 0,
              dropoffShortcutEnabled:
                  _pickedUpOrdersForDestination.isNotEmpty,
              showRouteInfoShortcut: _isDriverWorking &&
                  _routePolyline != null &&
                  _routePolyline!.isNotEmpty &&
                  _navigatingToOrderId == null,
              onRouteInfoTap: _showRouteInfoBottomSheet,
              routeInfoOperBadge: _jumlahPenumpangPickedUp > 0,
              routeInfoTooltip: l10nMap.routeInfo,
            );
          },
        ),
        // #6: Panel list penumpang (di bawah banner) — dulu di atas banner sehingga
        // area overlap menelan tap banner "Jemput: …".
        if ((_waitingPassengerCount > 0 || _pickedUpOrdersForDestination.isNotEmpty) &&
            _navigatingToOrderId == null)
          DriverStopsListOverlay(
            stackTop: MediaQuery.of(context).orientation == Orientation.landscape
                ? MediaQuery.of(context).padding.top + 200
                : 230,
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
        // Prioritas #4: Banner "Arahkan ke stop terdekat" — di atas panel stop agar tap konsisten.
        if (_navigatingToOrderId == null &&
            _nextTargetForNavigation != null) ...[
          _NextStopBanner(
            target: _nextTargetForNavigation!.$1!,
            isPickup: _nextTargetForNavigation!.$2,
            onTap: () => _navigateToNextTarget(),
          ),
        ],
        // Overlay "Menuju penumpang" (hijau) saat diarahkan ke penjemputan
        if (_navigatingToOrderId != null && !_navigatingToDestination)
          NavigatingToPassengerOverlay(
            routeToPassengerDistanceText: _routeToPassengerDistanceText,
            routeToPassengerDurationText: _routeToPassengerDurationText,
            routeToPassengerDistanceMeters: _routeToPassengerDistanceMeters,
            waitingPassengerCount: _waitingPassengerCount,
            navigatingToOrderId: _navigatingToOrderId,
            onExitNavigating: _exitNavigatingToPassenger,
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
            onAlternativeRoutes: _showAlternativeRoutesDuringNavigation,
          ),
        // Mute di kartu petunjuk atas (TurnByTurnBanner) saat navigasi step aktif;
        // di kiri bawah hanya saat kerja tanpa banner step (rute utama).
        if (_isDriverWorking || _navigatingToOrderId != null)
          if (!(_navigatingToOrderId != null && _routeSteps.isNotEmpty))
            Positioned(
              left: 16,
              bottom: 24,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(4),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isDriverWorking &&
                        _navigatingToOrderId == null &&
                        _routeDestLatLng != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        tooltip: l10nMap.driverRefreshRouteFromHere,
                        onPressed: _manualRerouteInProgress
                            ? null
                            : _onRefreshRouteFromHerePressed,
                        icon: _manualRerouteInProgress
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      icon: Icon(
                        VoiceNavigationService.instance.muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: VoiceNavigationService.instance.muted
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                      tooltip: VoiceNavigationService.instance.muted
                          ? 'Nyalakan suara arahan'
                          : 'Matikan suara arahan',
                      onPressed: () async {
                        await VoiceNavigationService.instance.toggleMuted();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
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
        // Petunjuk turn-by-turn di atas (gaya Google Maps); mute di kartu ini = selaras dengan teks & TTS.
        if (_navigatingToOrderId != null && _routeSteps.isNotEmpty)
          TurnByTurnBanner(
            steps: _routeSteps,
            currentStepIndex: _currentStepIndex >= 0 ? _currentStepIndex : 0,
            etaArrival: _routeToPassengerDurationSeconds != null
                ? DateTime.now().add(Duration(seconds: _routeToPassengerDurationSeconds!))
                : null,
            tollInfoText: _routeTollInfo,
            routeWarnings: _routeWarnings,
            accentColor: _navigatingToDestination
                ? const Color(0xFFE65100)
                : const Color(0xFF00B14F),
            voiceMuted: VoiceNavigationService.instance.muted,
            onVoiceMuteToggle: () async {
              await VoiceNavigationService.instance.toggleMuted();
              if (mounted) setState(() {});
            },
          ),
        // Mobil = marker di peta (posisi geografis akurat). Tidak pakai overlay tetap.
        // Tombol Fokus: recenter ke mobil saat driver geser/zoom manual
        if (!_cameraTrackingEnabled &&
            (_isDriverWorking || _navigatingToOrderId != null))
          DriverFocusButton(onTap: _focusOnCar),
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

  /// Beranda (peta + banner kontribusi). Tetap di IndexedStack agar GoogleMap tidak di-dispose saat pindah tab.
  Widget _buildDriverBerandaTab({
    required bool mapTabActive,
  }) {
    return Column(
      children: [
        // Stream hanya untuk banner — jangan bungkus GoogleMap (setiap emit = rebuild peta = jank di tab lain).
        StreamBuilder<DriverContributionStatus>(
          stream: DriverContributionService.streamContributionStatus(),
          builder: (context, contribSnap) {
            final status = contribSnap.data;
            final mustPay = status?.mustPayContribution ?? false;
            if (!mustPay) return const SizedBox.shrink();
            final total = status?.totalRupiah ?? 0;
            final fmt = (int n) => n.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
            final t = status?.contributionTravelRupiah ?? 0;
            final b = status?.contributionBarangRupiah ?? 0;
            final v = (status?.outstandingViolationFee ?? 0).round();
            return Container(
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
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const ContributionDriverScreen(),
                        ),
                      );
                      if (ok == true && mounted) setState(() {});
                    },
                    child: const Text('Bayar'),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: TickerMode(
            enabled: mapTabActive,
            child: _buildDriverMapScreen(),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherScreens() {
    // Lazy tab 1–4; tab 0 (Beranda) selalu slot pertama IndexedStack agar peta tetap mounted.
    // _visitedTabIndices diisi di onTap bottom bar / _registerTabVisit — bukan di sini.

    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildDriverBerandaTab(
          mapTabActive: _currentIndex == 0,
        ),
        _visitedTabIndices.contains(1)
            ? RepaintBoundary(
                child: KeyedSubtree(
                  key: const ValueKey('jadwal'),
                  child: DriverJadwalRuteScreen(
                    isDriverVerified: _canStartDriverWork,
                    onVerificationRequired: _showDriverVerificationGateDialog,
                    onOpenRuteFromJadwal: (origin, dest, scheduleId, routePolyline, routeCategory) {
                      if (!_canStartDriverWork) {
                        _showDriverVerificationGateDialog();
                        return;
                      }
                      setState(() {
                        _currentIndex = 0;
                        _pendingJadwalRouteLoad = true;
                        _isStartRouteLoading = false;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _loadRouteFromJadwal(
                            origin,
                            dest,
                            scheduleId,
                            routePolyline,
                            routeCategory,
                          );
                        }
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

      return StreamBuilder<UserShellRebuild>(
        stream: driverUserShellStream(user.uid),
        builder: (context, profileSnap) {
          if (!profileSnap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final p = profileSnap.data!;
          _driverProfileComplete = p.isVerified;
          _canStartDriverWork =
              p.isVerified && !p.adminVerificationBlocksFeatures;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateWakelock();
          });

          return Scaffold(
            // Pembatasan "Pesanan Aktif" hanya untuk penumpang; driver tetap bisa akses Beranda/rute.
            body: _buildOtherScreens(),
            bottomNavigationBar: TrakaMainBottomNavigationBar(
              currentIndex: _currentIndex,
              chatUnreadCount: _chatUnreadCount,
              scheduleTabIcon: TrakaScheduleTabIcon.schedule,
              onTap: (index) {
                _startWorkLoadingSnackTimer?.cancel();
                _startWorkLoadingSnackTimer = null;
                // Bongkar future Siap Kerja yang tertahan (Firestore antre) — cukup pindah tab, tidak harus tutup app.
                _startWorkCheckGen++;
                _driverStartWorkCheckFuture = null;
                if (mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                }
                setState(() {
                  _registerTabVisit(index);
                  // Hanya refresh Data Order saat pindah dari Chat (tab 2), bukan tiap tap (cegah kedip)
                  if (index == 3 && _currentIndex == 2) {
                    _dataOrderRefreshKey++;
                  }
                  _currentIndex = index;
                  if (index == 0) {
                    _isStartRouteLoading = false;
                    // Lepaskan flag jika muat rute dari jadwal gagal tanpa membersihkan state (geocode kosong, dll.)
                    if (_pendingJadwalRouteLoad &&
                        _alternativeRoutes.isEmpty &&
                        !_routeRestoreAwaitingPolyline) {
                      _pendingJadwalRouteLoad = false;
                    }
                  }
                });
                HybridForegroundRecovery.signalTabBecameVisible(index);
                if (index == 0) {
                  _checkActiveOrder();
                }
              },
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
    final mq = MediaQuery.of(context);
    final bannerTop = mq.orientation == Orientation.landscape
        ? mq.padding.top + 8
        : 180.0;
    final color = isPickup
        ? const Color(0xFF00B14F) // hijau penjemputan
        : const Color(0xFFE65100); // oranye pengantaran
    final label = isPickup ? 'Jemput' : 'Antar';
    final name = target.passengerName.trim().isEmpty
        ? (target.isKirimBarang ? 'Barang' : 'Penumpang')
        : target.passengerName;

    return Positioned(
      top: bannerTop,
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

/// Bottom sheet: pilih rute alternatif saat navigasi — daftar + tap di peta (garis berwarna).
class _AlternativeRoutesPickerSheet extends StatefulWidget {
  const _AlternativeRoutesPickerSheet({
    required this.alternatives,
    required this.origin,
    required this.destination,
  });

  final List<DirectionsResultWithSteps> alternatives;
  final LatLng origin;
  final LatLng destination;

  @override
  State<_AlternativeRoutesPickerSheet> createState() =>
      _AlternativeRoutesPickerSheetState();
}

class _AlternativeRoutesPickerSheetState
    extends State<_AlternativeRoutesPickerSheet> {
  GoogleMapController? _mapController;

  static const List<Color> _routeColors = [
    Color(0xFFFFC107),
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFFFF5722),
    Color(0xFF9C27B0),
  ];

  Set<Polyline> _buildPolylines() {
    final out = <Polyline>{};
    for (var i = 0; i < widget.alternatives.length; i++) {
      final pts = widget.alternatives[i].result.points;
      if (pts.length < 2) continue;
      out.add(
        Polyline(
          polylineId: PolylineId('nav_alt_$i'),
          points: pts,
          color: _routeColors[i % _routeColors.length].withValues(alpha: 0.88),
          width: 5,
          zIndex: widget.alternatives.length - i,
        ),
      );
    }
    return out;
  }

  void _pickFromLatLng(LatLng position) {
    double minD = double.infinity;
    var best = -1;
    for (var i = 0; i < widget.alternatives.length; i++) {
      final pts = widget.alternatives[i].result.points;
      if (pts.isEmpty) continue;
      final d = RouteUtils.distanceToPolyline(position, pts);
      if (d < minD) {
        minD = d;
        best = i;
      }
    }
    final n = widget.alternatives.length;
    final threshold = n <= 3 ? 500000.0 : 250000.0;
    if (best >= 0 && minD < threshold) {
      Navigator.of(context).pop(best);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tap pada garis rute. Jarak terdekat: ${(minD / 1000).toStringAsFixed(1)} km',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
  }

  Future<void> _fitBounds() async {
    final c = _mapController;
    if (c == null) return;
    var minLat = 90.0;
    var maxLat = -90.0;
    var minLng = 180.0;
    var maxLng = -180.0;
    void expand(LatLng p) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    expand(widget.origin);
    expand(widget.destination);
    for (final a in widget.alternatives) {
      for (final p in a.result.points) {
        expand(p);
      }
    }
    if ((maxLat - minLat).abs() < 1e-4) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if ((maxLng - minLng).abs() < 1e-4) {
      minLng -= 0.01;
      maxLng += 0.01;
    }
    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          56,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih rute alternatif',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap garis di peta atau pilih dari daftar',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: StyledGoogleMapBuilder(
                  builder: (style, _) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: widget.origin,
                            zoom: MapStyleService.defaultZoom,
                          ),
                          style: style,
                          mapType: MapType.normal,
                          polylines: _buildPolylines(),
                          markers: {
                            Marker(
                              markerId: const MarkerId('alt_origin'),
                              position: widget.origin,
                              infoWindow: const InfoWindow(title: 'Anda'),
                            ),
                            Marker(
                              markerId: const MarkerId('alt_dest'),
                              position: widget.destination,
                              infoWindow: const InfoWindow(title: 'Tujuan'),
                            ),
                          },
                          onMapCreated: (controller) {
                            setState(() => _mapController = controller);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) unawaited(_fitBounds());
                            });
                          },
                          onTap: _mapController != null ? null : _pickFromLatLng,
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: true,
                        ),
                        if (_mapController != null)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapUp: (details) async {
                                final mc = _mapController;
                                if (mc == null || !mounted) return;
                                try {
                                  final dpr =
                                      MediaQuery.devicePixelRatioOf(context);
                                  final latLng = await mc.getLatLng(
                                    ScreenCoordinate(
                                      x: (details.localPosition.dx * dpr)
                                          .round(),
                                      y: (details.localPosition.dy * dpr)
                                          .round(),
                                    ),
                                  );
                                  if (mounted) _pickFromLatLng(latLng);
                                } catch (_) {}
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: widget.alternatives.length,
              itemBuilder: (context, i) {
                final alt = widget.alternatives[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _routeColors[i % _routeColors.length]
                        .withValues(alpha: 0.22),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    '${alt.result.distanceText} • ${alt.result.durationText}',
                  ),
                  subtitle: alt.result.warnings.isNotEmpty
                      ? Text(
                          alt.result.warnings.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

