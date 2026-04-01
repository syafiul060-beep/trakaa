import 'dart:async';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_constants.dart';
import '../l10n/app_localizations.dart' show AppLocale;
import '../config/marker_assets.dart';
import '../config/province_island.dart';
import '../models/order_model.dart';
import '../services/app_analytics_service.dart';
import '../services/app_config_service.dart';
import '../services/auth_session_service.dart';
import '../services/camera_follow_engine.dart';
import '../services/car_icon_service.dart';
import '../services/chat_badge_service.dart';
import '../services/directions_service.dart';
import '../services/driver_car_marker_service.dart';
import '../services/driver_contribution_service.dart';
import '../services/driver_location_icon_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/driver_nav_premium_service.dart';
import '../services/driver_driving_ux_service.dart';
import '../services/driver_status_service.dart';
import '../services/field_observability_service.dart';
import '../services/map_device_tilt_service.dart';
import '../services/offline_nav_route_cache_service.dart';
import '../services/exemption_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/geocoding_service.dart';
import '../services/hybrid_foreground_recovery.dart';
import '../services/location_service.dart';
import '../services/low_ram_warning_service.dart';
import '../services/map_style_service.dart';
import '../services/marker_icon_service.dart';
import '../services/navigation_settings_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/order_service.dart';
import '../services/pending_purchase_recovery_service.dart';
import '../services/performance_trace_service.dart';
import '../services/route_background_handler.dart';
import '../services/route_journey_number_service.dart';
import '../services/route_optimization_service.dart';
import '../services/route_persistence_service.dart';
import '../services/route_session_service.dart';
import '../services/route_utils.dart';
import '../services/routes_toll_service.dart';
import '../services/theme_service.dart';
import '../services/traka_pin_bitmap_service.dart';
import '../services/travel_admin_region.dart';
import '../services/trip_service.dart';
import '../services/user_shell_profile_stream.dart';
import '../services/verification_service.dart';
import '../services/voice_navigation_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/app_logger.dart';
import '../utils/instruction_formatter.dart';
import '../utils/placemark_formatter.dart';
import '../widgets/driver_focus_button.dart';
import '../widgets/driver_nav_premium_map_chip.dart';
import '../widgets/driver_map_overlays.dart';
import '../widgets/driver_route_form_sheet.dart';
import '../widgets/driver_route_info_panel.dart';
import '../widgets/driver_stops_list_overlay.dart';
import '../widgets/lacak_tracking_info_sheet.dart';
import '../widgets/traka_pin_widgets.dart';
import '../widgets/map_destination_picker_screen.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/traka_empty_state.dart';
import '../widgets/navigating_to_destination_overlay.dart';
import '../widgets/navigating_to_passenger_overlay.dart';
import '../widgets/oper_driver_sheet.dart';
import '../widgets/promotion_banner_widget.dart';
import '../widgets/styled_google_map_builder.dart';
import '../widgets/traka_l10n_scope.dart';
import '../widgets/traka_bottom_sheet.dart';
import '../widgets/traka_loading_indicator.dart';
import '../widgets/traka_main_bottom_navigation_bar.dart';
import '../widgets/turn_by_turn_banner.dart';
import 'chat_list_driver_screen.dart';
import 'contribution_driver_screen.dart';
import 'driver_nav_premium_payment_screen.dart';
import 'offline_map_precache_screen.dart';
import 'data_order_driver_screen.dart';
import 'driver_jadwal_rute_screen.dart';
import 'login_screen.dart';
import 'profile_driver_screen.dart';

/// Tipe rute: dalam provinsi, antar provinsi, dalam negara.
enum RouteType { dalamProvinsi, antarProvinsi, dalamNegara }

/// Titik masuk fitur lapangan (tahap integrasi 2→4): ikon «tune» kontrol zoom → sheet
/// (precache OSM, bantuan lacak, pilih tujuan di peta memakai form); chip navigasi premium;
/// sensor tilt + sinkron [DriverDrivingUxService]/[FieldObservabilityService]; cache rute
/// [OfflineNavRouteCacheService] + arahan [NavigationDiagnostics] di [DirectionsService].
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

  /// Jangan membuat stream shell baru tiap [build] — [StreamBuilder] akan reset dan layar driver
  /// "putih" (hanya spinner) sampai baca Firestore awal selesai lagi.
  Stream<UserShellRebuild>? _cachedDriverUserShellStream;
  String? _cachedDriverUserShellStreamUid;

  Stream<UserShellRebuild> _driverUserShellStreamFor(String uid) {
    if (_cachedDriverUserShellStreamUid != uid) {
      _cachedDriverUserShellStreamUid = uid;
      _cachedDriverUserShellStream = driverUserShellStream(uid);
    }
    return _cachedDriverUserShellStream!;
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
  /// ETA lalu lintas di Directions + cek rute alternatif; off saat hemat data navigasi.
  bool get _directionsTrafficAware =>
      _trafficEnabled && !NavigationSettingsService.dataSaverEnabled;
  /// Rekomendasi rute alternatif saat macet: menit lebih cepat (null = tidak ada).
  int? _fasterAlternativeMinutesSaved;
  Timer? _trafficAlternativesCheckTimer;
  /// Zoom ringan sekali per step belokan (tahap 4).
  int _lastContextualZoomStepIndex = -999;
  Position? _currentPosition;
  Timer? _locationRefreshTimer;
  /// Lokasi rapat (stream) saat kerja / navigasi order — mengurangi keterlambatan vs polling timer.
  StreamSubscription<Position>? _driverNavPositionSub;
  DateTime? _lastDriverNavStreamAt;
  /// Supaya pemrosesan lokasi tumpang-tindih (stream + polling) tidak menulis state usang setelah await.
  int _applyDriverGpsToken = 0;
  /// Peringatan akurasi GPS di peta (hysteresis agar tidak berkedip).
  bool _showGpsAccuracyHint = false;
  bool _gpsAccuracyHintDismissed = false;
  double? _lastGpsAccuracyMeters;
  static const double _gpsAccuracyPoorMeters = 48.0;
  static const double _gpsAccuracyOkMeters = 30.0;
  Timer? _interpolationTimer;
  /// Timer untuk refresh token auth berkala (agar tidak kadaluarsa saat pakai lama).
  Timer? _authTokenRefreshTimer;

  /// Posisi yang ditampilkan di map (interpolasi untuk pergerakan halus).
  LatLng? _displayedPosition;

  /// Bila jarak driver ke titik geocode "tujuan awal" jadwal lebih dari ini, rute biru diminta dari lokasi driver (bukan dari titik jadwal).
  /// Nilai lebih kecil = lebih sering mengikuti posisi driver (garis tidak "janggal" di ujung jadwal).
  static const double _jadwalRouteStartFromDriverBeyondMeters = 200;

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
  /// Cegah double-tap panel info rute / form rute / oper driver menumpuk sheet.
  bool _routeInfoSheetOpen = false;
  bool _routeFormSheetOpen = false;
  bool _operDriverSheetOpen = false;
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
  /// Kunci admin asal/tujuan rute (untuk filter penumpang / `driver_status`).
  String? _routeOriginKabKey;
  String? _routeDestKabKey;
  String? _routeOriginProvKey;
  String? _routeDestProvKey;
  Timer? _routeAdminKeysResolveTimer;
  int _routeAdminKeysResolveGen = 0;
  double? _adminKeysCachedOLat;
  double? _adminKeysCachedOLng;
  double? _adminKeysCachedDLat;
  double? _adminKeysCachedDLng;

  // Tracking update lokasi ke Firestore (efisien: jika pindah 1.5 km atau per 12 menit)
  Position? _lastUpdatedPosition;
  DateTime? _lastUpdatedTime;
  int _consecutiveDriverStatusWriteFailures = 0;

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
  /// Jangan terlalu rendah — jitter GPS saat diam mudah melewati ~3 km/j (turunan jarak).
  static const double _homeBrowsingHeadingMinKmh = 7.0;

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

  /// TTS jarak ke manuver (gaya Google Maps): bucket meter yang sudah diumumkan untuk step aktif.
  final Set<int> _voiceProximityBuckets = {};
  int _voiceProximityStepIndex = -1;
  DateTime? _lastVoiceCueAt;

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
  /// Awal berhenti penuh saat navigasi/kerja — untuk north-up bertahap (mirip Google Maps).
  DateTime? _driverStoppedNavigatingAt;
  /// Bobot framing «nyasar» terbaru — dipakai zoom out / tilt landai ringan.
  double _navCameraOffRouteWeight = 0.0;
  /// Zoom out singkat sebelum manuver kompleks (satu kali per langkah TBT).
  DateTime? _maneuverOverviewZoomBoostUntil;
  int _maneuverOverviewFiredForStepIndex = -1;

  /// Overview kamera sebelum manuver TBT — sesuaikan angka di sini saja.
  static const double _kNavManeuverOverviewRemMinM = 118.0;
  static const double _kNavManeuverOverviewRemMaxM = 295.0;
  /// Picu hanya jika sampel jarak sebelumnya ≥ ini (hindari picu saat sudah mepet belok).
  static const double _kNavManeuverOverviewPrevRemMinM = 112.0;
  static const int _kNavManeuverOverviewEffectMs = 4800;
  /// Kurangi level zoom saat overview penuh (besar = lebih jauh / lebih luas).
  static const double _kNavManeuverOverviewZoomDelta = 0.42;
  /// Kurangi tilt (derajat) saat overview penuh — peta sedikit lebih «dari atas».
  static const double _kNavManeuverOverviewTiltDeltaDeg = 5.5;

  /// Setelah user geser peta navigasi: tampilkan petunjuk sekali per sesi layar.
  bool _hasShownMapGestureTrackingHint = false;

  // Long press detection untuk pilih rute alternatif
  // Badge chat: jumlah order dengan pesan belum dibaca driver
  StreamSubscription<List<OrderModel>>? _driverOrdersSub;
  List<OrderModel> _driverOrders = [];
  /// Set true setelah stream order driver pernah memuat snapshot — Siap Kerja bisa percaya daftar in-memory.
  bool _driverOrdersStreamReady = false;
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
  /// Order `pending_agreement` / `pending_receiver` — badge tab Pesanan + snackbar.
  int _ordersAttentionCount = 0;
  bool _hasAppliedDriverOrdersOnce = false;
  DateTime? _lastChatInAppSnackAt;
  DateTime? _lastOrdersInAppSnackAt;
  int _jumlahPenumpang = 0;
  int _jumlahBarang = 0;

  /// Jumlah penumpang yang sudah dijemput (picked_up) - untuk enable tombol Oper Driver.
  int _jumlahPenumpangPickedUp = 0;

  /// ID pesanan yang driver «Abaikan» pada banner penumpang dekat (bisa muncul lagi setelah menjauh).
  final Set<String> _dismissedPickupNearbyHintOrderIds = <String>{};
  /// Supaya getar + analytics `shown` sekali per «episode» (hilang saat banner off).
  String? _pickupNearbyBannerImpressionOrderId;
  /// «Arahkan ke stop terdekat» bisa disembunyikan lewat geser sampai stop berubah.
  String? _nextStopBannerContextKey;
  bool _nextStopBannerUserDismissed = false;

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
  /// Segmen laju per langkah Directions (warna jalur). Selalu sejajar dengan polyline yang memuat [_routeSteps] aktif.
  List<RoutePolylineTrafficSegment> _activeRouteTrafficSegments = [];
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
  /// Jarak tersisa ke akhir langkah TBT (untuk banner gaya Maps).
  double? _tbtRemainingMeters;
  /// Jarak sepanjang polyline ke awal langkah berikutnya (baris «Lalu»).
  double? _tbtNextStepRemainingMeters;
  DateTime? _lastTbtProjectionFailLog;
  /// Pesan singkat setelah re-route otomatis (chip hijau di banner).
  String? _rerouteStatusBanner;
  Timer? _rerouteStatusClearTimer;
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

  /// Setelah polyline/steps baru: kamera mengikuti garis lagi (tanpa paksa fokus jika user sedang geser peta).
  void _syncCameraAfterRouteRecalculated() {
    if (!mounted) return;
    _lastCameraTarget = null;
    _lastCameraBearing = null;
    _cameraFollowEngine.resetThrottle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cameraTrackingEnabled) return;
      if (_mapController == null || _displayedPosition == null) return;
      if (!_isDriverWorking && _navigatingToOrderId == null) return;
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      _animateCameraToDisplayed(_smoothedBearing, force: true);
    });
  }

  void _scheduleQuietRerouteBanner() {
    _rerouteStatusClearTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _rerouteStatusBanner = 'Rute disesuaikan dari posisi Anda';
    });
    _rerouteStatusClearTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _rerouteStatusBanner = null);
    });
  }

  double _snapMaxMetersForSpeed() {
    final kmh = _currentSpeedMps * 3.6;
    double cap;
    if (kmh >= 75) {
      cap = 142;
    } else if (kmh >= 45) {
      cap = 132;
    } else {
      cap = _snapToRoutePolylineMaxMeters;
    }
    final acc = _currentPosition?.accuracy;
    if (acc != null && acc.isFinite && acc > 42) {
      final over = ((acc - 42) / 95.0).clamp(0.0, 1.0);
      cap *= 1.0 - 0.38 * over;
    }
    return cap.clamp(46.0, 142.0);
  }

  /// 1 = percaya bearing dari polyline/GPS; turun saat akurasi buruk (terowongan, gedung).
  static double _gpsAccuracyTrustForBearing(double? accuracyMeters) {
    if (accuracyMeters == null || !accuracyMeters.isFinite || accuracyMeters <= 0) {
      return 0.78;
    }
    if (accuracyMeters <= 16) return 1.0;
    if (accuracyMeters <= 28) return 0.93;
    if (accuracyMeters >= 130) return 0.18;
    return 0.93 - (accuracyMeters - 28) / (130 - 28) * (0.93 - 0.18);
  }

  double _maneuverOverviewFade01() {
    final until = _maneuverOverviewZoomBoostUntil;
    if (until == null || !DateTime.now().isBefore(until)) return 0;
    return (until.difference(DateTime.now()).inMilliseconds /
            _kNavManeuverOverviewEffectMs)
        .clamp(0.0, 1.0);
  }

  void _maybeTriggerManeuverOverviewZoom(
    RouteStep step,
    double? prevRem,
    double clamped,
  ) {
    if (!_isDriverWorking && _navigatingToOrderId == null) return;
    if (!_cameraTrackingEnabled) return;
    if (!_stepLooksLikeTurn(step)) return;
    if (clamped < _kNavManeuverOverviewRemMinM ||
        clamped > _kNavManeuverOverviewRemMaxM) {
      return;
    }
    if (_maneuverOverviewFiredForStepIndex == _currentStepIndex) return;
    if (prevRem != null && prevRem < _kNavManeuverOverviewPrevRemMinM) return;
    _maneuverOverviewFiredForStepIndex = _currentStepIndex;
    _maneuverOverviewZoomBoostUntil = DateTime.now().add(
      const Duration(milliseconds: _kNavManeuverOverviewEffectMs),
    );
  }

  void _resetManeuverOverviewZoomState() {
    _maneuverOverviewZoomBoostUntil = null;
    _maneuverOverviewFiredForStepIndex = -1;
  }

  void _refreshTbtRemainingFromPosition(Position position) {
    if (!_isDriverWorking && _navigatingToOrderId == null) {
      _resetManeuverOverviewZoomState();
      if (_tbtRemainingMeters != null || _tbtNextStepRemainingMeters != null) {
        _tbtRemainingMeters = null;
        _tbtNextStepRemainingMeters = null;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_routeSteps.isEmpty ||
        _currentStepIndex < 0 ||
        _currentStepIndex >= _routeSteps.length) {
      _resetManeuverOverviewZoomState();
      if (_tbtRemainingMeters != null || _tbtNextStepRemainingMeters != null) {
        _tbtRemainingMeters = null;
        _tbtNextStepRemainingMeters = null;
        if (mounted) setState(() {});
      }
      return;
    }
    final poly = _activeNavigationPolyline ??
        ((_routePolyline != null && _routePolyline!.length >= 2)
            ? _routePolyline
            : null);
    if (poly == null || poly.length < 2) return;

    // Selalu proyeksi dari GPS mentah: posisi tersmooth sering tertinggal di belokan sehingga
    // jarak manuver «membengkak» (mis. sudah ~5 m masih menampilkan puluhan meter).
    final rawPos = LatLng(position.latitude, position.longitude);
    final pos = rawPos;
    var proj = RouteUtils.projectPointOntoPolyline(
      pos,
      poly,
      maxDistanceMeters: 320,
    );
    if (proj.$2 < 0) {
      proj = RouteUtils.projectPointOntoPolyline(
        pos,
        poly,
        maxDistanceMeters: 520,
      );
    }
    if (proj.$2 < 0) {
      proj = RouteUtils.projectPointOntoPolyline(
        rawPos,
        poly,
        maxDistanceMeters: 620,
      );
    }
    if (proj.$2 < 0) {
      _resetManeuverOverviewZoomState();
      if (_tbtRemainingMeters != null || _tbtNextStepRemainingMeters != null) {
        _tbtRemainingMeters = null;
        _tbtNextStepRemainingMeters = null;
        if (mounted) setState(() {});
      }
      return;
    }
    final distM = RouteUtils.distanceAlongPolyline(poly, proj.$2, proj.$3);
    final step = _routeSteps[_currentStepIndex];
    final rem = step.endDistanceMeters - distM;
    if (rem < -55 || rem > 12000) return;
    final clamped = rem.clamp(0.0, 99999.0);
    final prev = _tbtRemainingMeters;
    final delta = prev == null ? 999.0 : (prev - clamped).abs();
    var changed = false;
    final tightManeuver = clamped < 130;
    final minDelta = tightManeuver ? 4.0 : 12.0;
    final pctTol = tightManeuver ? 0.04 : 0.06;
    if (prev == null ||
        delta >= minDelta ||
        (prev > 120 && delta >= prev * pctTol)) {
      _tbtRemainingMeters = clamped;
      changed = true;
      if (clamped <= 22 && (prev == null || prev > 28)) {
        HapticFeedback.mediumImpact();
      }
    }
    double? nextRem;
    if (_currentStepIndex + 1 < _routeSteps.length) {
      final nextStart = _routeSteps[_currentStepIndex + 1].startDistanceMeters;
      nextRem = (nextStart - distM).clamp(0.0, 999999.0);
    }
    final prevNext = _tbtNextStepRemainingMeters;
    if (nextRem != null) {
      final nd = prevNext == null ? 999.0 : (prevNext - nextRem).abs();
      final nextThresh = tightManeuver ? 12.0 : 25.0;
      if (prevNext == null ||
          nd >= nextThresh ||
          (prevNext > 100 && nd >= prevNext * 0.07)) {
        _tbtNextStepRemainingMeters = nextRem;
        changed = true;
      }
    } else if (prevNext != null) {
      _tbtNextStepRemainingMeters = null;
      changed = true;
    }
    if (changed) {
      _maybeTriggerManeuverOverviewZoom(step, prev, clamped);
      if (mounted) setState(() {});
    }
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
  /// Saat sudah jauh dari garis rute: izinkan panggilan ulang lebih cepat (mirip Google Maps).
  static const int _rerouteDebounceSecondsFarOff = 6;
  static const double _farOffDeviationForFastRerouteMeters = 92.0;
  /// Jarak minimum sejak reroute terakhir / posisi referensi agar boleh reroute lagi.
  static const double _rerouteDebounceDistanceMeters = 40.0;
  /// Saat simpang besar dari rute navigasi (menuju penumpang/tujuan): refetch lebih agresif.
  static const double _refetchNavRouteNearDeviationMeters = 95.0;
  static const double _refetchNavRouteDistanceWhenFarMeters = 22.0;
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
    MapDeviceTiltService.instance.addListener(_onDeviceTiltChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshNavPremiumOwed());
    });
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      DriverNavPremiumService.clearPhoneExemptCache();
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
        int ordersAttention = 0;
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
          if (o.isPendingAgreement || o.isPendingReceiver) {
            ordersAttention++;
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
                  _activeRouteTrafficSegments = [];
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
                _resetVoiceProximityState();
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
                    _activeRouteTrafficSegments = [];
                    _currentStepIndex = -1;
                    _routeToPassengerDistanceText = '';
                    _routeToPassengerDurationText = '';
                    _lastPassengerLat = null;
                    _lastPassengerLng = null;
                  });
                  _resetVoiceProximityState();
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
          ordersAttentionCount: ordersAttention,
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
    _formDestPreviewNotifier.addListener(_onFormRoutePreviewChanged);
    NavigationSettingsService.dataSaverNotifier
        .addListener(_onNavigationDataSaverChanged);
    _restartLocationTimer();
  }

  void _onNavigationDataSaverChanged() {
    if (!mounted) return;
    if (_navigatingToOrderId != null && _trafficEnabled) {
      _stopTrafficAlternativesCheck();
      _startTrafficAlternativesCheck();
    }
  }

  void _onDriverBadgeOptimisticChanged() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prevChat = _chatUnreadCount;
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
    if (_hasAppliedDriverOrdersOnce && count > prevChat && _currentIndex != 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowDriverInAppTabSnacks(
          prevChat: prevChat,
          newChat: count,
          prevOrdersAttention: _ordersAttentionCount,
          newOrdersAttention: _ordersAttentionCount,
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      MapDeviceTiltService.instance.setBackgroundPaused(true);
      DriverDrivingUxService.clearForegroundDrivingContext();
      _driverPausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      MapDeviceTiltService.instance.setBackgroundPaused(false);
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
        if (_isDriverWorking || _navigatingToOrderId != null) {
          unawaited(_ensureDriverNavigationPositionStream());
        }
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
    required int ordersAttentionCount,
    required bool hasActive,
    required int penumpang,
    required int barang,
    required int penumpangPickedUp,
  }) {
    void apply() {
      if (!mounted) return;
      final prevChat = _chatUnreadCount;
      final prevOrdersAttention = _ordersAttentionCount;
      final isFirstApply = !_hasAppliedDriverOrdersOnce;
      setState(() {
        _driverOrdersStreamReady = true;
        _driverOrders = orders;
        _chatUnreadCount = count;
        _ordersAttentionCount = ordersAttentionCount;
        _hasActiveOrder = hasActive;
        _jumlahPenumpang = penumpang;
        _jumlahBarang = barang;
        _jumlahPenumpangPickedUp = penumpangPickedUp;
      });
      _hasAppliedDriverOrdersOnce = true;
      _loadPassengerMarkerIconsIfNeeded();
      if (isFirstApply) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowDriverInAppTabSnacks(
          prevChat: prevChat,
          newChat: count,
          prevOrdersAttention: prevOrdersAttention,
          newOrdersAttention: ordersAttentionCount,
        );
      });
    }

    _driverOrdersUiDebounce?.cancel();
    // Pertama kali: langsung (hindari blank); berikutnya: debounce lawan spam stream.
    if (_driverOrders.isEmpty) {
      apply();
      return;
    }
    _driverOrdersUiDebounce = Timer(const Duration(milliseconds: 180), apply);
  }

  static const Duration _driverInAppSnackMinGap = Duration(seconds: 6);

  /// Snackbar ringkas saat chat/pesanan bertambah dan driver tidak di tab terkait.
  void _maybeShowDriverInAppTabSnacks({
    required int prevChat,
    required int newChat,
    required int prevOrdersAttention,
    required int newOrdersAttention,
  }) {
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    final now = DateTime.now();
    if (newChat > prevChat && _currentIndex != 2) {
      if (_lastChatInAppSnackAt == null ||
          now.difference(_lastChatInAppSnackAt!) >= _driverInAppSnackMinGap) {
        _lastChatInAppSnackAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.driverInAppNewChatHint),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.driverInAppOpenChat,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _registerTabVisit(2);
                  _currentIndex = 2;
                });
              },
            ),
          ),
        );
      }
      return;
    }
    if (newOrdersAttention > prevOrdersAttention && _currentIndex != 3) {
      if (_lastOrdersInAppSnackAt == null ||
          now.difference(_lastOrdersInAppSnackAt!) >= _driverInAppSnackMinGap) {
        _lastOrdersInAppSnackAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.driverInAppNewOrderHint),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.driverInAppOpenOrders,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _registerTabVisit(3);
                  _currentIndex = 3;
                });
              },
            ),
          ),
        );
      }
    }
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
    // Disesuaikan dengan [CameraFollowEngine.maxAnimationMs]: prioritas gerakan halus,
    // bukan snap cepat (engine akan clamp panjang tween).
    int msFromDistance = 240;
    if (distanceMeters > 0) {
      msFromDistance =
          (220 + (distanceMeters / 200) * 360).round().clamp(220, 520);
    }
    int msFromBearing = 240;
    if (lastBearing != null) {
      double diff = (newBearing - lastBearing) % 360;
      if (diff > 180) diff -= 360;
      final bearingDeg = diff.abs();
      if (bearingDeg > 45) {
        msFromBearing =
            (260 + (bearingDeg / 90) * 140).round().clamp(280, 480);
      } else if (bearingDeg > 18) {
        msFromBearing =
            (230 + (bearingDeg / 45) * 110).round().clamp(230, 400);
      }
    }
    return Duration(
      milliseconds:
          msFromDistance > msFromBearing ? msFromDistance : msFromBearing,
    );
  }

  /// Target kamera terakhir untuk hitung durasi animasi proporsional.
  LatLng? _lastCameraTarget;
  /// Bearing kamera terakhir (untuk durasi rotasi halus saat belok).
  double? _lastCameraBearing;

  /// Durasi animasi marker: min 200ms; max dibatasi agar stream GPS tidak «ngejar» titik lama terlalu lama.
  static const int _animDurationMinMs = 200;
  static const int _animDurationMaxMs = 1300;
  static const int _animTickMs = 120;

  /// Durasi interpolasi satu langkah: jarak kecil = selesai cepat; loncat besar = ikut pacing GPS tapi ada cap.
  int _navigationInterpolationDurationMs({
    required int elapsedSinceLastFixMs,
    required double segmentMeters,
    double routeBearingDeltaDeg = 0,
  }) {
    final elapsed = elapsedSinceLastFixMs.clamp(80, 4000);
    int base;
    if (segmentMeters < 10) {
      base = elapsed.clamp(110, 380);
    } else if (segmentMeters < 35) {
      base = elapsed.clamp(130, 520);
    } else if (segmentMeters < 120) {
      base = (elapsed * 0.9).round().clamp(160, 750);
    } else {
      base = (elapsed * 0.88).round().clamp(200, _animDurationMaxMs);
    }
    final bd = routeBearingDeltaDeg;
    if (bd >= 52) {
      base = (base * 0.42).round().clamp(95, 420);
    } else if (bd >= 32) {
      base = (base * 0.58).round().clamp(105, 520);
    } else if (bd >= 18) {
      base = (base * 0.75).round().clamp(115, 620);
    }
    if (_isDriverWorking || _navigatingToOrderId != null) {
      base = (base * 0.78).round().clamp(_animDurationMinMs, 820);
    }
    return base;
  }

  /// Delta bearing sepanjang polyline (titik diproyeksi): besar setelah belokan → interpolasi lebih singkat.
  double _routeBearingDeltaForInterpolation(LatLng fromDisplayed, LatLng targetPos) {
    final polyline = _routePolyline ?? _activeNavigationPolyline;
    if (polyline == null || polyline.length < 2) return 0.0;
    final projDisp = RouteUtils.projectPointOntoPolyline(
      fromDisplayed,
      polyline,
      maxDistanceMeters: _snapToRoutePolylineMaxMeters,
    );
    final projTgt = RouteUtils.projectPointOntoPolyline(
      targetPos,
      polyline,
      maxDistanceMeters: _snapToRoutePolylineMaxMeters,
    );
    if (projDisp.$2 < 0 || projTgt.$2 < 0) return 0.0;
    final bDisp = RouteUtils.bearingOnPolylineAtPosition(
      projDisp.$1,
      polyline,
      segmentIndex: projDisp.$2,
      ratio: projDisp.$3,
    );
    final bTgt = RouteUtils.bearingOnPolylineAtPosition(
      projTgt.$1,
      polyline,
      segmentIndex: projTgt.$2,
      ratio: projTgt.$3,
    );
    var d = bTgt - bDisp;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d.abs();
  }

  /// Ikut kamera: [CameraFollowEngine] throttle + durasi dibatasi agar tidak bertumpuk
  /// (marker tetap halus tiap [_animTickMs]).

  /// Heading-up ala Google Maps: target kamera di depan mobil, ikon stabil di bawah tengah,
  /// peta yang bergeser/berputar. Tilt landai; zoom sedikit lebih jauh dari mode ride-hailing 3D.
  static const double _trackingTiltMoving = 24.0;
  static const double _trackingTiltIdle = 11.0;
  double _displayedZoom = 16.65;
  double _displayedTilt = 22.0;

  bool _navPremiumOwedCache = false;
  bool _navPremiumPhoneExemptCache = false;
  int? _lastFieldObsTab;
  bool? _lastFieldObsRouteNav;
  String? _lastFieldObsOrderId;
  bool? _lastUxNavigating;
  bool? _lastUxTbt;

  /// Zoom mengikuti kecepatan tanpa lompatan tier (kurangi «tiba-tiba dekat/jauh»).
  /// [offRouteWeight]: nyasar dari polyline → sedikit zoom out (lebih banyak konteks).
  double _getTrackingZoom(double speedKmh, {double offRouteWeight = 0}) {
    final s = speedKmh.clamp(0.0, 120.0);
    // Sedikit lebih «zoom out» dari mode Grab agar ruas jalan depan lebih luas (mirip Maps).
    double z;
    if (s < 5) {
      z = 16.07 + (s / 5) * 0.45;
    } else if (s < 20) {
      z = 16.52 + ((s - 5) / 15) * 0.38;
    } else if (s < 55) {
      z = 16.9 + ((s - 20) / 35) * 0.42;
    } else {
      z = 17.32 + ((s - 55) / 65).clamp(0.0, 1.0) * 0.35;
    }
    if (s < 1.2) z += 0.14; // hampir diam: sedikit zoom in — area sekitar lebih jelas
    if (offRouteWeight > 0.04) z -= 0.30 * offRouteWeight;
    final mo = _maneuverOverviewFade01();
    if (mo > 0.02) z -= _kNavManeuverOverviewZoomDelta * mo;
    return z;
  }

  /// Tilt naik turun halus antara idle dan mengemudi (bukan flip di 2 km/j).
  /// Nyasar: tilt sedikit diturunkan (peta lebih «atas», konteks samping).
  double _getTrackingTilt(double speedKmh, {double offRouteWeight = 0}) {
    final s = speedKmh.clamp(0.0, 40.0);
    double tilt;
    if (s <= 0.4) {
      tilt = _trackingTiltIdle;
    } else if (s >= 12) {
      tilt = _trackingTiltMoving;
    } else {
      final t = (s - 0.4) / 11.6;
      tilt = _trackingTiltIdle + (_trackingTiltMoving - _trackingTiltIdle) * t;
    }
    if (offRouteWeight > 0.05) tilt -= 6.5 * offRouteWeight;
    final mo = _maneuverOverviewFade01();
    if (mo > 0.02) tilt -= _kNavManeuverOverviewTiltDeltaDeg * mo;
    return tilt.clamp(5.0, _trackingTiltMoving);
  }

  /// Update zoom/tilt yang di-display (lerp lebih lambat = perubahan kecepatan tidak «jedug»).
  void _updateDisplayedZoomTilt() {
    final speedKmh = _currentSpeedMps * 3.6;
    final w = _navCameraOffRouteWeight;
    final targetZoom = _getTrackingZoom(speedKmh, offRouteWeight: w);
    final targetTilt = _getTrackingTilt(speedKmh, offRouteWeight: w);
    const alphaZoom = 0.19;
    const alphaTilt = 0.21;
    _displayedZoom += (targetZoom - _displayedZoom) * alphaZoom;
    _displayedTilt += (targetTilt - _displayedTilt) * alphaTilt;
  }

  double _effectiveCameraTiltForNav() {
    if (!MapDeviceTiltService.supportsPlatform) return _displayedTilt;
    if (!_isDriverWorking && _navigatingToOrderId == null) {
      return _displayedTilt;
    }
    return (_displayedTilt + MapDeviceTiltService.instance.offsetDegrees)
        .clamp(0.0, 60.0);
  }

  void _onDeviceTiltChanged() {
    if (!mounted) return;
    if (_isDriverWorking || _navigatingToOrderId != null) {
      setState(() {});
    }
  }

  void _syncMapDeviceTiltSession() {
    if (!MapDeviceTiltService.supportsPlatform) return;
    if (_isDriverWorking || _navigatingToOrderId != null) {
      MapDeviceTiltService.instance.setOrientation(
        MediaQuery.orientationOf(context),
      );
      MapDeviceTiltService.instance.startListening();
    } else {
      MapDeviceTiltService.instance.stopListening();
    }
  }

  void _syncFieldObservabilityIfChanged() {
    final tab = _currentIndex;
    final routeNav = _isDriverWorking &&
        (_routePolyline != null && _routePolyline!.length >= 2);
    final oid = _navigatingToOrderId;
    if (_lastFieldObsTab == tab &&
        _lastFieldObsRouteNav == routeNav &&
        _lastFieldObsOrderId == oid) {
      return;
    }
    _lastFieldObsTab = tab;
    _lastFieldObsRouteNav = routeNav;
    _lastFieldObsOrderId = oid;
    FieldObservabilityService.syncDriverHome(
      tabIndex: tab,
      routeNavActive: routeNav || oid != null,
      orderNavigationId: oid,
    );
  }

  void _syncDriverDrivingUxIfChanged() {
    final nav = _navigatingToOrderId != null;
    final tbt = _routeSteps.isNotEmpty &&
        (nav ||
            (_isDriverWorking &&
                _routePolyline != null &&
                _routePolyline!.length >= 2));
    if (_lastUxNavigating == nav && _lastUxTbt == tbt) return;
    _lastUxNavigating = nav;
    _lastUxTbt = tbt;
    DriverDrivingUxService.syncDriverMapState(
      navigatingToOrder: nav,
      turnByTurnChromeVisible: tbt,
    );
  }

  Future<void> _refreshNavPremiumOwed() async {
    final o = await DriverNavPremiumService.hasOwedPayment();
    final exempt = await DriverNavPremiumService.fetchPhoneExempt();
    if (!mounted) return;
    setState(() {
      _navPremiumOwedCache = o;
      _navPremiumPhoneExemptCache = exempt;
    });
  }

  void _persistOfflineWorkRouteFromSteps(DirectionsResultWithSteps withSteps) {
    if (_routeDestLatLng == null) return;
    final idx = _currentStepIndex >= 0 ? _currentStepIndex : 0;
    unawaited(
      OfflineNavRouteCacheService.saveWorkRoute(
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
        polyline: withSteps.result.points,
        steps: withSteps.steps,
        currentStepIndex: idx,
        distanceText: withSteps.result.distanceText,
        durationText: withSteps.result.durationText,
        durationSeconds: withSteps.result.durationSeconds,
        warnings: withSteps.result.warnings,
        tollInfoText: withSteps.result.tollInfoText,
        trafficSegments: withSteps.trafficSegments,
      ),
    );
  }

  void _persistOfflineOrderNavFromSteps({
    required OrderModel order,
    required DirectionsResultWithSteps withSteps,
    required double destLat,
    required double destLng,
    required bool navigatingToDestination,
    int? stepIndexOverride,
  }) {
    final idx = stepIndexOverride ??
        (_currentStepIndex >= 0 ? _currentStepIndex : 0);
    unawaited(
      OfflineNavRouteCacheService.saveOrderNavigation(
        orderId: order.id,
        navigatingToDestination: navigatingToDestination,
        destLat: destLat,
        destLng: destLng,
        polyline: withSteps.result.points,
        steps: withSteps.steps,
        currentStepIndex: idx,
        distanceText: withSteps.result.distanceText,
        durationText: withSteps.result.durationText,
        durationSeconds: withSteps.result.durationSeconds,
        warnings: withSteps.result.warnings,
        tollInfoText: withSteps.result.tollInfoText,
        trafficSegments: withSteps.trafficSegments,
      ),
    );
  }

  /// Update cache offline dengan indeks langkah TBT terbaru (polyline & langkah sama seperti sesi aktif).
  void _persistOfflineNavSnapshotForStep(int stepIdx) {
    if (_routeSteps.isEmpty) return;
    final clamped = stepIdx.clamp(0, _routeSteps.length - 1);

    List<LatLng>? poly;
    if (_navigatingToOrderId != null) {
      poly = _navigatingToDestination
          ? _polylineToDestination
          : _polylineToPassenger;
    } else if (_isDriverWorking) {
      poly = _routePolyline;
    }
    if (poly == null || poly.length < 2) return;

    final distM = RouteUtils.polylineLengthMeters(poly);
    final distKm = distM / 1000.0;
    final orderNav = _navigatingToOrderId != null;
    final distanceText = orderNav
        ? _routeToPassengerDistanceText
        : _routeDistanceText;
    final durationText = orderNav
        ? _routeToPassengerDurationText
        : _routeDurationText;
    final durationSeconds = orderNav
        ? (_routeToPassengerDurationSeconds ?? 0)
        : (_routeEstimatedDurationSeconds ?? 0);

    final result = DirectionsResult(
      points: poly,
      distanceKm: distKm,
      distanceText: distanceText,
      durationSeconds: durationSeconds,
      durationText: durationText,
      tollInfoText: _routeTollInfo,
      warnings: _routeWarnings,
    );
    final withSteps = DirectionsResultWithSteps(
      result: result,
      steps: _routeSteps,
      trafficSegments:
          List<RoutePolylineTrafficSegment>.from(_activeRouteTrafficSegments),
    );

    if (orderNav) {
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
        (destLat, destLng) = _getOrderDestinationLatLng(navOrder);
      } else {
        destLat = navOrder.passengerLiveLat ??
            navOrder.passengerLat ??
            navOrder.originLat;
        destLng = navOrder.passengerLiveLng ??
            navOrder.passengerLng ??
            navOrder.originLng;
      }
      if (destLat == null || destLng == null) return;
      _persistOfflineOrderNavFromSteps(
        order: navOrder,
        withSteps: withSteps,
        destLat: destLat,
        destLng: destLng,
        navigatingToDestination: _navigatingToDestination,
        stepIndexOverride: clamped,
      );
    } else {
      if (_routeDestLatLng == null) return;
      unawaited(
        OfflineNavRouteCacheService.saveWorkRoute(
          destLat: _routeDestLatLng!.latitude,
          destLng: _routeDestLatLng!.longitude,
          polyline: poly,
          steps: _routeSteps,
          currentStepIndex: clamped,
          distanceText: distanceText,
          durationText: durationText,
          durationSeconds: durationSeconds,
          warnings: _routeWarnings,
          tollInfoText: _routeTollInfo,
          trafficSegments:
              List<RoutePolylineTrafficSegment>.from(_activeRouteTrafficSegments),
        ),
      );
    }
  }

  Future<void> _openNavPremiumPaymentScreen() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const DriverNavPremiumPaymentScreen(),
      ),
    );
    if (mounted) await _refreshNavPremiumOwed();
  }

  Future<void> _showDriverNavPremiumInfoSheet() async {
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    final exempt =
        _navPremiumPhoneExemptCache || await DriverNavPremiumService.fetchPhoneExempt(forceRefresh: true);
    if (mounted) setState(() => _navPremiumPhoneExemptCache = exempt);
    if (!mounted) return;
    await showTrakaModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: bottomInset + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.driverNavPremiumInfoTitle,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.driverNavPremiumInfoIntro,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.driverNavPremiumInfoBullet1,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.driverNavPremiumInfoBullet2,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.driverNavPremiumInfoBullet3,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.driverNavPremiumWhyPaid,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (exempt) ...[
                  const SizedBox(height: 16),
                  Text(
                    TrakaL10n.of(ctx).locale == AppLocale.id
                        ? 'Akun Anda termasuk pembebasan navigasi premium (daftar nomor di Pengaturan admin → Navigasi premium). Tidak perlu bayar lewat Play Store.'
                        : 'Your account is exempt from premium navigation billing (admin phone list). No in-app purchase required.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
                const SizedBox(height: 20),
                if (!exempt)
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(_openNavPremiumPaymentScreen());
                    },
                    child: Text(l10n.driverNavPremiumInfoCtaPay),
                  ),
                if (!exempt) const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.driverNavPremiumInfoClose),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<MapPickerResult?> _pickDestinationOnMapFromSheet(
    BuildContext sheetCtx, {
    required String destText,
    double? destLat,
    double? destLng,
  }) async {
    final pos = _currentPosition;
    final initial = await initialTargetForDestinationMapPickerWithLoading(
      context: sheetCtx,
      destText: destText,
      destLat: destLat,
      destLng: destLng,
      userLocation:
          pos != null ? LatLng(pos.latitude, pos.longitude) : null,
    );
    if (!mounted || !sheetCtx.mounted) return null;
    final device =
        pos != null ? LatLng(pos.latitude, pos.longitude) : null;
    final pickTitle = TrakaL10n.of(sheetCtx).pickOnMapActionLabel;
    return Navigator.of(sheetCtx).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapDestinationPickerScreen(
          initialCameraTarget: initial,
          deviceLocation: device,
          title: pickTitle,
          pinVariant: TrakaRoutePinVariant.destination,
        ),
      ),
    );
  }

  Future<void> _showDriverMapToolsMenu() async {
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    await showTrakaModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(l10n.offlineMapPrecacheTitle),
                subtitle: Text(
                  l10n.offlineMapPrecacheIntro,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const OfflineMapPrecacheScreen(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.mapToolsLacakHelpTitle),
                subtitle: Text(
                  l10n.mapToolsLacakHelpSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    showLacakTrackingInfoSheet(
                      context,
                      audience: LacakTrackingAudience.lacakDriverMap,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(l10n.pickOnMapActionLabel),
                subtitle: Text(
                  l10n.driverRoutePassengerMatchingHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!_canStartDriverWork) {
                    _showDriverVerificationGateDialog();
                    return;
                  }
                  unawaited(_openMapPickerStandaloneFromTools());
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Dari menu peta: buka picker; jika rute sudah dipilih, isi tujuan akhir.
  Future<void> _openMapPickerStandaloneFromTools() async {
    if (!mounted) return;
    final pos = _currentPosition;
    final initial = _routeDestLatLng ??
        _formDestPreviewNotifier.value ??
        (pos != null
            ? LatLng(pos.latitude, pos.longitude)
            : const LatLng(-3.3194, 114.5907));
    final device =
        pos != null ? LatLng(pos.latitude, pos.longitude) : null;
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapDestinationPickerScreen(
          initialCameraTarget: initial,
          deviceLocation: device,
          title: TrakaL10n.of(context).pickOnMapActionLabel,
          pinVariant: TrakaRoutePinVariant.destination,
        ),
      ),
    );
    if (r == null || !mounted) return;
    final dest = LatLng(r.lat, r.lng);
    _formDestPreviewNotifier.value = dest;
    if (_routeOriginLatLng != null && (_routeSelected || _isDriverWorking)) {
      setState(() {
        _routeDestLatLng = dest;
        _routeDestText = r.label;
      });
      await _persistCurrentRoute();
      if (_currentPosition != null) {
        unawaited(
          _maybeRerouteFromCurrentPosition(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            force: true,
            quiet: true,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TrakaL10n.of(context).locale == AppLocale.id
                ? 'Titik di peta tersimpan di pratinjau. Buka form rute (tombol biru) untuk memuat rute ke lokasi ini.'
                : 'Map point saved as preview. Open the route form to build a route to this location.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  double _gpsDistanceToActiveRouteMeters(List<LatLng> pl) {
    final p = _currentPosition;
    if (p == null) return 0;
    return RouteUtils.distanceToPolyline(
      LatLng(p.latitude, p.longitude),
      pl,
    );
  }

  /// Saat menyimpang jauh dari polyline, target kamera yang hanya «maju di garis biru»
  /// membuat titik pandang jauh dari posisi mobil → panah biru mentok pinggir/atas.
  /// Bobot 0 = sepenuhnya sepanjang rute; 1 = mengikuti mobil + [bearing] aktual.
  double _cameraOffRouteFramingWeight(double deviationMeters) {
    const start = 30.0;
    const end = 78.0;
    if (deviationMeters <= start) return 0;
    if (deviationMeters >= end) return 1;
    final t = (deviationMeters - start) / (end - start);
    return t * t * (3 - 2 * t);
  }

  /// Interpolasi bearing terpendek (untuk transisi heading-up → utara saat parkir lama).
  static double _lerpBearingDegrees(double fromDg, double toDg, double t) {
    if (t <= 0) return fromDg % 360;
    if (t >= 1) return toDg % 360;
    var from = fromDg % 360;
    final to = toDg % 360;
    var diff = to - from;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (from + diff * t) % 360;
  }

  /// Setelah ~22 dtk berhenti: blend perlahan ke peta utara ke atas; lampu merah tetap heading-up.
  static double _stationaryNorthUpBlendSeconds(double seconds) {
    if (seconds <= 22) return 0;
    final u = ((seconds - 22) / 16.0).clamp(0.0, 1.0);
    return u * u * (3 - 2 * u);
  }

  /// Titik pandang kamera di depan GPS (meter) — makin jauh, makin «ikon di bawah, jalan di atas»
  /// seperti Google Maps. Tetap dibatasi oleh [RouteUtils.pointAheadOnPolyline] maxDistance.
  double _getCameraOffsetAheadMeters() {
    final speedKmh = _currentSpeedMps * 3.6;
    if (speedKmh < 8) return 102.0 + speedKmh * 1.15;
    if (speedKmh < 25) return 111.2 + (speedKmh - 8) * 3.45;
    if (speedKmh < 50) return 169.85 + (speedKmh - 25) * 2.55;
    if (speedKmh < 85) return 233.6 + (speedKmh - 50) * 1.75;
    return 294.85 + (speedKmh - 85).clamp(0, 40) * 0.42;
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
      final navFollow =
          _isDriverWorking || _navigatingToOrderId != null;
      if (_interpolationProgress >= 1) {
        _displayedPosition = _targetPosition;
        _interpStartPos = null;
        _interpolationTimer?.cancel();
        if (!navFollow) {
          double bearing = 0;
          if (polyline != null && polyline.length >= 2 && _interpEndSeg >= 0) {
            bearing = RouteUtils.bearingOnPolylineAtPosition(
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
        }
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
          if (!navFollow) {
            _displayedBearing = bearing;
            _smoothedBearing = _smoothBearing(_smoothedBearing, bearing);
          }
        } else {
          final lat = start.latitude + (end.latitude - start.latitude) * t;
          final lng = start.longitude + (end.longitude - start.longitude) * t;
          _displayedPosition = LatLng(lat, lng);
          if (!navFollow) {
            final bearing = RouteUtils.bearingBetween(
              _displayedPosition!,
              _targetPosition!,
            );
            _displayedBearing = bearing;
            _smoothedBearing = _smoothBearing(_smoothedBearing, bearing);
          }
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
    final segmentM = Geolocator.distanceBetween(
      _displayedPosition!.latitude,
      _displayedPosition!.longitude,
      next.pos.latitude,
      next.pos.longitude,
    );
    final routeBd = _routeBearingDeltaForInterpolation(_displayedPosition!, next.pos);
    final durationMs = _navigationInterpolationDurationMs(
      elapsedSinceLastFixMs: 320,
      segmentMeters: segmentM,
      routeBearingDeltaDeg: routeBd,
    );
    _startInterpolation(durationMs: durationMs);
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
  static const double _bearingHysteresisDeg = 11.0;
  /// Sedikit lebih halus di jalan lurus agar rotasi kamera tidak «bergetar».
  static const double _bearingSmoothAlpha = 0.034;
  /// Belok besar: tetap responsif, sedikit lebih reda agar transisi kamera lembut.
  static const double _bearingSmoothAlphaTurn = 0.095;
  /// Hanya pakai alphaTurn saat belok besar (>30°).
  static const double _bearingTurnThresholdDeg = 30.0;
  /// Kecepatan minimum (m/s) untuk update bearing dari GPS (kurangi noise saat lambat).
  static const double _bearingMinSpeedMps = 3.5; // ~12.6 km/jam
  /// Di bawah ini = diam: bekukan bearing & target kamera di posisi mobil.
  static const double _stationarySpeedMps = 1.5; // ~5.4 km/jam

  /// Snap ikon ke polyline biru hanya jika GPS dalam radius ini. Di luar itu pakai
  /// koordinat GPS mentah — jalan baru / perkampungan yang belum ada di basemap
  /// Google (polyline mengikuti graf jaringan, bukan jalan fisik di lapangan).
  static const double _snapToRoutePolylineMaxMeters = 118.0;

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

  void _resetVoiceProximityState() {
    _voiceProximityBuckets.clear();
    _voiceProximityStepIndex = -1;
  }

  /// Pengumuman jarak ke manuver (500 / 200 / 80 m) untuk langkah yang terlihat seperti belokan.
  void _maybeAnnounceNavigationProximity(Position position) {
    if (VoiceNavigationService.instance.muted) return;
    if (_routeSteps.isEmpty ||
        _currentStepIndex < 0 ||
        _currentStepIndex >= _routeSteps.length) {
      return;
    }
    if (!_isDriverWorking && _navigatingToOrderId == null) return;

    final poly = _activeNavigationPolyline ??
        ((_routePolyline != null && _routePolyline!.length >= 2)
            ? _routePolyline
            : null);
    if (poly == null || poly.length < 2) return;

    final raw = LatLng(position.latitude, position.longitude);
    final pos = raw;
    var proj = RouteUtils.projectPointOntoPolyline(
      pos,
      poly,
      maxDistanceMeters: 320,
    );
    if (proj.$2 < 0) {
      proj = RouteUtils.projectPointOntoPolyline(
        pos,
        poly,
        maxDistanceMeters: 520,
      );
    }
    if (proj.$2 < 0) {
      proj = RouteUtils.projectPointOntoPolyline(
        raw,
        poly,
        maxDistanceMeters: 620,
      );
    }
    final seg = proj.$2;
    final ratio = proj.$3;
    if (seg < 0) return;
    final distM = RouteUtils.distanceAlongPolyline(poly, seg, ratio);
    final step = _routeSteps[_currentStepIndex];
    if (!_stepLooksLikeTurn(step)) return;

    if (_voiceProximityStepIndex != _currentStepIndex) {
      _voiceProximityStepIndex = _currentStepIndex;
      _voiceProximityBuckets.clear();
    }

    final remaining = step.endDistanceMeters - distM;
    if (remaining < -35 || remaining > 1650) return;

    const ordered = [80, 200, 500, 1000];
    int? chosen;
    for (final b in ordered) {
      if (_voiceProximityBuckets.contains(b)) continue;
      if (remaining <= b) {
        chosen = b;
        break;
      }
    }
    if (chosen == null) return;

    final now = DateTime.now();
    final minGapMs = chosen <= 200 ? 3400 : 4200;
    if (_lastVoiceCueAt != null &&
        now.difference(_lastVoiceCueAt!).inMilliseconds < minGapMs) {
      return;
    }

    for (final b in ordered) {
      if (b >= chosen) _voiceProximityBuckets.add(b);
    }
    _lastVoiceCueAt = now;
    final maneuver = InstructionFormatter.maneuverPhraseOnly(step);
    final String distPhrase;
    if (chosen >= 1000) {
      distPhrase = 'Sekitar satu kilometer lagi';
    } else if (chosen >= 200) {
      distPhrase = '$chosen meter lagi';
    } else {
      distPhrase = '$chosen meter lagi';
    }
    final cue = '$distPhrase, $maneuver';
    HapticFeedback.lightImpact();
    unawaited(VoiceNavigationService.instance.speakCue(cue));
  }

  /// Animate kamera — diselaraskan pola Google Maps navigation:
  /// - Jalan + di rute: heading-up, titik pandang di depan sepanjang polyline, zoom/tilt vs kecepatan.
  /// - Jalan + nyasar: campuran target mengikuti mobil (sudah ada) + zoom out / tilt landai ringan.
  /// - Berhenti pendek: tetap heading-up + sedikit jalan di depan (persimpangan).
  /// - Berhenti lama (~22s+): transisi lembut ke utara ke atas + target ke titik mobil.
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
      final rawCam = _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : null;
      final polyAnchor = (rawCam != null &&
              Geolocator.distanceBetween(
                    pos.latitude,
                    pos.longitude,
                    rawCam.latitude,
                    rawCam.longitude,
                  ) >
                  20)
          ? rawCam
          : pos;
      final isStationary = _currentSpeedMps < _stationarySpeedMps;

      if (hasPoly) {
        final pl = polyline;
        if (!isStationary) {
          _navCameraOffRouteWeight =
              _cameraOffRouteFramingWeight(_gpsDistanceToActiveRouteMeters(pl));
        } else {
          _navCameraOffRouteWeight =
              (_navCameraOffRouteWeight * 0.86).clamp(0.0, 1.0);
        }
      } else {
        _navCameraOffRouteWeight = 0.0;
      }

      double northUpBlend = 0.0;
      if (isStationary &&
          hasPoly &&
          _driverStoppedNavigatingAt != null) {
        final sec = DateTime.now()
                .difference(_driverStoppedNavigatingAt!)
                .inMilliseconds /
            1000.0;
        northUpBlend = _stationaryNorthUpBlendSeconds(sec);
      }

      final LatLng target;
      if (isStationary) {
        if (hasPoly && bearing.isFinite) {
          final aheadT =
              RouteUtils.offsetPoint(pos, bearing % 360, 22.0);
          target = LatLng(
            aheadT.latitude +
                (pos.latitude - aheadT.latitude) * northUpBlend,
            aheadT.longitude +
                (pos.longitude - aheadT.longitude) * northUpBlend,
          );
        } else {
          target = pos;
        }
      } else if (hasPoly) {
        final pl = polyline;
        final aheadBase = _getCameraOffsetAheadMeters();
        final w = _navCameraOffRouteWeight;
        final polyTarget = RouteUtils.pointAheadOnPolyline(
          polyAnchor,
          pl,
          aheadBase,
          maxDistanceMeters: 320,
        );
        if (w <= 0.0) {
          final headingPt = bearing.isFinite
              ? RouteUtils.offsetPoint(
                  pos,
                  bearing % 360,
                  aheadBase.clamp(72.0, 280.0),
                )
              : null;
          if (polyTarget != null && headingPt != null) {
            // Titik pandang utama mengikuti arah HP; polyline hanya men-stabilkan sedikit.
            target = LatLng(
              polyTarget.latitude * 0.18 + headingPt.latitude * 0.82,
              polyTarget.longitude * 0.18 + headingPt.longitude * 0.82,
            );
          } else {
            target = headingPt ?? polyTarget ?? pos;
          }
        } else if (!bearing.isFinite) {
          target = polyTarget ?? pos;
        } else {
          final br = bearing % 360.0;
          final aheadFollow =
              (aheadBase * (1.0 - 0.62 * w)).clamp(48.0, aheadBase);
          final followTarget = RouteUtils.offsetPoint(pos, br, aheadFollow);
          if (polyTarget == null || w >= 1.0) {
            target = followTarget;
          } else {
            target = LatLng(
              polyTarget.latitude +
                  (followTarget.latitude - polyTarget.latitude) * w,
              polyTarget.longitude +
                  (followTarget.longitude - polyTarget.longitude) * w,
            );
          }
        }
      } else {
        // Tanpa garis rute: heading GPS + titik pandang jauh ke depan (konsisten dengan ada polyline).
        final aheadM = _getCameraOffsetAheadMeters().clamp(100.0, 280.0);
        target = !isStationary && bearing.isFinite
            ? RouteUtils.offsetPoint(pos, bearing, aheadM)
            : pos;
      }
      final double camBearing;
      if (hasPoly) {
        camBearing = _lerpBearingDegrees(bearing, 0.0, northUpBlend);
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
      if (!snapFocus && distanceMeters < 2.5) {
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
        if (bearingDiff < 8.0) {
          _lastCameraTarget = target;
          _lastCameraBearing = camBearing;
          return;
        }
      }
      final duration = snapFocus
          ? const Duration(milliseconds: 420)
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
            tilt: _effectiveCameraTiltForNav(),
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

  /// Saat mulai kerja: langsung pakai jalur kamera yang sama dengan navigasi (target di depan, heading-up).
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
      _hasShownMapGestureTrackingHint = false;
      _lastCameraTarget = null;
      _lastCameraBearing = null;
      _cameraFollowEngine.resetThrottle();
      _suppressNextCameraMoveStarted = true;
      _updateDisplayedZoomTilt();
      _animateCameraToDisplayed(_smoothedBearing, force: true, snapFocus: true);
    } catch (_) {}
  }

  /// Tombol Fokus: recenter ke mobil, kembali ke mode ikuti (Google Maps–style).
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
    final navActive = _isDriverWorking || _navigatingToOrderId != null;
    if (navActive) {
      unawaited(_ensureDriverNavigationPositionStream());
      // Stream = sumber utama titik GPS; timer ini untuk cek tujuan + fallback jika stream diam.
      _locationRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
        final silent = _lastDriverNavStreamAt == null ||
            DateTime.now().difference(_lastDriverNavStreamAt!).inSeconds > 14;
        if (silent && mounted) {
          await _getCurrentLocation(forTracking: true);
        }
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
    } else {
      _cancelDriverNavigationPositionStream();
      _lastDriverNavStreamAt = null;
      // Bukan Siap Kerja / navigasi order: jarang bangunkan GPS (hemat baterai & data).
      _locationRefreshTimer = Timer.periodic(const Duration(seconds: 120), (_) async {
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
  }

  void _cancelDriverNavigationPositionStream() {
    _driverNavPositionSub?.cancel();
    _driverNavPositionSub = null;
  }

  Future<void> _ensureDriverNavigationPositionStream() async {
    if (_driverNavPositionSub != null) return;
    if (!(_isDriverWorking || _navigatingToOrderId != null)) return;
    final ok = await LocationService.requestPermission();
    if (!ok || !mounted) return;
    if (mounted) {
      await LocationService.promptBackgroundLocationForLiveTrackingIfNeeded(
        context,
        kind: LiveLocationBackgroundPromptKind.driverNavigation,
      );
    }
    if (!mounted) return;
    if (!await Geolocator.isLocationServiceEnabled()) return;
    try {
      _driverNavPositionSub =
          LocationService.driverHighFrequencyPositionStream().listen(
        (pos) {
          unawaited(_onDriverNavigationStreamPosition(pos));
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  Future<void> _onDriverNavigationStreamPosition(Position position) async {
    if (!mounted) return;
    if (position.isMocked && !kDisableFakeGpsCheck) {
      final allowed = await ExemptionService.isCurrentUserFakeGpsAllowed();
      if (!allowed) {
        if (mounted) FakeGpsOverlayService.showOverlay();
        return;
      }
    }
    _lastDriverNavStreamAt = DateTime.now();
    await _applyDriverGpsPosition(position, forTracking: true);
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

  void _onFormRoutePreviewChanged() {
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
    if (mounted) _syncMapDeviceTiltSession();
  }

  @override
  void dispose() {
    NavigationSettingsService.dataSaverNotifier
        .removeListener(_onNavigationDataSaverChanged);
    _locationPulseController
      ..removeListener(_onLocationPulseTick)
      ..dispose();
    NotificationNavigationService.unregisterOpenProfileTab();
    WidgetsBinding.instance.removeObserver(this);
    MapDeviceTiltService.instance
      ..removeListener(_onDeviceTiltChanged)
      ..stopListening();
    _authTokenRefreshTimer?.cancel();
    _sessionInvalidCheckTimer?.cancel();
    _authStateSub?.cancel();
    WakelockPlus.disable();
    _formDestPreviewNotifier.removeListener(_onFormRoutePreviewChanged);
    _formDestPreviewNotifier.dispose();
    _disposeDriverOrdersSub();
    _locationRefreshTimer?.cancel();
    _cancelDriverNavigationPositionStream();
    _interpolationTimer?.cancel();
    _movementDebounceTimer?.cancel();
    _rerouteStatusClearTimer?.cancel();
    _trafficAlternativesCheckTimer?.cancel();
    _driverOrdersUiDebounce?.cancel();
    _pendingJadwalSafetyTimer?.cancel();
    _routeAdminKeysResolveTimer?.cancel();
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

  void _cancelRouteAdminKeysResolve() {
    _routeAdminKeysResolveTimer?.cancel();
    _routeAdminKeysResolveGen++;
  }

  void _resetRouteAdminKeysFields() {
    _routeOriginKabKey = null;
    _routeDestKabKey = null;
    _routeOriginProvKey = null;
    _routeDestProvKey = null;
    _adminKeysCachedOLat = null;
    _adminKeysCachedOLng = null;
    _adminKeysCachedDLat = null;
    _adminKeysCachedDLng = null;
  }

  void _scheduleRouteAdminKeysResolve() {
    _routeAdminKeysResolveTimer?.cancel();
    if (_routeOriginLatLng == null ||
        _routeDestLatLng == null ||
        !_isDriverWorking) {
      return;
    }
    _routeAdminKeysResolveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_resolveRouteAdminKeys());
    });
  }

  Future<void> _resolveRouteAdminKeys() async {
    final o = _routeOriginLatLng;
    final d = _routeDestLatLng;
    if (o == null || d == null || !mounted || !_isDriverWorking) return;

    final oLat = o.latitude;
    final oLng = o.longitude;
    final dLat = d.latitude;
    final dLng = d.longitude;

    final startGen = _routeAdminKeysResolveGen;

    if (_adminKeysCachedOLat == oLat &&
        _adminKeysCachedOLng == oLng &&
        _adminKeysCachedDLat == dLat &&
        _adminKeysCachedDLng == dLng) {
      return;
    }

    final originReg = await TravelAdminRegion.fromCoordinates(oLat, oLng);
    final destReg = await TravelAdminRegion.fromCoordinates(dLat, dLng);
    if (!mounted || startGen != _routeAdminKeysResolveGen) return;

    final o2 = _routeOriginLatLng;
    final d2 = _routeDestLatLng;
    if (o2 == null ||
        d2 == null ||
        o2.latitude != oLat ||
        o2.longitude != oLng ||
        d2.latitude != dLat ||
        d2.longitude != dLng ||
        !_isDriverWorking) {
      return;
    }

    setState(() {
      _routeOriginKabKey = originReg?.kabupatenKey;
      _routeOriginProvKey = originReg?.provinceKey;
      _routeDestKabKey = destReg?.kabupatenKey;
      _routeDestProvKey = destReg?.provinceKey;
      _adminKeysCachedOLat = oLat;
      _adminKeysCachedOLng = oLng;
      _adminKeysCachedDLat = dLat;
      _adminKeysCachedDLng = dLng;
    });
    final pos = _currentPosition;
    if (pos != null && _isDriverWorking) {
      unawaited(_updateDriverStatusToFirestore(pos));
    }
  }

  /// Mengembalikan state setelah [getAlternativeRoutes] gagal — jangan biarkan UI "aktif" tanpa polyline.
  void _revertOptimisticRouteRestoreFailure() {
    if (!mounted) return;
    _cancelRouteAdminKeysResolve();
    setState(() {
      _isDriverWorking = false;
      _routePolyline = null;
      _activeRouteTrafficSegments = [];
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
      _resetRouteAdminKeysFields();
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
      trafficAware: _directionsTrafficAware,
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
      final offline = await OfflineNavRouteCacheService.loadWorkRouteMatch(
        destLat: dLat,
        destLng: dLng,
      );
      if (offline != null && mounted) {
        var journeyNumber = firestoreRoute?.routeJourneyNumber;
        if (journeyNumber == null || journeyNumber.isEmpty) {
          journeyNumber =
              await RouteJourneyNumberService.generateRouteJourneyNumber();
        }
        if (!mounted) return;
        final w = offline.data;
        final startedAt = DateTime.now();
        setState(() {
          _routeRestoreAwaitingPolyline = false;
          _routeOriginLatLng = LatLng(oLat, oLng);
          _routeDestLatLng = LatLng(dLat, dLng);
          _routeOriginText = originText;
          _routeDestText = destText;
          _routePolyline = w.result.points;
          _routeDistanceText = w.result.distanceText;
          _routeDurationText = w.result.durationText;
          _alternativeRoutes = [w.result];
          _selectedRouteIndex = 0;
          _routeSelected = true;
          _originalRouteIndex = 0;
          _lastRouteSwitchTime = null;
          _isDriverWorking = true;
          _destinationReachedAt = null;
          _routeJourneyNumber = journeyNumber;
          _routeStartedAt = firestoreRoute?.routeStartedAt ?? startedAt;
          _routeEstimatedDurationSeconds =
              firestoreRoute?.estimatedDurationSeconds ??
              w.result.durationSeconds;
          _activeRouteFromJadwal = fromJadwal ?? false;
          _routeSteps = w.steps;
          _activeRouteTrafficSegments = w.trafficSegments;
          _currentStepIndex = offline.currentStepIndex;
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
        _registerRouteBackgroundHandler();
        await _persistCurrentRoute();
        if (_currentPosition != null) {
          unawaited(_updateDriverStatusToFirestore(_currentPosition!));
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final pos = _currentPosition;
            if (pos != null && _isDriverWorking) {
              await _updateDriverStatusToFirestore(pos);
            }
          });
        }
        _restartLocationTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TrakaL10n.of(context).locale == AppLocale.id
                    ? 'Memakai petunjuk jalan terakhir yang tersimpan (koneksi terbatas).'
                    : 'Using last saved turn-by-turn (limited connectivity).',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
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
      _activeRouteTrafficSegments = [];
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

  void _updateGpsAccuracyHintFromPosition(Position position) {
    final nav = _isDriverWorking || _navigatingToOrderId != null;
    if (!nav) {
      if (_showGpsAccuracyHint || _gpsAccuracyHintDismissed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _showGpsAccuracyHint = false;
            _gpsAccuracyHintDismissed = false;
            _lastGpsAccuracyMeters = null;
          });
        });
      }
      return;
    }
    final acc = position.accuracy;
    if (!acc.isFinite || acc <= 0) return;
    _lastGpsAccuracyMeters = acc;
    if (acc <= _gpsAccuracyOkMeters) {
      if (_showGpsAccuracyHint || _gpsAccuracyHintDismissed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _showGpsAccuracyHint = false;
            _gpsAccuracyHintDismissed = false;
          });
        });
      }
      return;
    }
    if (acc >= _gpsAccuracyPoorMeters && !_gpsAccuracyHintDismissed) {
      if (!_showGpsAccuracyHint) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _showGpsAccuracyHint = true);
        });
      }
    }
  }

  /// Terapkan satu sampel GPS ke peta, interpolasi, Firestore, TTS (dipakai stream + polling).
  Future<void> _applyDriverGpsPosition(Position position, {required bool forTracking}) async {
    if (!mounted) return;
    final applyToken = ++_applyDriverGpsToken;
    _currentPosition = position;

    _updateGpsAccuracyHintFromPosition(position);
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
        maxDistanceMeters: _snapMaxMetersForSpeed(),
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
      final blend = (_isDriverWorking || _navigatingToOrderId != null) ? 0.05 : 0.12;
      targetPos = LatLng(
        targetPos.latitude * (1.0 - blend) + predicted.latitude * blend,
        targetPos.longitude * (1.0 - blend) + predicted.longitude * blend,
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

    // Beranda (bukan mode kerja / navigasi order): jitter antar fix → EMA «kecepatan» tetap
    // positif sehingga panah biru muncul padahal belum bergerak. Rem jika perpindahan kecil
    // dan perangkat tidak melaporkan gerak nyata.
    if (!_isDriverWorking && _navigatingToOrderId == null) {
      final prev = _lastPositionForSpeed;
      if (prev != null) {
        final distQuiet = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          position.latitude,
          position.longitude,
        );
        final spd = position.speed;
        final deviceReportsMoving = spd.isFinite &&
            spd >= 0 &&
            spd < 55 &&
            spd >= 1.15; // ~4 km/j — di bawah ini anggap diam / noise
        if (distQuiet < 2.8 && !deviceReportsMoving) {
          _currentSpeedMps *= 0.52;
          if (_currentSpeedMps < 0.18) {
            _currentSpeedMps = 0.0;
          }
        }
      }
    }

    if (_isDriverWorking || _navigatingToOrderId != null) {
      final stopped = _currentSpeedMps < _stationarySpeedMps;
      if (stopped) {
        _driverStoppedNavigatingAt ??= DateTime.now();
      } else {
        _driverStoppedNavigatingAt = null;
      }
    } else {
      _driverStoppedNavigatingAt = null;
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
      final lagMeters = Geolocator.distanceBetween(
        _displayedPosition!.latitude,
        _displayedPosition!.longitude,
        rawLatLng.latitude,
        rawLatLng.longitude,
      );
      final forceSnap = (_isDriverWorking || _navigatingToOrderId != null) &&
          lagMeters > 34.0;
      final isAnimating = _interpolationTimer?.isActive ?? false;
      if (forceSnap) {
        _interpolationTimer?.cancel();
        _positionQueue.clear();
        _displayedPosition = targetPos;
        _targetPosition = targetPos;
        _interpEndSeg = targetSeg;
        _interpEndRatio = targetRatio;
        _interpStartPos = null;
        _interpolationProgress = 0;
        _lastPositionTimestamp = position.timestamp;
      } else if (isAnimating) {
        _enqueuePosition(targetPos, targetSeg, targetRatio);
      } else {
        _targetPosition = targetPos;
        _interpEndSeg = targetSeg;
        _interpEndRatio = targetRatio;
        final now = position.timestamp;
        final elapsedMs = _lastPositionTimestamp != null
            ? now.difference(_lastPositionTimestamp!).inMilliseconds
            : 800;
        _lastPositionTimestamp = now;
        final segmentM = Geolocator.distanceBetween(
          _displayedPosition!.latitude,
          _displayedPosition!.longitude,
          targetPos.latitude,
          targetPos.longitude,
        );
        final routeBd =
            _routeBearingDeltaForInterpolation(_displayedPosition!, targetPos);
        final durationMs = _navigationInterpolationDurationMs(
          elapsedSinceLastFixMs: elapsedMs,
          segmentMeters: segmentM,
          routeBearingDeltaDeg: routeBd,
        );
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
        final farFromLine =
            routeDeviationMeters >= _refetchNavRouteNearDeviationMeters;
        final debounceDist = farFromLine
            ? _refetchNavRouteDistanceWhenFarMeters
            : _rerouteDebounceDistanceMeters;
        final shouldRefetch = lastFetch == null ||
            Geolocator.distanceBetween(
                  lastFetch.latitude,
                  lastFetch.longitude,
                  rawLatLng.latitude,
                  rawLatLng.longitude,
                ) >
                debounceDist;
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
            routeDeviationMeters: routeDeviationMeters,
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

    // Deteksi pergerakan: jarak antar sample ATAU kecepatan tersaring (GPS speed Android sering 0).
    bool isMoving = false;
    if (_isDriverWorking) {
      final speedKmhFiltered = _currentSpeedMps * 3.6;
      if (_lastPositionForMovement != null) {
        final distance = Geolocator.distanceBetween(
          _lastPositionForMovement!.latitude,
          _lastPositionForMovement!.longitude,
          position.latitude,
          position.longitude,
        );
        isMoving = distance > 3.5 || speedKmhFiltered >= 1.6;
      } else if (_positionWhenStarted != null) {
        final distance = Geolocator.distanceBetween(
          _positionWhenStarted!.latitude,
          _positionWhenStarted!.longitude,
          position.latitude,
          position.longitude,
        );
        isMoving = distance > 8 || speedKmhFiltered >= 1.6;
      } else {
        isMoving = speedKmhFiltered >= 1.6;
      }

      // Bearing: polyline + lookahead (jalan lurus), fusion heading saat salah arah vs rute;
      // GPS heading saat jalan cukup kencang tanpa polyline dekat.
      double rawBearing = 0.0;
      bool skipBearingUpdate = false;
      final speedMps = _effectiveSpeedMps(position);
      final isStationary = !speedMps.isFinite || speedMps < _stationarySpeedMps;
      if (polyline != null && polyline.length >= 2 && targetSeg >= 0) {
        final routeBearing = RouteUtils.bearingOnPolylineAtPosition(
          rawLatLng,
          polyline,
          segmentIndex: targetSeg,
          ratio: targetRatio,
        );
        // Panah mengikuti heading perangkat saat bergerak (bukan terikat polyline).
        if (position.heading.isFinite &&
            (speedMps >= _bearingMinSpeedMps ||
                routeDeviationMeters >= 38) &&
            !isStationary) {
          rawBearing = position.heading % 360;
        } else {
          rawBearing = routeBearing;
        }
      } else if (!isStationary && position.heading.isFinite) {
        rawBearing = position.heading;
        if (!speedMps.isFinite || speedMps < _bearingMinSpeedMps) {
          skipBearingUpdate = true;
        }
      } else if (polyline != null && polyline.length >= 2) {
        rawBearing = RouteUtils.bearingBetween(rawLatLng, polyline.last);
      } else if (isStationary) {
        skipBearingUpdate = true;
      }
      if (!skipBearingUpdate) {
        _displayedBearing = rawBearing;
        final prevSmoothed = _smoothedBearing;
        var nextSmoothed = _smoothBearing(_smoothedBearing, rawBearing);
        final trust = _gpsAccuracyTrustForBearing(position.accuracy);
        if (trust < 0.91) {
          nextSmoothed = RouteUtils.smoothBearingDegrees(
            prevSmoothed,
            nextSmoothed,
            alpha: trust.clamp(0.12, 1.0),
          );
        }
        _smoothedBearing = nextSmoothed;
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
      if (!mounted || applyToken != _applyDriverGpsToken) return;
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

    if ((_isDriverWorking || _navigatingToOrderId != null) &&
        _routeSteps.isNotEmpty) {
      _refreshTbtRemainingFromPosition(position);
      _maybeAnnounceNavigationProximity(position);
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
    // Jangan await di sini: POST hybrid + Roads di server bisa lambat → memblokir
    // interpolasi & kamera; ikon tertinggal km dan UI terasa macet.
    if (_isDriverWorking &&
        (_lastUpdatedTime == null || _shouldUpdateFirestore(position))) {
      unawaited(_updateDriverStatusToFirestore(position));
    }

    if (!mounted || applyToken != _applyDriverGpsToken) return;

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
        await _applyDriverGpsPosition(position, forTracking: forTracking);
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
              _activeRouteTrafficSegments = [];
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
              routeOriginKabKey: _routeOriginKabKey,
              routeDestKabKey: _routeDestKabKey,
              routeOriginProvKey: _routeOriginProvKey,
              routeDestProvKey: _routeDestProvKey,
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
              _activeRouteTrafficSegments = [];
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
              routeOriginKabKey: _routeOriginKabKey,
              routeDestKabKey: _routeDestKabKey,
              routeOriginProvKey: _routeOriginProvKey,
              routeDestProvKey: _routeDestProvKey,
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
    if (_isDriverWorking &&
        _routeOriginLatLng != null &&
        _routeDestLatLng != null) {
      _scheduleRouteAdminKeysResolve();
    }
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
        routeOriginKabKey: _routeOriginKabKey,
        routeDestKabKey: _routeDestKabKey,
        routeOriginProvKey: _routeOriginProvKey,
        routeDestProvKey: _routeDestProvKey,
      );
      // Update tracking untuk pengecekan berikutnya
      _consecutiveDriverStatusWriteFailures = 0;
      _lastUpdatedPosition = position;
      _lastUpdatedTime = DateTime.now();
      if (mounted) setState(() {});
    } catch (e, st) {
      logError('DriverScreen._updateDriverStatusToFirestore', e, st);
      if (!mounted) return;
      _consecutiveDriverStatusWriteFailures++;
      if (_consecutiveDriverStatusWriteFailures >= 5) {
        _consecutiveDriverStatusWriteFailures = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lokasi driver tidak terkirim beberapa kali. Periksa jaringan lalu coba lagi.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      }
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
    _rerouteStatusClearTimer?.cancel();
    _cancelRouteAdminKeysResolve();
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
      _activeRouteTrafficSegments = [];
      _currentStepIndex = -1;
      _tbtRemainingMeters = null;
      _tbtNextStepRemainingMeters = null;
      _rerouteStatusBanner = null;
      _routeStepsHydrateRequested = false;
      _lastMissedTurnRerouteAt = null;
      _routeRecalculateDepth = 0;
      _routeOriginLatLng = null;
      _routeDestLatLng = null;
      _routeOriginText = '';
      _routeDestText = '';
      _resetRouteAdminKeysFields();
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
      _displayedZoom = 16.65;
      _displayedTilt = 22.0;
      _currentSpeedMps = 0.0;
      _lastEtaThrottleDest = null;
      _lastDirectionsEtaFetchAt = null;
      _lastDirectionsEtaFetchPosition = null;
    });
    _resetVoiceProximityState();
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
    if (_driverStartWorkCheckFuture != null) {
      // Jangan tunggu future lama (bisa ~20+ detik) — tap ulang harus segera memulai cek baru.
      _startWorkCheckGen++;
      _startWorkLoadingSnackTimer?.cancel();
      _startWorkLoadingSnackTimer = null;
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
      _driverStartWorkCheckFuture = null;
    }

    Future<void> guardedRun() async {
      try {
        await _checkScheduledOrdersThenShowRouteSheetBody()
            .timeout(const Duration(seconds: 12));
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
    // SnackBar baru setelah jeda lama — sebagian besar cek selesai dari cache; kalau 450ms snack
    // sering muncul lalu menggantung saat antrean tulis jadwal penuh.
    _startWorkLoadingSnackTimer?.cancel();
    if (mounted) {
      // Hanya jika masih perlu nunggu query Firestore (stream belum pernah emit).
      _startWorkLoadingSnackTimer = Timer(const Duration(milliseconds: 2800), () {
        _startWorkLoadingSnackTimer = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memeriksa pesanan terjadwal…'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 8),
          ),
        );
      });
    }
    var postedFollowUpSnack = false;
    try {
      // Stream beranda: hindari query orders tambahan (sering mengantre di belakang tulis jadwal besar).
      var orders = OrderService.scheduledOrdersWithAgreedFromList(_driverOrders);
      final needsFirestoreOrders =
          orders.isEmpty && !_driverOrdersStreamReady;
      if (!needsFirestoreOrders) {
        _startWorkLoadingSnackTimer?.cancel();
        _startWorkLoadingSnackTimer = null;
      }
      if (needsFirestoreOrders) {
        orders = await OrderService.getDriverScheduledOrdersWithAgreed();
      }
      if (mounted) {
        _startWorkLoadingSnackTimer?.cancel();
        _startWorkLoadingSnackTimer = null;
        ScaffoldMessenger.of(context).clearSnackBars();
      }
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
          postedFollowUpSnack = true;
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
      // Tutup snack "Memeriksa…" jika masih terpasang; jangan hapus snack susulan (instruksi rute).
      if (mounted && !postedFollowUpSnack) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    }
  }

  /// Bersihkan rute draf (alternatif ada tapi belum dipilih / state setengah dari jadwal), lalu alur Siap Kerja dari awal.
  void _clearDraftRoutesAndOpenStartFlow() {
    if (!_canStartDriverWork) {
      _showDriverVerificationGateDialog();
      return;
    }
    _resetJourneyNumberPrefetch();
    _cancelRouteAdminKeysResolve();
    setState(() {
      _pendingJadwalRouteLoad = false;
      _isStartRouteLoading = false;
      _routeRestoreAwaitingPolyline = false;
      _alternativeRoutes = [];
      _selectedRouteIndex = -1;
      _routePolyline = null;
      _activeRouteTrafficSegments = [];
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
      _resetRouteAdminKeysFields();
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
      unawaited(_scheduleDriverGpsBatteryHintIfNeeded());
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
  static const String _keyDriverGpsBatteryHintShown =
      'driver_gps_battery_hint_shown_v1';

  /// Setelah mulai kerja: ingatkan sekali soal penghemat baterai vs GPS (jeda agar tidak tabrakan dengan SnackBar).
  Future<void> _scheduleDriverGpsBatteryHintIfNeeded() async {
    if (kIsWeb) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _maybeShowDriverGpsBatteryHintOnce();
  }

  Future<void> _maybeShowDriverGpsBatteryHintOnce() async {
    if (kIsWeb || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyDriverGpsBatteryHintShown) == true) return;
      if (!mounted) return;
      final l10n = TrakaL10n.of(context);
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.driverStartWorkBatteryTitle),
          content: SingleChildScrollView(
            child: Text(l10n.driverStartWorkBatteryBody),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.driverStartWorkBatteryOk),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await AppSettings.openAppSettings();
              },
              child: Text(l10n.driverStartWorkBatteryOpenSettings),
            ),
          ],
        ),
      );
      await prefs.setBool(_keyDriverGpsBatteryHintShown, true);
    } catch (_) {}
  }

  Future<void> _showDriverMapHintOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyDriverMapHintShown) == true) return;
      await prefs.setBool(_keyDriverMapHintShown, true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Ini posisi Anda. Garis biru = rute Anda. Geser peta untuk lihat jalan lain.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (_) {}
  }

  void _showRouteInfoBottomSheet() {
    if (_routeInfoSheetOpen) return;
    _routeInfoSheetOpen = true;
    showTrakaModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
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
                  padding: const EdgeInsets.only(bottom: 24),
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
    ).whenComplete(() {
      _routeInfoSheetOpen = false;
    });
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
    if (_operDriverSheetOpen) return;
    _operDriverSheetOpen = true;
    showOperDriverSheet(
      context,
      orders: pickedUpOrders,
      onTransfersCreated: (transfers) =>
          showOperDriverBarcodeDialog(context, transfers: transfers),
    ).whenComplete(() {
      _operDriverSheetOpen = false;
    });
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

    showTrakaModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
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
                iconBackground:
                    AppTheme.mapDeliveryAccent.withValues(alpha: 0.12),
                iconColor: AppTheme.mapDeliveryAccent,
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

  /// Titik awal permintaan Directions: [nominalOrigin] (geocode jadwal / form). Jika mobil cukup jauh + GPS oke, pakai posisi driver — sama untuk jadwal maupun Siap Kerja.
  ({double lat, double lng, bool routeStartsFromDriver})
      _directionsOriginFromDriverIfFarFromNominal(
    double nominalOriginLat,
    double nominalOriginLng,
  ) {
    LatLng? car;
    if (_displayedPosition != null) {
      car = _displayedPosition;
    } else if (_currentPosition != null) {
      car = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    if (car == null) {
      return (
        lat: nominalOriginLat,
        lng: nominalOriginLng,
        routeStartsFromDriver: false,
      );
    }
    final distM = Geolocator.distanceBetween(
      car.latitude,
      car.longitude,
      nominalOriginLat,
      nominalOriginLng,
    );
    final acc = _currentPosition?.accuracy;
    final gpsOk = acc == null || acc <= 250;
    if (distM > _jadwalRouteStartFromDriverBeyondMeters && gpsOk) {
      return (
        lat: car.latitude,
        lng: car.longitude,
        routeStartsFromDriver: true,
      );
    }
    return (
      lat: nominalOriginLat,
      lng: nominalOriginLng,
      routeStartsFromDriver: false,
    );
  }

  /// Polyline di Firestore dipangkas (ringan); setelah peta tampil, satukan geometri halus dari Google Directions
  /// di latar — tanpa sheet pilih alternatif (tetap satu rute, [_routeSelected] true).
  Future<void> _refineJadwalPolylineWithGoogleDirections({
    required int loadGen,
    required String? scheduleId,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      var list = await DirectionsService.getAlternativeRoutes(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _directionsTrafficAware,
      );
      if (list.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || loadGen != _loadRouteFromJadwalGen) return;
        list = await DirectionsService.getAlternativeRoutes(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          trafficAware: false,
        );
      }
      if (!mounted || loadGen != _loadRouteFromJadwalGen) return;
      if (list.isEmpty) return;
      if (scheduleId != null &&
          scheduleId.isNotEmpty &&
          _currentScheduleId != scheduleId) {
        return;
      }
      final smooth = list.first;
      if (smooth.points.length < 2) return;
      if (!mounted || loadGen != _loadRouteFromJadwalGen) return;
      setState(() {
        _alternativeRoutes = [smooth];
        _selectedRouteIndex = 0;
        _routeSelected = true;
        _routePolyline = smooth.points;
        _routeDistanceText = smooth.distanceText;
        _routeDurationText = smooth.durationText;
        _activeRouteTrafficSegments = [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAlternativeRoutesBounds();
      });
    } catch (_) {}
  }

  /// Dari Jadwal & Rute (icon rute): muat rute dari tujuan awal/akhir jadwal.
  /// Bila [routePolyline] ada (disimpan saat buat jadwal), dulu garis cepat dari snapshot Firestore;
  /// lalu [_refineJadwalPolylineWithGoogleDirections] memperhalus di latar (satu rute, tanpa pilih lagi).
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
      final scheduleOriginLat = originLocations.first.latitude;
      final scheduleOriginLng = originLocations.first.longitude;
      final destLat = destLocations.first.latitude;
      final destLng = destLocations.first.longitude;

      final originAdj = _directionsOriginFromDriverIfFarFromNominal(
        scheduleOriginLat,
        scheduleOriginLng,
      );
      var originLat = originAdj.lat;
      var originLng = originAdj.lng;
      final routeStartsFromDriver = originAdj.routeStartsFromDriver;

      List<DirectionsResult> alternatives;
      int preSelectedIndex;
      bool preSelected;

      // Polyline tersimpan = jadwal O→D dari geocode; tidak cocok jika garis dimulai dari mobil.
      DirectionsResult? savedFromPolyline;
      if (!routeStartsFromDriver &&
          routePolyline != null &&
          routePolyline.length >= 2) {
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

      if (savedFromPolyline != null) {
        // Rute sudah dipilih saat buat jadwal: satu garis saja, langsung siap "Mulai Rute"
        // (jangan panggil Directions untuk alternatif — hindari pilih rute lagi di beranda).
        alternatives = [savedFromPolyline];
        preSelectedIndex = 0;
        preSelected = true;
      } else {
        var apiAlternatives = await DirectionsService.getAlternativeRoutes(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
          trafficAware: _directionsTrafficAware,
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
        alternatives = apiAlternatives;
        // Sama seperti Siap Kerja: satu alternatif → langsung dipilih (boleh Mulai Rute ini).
        if (alternatives.length == 1) {
          preSelectedIndex = 0;
          preSelected = true;
        } else {
          preSelectedIndex = -1;
          preSelected = false;
        }
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
        _activeRouteTrafficSegments = [];
        _activeRouteFromJadwal = true;
        _currentScheduleId = scheduleId;
        _currentRouteCategory = routeCategory;
        _pendingJadwalRouteLoad = false;
        if (preSelected && selRoute != null) {
          _routeEstimatedDurationSeconds = selRoute.durationSeconds;
          _routeStartedAt = DateTime.now();
          if (scheduleId != null && scheduleId.isNotEmpty) {
            _routeJourneyNumber = OrderService.routeJourneyNumberScheduled;
          } else {
            _routeJourneyNumber = null;
            unawaited(_awaitJourneyNumberAfterSelectWithSnacks());
          }
        } else {
          _routeEstimatedDurationSeconds = null;
          _routeStartedAt = null;
          _routeJourneyNumber = null;
        }
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
              content: Text(
                routeStartsFromDriver
                    ? 'Rute dari lokasi Anda ke tujuan jadwal. Pilih garis di peta jika ada beberapa alternatif.'
                    : TrakaL10n.of(context).selectRouteOnMapHint,
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitAlternativeRoutesBounds();
        });
        if (savedFromPolyline != null) {
          unawaited(
            _refineJadwalPolylineWithGoogleDirections(
              loadGen: loadGen,
              scheduleId: scheduleId,
              originLat: originLat,
              originLng: originLng,
              destLat: destLat,
              destLng: destLng,
            ),
          );
        }
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
      if (loadGen == _loadRouteFromJadwalGen && _pendingJadwalRouteLoad) {
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

    final originAdj = _directionsOriginFromDriverIfFarFromNominal(
      newOrigin.latitude,
      newOrigin.longitude,
    );
    final dirOriginLat = originAdj.lat;
    final dirOriginLng = originAdj.lng;
    final routeStartsFromDriver = originAdj.routeStartsFromDriver;

    var alternatives = await DirectionsService.getAlternativeRoutes(
      originLat: dirOriginLat,
      originLng: dirOriginLng,
      destLat: newDest.latitude,
      destLng: newDest.longitude,
      trafficAware: _directionsTrafficAware,
    );
    if (!mounted) return;
    if (alternatives.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      alternatives = await DirectionsService.getAlternativeRoutes(
        originLat: dirOriginLat,
        originLng: dirOriginLng,
        destLat: newDest.latitude,
        destLng: newDest.longitude,
        trafficAware: false,
      );
    }
    if (!mounted) return;
    if (alternatives.isNotEmpty) {
      _resetJourneyNumberPrefetch();
      setState(() {
        _routeOriginLatLng = LatLng(dirOriginLat, dirOriginLng);
        _routeDestLatLng = newDest;
        _routeOriginText = prevDestText;
        _routeDestText = prevOriginText;
        _alternativeRoutes = alternatives;
        _isDriverWorking = false;
        _activeRouteFromJadwal = false;
        _currentScheduleId = null;
        if (alternatives.length > 1) {
          _selectedRouteIndex = -1;
          _routeSelected = false;
          _routePolyline = null;
          _activeRouteTrafficSegments = [];
          _routeDistanceText = '';
          _routeDurationText = '';
          _routeJourneyNumber = null;
          _routeEstimatedDurationSeconds = null;
          _routeStartedAt = null;
        }
      });
      if (alternatives.length == 1) {
        await _selectRouteAndStart(0);
      } else {
        _startJourneyNumberPrefetch();
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAlternativeRoutesBounds();
      });
      final l10n = TrakaL10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alternatives.length == 1
                ? 'Rute sudah dipilih. Tap Mulai Rute ini untuk mulai bekerja.'
                : routeStartsFromDriver
                ? 'Rute dari lokasi Anda ke tujuan. Pilih garis di peta jika ada beberapa alternatif.'
                : l10n.selectRouteOnMapHint,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TrakaL10n.of(context).failedToLoadRouteDirections,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
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
    if (_routeFormSheetOpen) return;
    _routeFormSheetOpen = true;
    unawaited(TrakaPinBitmapService.ensureLoaded(context));
    final currentContext = context; // Capture context for use in callback
    showTrakaModalBottomSheet<void>(
      context: currentContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
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
        onPickDestinationOnMap: ({
          required String destText,
          double? destLat,
          double? destLng,
        }) =>
            _pickDestinationOnMapFromSheet(
              ctx,
              destText: destText,
              destLat: destLat,
              destLng: destLng,
            ),
        onRouteRequest:
            (
              originLat,
              originLng,
              originText,
              destLat,
              destLng,
              destText,
            ) async {
              try {
                Navigator.pop(ctx);
                final originAdj = _directionsOriginFromDriverIfFarFromNominal(
                  originLat,
                  originLng,
                );
                final dirOriginLat = originAdj.lat;
                final dirOriginLng = originAdj.lng;
                final routeStartsFromDriver = originAdj.routeStartsFromDriver;

                var alternatives = await DirectionsService.getAlternativeRoutes(
                  originLat: dirOriginLat,
                  originLng: dirOriginLng,
                  destLat: destLat,
                  destLng: destLng,
                  trafficAware: _directionsTrafficAware,
                );
                if (!mounted) return;
                if (alternatives.isEmpty) {
                  await Future<void>.delayed(const Duration(milliseconds: 600));
                  if (!mounted) return;
                  alternatives = await DirectionsService.getAlternativeRoutes(
                    originLat: dirOriginLat,
                    originLng: dirOriginLng,
                    destLat: destLat,
                    destLng: destLng,
                    trafficAware: false,
                  );
                }
                if (!mounted) return;
                if (alternatives.isNotEmpty) {
                  _resetJourneyNumberPrefetch();
                  setState(() {
                    _routeOriginLatLng = LatLng(dirOriginLat, dirOriginLng);
                    _routeDestLatLng = LatLng(destLat, destLng);
                    _routeOriginText = originText;
                    _routeDestText = destText;
                    _alternativeRoutes = alternatives;
                    _isDriverWorking = false;
                    if (alternatives.length > 1) {
                      _selectedRouteIndex = -1;
                      _routeSelected = false;
                      _routePolyline = null;
                      _activeRouteTrafficSegments = [];
                      _routeDistanceText = '';
                      _routeDurationText = '';
                      _routeJourneyNumber = null;
                      _routeEstimatedDurationSeconds = null;
                      _routeStartedAt = null;
                    }
                  });
                  if (alternatives.length == 1) {
                    await _selectRouteAndStart(0);
                  } else {
                    _startJourneyNumberPrefetch();
                  }
                  if (!mounted) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fitAlternativeRoutesBounds();
                  });
                  final l10n = TrakaL10n.of(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        alternatives.length == 1
                            ? 'Rute sudah dipilih. Tap Mulai Rute ini untuk mulai bekerja.'
                            : routeStartsFromDriver
                                ? 'Rute dari lokasi Anda ke tujuan. Pilih garis di peta jika ada beberapa alternatif.'
                                : l10n.selectRouteOnMapHint,
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TrakaL10n.of(context).failedToLoadRouteDirections,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e, st) {
                logError('onRouteRequest', e, st);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      kDebugMode
                          ? 'Gagal memproses rute: $e'
                          : 'Gagal memproses rute. Tutup aplikasi dari recent lalu buka lagi.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 6),
                    backgroundColor: Colors.red.shade800,
                  ),
                );
              }
            },
      ),
    ).whenComplete(() {
      _routeFormSheetOpen = false;
    });
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

  /// Marker posisi driver saat beranda: pin default Maps (hijau).
  Future<void> _loadBlueDotOnce() async {
    if (_blueDotIcon != null) return;
    if (!mounted) return;
    await TrakaPinBitmapService.ensureLoaded(context);
    if (!mounted) return;
    final pin = TrakaPinBitmapService.mapAwal;
    if (pin != null) {
      _blueDotIcon = pin;
      setState(() {});
      return;
    }
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
    if (!mounted) return;
    await TrakaPinBitmapService.ensureLoaded(context);
    if (!mounted) return;
    if (_carIconRed != null && _carIconGreen != null) {
      setState(() {});
      return;
    }
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
        // Marker mobil saat jalan; berhenti → pin akhir Traka (bukan ikon mobil).
        final isMoving = _isMovingStable;
        if (!isMoving) {
          final pinStop = TrakaPinBitmapService.mapAwal ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          markers.add(
            Marker(
              markerId: const MarkerId('current_location'),
              position: displayLatLng,
              icon: pinStop,
              anchor: const Offset(0.5, 1.0),
              zIndexInt: 4,
            ),
          );
        } else {
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
            zIndexInt: 4,
          ),
        );
        }
        }
      } else {
        // Beranda non-aktif: titik biru saat pelan; panah biru + arah saat sedang bergerak (bukan cone).
        final speedKmh = _currentSpeedMps * 3.6;
        final showHeading = speedKmh >= _homeBrowsingHeadingMinKmh;
        final arrow = _homeBrowsingArrowIcon;
        final useArrow = showHeading && arrow != null;
        final pinAwalLoc = TrakaPinBitmapService.mapAwal;
        final icon = useArrow
            ? arrow
            : (pinAwalLoc ??
                _blueDotIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure));
        final anchorUser =
            Offset(0.5, useArrow ? 0.33 : (pinAwalLoc != null ? 1.0 : 0.5));
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: displayLatLng,
            icon: icon,
            rotation: useArrow ? _bearingForHomeBrowsingMarker() : 0.0,
            flat: useArrow,
            anchor: anchorUser,
            zIndexInt: 4,
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
      final pinO = TrakaPinBitmapService.mapAwal ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: _routeOriginLatLng!,
          icon: pinO,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }
    // Preview tujuan dari form (saat isi form rute, sebelum submit).
    // Jangan tampilkan jika rute sudah punya destination—hindari 2 pin di tujuan.
    final formPreview = _formDestPreviewNotifier.value;
    if (formPreview != null && _routeDestLatLng == null) {
      final pinP = TrakaPinBitmapService.mapAhir ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      markers.add(
        Marker(
          markerId: const MarkerId('form_dest_preview'),
          position: formPreview,
          icon: pinP,
          anchor: const Offset(0.5, 1.0),
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
      final pinD = TrakaPinBitmapService.mapAhir ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _routeDestLatLng!,
          icon: pinD,
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

  /// Sama filter pin [_buildMarkers] — urut **terdekat dari posisi driver** (bukan sepanjang polyline utama).
  List<OrderModel> _ordersForMapPickupsSorted() {
    final chaseCamActive = _isDriverWorking || _navigatingToOrderId != null;
    final hasRoute = _routeOriginLatLng != null && _routeDestLatLng != null;
    final list = <OrderModel>[];
    if (chaseCamActive || hasRoute) {
      for (final order in _driverOrders) {
        if (order.status == OrderService.statusCompleted) continue;
        if (!_isOrderForCurrentRoute(order)) continue;
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
    final list = <OrderModel>[];
    if (chaseCamActive || hasRoute) {
      for (final order in _driverOrders) {
        if (order.status == OrderService.statusCompleted) continue;
        if (!_isOrderForCurrentRoute(order)) continue;
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
    await showTrakaModalBottomSheet<void>(
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
                        color: AppTheme.mapPickupAccent, size: 22),
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
    await showTrakaModalBottomSheet<void>(
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
                    Icon(Icons.flag, color: AppTheme.mapDropoffAccent, size: 22),
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
    final list = <OrderModel>[];
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusPickedUp) continue;
      if (order.orderType != OrderModel.typeTravel &&
          order.orderType != OrderModel.typeKirimBarang) {
        continue;
      }
      if (!_isOrderForCurrentRoute(order)) continue;
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
      final live = order.coordsForDriverDropoffProximity;
      if (live != null) return (live.$1, live.$2);
      return (
        order.receiverLat ?? order.destLat,
        order.receiverLng ?? order.destLng,
      );
    }
    return (order.destLat, order.destLng);
  }

  /// Pesanan terjadwal: cocokkan [scheduleId] format baru (`…_h…`) vs legacy (`…_depMillis`).
  bool _scheduleIdsMatchForActiveJadwal(String orderScheduleId) {
    final cur = _currentScheduleId;
    if (cur == null || cur.isEmpty) return false;
    if (orderScheduleId.isEmpty) return false;
    if (cur == orderScheduleId) return true;
    return ScheduleIdUtil.toLegacy(cur) ==
        ScheduleIdUtil.toLegacy(orderScheduleId);
  }

  /// Cek apakah order termasuk dalam rute aktif saat ini (untuk tampilan map).
  /// Pesanan terjadwal memakai tanggal **[DriverScheduleService.todayYmdWibString]** + [scheduleId].
  bool _isOrderForCurrentRoute(OrderModel order) {
    if (order.isScheduledOrder) {
      if (_currentScheduleId == null) return false;
      final oid = order.scheduleId;
      if (oid == null || oid.isEmpty) return false;
      // Satu kalender dengan chip Jadwal (WIB), bukan jam lokal perangkat saja.
      if ((order.scheduledDate ?? '') !=
          DriverScheduleService.todayYmdWibString) {
        return false;
      }
      return _scheduleIdsMatchForActiveJadwal(oid);
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
    final list = <OrderModel>[];
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger) {
        continue;
      }
      final lat = order.passengerLat ?? order.originLat;
      final lng = order.passengerLng ?? order.originLng;
      if (lat == null || lng == null) continue;
      if (!_isOrderForCurrentRoute(order)) continue;
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

  /// Saran UI saat titik jemput agreed dalam radius dekat & belum navigasi jemput aktif.
  ({OrderModel order, double distanceMeters})? _pickupNearbyHintCandidate() {
    if (!_isDriverWorking || _currentPosition == null) return null;
    if (_waitingPassengerOrders.isEmpty) return null;
    if (_navigatingToOrderId != null && !_navigatingToDestination) return null;

    final pos = _currentPosition!;
    OrderModel? best;
    var bestDist = double.infinity;

    for (final o in _waitingPassengerOrders) {
      final lat = o.passengerLiveLat ?? o.passengerLat ?? o.originLat;
      final lng = o.passengerLiveLng ?? o.passengerLng ?? o.originLng;
      if (lat == null || lng == null) continue;
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      final suppressed = _dismissedPickupNearbyHintOrderIds.contains(o.id) &&
          d < AppConstants.driverPickupNearbyHintReshowMeters;
      if (suppressed) continue;
      if (d < bestDist) {
        bestDist = d;
        best = o;
      }
    }
    if (best == null ||
        bestDist > AppConstants.driverPickupNearbyHintMaxMeters) {
      return null;
    }
    return (order: best, distanceMeters: bestDist);
  }

  void _syncNextStopBannerDismissState() {
    final navTuple = _nextTargetForNavigation;
    final String? nextKey = (navTuple != null && navTuple.$1 != null)
        ? '${navTuple.$1!.id}_${navTuple.$2}'
        : null;
    if (_nextStopBannerContextKey != nextKey) {
      _nextStopBannerContextKey = nextKey;
      _nextStopBannerUserDismissed = false;
    }
  }

  /// Jumlah pesanan terjadwal untuk hari ini yang sudah kesepakatan dan belum dijemput (untuk banner pengingat).
  int get _scheduledAgreedCountForToday {
    final todayWib = DriverScheduleService.todayYmdWibString;
    return _driverOrders.where((o) {
      if (!o.isScheduledOrder || (o.scheduledDate ?? '') != todayWib) {
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
    for (final order in _driverOrders) {
      if (order.status != OrderService.statusAgreed ||
          order.hasDriverScannedPassenger ||
          (order.passengerLat == null && order.originLat == null)) {
        continue;
      }
      if (!_isOrderForCurrentRoute(order)) continue;
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

  Future<void> _onPickupNearbyBannerNavigate(
    OrderModel order, {
    int? bannerDistanceMeters,
  }) async {
    AppAnalyticsService.logDriverPickupNearbyBanner(
      action: 'navigate',
      distanceMeters: bannerDistanceMeters,
    );
    unawaited(VoiceNavigationService.instance.init());
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
      AppAnalyticsService.logDriverStopShortcutEducationalTap(
        shortcut: 'pickup',
        reason: 'no_agreed_pickups',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).driverStopShortcutPickupEmpty),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
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
      final pickups = _waitingPassengerOrders;
      final needPickupFirst = pickups.isNotEmpty;
      AppAnalyticsService.logDriverStopShortcutEducationalTap(
        shortcut: 'dropoff',
        reason:
            needPickupFirst ? 'need_pickup_first' : 'no_flow_yet',
      );
      if (!mounted) return;
      final l10n = TrakaL10n.of(context);
      final msg = needPickupFirst
          ? l10n.driverStopShortcutDropoffNeedPickupFirst
          : l10n.driverStopShortcutDropoffEmptyFlow;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
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
      final sw = Stopwatch()..start();
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
        trafficAware: _directionsTrafficAware,
      );
      sw.stop();
      if (!mounted) return;
      AppAnalyticsService.logDriverNavRouteFetch(
        scope: 'hydrate_steps',
        success: outcome.data != null,
        latencyMs: sw.elapsedMilliseconds,
        errorKey: outcome.errorStatus,
        staleCache: outcome.usedStaleCache,
      );
      final withSteps = outcome.data;
      if (withSteps == null) return;
      _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: false);
      _resetVoiceProximityState();
      setState(() {
        // Polyline + steps harus dari respons yang sama (jarak kumulatif step konsisten).
        _routePolyline = withSteps.result.points;
        _routeDistanceText = withSteps.result.distanceText;
        _routeDurationText = withSteps.result.durationText;
        _routeEstimatedDurationSeconds = withSteps.result.durationSeconds;
        _routeSteps = withSteps.steps;
        _activeRouteTrafficSegments = withSteps.trafficSegments;
        _currentStepIndex = withSteps.steps.isNotEmpty ? 0 : -1;
      });
      _persistOfflineWorkRouteFromSteps(withSteps);
      var spokeFromStepChange = false;
      if (_currentPosition != null) {
        spokeFromStepChange = _updateCurrentStepFromPosition(_currentPosition!);
      }
      if (!spokeFromStepChange &&
          mounted &&
          _routeSteps.isNotEmpty &&
          _currentStepIndex >= 0) {
        await VoiceNavigationService.instance.init();
        if (mounted) _speakCurrentStep();
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
    double? routeDeviationMeters,
  }) async {
    if (_routeDestLatLng == null) return false;
    final now = DateTime.now();
    if (!force) {
      final farOff = routeDeviationMeters != null &&
          routeDeviationMeters >= _farOffDeviationForFastRerouteMeters;
      final debounceSec =
          farOff ? _rerouteDebounceSecondsFarOff : _rerouteDebounceSeconds;
      if (_lastRerouteAt != null) {
        final secSince = now.difference(_lastRerouteAt!).inSeconds;
        if (secSince < debounceSec) return false;
      }
      if (_lastReroutePosition != null) {
        final dist = Geolocator.distanceBetween(
          _lastReroutePosition!.latitude,
          _lastReroutePosition!.longitude,
          currentPos.latitude,
          currentPos.longitude,
        );
        final debounceDist = farOff ? _refetchNavRouteDistanceWhenFarMeters : _rerouteDebounceDistanceMeters;
        if (dist < debounceDist) return false;
      }
    }

    _pushRouteRecalculate();
    try {
      final sw = Stopwatch()..start();
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: currentPos.latitude,
        originLng: currentPos.longitude,
        destLat: _routeDestLatLng!.latitude,
        destLng: _routeDestLatLng!.longitude,
        trafficAware: _directionsTrafficAware,
      );
      sw.stop();
      if (!mounted) return false;
      AppAnalyticsService.logDriverNavRouteFetch(
        scope: 'main',
        success: outcome.data != null,
        latencyMs: sw.elapsedMilliseconds,
        errorKey: outcome.errorStatus,
        staleCache: outcome.usedStaleCache,
      );
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
        _resetVoiceProximityState();
        setState(() {
          _routePolyline = withSteps.result.points;
          _routeDistanceText = withSteps.result.distanceText;
          _routeDurationText = withSteps.result.durationText;
          _routeEstimatedDurationSeconds = withSteps.result.durationSeconds;
          _routeSteps = withSteps.steps;
          _activeRouteTrafficSegments = withSteps.trafficSegments;
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
        if (quiet) {
          _scheduleQuietRerouteBanner();
        } else if (mounted) {
          final l10n = TrakaL10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.routeUpdated),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        _persistOfflineWorkRouteFromSteps(withSteps);
        _syncCameraAfterRouteRecalculated();
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
      final sw = Stopwatch()..start();
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _directionsTrafficAware,
      );
      sw.stop();
      if (!mounted) return;
      AppAnalyticsService.logDriverNavRouteFetch(
        scope: 'to_passenger',
        success: outcome.data != null,
        latencyMs: sw.elapsedMilliseconds,
        errorKey: outcome.errorStatus,
        staleCache: outcome.usedStaleCache,
      );
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
        final result = withSteps.result;
        _resetVoiceProximityState();
        setState(() {
          _polylineToPassenger = result.points;
          _routeSteps = withSteps.steps;
          _activeRouteTrafficSegments = withSteps.trafficSegments;
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
        if (!quiet) {
          _fitRouteToPassengerBounds();
        }
        if (_currentPosition != null) {
          if (!_updateCurrentStepFromPosition(_currentPosition!)) {
            if (!quiet) _speakCurrentStep();
          }
        } else {
          if (!quiet) _speakCurrentStep();
        }
        if (quiet) {
          _scheduleQuietRerouteBanner();
          _syncCameraAfterRouteRecalculated();
        }
        _persistOfflineOrderNavFromSteps(
          order: order,
          withSteps: withSteps,
          destLat: destLat,
          destLng: destLng,
          navigatingToDestination: false,
        );
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
        _resetVoiceProximityState();
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
          _activeRouteTrafficSegments = [];
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
      final sw = Stopwatch()..start();
      final outcome = await DirectionsService.getRouteWithSteps(
        originLat: _currentPosition!.latitude,
        originLng: _currentPosition!.longitude,
        destLat: destLat,
        destLng: destLng,
        trafficAware: _directionsTrafficAware,
      );
      sw.stop();
      if (!mounted) return;
      AppAnalyticsService.logDriverNavRouteFetch(
        scope: 'to_destination',
        success: outcome.data != null,
        latencyMs: sw.elapsedMilliseconds,
        errorKey: outcome.errorStatus,
        staleCache: outcome.usedStaleCache,
      );
      final withSteps = outcome.data;
      if (withSteps != null) {
        _notifyDirectionsStaleFromOutcome(outcome, showSnackBar: !quiet);
        final result = withSteps.result;
        _resetVoiceProximityState();
        setState(() {
          _polylineToDestination = result.points;
          _routeSteps = withSteps.steps;
          _activeRouteTrafficSegments = withSteps.trafficSegments;
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
        if (!quiet) {
          _fitRouteToDestinationBounds();
        }
        if (_currentPosition != null) {
          if (!_updateCurrentStepFromPosition(_currentPosition!)) {
            if (!quiet) _speakCurrentStep();
          }
        } else {
          if (!quiet) _speakCurrentStep();
        }
        if (quiet) {
          _scheduleQuietRerouteBanner();
          _syncCameraAfterRouteRecalculated();
        }
        _persistOfflineOrderNavFromSteps(
          order: order,
          withSteps: withSteps,
          destLat: destLat,
          destLng: destLng,
          navigatingToDestination: true,
        );
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
        _resetVoiceProximityState();
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
          _activeRouteTrafficSegments = [];
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
      _activeRouteTrafficSegments = [];
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
    _resetVoiceProximityState();
    _fitMapToMainRoute();
  }

  void _exitNavigatingToDestination() {
    _exitNavigatingToPassenger();
  }

  void _startTrafficAlternativesCheck() {
    _trafficAlternativesCheckTimer?.cancel();
    if (!_trafficEnabled || _navigatingToOrderId == null) return;
    if (NavigationSettingsService.dataSaverEnabled) return;
    _trafficAlternativesCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkFasterAlternativeRoute(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(minutes: 2), () {
        if (mounted && _navigatingToOrderId != null) {
          _checkFasterAlternativeRoute();
        }
      });
    });
  }

  void _stopTrafficAlternativesCheck() {
    _trafficAlternativesCheckTimer?.cancel();
    _trafficAlternativesCheckTimer = null;
  }

  Future<void> _checkFasterAlternativeRoute() async {
    if (!mounted ||
        _navigatingToOrderId == null ||
        !_trafficEnabled ||
        NavigationSettingsService.dataSaverEnabled) {
      return;
    }
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
      trafficAware: _directionsTrafficAware,
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
      trafficAware: _directionsTrafficAware,
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

    final selected = await showTrakaModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.88,
        child: _AlternativeRoutesPickerSheet(
          alternatives: alternatives,
          origin: origin,
          destination: destination,
        ),
      ),
    );

    if (selected == null || !mounted) return;

    final chosen = alternatives[selected];
    _resetVoiceProximityState();
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
      _activeRouteTrafficSegments = chosen.trafficSegments;
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
    final rawPos = LatLng(position.latitude, position.longitude);
    // Sama seperti TBT: proyeksi dari GPS mentah agar langkah aktif & suara selaras dengan jalan.
    final pos = rawPos;
    var (_, segmentIndex, ratio) = RouteUtils.projectPointOntoPolyline(
      pos,
      poly,
      maxDistanceMeters: 300,
    );
    if (segmentIndex < 0) {
      final retry = RouteUtils.projectPointOntoPolyline(
        pos,
        poly,
        maxDistanceMeters: 480,
      );
      segmentIndex = retry.$2;
      ratio = retry.$3;
    }
    if (segmentIndex < 0) {
      final retry2 = RouteUtils.projectPointOntoPolyline(
        rawPos,
        poly,
        maxDistanceMeters: 620,
      );
      segmentIndex = retry2.$2;
      ratio = retry2.$3;
    }
    if (segmentIndex < 0) {
      final n = DateTime.now();
      if (_lastTbtProjectionFailLog == null ||
          n.difference(_lastTbtProjectionFailLog!).inSeconds >= 45) {
        _lastTbtProjectionFailLog = n;
        AppAnalyticsService.logDriverNavTbtProjectionFail();
      }
      return false;
    }
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
      _persistOfflineNavSnapshotForStep(stepIdx);
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
    _lastVoiceCueAt = DateTime.now();
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

  static const Color _polylinePenjemputanColor = AppTheme.mapPickupAccent;
  static const Color _polylinePengantaranColor = AppTheme.mapDropoffAccent;

  Color _trafficTintForRatio(double trafficRatio, Color baseColor) {
    if (trafficRatio <= 1.04) return baseColor;
    if (trafficRatio <= 1.18) {
      return Color.lerp(baseColor, AppTheme.mapPickupAccent, 0.5) ?? baseColor;
    }
    if (trafficRatio <= 1.38) {
      return AppTheme.mapRouteOrange;
    }
    return AppTheme.mapStopRed;
  }

  double? _distanceAlongRouteMetersForTraffic(List<LatLng> fullRoute) {
    final pos = _displayedPosition ??
        (_currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : null);
    if (pos == null || fullRoute.length < 2) return null;
    for (final maxD in [260.0, 420.0, 640.0]) {
      final p =
          RouteUtils.projectPointOntoPolyline(pos, fullRoute, maxDistanceMeters: maxD);
      if (p.$2 >= 0) {
        return RouteUtils.distanceAlongPolyline(fullRoute, p.$2, p.$3);
      }
    }
    return null;
  }

  /// Amber «lewat» + sisa maju; sisa dipecah warna lalu lintas bila [useTraffic].
  void _addForwardPolylinesWithTraffic({
    required Set<Polyline> polylines,
    required List<LatLng> fullRoute,
    required Color baseColor,
    required int width,
    required String idPrefix,
    bool useTraffic = false,
    bool consumeTapEvents = false,
    VoidCallback? onTap,
    Color? passedColorOverride,
  }) {
    if (fullRoute.length < 2) return;
    final passedWidth = width >= 6 ? 6 : 5;
    final passedColor = passedColorOverride ?? Colors.amber.shade300;
    final (passed, remaining) = _splitPolylineAtDriver(fullRoute);
    if (passed.length >= 2) {
      polylines.add(
        _styledDriverRoutePolyline(
          polylineId: PolylineId('${idPrefix}_passed'),
          points: passed,
          color: passedColor,
          width: passedWidth,
        ),
      );
    }
    if (remaining.length < 2) return;

    final segOk = useTraffic && _activeRouteTrafficSegments.isNotEmpty;
    if (!segOk) {
      polylines.add(
        _styledDriverRoutePolyline(
          polylineId: PolylineId('${idPrefix}_rem'),
          points: remaining,
          color: baseColor,
          width: width,
          consumeTapEvents: consumeTapEvents,
          onTap: onTap,
        ),
      );
      return;
    }

    final driverDist = _distanceAlongRouteMetersForTraffic(fullRoute);
    if (driverDist == null) {
      polylines.add(
        _styledDriverRoutePolyline(
          polylineId: PolylineId('${idPrefix}_rem'),
          points: remaining,
          color: baseColor,
          width: width,
          consumeTapEvents: consumeTapEvents,
          onTap: onTap,
        ),
      );
      return;
    }

    var drawn = 0;
    var maxEndAlong = driverDist;
    var trafficIdx = 0;
    for (final seg in _activeRouteTrafficSegments) {
      if (seg.endDistanceMeters <= driverDist - 0.5) continue;
      final sm = math.max(seg.startDistanceMeters, driverDist);
      final em = seg.endDistanceMeters;
      if (em <= sm + 0.5) continue;
      final slice =
          RouteUtils.slicePolylineByDistanceRange(fullRoute, sm, em);
      if (slice.length < 2) continue;
      final c = _trafficTintForRatio(seg.trafficRatio, baseColor);
      polylines.add(
        _styledDriverRoutePolyline(
          polylineId: PolylineId('${idPrefix}_tf_$trafficIdx'),
          points: slice,
          color: c,
          width: width,
          consumeTapEvents: consumeTapEvents && drawn == 0,
          onTap: drawn == 0 ? onTap : null,
        ),
      );
      drawn++;
      maxEndAlong = math.max(maxEndAlong, em);
      trafficIdx++;
    }

    final totalGeo = RouteUtils.polylineLengthMeters(fullRoute);
    final gapStart = math.max(driverDist, maxEndAlong - 1.5);
    if (gapStart < totalGeo - 6) {
      final tail =
          RouteUtils.slicePolylineByDistanceRange(fullRoute, gapStart, totalGeo);
      if (tail.length >= 2) {
        polylines.add(
          _styledDriverRoutePolyline(
            polylineId: PolylineId('${idPrefix}_tail'),
            points: tail,
            color: baseColor,
            width: width,
            consumeTapEvents: consumeTapEvents && drawn == 0,
            onTap: drawn == 0 ? onTap : null,
          ),
        );
        drawn++;
      }
    }

    if (drawn == 0) {
      polylines.add(
        _styledDriverRoutePolyline(
          polylineId: PolylineId('${idPrefix}_rem_fb'),
          points: remaining,
          color: baseColor,
          width: width,
          consumeTapEvents: consumeTapEvents,
          onTap: onTap,
        ),
      );
    }
  }

  Polyline _styledDriverRoutePolyline({
    required PolylineId polylineId,
    required List<LatLng> points,
    required Color color,
    required int width,
    List<PatternItem> patterns = const [],
    bool consumeTapEvents = false,
    VoidCallback? onTap,
  }) {
    return Polyline(
      polylineId: polylineId,
      points: points,
      color: color,
      width: width,
      patterns: patterns,
      consumeTapEvents: consumeTapEvents,
      onTap: onTap,
      geodesic: true,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
  }

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
            _styledDriverRoutePolyline(
              polylineId: const PolylineId('route_main_passed'),
              points: passed,
              color: Colors.amber.shade300,
              width: 4,
            ),
          );
        }
        if (remaining.length >= 2) {
          polylines.add(
            _styledDriverRoutePolyline(
              polylineId: const PolylineId('route_main_faded'),
              points: remaining,
              color: Colors.grey.shade400,
              width: 4,
            ),
          );
        }
      }
      // Rute ke penumpang/tujuan: lewat + sisa (warna lalu lintas per segmen bila tersedia).
      _addForwardPolylinesWithTraffic(
        polylines: polylines,
        fullRoute: navPolyline,
        baseColor: routeColor,
        width: 6,
        idPrefix: 'route_to_passenger',
        useTraffic: _activeRouteTrafficSegments.isNotEmpty,
        consumeTapEvents: true,
        onTap: () {
          unawaited(_showAlternativeRoutesDuringNavigation());
        },
      );
      return polylines;
    }

    // Tampilkan semua alternatif rute jika ada (warna per rute: biru, hijau, oranye, ungu)
    if (_alternativeRoutes.isNotEmpty) {
      for (int i = 0; i < _alternativeRoutes.length; i++) {
        final route = _alternativeRoutes[i];
        final routeColor = routeColorForIndex(i);
        final isSelected = i == _selectedRouteIndex && _routeSelected;
        if (isSelected && _isDriverWorking) {
          final activePts = (_routePolyline != null && _routePolyline!.length >= 2)
              ? _routePolyline!
              : route.points;
          _addForwardPolylinesWithTraffic(
            polylines: polylines,
            fullRoute: activePts,
            baseColor: routeColor,
            width: 9,
            idPrefix: 'route_$i',
            useTraffic: _navigatingToOrderId == null &&
                _activeRouteTrafficSegments.isNotEmpty,
            passedColorOverride: routeColor.withValues(alpha: 0.5),
          );
        } else {
          final points = isSelected
              ? _trimPolylineFromDriver(route.points)
              : route.points;
          if (points.length >= 2) {
            polylines.add(
              _styledDriverRoutePolyline(
                polylineId: PolylineId('route_$i'),
                points: points,
                color: routeColor,
                width: isSelected ? 9 : 4,
                patterns: const [],
              ),
            );
          }
        }
      }
    } else if (_routePolyline != null && _routePolyline!.isNotEmpty) {
      _addForwardPolylinesWithTraffic(
        polylines: polylines,
        fullRoute: _routePolyline!,
        baseColor: Theme.of(context).colorScheme.primary,
        width: 5,
        idPrefix: 'route',
        useTraffic: _navigatingToOrderId == null &&
            _activeRouteTrafficSegments.isNotEmpty,
      );
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
    if (selectedRoute.points.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Data rute tidak valid (garis kosong). Coba tujuan lain atau lagi nanti.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
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
      _activeRouteTrafficSegments = [];
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
    final showTbtPadding = _routeSteps.isNotEmpty &&
        ((_navigatingToOrderId != null) ||
            (_isDriverWorking &&
                _routePolyline != null &&
                _routePolyline!.length >= 2));
    if (showTbtPadding) {
      // Selaras dengan [TurnByTurnBanner] (pill + jarak + kartu petunjuk).
      top = safeTop + (landscape ? 186 : 238);
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
    } else if (_isDriverWorking && showTbtPadding) {
      // Sedikit lebih tinggi dari tepi bawah: jalan depan tetap lega, panah tidak «nempel» bawah.
      final wBottom = safeBottom + (landscape ? 152 : 198);
      if (wBottom > bottom) bottom = wBottom;
    }
    if (_fasterAlternativeMinutesSaved != null &&
        _fasterAlternativeMinutesSaved! >= 2) {
      final altBottom = safeBottom + 268;
      if (altBottom > bottom) bottom = altBottom;
    }
    if (_isDriverWorking || _navigatingToOrderId != null) {
      final navPremiumRail =
          safeBottom + (landscape ? 118 : 158);
      if (navPremiumRail > bottom) bottom = navPremiumRail;
    }

    double left = 8;
    final muteBottomLeft = (_isDriverWorking || _navigatingToOrderId != null) &&
        !showTbtPadding;
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
    if (_navigatingToOrderId == null && !_isDriverWorking) return;
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
    _syncNextStopBannerDismissState();
    final pickupNearbyHint = _pickupNearbyHintCandidate();
    final showNextStopBanner = _navigatingToOrderId == null &&
        _nextTargetForNavigation != null &&
        !_nextStopBannerUserDismissed &&
        !(pickupNearbyHint != null &&
            _nextTargetForNavigation!.$2 &&
            _nextTargetForNavigation!.$1?.id == pickupNearbyHint.order.id);

    if (pickupNearbyHint == null) {
      _pickupNearbyBannerImpressionOrderId = null;
    } else if (_pickupNearbyBannerImpressionOrderId !=
        pickupNearbyHint.order.id) {
      _pickupNearbyBannerImpressionOrderId = pickupNearbyHint.order.id;
      final distShown = pickupNearbyHint.distanceMeters.round();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        AppAnalyticsService.logDriverPickupNearbyBanner(
          action: 'shown',
          distanceMeters: distShown,
        );
      });
    }

    final showDriverTbtBanner = _routeSteps.isNotEmpty &&
        ((_navigatingToOrderId != null) ||
            (_isDriverWorking &&
                _routePolyline != null &&
                _routePolyline!.length >= 2));
    final mqMap = MediaQuery.of(context);
    MapDeviceTiltService.instance.setOrientation(mqMap.orientation);
    _syncFieldObservabilityIfChanged();
    _syncDriverDrivingUxIfChanged();
    final gpsWeakBannerTop = mqMap.padding.top +
        (showDriverTbtBanner
            ? (mqMap.orientation == Orientation.landscape ? 198.0 : 250.0)
            : 52.0);
    final pickupShortcutTooltip = _waitingPassengerCount > 0
        ? 'Penjemputan'
        : 'Penjemputan — aktif setelah ada pemesan yang setuju';
    final dropoffShortcutTooltip =
        _pickedUpOrdersForDestination.isNotEmpty
            ? 'Pengantaran'
            : _waitingPassengerCount > 0
                ? 'Pengantaran — selesaikan penjemputan dulu'
                : 'Pengantaran — setelah penjemputan selesai';

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
                    if (!_hasShownMapGestureTrackingHint && mounted) {
                      _hasShownMapGestureTrackingHint = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        messenger?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Satu jari: geser peta. Dua jari: zoom dan putar. '
                              'Tap tombol fokus untuk kembali mengikuti posisi Anda.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 5),
                          ),
                        );
                      });
                    }
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
                      TrakaLoadingIndicator(
                        size: 20,
                        variant: TrakaLoadingVariant.onLightSurface,
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
                    TrakaLoadingIndicator(
                      size: 22,
                      variant: TrakaLoadingVariant.onLightSurface,
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
        // Kartu petunjuk di bawah chrome atas (pill kerja + kolom kanan) — diletakkan sebelum pill agar z-order: kontrol di atas.
        if (_routeSteps.isNotEmpty &&
            ((_navigatingToOrderId != null) ||
                (_isDriverWorking &&
                    _routePolyline != null &&
                    _routePolyline!.length >= 2)))
          TurnByTurnBanner(
            steps: _routeSteps,
            currentStepIndex: _currentStepIndex >= 0 ? _currentStepIndex : 0,
            remainingMetersToManeuver: _tbtRemainingMeters,
            rerouteStatusText: _rerouteStatusBanner,
            distanceToNextStepMeters: _tbtNextStepRemainingMeters,
            onResumeCameraTracking:
                _rerouteStatusBanner != null ? _focusOnCar : null,
            etaArrival: _routeToPassengerDurationSeconds != null
                ? DateTime.now()
                    .add(Duration(seconds: _routeToPassengerDurationSeconds!))
                : (_routeEstimatedDurationSeconds != null
                    ? DateTime.now().add(
                        Duration(seconds: _routeEstimatedDurationSeconds!),
                      )
                    : null),
            tollInfoText: _routeTollInfo,
            routeWarnings: _routeWarnings,
            accentColor: _navigatingToOrderId != null
                ? (_navigatingToDestination
                    ? AppTheme.mapDropoffAccent
                    : AppTheme.mapPickupAccent)
                : AppTheme.primary,
            voiceMuted: VoiceNavigationService.instance.muted,
            onVoiceMuteToggle: () async {
              await VoiceNavigationService.instance.toggleMuted();
              if (mounted) setState(() {});
            },
          ),
        DriverWorkToggleButton(
          isDriverWorking: _isDriverWorking,
          routeSelected: _routeSelected,
          hasActiveOrder: _hasActiveOrder,
          onTap: _onDriverWorkPillTap,
        ),
        if (_isDriverWorking || _navigatingToOrderId != null)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DriverMapStopShortcutsAbovePremium(
                  show: _isDriverWorking,
                  onPickupTap: _isDriverWorking
                      ? () => unawaited(_onPickupStopShortcutTap())
                      : null,
                  onDropoffTap: _isDriverWorking
                      ? () => unawaited(_onDropoffStopShortcutTap())
                      : null,
                  pickupEnabled: _waitingPassengerCount > 0,
                  dropoffEnabled: _pickedUpOrdersForDestination.isNotEmpty,
                  pickupTooltip: pickupShortcutTooltip,
                  dropoffTooltip: dropoffShortcutTooltip,
                ),
                if (_isDriverWorking) const SizedBox(height: 12),
                DriverNavPremiumMapChip(
                  enabled: true,
                  debtBlocked:
                      _navPremiumOwedCache && !_navPremiumPhoneExemptCache,
                  dense: true,
                  tooltip: _navPremiumOwedCache && !_navPremiumPhoneExemptCache
                      ? (l10nMap.locale == AppLocale.id
                          ? 'Tunggakan nav premium — ketuk untuk info & pembayaran'
                          : 'Premium nav owed — tap for info & payment')
                      : (l10nMap.locale == AppLocale.id
                          ? 'Ketuk untuk penjelasan navigasi premium'
                          : 'Tap for premium navigation details'),
                  onTap: _showDriverNavPremiumInfoSheet,
                ),
              ],
            ),
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
              showPickupDropoffShortcuts: false,
              onPickupShortcutTap: null,
              onDropoffShortcutTap: null,
              pickupShortcutEnabled: _waitingPassengerCount > 0,
              dropoffShortcutEnabled:
                  _pickedUpOrdersForDestination.isNotEmpty,
              pickupShortcutTooltip: pickupShortcutTooltip,
              dropoffShortcutTooltip: dropoffShortcutTooltip,
              showRouteInfoShortcut: _isDriverWorking &&
                  _routePolyline != null &&
                  _routePolyline!.isNotEmpty &&
                  _navigatingToOrderId == null,
              onRouteInfoTap: _showRouteInfoBottomSheet,
              routeInfoOperBadge: _jumlahPenumpangPickedUp > 0,
              routeInfoTooltip: l10nMap.routeInfo,
              onMapToolsTap: _showDriverMapToolsMenu,
            );
          },
        ),
        // #6: Panel list penumpang (di bawah banner) — dulu di atas banner sehingga
        // area overlap menelan tap banner "Jemput: …".
        if ((_waitingPassengerCount > 0 || _pickedUpOrdersForDestination.isNotEmpty) &&
            _navigatingToOrderId == null)
          DriverStopsListOverlay(
            stackTop: MediaQuery.of(context).orientation == Orientation.landscape
                ? MediaQuery.of(context).padding.top + 258
                : 288,
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
        if (showNextStopBanner) ...[
          _NextStopBanner(
            target: _nextTargetForNavigation!.$1!,
            isPickup: _nextTargetForNavigation!.$2,
            onTap: () => _navigateToNextTarget(),
            onDismiss: () => setState(() => _nextStopBannerUserDismissed = true),
          ),
        ],
        if (pickupNearbyHint != null)
          _PickupPassengerNearbyBanner(
            order: pickupNearbyHint.order,
            distanceMeters: pickupNearbyHint.distanceMeters.round(),
            stackBelowNextStop: showNextStopBanner,
            onNavigate: () => unawaited(
              _onPickupNearbyBannerNavigate(
                pickupNearbyHint.order,
                bannerDistanceMeters:
                    pickupNearbyHint.distanceMeters.round(),
              ),
            ),
            onDismiss: () {
              AppAnalyticsService.logDriverPickupNearbyBanner(
                action: 'dismiss',
                distanceMeters:
                    pickupNearbyHint.distanceMeters.round(),
              );
              setState(() {
                _dismissedPickupNearbyHintOrderIds
                    .add(pickupNearbyHint.order.id);
              });
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
                            ? TrakaLoadingIndicator(
                                size: 18,
                                variant: TrakaLoadingVariant.onLightSurface,
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
                color: AppTheme.mapPickupAccent,
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
        if (_showGpsAccuracyHint &&
            (_isDriverWorking || _navigatingToOrderId != null) &&
            (_lastGpsAccuracyMeters != null))
          Positioned(
            top: gpsWeakBannerTop,
            left: 10,
            right: 10,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 10),
                      child: Icon(
                        Icons.gps_not_fixed_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        child: Text(
                          'Sinyal GPS lemah (~${_lastGpsAccuracyMeters!.round()} m). '
                          'Posisi di peta bisa kurang akurat. Pindah ke area terbuka jika bisa.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _gpsAccuracyHintDismissed = true;
                          _showGpsAccuracyHint = false;
                        });
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            String fmt(int n) => n.toString().replaceAllMapped(
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
                      final sid = scheduleId ?? '';
                      if (sid.isNotEmpty &&
                          !ScheduleIdUtil.scheduleIdDateMatchesTodayWib(
                            sid,
                            DriverScheduleService.todayYmdWibString,
                          )) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              TrakaL10n.of(context).driverJadwalRouteWrongDateWib,
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
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
          return Scaffold(
            body: Center(
              child: TrakaLoadingIndicator(
                size: 48,
                variant: TrakaLoadingVariant.onLightSurface,
              ),
            ),
          );
        }
        return Scaffold(
          body: Center(
            child: TrakaEmptyState(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.orange.shade700,
              title: 'Sesi tidak valid. Silakan login ulang.',
              action: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true)
                      .pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.login),
                label: const Text('Ke Login'),
              ),
            ),
          ),
        );
      }
      _sessionInvalidConfirmed = false;

      return StreamBuilder<UserShellRebuild>(
        stream: _driverUserShellStreamFor(user.uid),
        initialData: const UserShellRebuild(
          isVerified: true,
          adminVerificationBlocksFeatures: false,
        ),
        builder: (context, profileSnap) {
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
              ordersAttentionCount: _ordersAttentionCount,
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
    required this.onDismiss,
  });

  final OrderModel target;
  final bool isPickup;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bannerTop = mq.orientation == Orientation.landscape
        ? mq.padding.top + 8
        : 180.0;
    final color = isPickup
        ? AppTheme.mapPickupAccent // leg penjemputan
        : AppTheme.mapDropoffAccent;
    final label = isPickup ? 'Jemput' : 'Antar';
    final name = target.passengerName.trim().isEmpty
        ? (target.isKirimBarang ? 'Barang' : 'Penumpang')
        : target.passengerName;

    return Positioned(
      top: bannerTop,
      left: 16,
      right: 16,
      child: Dismissible(
        key: ValueKey('next_stop_${target.id}_$isPickup'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
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
      ),
    );
  }
}

/// Banner penumpang dekat titik jemput — [Arahkan] atau [Abaikan] (sembunyikan sampai menjauh).
class _PickupPassengerNearbyBanner extends StatelessWidget {
  const _PickupPassengerNearbyBanner({
    required this.order,
    required this.distanceMeters,
    required this.stackBelowNextStop,
    required this.onNavigate,
    required this.onDismiss,
  });

  final OrderModel order;
  final int distanceMeters;
  final bool stackBelowNextStop;
  final VoidCallback onNavigate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final baseTop = mq.orientation == Orientation.landscape
        ? mq.padding.top + 8
        : 180.0;
    final top = baseTop + (stackBelowNextStop ? 72 : 0);
    final l10n = TrakaL10n.of(context);
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Dismissible(
        key: ValueKey('pickup_nearby_banner_${order.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.person_pin_circle,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.driverPickupNearbyBannerTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.driverPickupNearbyBannerBody(distanceMeters),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onDismiss,
                      child: Text(l10n.driverPickupNearbyBannerDismiss),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: onNavigate,
                      child: Text(l10n.driverPickupNearbyBannerNavigate),
                    ),
                  ],
                ),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureRouteAltPins());
    });
  }

  Future<void> _ensureRouteAltPins() async {
    await TrakaPinBitmapService.ensureLoaded(context);
    if (mounted) setState(() {});
  }

  Set<Marker> _buildAltEndpointMarkers() {
    final o = TrakaPinBitmapService.mapAwal ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    final d = TrakaPinBitmapService.mapAhir ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    return {
      Marker(
        markerId: const MarkerId('alt_origin'),
        position: widget.origin,
        icon: o,
        anchor: const Offset(0.5, 1.0),
        infoWindow: const InfoWindow(title: 'Awal'),
      ),
      Marker(
        markerId: const MarkerId('alt_dest'),
        position: widget.destination,
        icon: d,
        anchor: const Offset(0.5, 1.0),
        infoWindow: const InfoWindow(title: 'Tujuan akhir'),
      ),
    };
  }

  static final List<Color> _routeColors = [
    AppTheme.mapPickupAccent,
    AppTheme.primary,
    AppTheme.mapDeliveryAccent,
    AppTheme.mapDropoffAccent,
    AppTheme.mapRoutePurple,
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
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
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
                          markers: _buildAltEndpointMarkers(),
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

