import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/car_icon_service.dart';
import '../services/passenger_driver_car_icon.dart';
import '../services/geocoding_service.dart';

import '../utils/placemark_formatter.dart';
import '../utils/app_logger.dart';
import '../widgets/kirim_barang_pilih_jenis_sheet.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_constants.dart';
import '../config/traka_realtime_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/estimate_loading_dialog.dart';
import '../widgets/traka_l10n_scope.dart';
import '../theme/responsive.dart';
import '../services/location_service.dart';
import '../services/active_drivers_service.dart';
import '../services/app_analytics_service.dart';
import '../services/driver_status_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../models/order_model.dart';
import '../services/chat_badge_service.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/order_service.dart';
import '../services/passenger_first_chat_message.dart';
import '../services/passenger_proximity_notification_service.dart';
import '../services/receiver_proximity_notification_service.dart';
import '../services/user_shell_profile_stream.dart';
import '../services/verification_service.dart';
import '../services/auth_session_service.dart';
import '../services/violation_service.dart';
import '../services/low_ram_warning_service.dart';
import '../services/pending_purchase_recovery_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/performance_trace_service.dart';
import '../services/directions_service.dart';
import '../services/driver_location_icon_service.dart';
import '../services/camera_follow_engine.dart';
import '../services/map_style_service.dart';
import '../widgets/styled_google_map_builder.dart';
import '../services/route_utils.dart';
import '../services/passenger_map_realtime_socket.dart';
import '../services/traka_api_service.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/penumpang_map_overlays.dart';
import '../widgets/recommended_driver_glow_overlay.dart';
import '../widgets/kirim_barang_link_receiver_sheet.dart';
import '../widgets/passenger_duplicate_pending_order_dialog.dart';
import '../models/driver_track_state.dart';
import '../widgets/penumpang_driver_detail_sheet.dart';
import '../widgets/penumpang_route_form_sheet.dart';
import '../widgets/promotion_banner_widget.dart';
import 'data_order_screen.dart';
import 'violation_pay_screen.dart';
import 'pesan_screen.dart';
import 'chat_penumpang_screen.dart';
import 'chat_room_penumpang_screen.dart';
import 'profile_penumpang_screen.dart';
import 'login_screen.dart';
import '../widgets/traka_main_bottom_navigation_bar.dart';

class PenumpangScreen extends StatefulWidget {
  final String? prefillOrigin;
  final String? prefillDest;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;

  const PenumpangScreen({
    super.key,
    this.prefillOrigin,
    this.prefillDest,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
  });

  @override
  State<PenumpangScreen> createState() => _PenumpangScreenState();
}

class _PenumpangScreenState extends State<PenumpangScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  /// Tab 0 = beranda peta; untuk throttle animasi denyut lokasi.
  bool get _passengerMapTabVisible => _currentIndex == 0;
  final Set<int> _visitedTabIndices = {};
  GoogleMapController? _mapController;
  final CameraFollowEngine _passengerMapCameraEngine = CameraFollowEngine();
  MapType _mapType = MapType.normal; // Default: peta jalan
  /// Layer lalu lintas Google Maps (toggle; default aktif).
  bool _trafficEnabled = true;
  Position? _currentPosition;
  String _currentLocationText = 'Mengambil lokasi...';
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  final GlobalKey _formSectionKey = GlobalKey();
  String? _currentKabupaten; // subAdministrativeArea (kabupaten/kota)
  /// Slug kab/kota untuk Redis GEO hybrid — selaras dengan yang dikirim driver saat update lokasi.
  String? get _passengerCitySlugForGeoMatch =>
      PlacemarkFormatter.citySlugForGeoMatching(_currentKabupaten);
  String? _currentProvinsi; // administrativeArea (provinsi)
  String? _currentPulau; // pulau (diturunkan dari provinsi)
  Timer? _locationRefreshTimer;
  Timer? _authTokenRefreshTimer;

  /// Tunggu sebelum tampilkan "Sesi tidak valid" — hindari logout palsu saat token refresh (mis. setelah telpon WA).
  Timer? _sessionInvalidCheckTimer;
  bool _sessionInvalidConfirmed = false;
  StreamSubscription<User?>? _authStateSub;

  // State untuk driver aktif yang ditemukan
  List<ActiveDriverRoute> _foundDrivers = [];
  bool _isSearchingDrivers = false;
  bool _searchDriverFailed = false;
  double? _passengerDestLat;
  double? _passengerDestLng;

  // Cache icon mobil: CarIconService (traka_car_icons_premium) + PremiumPassengerCarIconSet
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;
  /// Titik biru lokasi penumpang (gaya Google Maps), menggantikan pin default.
  BitmapDescriptor? _passengerBlueDotIcon;

  late final AnimationController _passengerLocationPulseController;
  int _passengerLocationPulseBucket = -1;
  PremiumPassengerCarIconSet? _premiumCarIcons;
  /// Zoom peta terakhir untuk skala bitmap mobil (diselaraskan dengan [CarIconService.passengerMapZoomBucket]).
  double _mapZoomForCarIcons = MapStyleService.defaultZoom;
  int _carIconZoomBucket = CarIconService.passengerMapZoomBucket(
    MapStyleService.defaultZoom,
  );
  Timer? _carIconZoomDebounce;

  // Real-time + semut + snap-to-road untuk driver di map
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _driverStreamSubs = {};
  final Map<String, DriverTrackState> _driverTrackStates = {};
  final Map<String, List<LatLng>> _driverPolylines = {};
  Timer? _interpolationTimer;
  /// Redis → worker → Socket.IO (Tahap 4); opsional, fallback ke stream hybrid/Firestore.
  PassengerMapRealtimeSocket? _mapRealtimeSocket;
  /// Driver yang polyline-nya ditampilkan (hanya saat di-tap, agar map tidak ramai).
  String? _selectedDriverUidForPolyline;
  static const double _interpolationMinDistanceMeters = 0.5;
  /// Throttle setState: kurangi rebuild native marker (Google Maps) agar tap ikon stabil.
  DateTime? _lastInterpolationSetStateTime;
  static const int _interpolationSetStateMinMsIdle = 140;
  /// Saat user geser/zoom peta manual — kurangi rebuild agar tidak berebut dengan gesture.
  static const int _interpolationSetStateMinMsGesturing = 280;
  /// True saat kamera sedang digeser/di-zoom (bukan hanya idle).
  bool _passengerMapUserGesturing = false;

  /// Beranda: default north-up; true = kamera ikut bearing GPS (heading-up).
  bool _passengerMapFollowHeading = false;
  double? _lastPassengerHeadingDeg;
  StreamSubscription<Position>? _passengerHeadingPositionSub;

  // State untuk visibilitas form (disembunyikan setelah klik Cari)
  bool _isFormVisible = true;

  /// True jika pencarian terakhir via "Driver sekitar" (untuk retry & FAB Cari ulang).
  bool _lastSearchWasNearby = false;

  /// Banner: mode sekitar dari fallback (snackbar/dialog), bukan tap langsung "Driver sekitar".
  bool _showNearbyModeHintBanner = false;

  /// Jarak asal–tujuan (m) pada pencarian rute terakhir — untuk durasi sesi & petunjuk snackbar.
  double? _lastRouteSearchOdMeters;

  /// Radius terakhir mode «Driver sekitar» (meter); tampilan label & filter.
  double _nearbyFilterRadiusMeters =
      ActiveDriversService.maxDriverDistanceFromPickupMeters;

  /// Debounce: waktu terakhir tap "Driver sekitar" (mencegah double tap).
  DateTime? _lastDriverSekitarTapAt;

  /// Batasi durasi mode «driver di peta» (belum sepakat) — hemat API/baterai.
  Timer? _driverSearchSessionTimer;

  // State untuk tracking active travel order
  bool _hasActiveTravelOrder = false;
  /// Hanya log analytics `shown` sekali per periode blokir (false→true).
  bool _loggedTravelBlockOverlayShown = false;

  // State untuk mode "Pilih di Map"
  LatLng? _selectedDestinationPosition; // Posisi tujuan yang dipilih di map
  String? _selectedDestinationAddress; // Alamat dari reverse geocoding
  int _reverseGeocodeSeq = 0;

  // Badge unread chat penumpang
  StreamSubscription<List<OrderModel>>? _passengerOrdersSub;
  StreamSubscription<List<OrderModel>>? _receiverOrdersSub;
  List<OrderModel> _passengerOrdersForBadge = [];
  List<OrderModel> _receiverOrdersForBadge = [];
  int _chatUnreadCount = 0;
  void _onBadgeOptimisticChanged() {
    if (mounted) _updateChatUnreadCount();
  }

  /// Tab 1–4 lazy; panggil dari setState / handler — jangan mutasi [Set] ini di dalam build().
  void _registerTabVisit(int index) {
    if (index >= 1 && index <= 4) {
      _visitedTabIndices.add(index);
    }
  }

  @override
  void initState() {
    super.initState();
    _passengerLocationPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _passengerLocationPulseController.addListener(_onPassengerLocationPulseTick);
    NotificationNavigationService.registerOpenProfileTab(() {
      if (!mounted) return;
      setState(() {
        _registerTabVisit(4);
        _currentIndex = 4;
      });
    });
    unawaited(PerformanceTraceService.stopStartupToInteractive());
    WidgetsBinding.instance.addObserver(this);
    PendingPurchaseRecoveryService.startRecoveryListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NotificationNavigationService.maybeExecutePendingNavigation(context);
    });
    _startAuthTokenRefreshTimer();
    _destinationFocusNode.addListener(_onDestinationFocusChange);
    // Notifikasi: kesepakatan sudah terjadi + driver mendekati (5 km, 1 km, 500 m)
    PassengerProximityNotificationService.start();
    // Notifikasi penerima Lacak Barang: driver mendekati (5 km, 1 km, 500 m)
    ReceiverProximityNotificationService.start();
    // Cek apakah ada active travel order
    _checkActiveTravelOrder();
    // Decode bitmap marker setelah frame pertama — hindari jank saat transisi login → beranda.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadCarIcons());
        unawaited(_loadPassengerBlueDotOnce());
      }
    });
    // Tampilkan lokasi cache dulu (cepat), lalu lokasi akurat di background
    Future.microtask(() async {
      if (!mounted) return;
      final cached = await LocationService.getCachedPosition();
      if (cached != null && mounted) {
        setState(() => _currentPosition = cached);
        _updateLocationText(cached);
        if (_mapController != null && mounted) {
          unawaited(_applyPassengerMapCamera(force: true));
        }
      }
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _getCurrentLocation();
      });
    });
    // Refresh lokasi setiap 30 detik (hemat baterai & data)
    _locationRefreshTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      _getCurrentLocation();
    });

    // Peringatan RAM rendah (sekali saja, jika < 4GB)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LowRamWarningService.checkAndShowIfNeeded(context);
    });

    // Jika ada prefill origin dan dest, langsung cari driver aktif
    if (widget.prefillOrigin != null &&
        widget.prefillDest != null &&
        widget.originLat != null &&
        widget.originLng != null &&
        widget.destLat != null &&
        widget.destLng != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchDriversWithPrefill();
        }
      });
    }

    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        _sessionInvalidCheckTimer?.cancel();
        _sessionInvalidConfirmed = false;
        setState(() {});
      }
    });
    // Stream pesanan penumpang + receiver untuk badge unread chat
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _passengerOrdersSub =
          OrderService.streamOrdersForPassenger(includeHidden: false).listen(
        (orders) {
          if (!mounted) return;
          setState(() => _passengerOrdersForBadge = orders);
          _updateChatUnreadCount();
          // Cek ulang active travel order saat data pesanan berubah (mis. kesepakatan baru)
          _checkActiveTravelOrder();
        },
      );
      _receiverOrdersSub =
          OrderService.streamOrdersForReceiver(uid, includeHidden: false).listen(
        (orders) {
          if (!mounted) return;
          setState(() => _receiverOrdersForBadge = orders);
          _updateChatUnreadCount();
        },
      );
      ChatBadgeService.instance.addListener(_onBadgeOptimisticChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshAuthTokenSilently();
      _checkActiveTravelOrder();
      if (mounted) unawaited(_getCurrentLocation());
    }
  }

  void _refreshAuthTokenSilently() {
    AuthSessionService.refreshTokenSilently();
  }

  void _startAuthTokenRefreshTimer() {
    _authTokenRefreshTimer?.cancel();
    _authTokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 25),
      (_) => _refreshAuthTokenSilently(),
    );
  }

  void _updateChatUnreadCount() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    int count = 0;
    final badgeService = ChatBadgeService.instance;
    for (final o in _passengerOrdersForBadge) {
      if (o.isCompleted || o.status == OrderService.statusCancelled) continue;
      if (badgeService.isOptimisticRead(o.id)) continue;
      if (o.hasUnreadChatForPassenger(uid)) {
        count++;
      }
    }
    for (final o in _receiverOrdersForBadge) {
      if (o.isCompleted || o.status == OrderService.statusCancelled) continue;
      if (badgeService.isOptimisticRead(o.id)) continue;
      if (o.hasUnreadChatForReceiver(uid)) {
        count++;
      }
    }
    setState(() => _chatUnreadCount = count);
  }

  /// Snackbar jika pencarian rute tidak ada hasil: tawarkan mode [Driver sekitar].
  void _showNoRouteMatchSnackBarWithNearbyAction({double? odMeters}) {
    if (!mounted) return;
    final isLongOd = odMeters != null && odMeters >= 70000;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TrakaL10n.of(context).noActiveDriversForRoute),
            const SizedBox(height: 6),
            Text(
              TrakaL10n.of(context).noRouteMatchSnackHintLine,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
            if (isLongOd) ...[
              const SizedBox(height: 6),
              Text(
                TrakaL10n.of(context).noRouteMatchLongTripExtraLine,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
            ],
          ],
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: TrakaL10n.of(context).showNearbyDriversAction,
          onPressed: () {
            AppAnalyticsService.logPassengerDriverSearchOutcome(
              outcome: 'nearby_fallback_from_route',
              searchMode: 'route',
            );
            unawaited(_onDriverSekitarTap(force: true, fromRouteFallback: true));
          },
        ),
      ),
    );
  }

  Future<void> _showDirectionsAllFailedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = TrakaL10n.of(ctx);
        return AlertDialog(
          title: Text(l10n.routeDirectionsAllFailedTitle),
          content: Text(l10n.routeDirectionsAllFailedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                AppAnalyticsService.logPassengerDriverSearchOutcome(
                  outcome: 'nearby_fallback_from_route',
                  searchMode: 'route',
                );
                unawaited(_onDriverSekitarTap(force: true, fromRouteFallback: true));
              },
              child: Text(l10n.showNearbyDriversAction),
            ),
          ],
        );
      },
    );
  }

  /// Cari driver aktif dengan origin dan destination yang sudah diisi dari pesan_screen.
  Future<void> _searchDriversWithPrefill() async {
    _lastSearchWasNearby = false;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'route');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (_abortSearchIfTravelHomeBlocked()) return;
    if (widget.originLat == null ||
        widget.originLng == null ||
        widget.destLat == null ||
        widget.destLng == null) {
      return;
    }

    // Set destination controller dengan prefill dest
    if (widget.prefillDest != null) {
      _destinationController.text = widget.prefillDest!;
      _passengerDestLat = widget.destLat;
      _passengerDestLng = widget.destLng;
    }

    // Set current position dengan origin yang sudah diisi
    if (widget.originLat != null && widget.originLng != null) {
      setState(() {
        _currentPosition = Position(
          latitude: widget.originLat!,
          longitude: widget.originLng!,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
        _currentLocationText = widget.prefillOrigin ?? 'Lokasi awal';
      });
    }

    // Langsung cari driver aktif menggunakan logika yang sama
    _cancelDriverSearchSessionTimer();
    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
    });

    try {
      final oLat = widget.originLat;
      final oLng = widget.originLng;
      final dLat = widget.destLat;
      final dLng = widget.destLng;
      _lastRouteSearchOdMeters = (oLat != null && oLng != null && dLat != null && dLng != null)
          ? Geolocator.distanceBetween(oLat, oLng, dLat, dLng)
          : null;
      final mapResult = await ActiveDriversService.getActiveDriversForMapResult(
        passengerOriginLat: oLat,
        passengerOriginLng: oLng,
        passengerDestLat: dLat,
        passengerDestLng: dLng,
        city: _passengerCitySlugForGeoMatch,
      );

      if (mounted) {
        if (mapResult.allCandidatesFailedAtDirections) {
          setState(() {
            _isSearchingDrivers = false;
            _searchDriverFailed = false;
          });
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_directions_all_failed',
            searchMode: 'prefill',
          );
          await _showDirectionsAllFailedDialog();
          return;
        }
        setState(() {
          _foundDrivers = mapResult.drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
          if (mapResult.drivers.isNotEmpty) {
            _showNearbyModeHintBanner = false;
          }
        });

        if (_foundDrivers.isEmpty) {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_empty',
            driverCount: 0,
            searchMode: 'prefill',
          );
          _showNoRouteMatchSnackBarWithNearbyAction(
            odMeters: _lastRouteSearchOdMeters,
          );
        } else {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_ok',
            driverCount: mapResult.drivers.length,
            searchMode: 'prefill',
          );
          // Urutan: load icon dulu, baru setup stream (agar marker siap saat render).
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) {
            _scheduleDriverSearchSessionExpiry();
            _updateMapCameraForDrivers();
            _schedulePassengerMapDriverMarkersRefresh();
          }
        }
      }
    } catch (e, st) {
      logError('PenumpangScreen._searchDriversWithPrefill', e, st);
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
          _searchDriverFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TrakaL10n.of(context).searchDriverFailed}: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: TrakaL10n.of(context).retry,
              onPressed: () => _searchDriversWithPrefill(),
            ),
          ),
        );
      }
    }
  }

  /// Travel yang memblokir beranda: satu sumber kebenaran [OrderService.passengerOrdersContainBlockingTravel].
  Future<void> _checkActiveTravelOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = false;
        });
      }
      return;
    }

    try {
      final orders = await OrderService.getOrdersForPassenger(user.uid);
      final activeTravelOrder =
          OrderService.passengerOrdersContainBlockingTravel(orders);

      if (mounted) {
        final wasBlocking = _hasActiveTravelOrder;
        setState(() {
          _hasActiveTravelOrder = activeTravelOrder;
          if (!activeTravelOrder) {
            _loggedTravelBlockOverlayShown = false;
          }
        });
        if (activeTravelOrder && !wasBlocking) {
          _clearDriversBecauseTravelBlocking();
        }
        if (activeTravelOrder && !wasBlocking && !_loggedTravelBlockOverlayShown) {
          _loggedTravelBlockOverlayShown = true;
          AppAnalyticsService.logPassengerHomeTravelBlock(action: 'shown');
        }
      }
    } catch (e, st) {
      logError('PenumpangScreen._checkActiveTravelOrder', e, st);
      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = false;
          _loggedTravelBlockOverlayShown = false;
        });
      }
    }
  }

  void _cancelDriverSearchSessionTimer() {
    _driverSearchSessionTimer?.cancel();
    _driverSearchSessionTimer = null;
  }

  /// Radius «Driver sekitar» (km) untuk label tombol & banner memuat — mempertimbangkan OD rute terakhir.
  int get _driverSekitarRadiusKmLabel {
    if (_isFormVisible && _lastRouteSearchOdMeters != null) {
      return (ActiveDriversService.nearbySearchRadiusMetersForPriorOd(
                _lastRouteSearchOdMeters,
              ) /
              1000)
          .round()
          .clamp(1, 200);
    }
    return (_nearbyFilterRadiusMeters / 1000).round().clamp(1, 200);
  }

  /// Setelah travel punya kesepakatan harga: hentikan tracking driver di peta (di belakang overlay).
  void _clearDriversBecauseTravelBlocking() {
    _cancelDriverSearchSessionTimer();
    final hadSession =
        _foundDrivers.isNotEmpty || _driverStreamSubs.isNotEmpty;
    if (!hadSession) return;
    _disposeDriverTracking();
    if (!mounted) return;
    setState(() {
      _foundDrivers = [];
      _isSearchingDrivers = false;
      _searchDriverFailed = false;
      _showNearbyModeHintBanner = false;
    });
  }

  void _scheduleDriverSearchSessionExpiry() {
    _cancelDriverSearchSessionTimer();
    if (_foundDrivers.isEmpty) return;
    final minutes = AppConstants.passengerDriverSearchSessionMinutesForOd(
      _lastRouteSearchOdMeters,
    );
    _driverSearchSessionTimer = Timer(
      Duration(minutes: minutes),
      _onDriverSearchSessionExpired,
    );
  }

  void _onDriverSearchSessionExpired() {
    _driverSearchSessionTimer = null;
    if (!mounted) return;
    if (_hasActiveTravelOrder) return;
    if (_foundDrivers.isEmpty) return;
    _disposeDriverTracking();
    setState(() {
      _foundDrivers = [];
      _isFormVisible = true;
      _showNearbyModeHintBanner = false;
      _isSearchingDrivers = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TrakaL10n.of(context).passengerDriverSearchSessionExpiredBody,
        ),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// True = hentikan (sudah ada travel dengan kesepakatan — beranda diblokir).
  bool _abortSearchIfTravelHomeBlocked() {
    if (!_hasActiveTravelOrder) return false;
    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(TrakaL10n.of(context).activeTravelOrderSubtitle),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return true;
  }

  void _onDestinationFocusChange() {
    if (_destinationFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _formSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _passengerLocationPulseController
      ..removeListener(_onPassengerLocationPulseTick)
      ..dispose();
    NotificationNavigationService.unregisterOpenProfileTab();
    WidgetsBinding.instance.removeObserver(this);
    _authTokenRefreshTimer?.cancel();
    _sessionInvalidCheckTimer?.cancel();
    _authStateSub?.cancel();
    PassengerProximityNotificationService.stop();
    ReceiverProximityNotificationService.stop();
    _disposeDriverTracking();
    _passengerOrdersSub?.cancel();
    _receiverOrdersSub?.cancel();
    ChatBadgeService.instance.removeListener(_onBadgeOptimisticChanged);
    _cancelDriverSearchSessionTimer();
    _destinationFocusNode.removeListener(_onDestinationFocusChange);
    _destinationFocusNode.dispose();
    _locationRefreshTimer?.cancel();
    _carIconZoomDebounce?.cancel();
    _destinationController.dispose();
    _passengerHeadingPositionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// [disposeRealtimeSocket]: false saat Map WS aktif — hindari putus/sambung Socket.IO
  /// tiap pencarian (mahal) dan biarkan [PassengerMapRealtimeSocket.connect] reuse.
  void _disposeDriverTracking({bool disposeRealtimeSocket = true}) {
    if (disposeRealtimeSocket) {
      _mapRealtimeSocket?.dispose();
      _mapRealtimeSocket = null;
    }
    for (final sub in _driverStreamSubs.values) {
      sub.cancel();
    }
    _driverStreamSubs.clear();
    _driverTrackStates.clear();
    _driverPolylines.clear();
    _interpolationTimer?.cancel();
    _interpolationTimer = null;
  }

  double _passengerMapBearingDegrees() {
    if (!_passengerMapFollowHeading) return 0;
    final p = _currentPosition;
    if (p == null) return 0;
    final h = p.heading;
    if (h.isFinite && h != 0) {
      _lastPassengerHeadingDeg = h;
      return h;
    }
    return _lastPassengerHeadingDeg ?? 0;
  }

  Future<void> _applyPassengerMapCamera({bool force = false}) async {
    final c = _mapController;
    if (c == null || !mounted) return;
    final pos = _currentPosition;
    if (pos == null) return;
    try {
      final zoom = await c.getZoomLevel();
      _passengerMapCameraEngine.tryAnimateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.latitude, pos.longitude),
            zoom: zoom,
            tilt: MapStyleService.defaultTilt,
            bearing: _passengerMapBearingDegrees(),
          ),
        ),
        duration: const Duration(milliseconds: 320),
        force: force,
      );
    } catch (_) {}
  }

  void _onPassengerMapHeadingToggle() {
    HapticFeedback.lightImpact();
    setState(() {
      _passengerMapFollowHeading = !_passengerMapFollowHeading;
    });
    if (_passengerMapFollowHeading) {
      _startPassengerHeadingStream();
      unawaited(_applyPassengerMapCamera(force: true));
    } else {
      _passengerHeadingPositionSub?.cancel();
      _passengerHeadingPositionSub = null;
      unawaited(_applyPassengerMapCamera(force: true));
    }
  }

  void _startPassengerHeadingStream() {
    _passengerHeadingPositionSub?.cancel();
    _passengerHeadingPositionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      (position) {
        if (!mounted || !_passengerMapFollowHeading) return;
        setState(() {
          _currentPosition = position;
        });
        unawaited(_applyPassengerMapCamera(force: false));
      },
      onError: (_) {},
    );
  }

  Future<void> _setupDriverTracking() async {
    _disposeDriverTracking(
      disposeRealtimeSocket: !TrakaRealtimeConfig.isEnabled,
    );
    if (_foundDrivers.isEmpty) return;

    for (var i = 0; i < _foundDrivers.length; i++) {
      final driver = _foundDrivers[i];
      final pos = LatLng(driver.driverLat, driver.driverLng);
      final state = DriverTrackState(
        displayed: pos,
        target: pos,
        lastUpdated: driver.lastUpdated,
      );
      _driverTrackStates[driver.driverUid] = state;

      // Bearing awal: driver -> tujuan rute (agar icon tidak menghadap sembarangan)
      try {
        final dest = LatLng(driver.routeDestLat, driver.routeDestLng);
        state.bearing = RouteUtils.bearingBetween(pos, dest);
        state.smoothedBearing = state.bearing;
      } catch (_) {}

      // Fetch rute driver untuk interpolasi + tampilan polyline. Max 8 agar tidak terlalu banyak API.
      if (i >= 8) continue;
      final result = await DirectionsService.getRoute(
        originLat: driver.routeOriginLat,
        originLng: driver.routeOriginLng,
        destLat: driver.routeDestLat,
        destLng: driver.routeDestLng,
      );
      if (result != null && result.points.length >= 2) {
        _driverPolylines[driver.driverUid] = result.points;
      }

      // Hybrid API mem-poll tiap 4 d per driver — jika Map WS aktif, lokasi live
      // sudah lewat Socket.IO; dobel stream = beban jaringan + jank.
      if (!TrakaRealtimeConfig.isEnabled) {
        _driverStreamSubs[driver.driverUid] = DriverStatusService
            .streamDriverStatusData(driver.driverUid)
            .listen((d) => _onDriverStatusUpdate(driver.driverUid, d));
      }
    }

    _startInterpolationTimer();
    await _maybeStartPassengerMapRealtimeSocket();
    if (kDebugMode && _foundDrivers.isNotEmpty) {
      if (TrakaRealtimeConfig.isEnabled) {
        debugPrint(
          'Traka map: Socket.IO ON (${TrakaRealtimeConfig.realtimeWsUrl.trim()}) — '
          'DriverStatusService polling OFF, ${_foundDrivers.length} driver.',
        );
      } else {
        debugPrint(
          'Traka map: Socket.IO OFF — DriverStatusService polling ON '
          'untuk ${_foundDrivers.length} driver.',
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _maybeStartPassengerMapRealtimeSocket() async {
    if (!TrakaRealtimeConfig.isEnabled) return;
    final pos = _currentPosition;
    if (pos == null || _foundDrivers.isEmpty) return;

    String? auth;
    final staticTok = TrakaRealtimeConfig.socketAuthToken.trim();
    if (staticTok.isNotEmpty) {
      auth = staticTok;
    } else {
      auth = await TrakaApiService.fetchRealtimeMapWsTicket();
      if (auth == null && kDebugMode) {
        debugPrint(
          'Traka map WS: no ws-ticket (login/API secret?). Open worker still OK if no auth env.',
        );
      }
    }

    _mapRealtimeSocket ??= PassengerMapRealtimeSocket();
    _mapRealtimeSocket!.connect(
      url: TrakaRealtimeConfig.realtimeWsUrl.trim(),
      authToken: auth,
      lat: pos.latitude,
      lng: pos.longitude,
      onDriverLocation: _onRealtimeDriverLocation,
    );
  }

  void _onRealtimeDriverLocation(Map<String, dynamic> d) {
    if (!mounted) return;
    final uid = d['uid'] as String?;
    if (uid == null || !_driverTrackStates.containsKey(uid)) return;
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final ts = d['ts'];
    int? tsMs;
    if (ts is int) {
      tsMs = ts;
    } else if (ts is num) {
      tsMs = ts.toInt();
    }
    _onDriverStatusUpdate(uid, {
      'latitude': lat,
      'longitude': lng,
      if (tsMs != null) 'lastUpdated': tsMs,
    });
  }

  void _onDriverStatusUpdate(String driverUid, Map<String, dynamic>? d) {
    if (!mounted) return;
    final state = _driverTrackStates[driverUid];
    if (state == null) return;
    if (d == null) return;

    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    final lastUpdatedRaw = d['lastUpdated'];
    DateTime? lastUpdated;
    if (lastUpdatedRaw is Timestamp) {
      lastUpdated = lastUpdatedRaw.toDate();
    } else if (lastUpdatedRaw is String) {
      lastUpdated = DateTime.tryParse(lastUpdatedRaw);
    } else if (lastUpdatedRaw is int) {
      lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedRaw);
    } else if (lastUpdatedRaw is num) {
      lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedRaw.toInt());
    }
    if (lat == null || lng == null) return;

    // Posisi aktual GPS (tidak di-snap ke jalan—driver bisa parkir/di samping jalan)
    final rawLatLng = LatLng(lat, lng);
    int targetSeg = -1;
    double targetRatio = 0;
    final polyline = _driverPolylines[driverUid];
    if (polyline != null && polyline.length >= 2) {
      final projected = RouteUtils.projectPointOntoPolyline(
        rawLatLng,
        polyline,
        maxDistanceMeters: 150,
      );
      targetSeg = projected.$2;
      targetRatio = projected.$3;
    }

    state.target = rawLatLng;
    state.lastUpdated = lastUpdated;
    state.interpEndSeg = targetSeg;
    state.interpEndRatio = targetRatio;
    state.usePolyline = false;
    state.progress = 0;

    // Jangan setState di sini — tiap driver bisa memicu beberapa kali/detik dan membebani UI.
    // Timer interpolasi memindahkan `displayed` → `target` dan memanggil setState ter-throttle.
  }

  void _startInterpolationTimer() {
    _interpolationTimer?.cancel();
    _interpolationTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.passengerMapInterpolationIntervalMs),
      (_) {
        if (!mounted || _currentIndex != 0) return;
        bool changed = false;
        for (final entry in _driverTrackStates.entries) {
          final state = entry.value;
          final dist = Geolocator.distanceBetween(
            state.displayed.latitude,
            state.displayed.longitude,
            state.target.latitude,
            state.target.longitude,
          );
          if (dist < _interpolationMinDistanceMeters) {
            state.displayed = state.target;
          } else {
            // Ease-in-out: lebih cepat saat jauh, melambat saat dekat
            final factor = (0.15 + 0.25 * (dist / 100).clamp(0.0, 1.0)).clamp(0.0, 1.0);
            final lat = state.displayed.latitude + (state.target.latitude - state.displayed.latitude) * factor;
            final lng = state.displayed.longitude + (state.target.longitude - state.displayed.longitude) * factor;
            state.displayed = LatLng(lat, lng);
          }
          // Bearing untuk rotasi icon: arah displayed -> target. Asset depan = selatan.
          try {
            state.bearing = RouteUtils.bearingBetween(state.displayed, state.target);
            state.smoothedBearing = RouteUtils.smoothBearingDegrees(
              state.smoothedBearing,
              state.bearing,
              alpha: AppConstants.passengerMapBearingSmoothAlpha,
            );
          } catch (_) {
            // Koordinat invalid: pertahankan bearing sebelumnya
          }
          changed = true;
        }
        if (changed && mounted && _currentIndex == 0) {
          final now = DateTime.now();
          final minMs = _passengerMapUserGesturing
              ? _interpolationSetStateMinMsGesturing
              : _interpolationSetStateMinMsIdle;
          if (_lastInterpolationSetStateTime == null ||
              now.difference(_lastInterpolationSetStateTime!).inMilliseconds >=
                  minMs) {
            _lastInterpolationSetStateTime = now;
            setState(() {});
          }
        }
      },
    );
  }

  /// Cek pelanggaran belum bayar; jika ada, redirect ke layar bayar dan return true.
  Future<bool> _checkAndRedirectIfOutstandingViolation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final hasOutstanding = await ViolationService.hasOutstandingViolation(user.uid);
    if (hasOutstanding && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ViolationPayScreen(),
        ),
      );
      return true;
    }
    return false;
  }

  /// Fungsi tombol Cari: tetap di halaman beranda dan tampilkan driver aktif sesuai kriteria
  Future<void> _onSearch() async {
    _lastSearchWasNearby = false;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'route');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (_abortSearchIfTravelHomeBlocked()) return;
    if (!mounted) return;
    // Validasi: form tujuan harus diisi
    final tujuanText = _destinationController.text.trim();
    if (tujuanText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).fillDestinationFirst),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validasi: lokasi penumpang harus tersedia
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).waitingPassengerLocation),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _cancelDriverSearchSessionTimer();
    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
    });

    try {
      // Geocode tujuan penumpang untuk mendapatkan koordinat
      // Prioritas: gunakan koordinat dari map selection jika ada, jika tidak geocode dari text
      double? destLat = _passengerDestLat;
      double? destLng = _passengerDestLng;

      if (destLat == null || destLng == null) {
        try {
          final locations = await GeocodingService.locationFromAddress(
            tujuanText,
          );
          if (locations.isNotEmpty) {
            destLat = locations.first.latitude;
            destLng = locations.first.longitude;
            _passengerDestLat = destLat;
            _passengerDestLng = destLng;
            // Update marker tujuan jika belum ada
            if (_selectedDestinationPosition == null) {
              _selectedDestinationPosition = LatLng(destLat, destLng);
              _selectedDestinationAddress = tujuanText;
            }
          } else {
            throw Exception('Tujuan tidak ditemukan');
          }
    } catch (e, st) {
      logError('PenumpangScreen._onSearch geocode/dest', e, st);
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
        });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(TrakaL10n.of(context).failedToFindDestinationDetail(e)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      // Cari driver aktif sesuai kriteria:
      // - Rute driver harus melewati lokasi awal dan tujuan penumpang (berdasarkan polyline)
      // - Sebelum driver melewati titik awal penumpang: jarak <= 50 km dari titik awal penumpang, maksimal 20 driver
      // - Setelah driver melewati titik awal penumpang: jarak <= 10 km dari titik awal penumpang, maksimal 10 driver
      _lastRouteSearchOdMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        destLat,
        destLng,
      );
      final mapResult = await ActiveDriversService.getActiveDriversForMapResult(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
        city: _passengerCitySlugForGeoMatch,
      );

      if (mounted) {
        if (mapResult.allCandidatesFailedAtDirections) {
          setState(() {
            _isSearchingDrivers = false;
            _searchDriverFailed = false;
          });
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_directions_all_failed',
            searchMode: 'route',
          );
          await _showDirectionsAllFailedDialog();
          return;
        }
        setState(() {
          _foundDrivers = mapResult.drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
          if (mapResult.drivers.isNotEmpty) {
            _showNearbyModeHintBanner = false;
          }
        });

        if (_foundDrivers.isEmpty) {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_empty',
            driverCount: 0,
            searchMode: 'route',
          );
          _showNoRouteMatchSnackBarWithNearbyAction(
            odMeters: _lastRouteSearchOdMeters,
          );
        } else {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_ok',
            driverCount: mapResult.drivers.length,
            searchMode: 'route',
          );
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) {
            _scheduleDriverSearchSessionExpiry();
            _updateMapCameraForDrivers();
            _schedulePassengerMapDriverMarkersRefresh();
          }
        }
      }
    } catch (e, st) {
      logError('PenumpangScreen._onSearch', e, st);
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
          _searchDriverFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TrakaL10n.of(context).searchDriverFailed}: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: TrakaL10n.of(context).retry,
              onPressed: () => _onSearch(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _currentLocationText = 'Izin lokasi tidak diberikan';
        });
      }
      return;
    }

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

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _currentLocationText = 'GPS tidak aktif. Silakan aktifkan GPS.';
          });
        }
        return;
      }
    }

    try {
      // Force refresh untuk mendapatkan lokasi terbaru (tidak cache)
      // Retry maksimal 2 kali jika gagal mendapatkan lokasi
      Position? position;
      for (int retry = 0; retry < 3; retry++) {
        final result =
            await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
        );
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
        final result =
            await LocationService.getCurrentPositionWithMockCheck(
          forceRefresh: true,
        );
        if (result.isFakeGpsDetected) {
          if (mounted) FakeGpsOverlayService.showOverlay();
          return;
        }
        position = result.position;
      }

      if (position != null && mounted) {
        final previousPosition = _currentPosition;
        setState(() {
          _currentPosition = position;
        });
        _mapRealtimeSocket?.updatePassengerPosition(
          position.latitude,
          position.longitude,
        );
        await _updateLocationText(position);

        // Update marker di maps jika lokasi berubah signifikan (lebih dari 10 meter)
        if (previousPosition != null) {
          final distance = Geolocator.distanceBetween(
            previousPosition.latitude,
            previousPosition.longitude,
            position.latitude,
            position.longitude,
          );

          // Jika perpindahan lebih dari 10 meter, update camera
          if (distance > 10 && _mapController != null && mounted) {
            unawaited(_applyPassengerMapCamera(force: true));
          }
        } else if (_mapController != null && mounted) {
          // Jika ini pertama kali dapat lokasi, animate ke lokasi tersebut
          unawaited(_applyPassengerMapCamera(force: true));
        }
      } else if (mounted) {
        setState(() {
          _currentLocationText = 'Tidak dapat memperoleh lokasi';
        });
      }
    } catch (e, st) {
      logError('PenumpangScreen._getCurrentLocation', e, st);
      if (mounted) {
        setState(() {
          _currentLocationText = 'Error: $e';
        });
      }
    }
  }

  Future<void> _updateLocationText(Position position) async {
    try {
      // Pastikan menggunakan koordinat terbaru, bukan cache
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final provinsi = place.administrativeArea ?? '';
        final kabupaten = place.subAdministrativeArea ?? '';

        // Pastikan state masih mounted sebelum update
        if (!mounted) return;

        setState(() {
          _currentProvinsi = provinsi.isNotEmpty ? provinsi : null;
          _currentKabupaten = kabupaten.isNotEmpty ? kabupaten : null;
          _currentPulau = _derivePulauFromProvinsi(provinsi);
          // Format untuk lokasi asal: hanya kecamatan, kabupaten, provinsi
          _currentLocationText = _formatPlacemarkForOrigin(place);
        });
      } else if (mounted) {
        // Jika tidak ada placemark, tampilkan koordinat
        setState(() {
          _currentLocationText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentLocationText =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  /// Mengembalikan nama pulau dari nama provinsi (Indonesia).
  String? _derivePulauFromProvinsi(String provinsi) {
    if (provinsi.isEmpty) return null;
    final p = provinsi.toLowerCase();
    if (p.contains('kalimantan')) return 'Kalimantan';
    if (p.contains('jawa')) return 'Jawa';
    if (p.contains('sumatra') || p.contains('sumatera')) return 'Sumatra';
    if (p.contains('sulawesi')) return 'Sulawesi';
    if (p.contains('bali')) return 'Bali';
    if (p.contains('nusa tenggara')) return 'Nusa Tenggara';
    if (p.contains('maluku')) return 'Maluku';
    if (p.contains('papua')) return 'Papua';
    return null;
  }

  String _formatPlacemarkForOrigin(Placemark placemark) =>
      PlacemarkFormatter.formatShort(placemark);

  /// Handler saat marker tujuan di-drag
  void _onDestinationMarkerDragged(LatLng newPosition) async {
    setState(() {
      _selectedDestinationPosition = newPosition;
      _passengerDestLat = newPosition.latitude;
      _passengerDestLng = newPosition.longitude;
      _selectedDestinationAddress = 'Memuat alamat...';
    });

    await _reverseGeocodeDestination(newPosition);
  }

  /// Reverse geocode koordinat menjadi alamat dan update form
  Future<void> _reverseGeocodeDestination(LatLng position) async {
    final seq = ++_reverseGeocodeSeq;
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (!mounted || seq != _reverseGeocodeSeq) return;

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final displayText = PlacemarkFormatter.formatDetail(placemark);

        setState(() {
          _selectedDestinationAddress = displayText;
          _destinationController.text = displayText;
        });
      } else {
        setState(() {
          _selectedDestinationAddress = 'Lokasi tidak ditemukan';
          _destinationController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      // Jika error, gunakan koordinat sebagai fallback
      if (mounted && seq == _reverseGeocodeSeq) {
        setState(() {
          _selectedDestinationAddress =
              'Koordinat: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _destinationController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }
    }
  }

  void _toggleMapType() {
    setState(() {
      // Toggle antara normal dan hybrid (satelit dengan label)
      _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  void _togglePassengerTraffic() {
    setState(() {
      _trafficEnabled = !_trafficEnabled;
    });
  }

  /// Buka form pencarian dalam modal bottom sheet (seperti form driver)
  void _showSearchFormSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => PenumpangRouteFormSheet(
        originText: _currentLocationText,
        currentKabupaten: _currentKabupaten,
        currentProvinsi: _currentProvinsi,
        currentPulau: _currentPulau,
        originLat: _currentPosition?.latitude,
        originLng: _currentPosition?.longitude,
        initialDest: _destinationController.text.trim().isEmpty
            ? null
            : _destinationController.text,
        mapController: _mapController,
        onSearch: (
          String destText,
          double destLat,
          double destLng,
        ) async {
          Navigator.pop(ctx);
          await _onSearchFromSheet(destText, destLat, destLng);
        },
      ),
    );
  }

  /// Tujuan siap untuk order: teks + koordinat (bukan placeholder).
  bool _destinationCompleteForOrder() {
    final t = _destinationController.text.trim();
    if (t.isEmpty) return false;
    return _passengerDestLat != null && _passengerDestLng != null;
  }

  void _applyDestinationFromGate(
    String destText,
    double destLat,
    double destLng,
  ) {
    setState(() {
      _destinationController.text = destText;
      _passengerDestLat = destLat;
      _passengerDestLng = destLng;
      _selectedDestinationPosition = LatLng(destLat, destLng);
      _selectedDestinationAddress = destText;
    });
  }

  /// Sheet isi tujuan sebelum Pesan Travel / Kirim Barang dari detail driver.
  void _showDestinationGateSheet({required VoidCallback onDestinationReady}) {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).waitingPassengerLocation),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => PenumpangRouteFormSheet(
        sheetTitle: 'Isi tujuan perjalanan',
        primaryButtonLabel: 'Lanjutkan',
        primaryButtonIcon: Icons.arrow_forward,
        originText: _currentLocationText,
        currentKabupaten: _currentKabupaten,
        currentProvinsi: _currentProvinsi,
        currentPulau: _currentPulau,
        originLat: _currentPosition?.latitude,
        originLng: _currentPosition?.longitude,
        initialDest: _destinationController.text.trim().isEmpty
            ? null
            : _destinationController.text,
        mapController: _mapController,
        onSearch: (destText, destLat, destLng) {
          Navigator.pop(ctx);
          _applyDestinationFromGate(destText, destLat, destLng);
          onDestinationReady();
        },
      ),
    );
  }

  /// Handler Cari dari form sheet
  Future<void> _onSearchFromSheet(
    String destText,
    double destLat,
    double destLng,
  ) async {
    _lastSearchWasNearby = false;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'route');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (_abortSearchIfTravelHomeBlocked()) return;
    _cancelDriverSearchSessionTimer();
    setState(() {
      _destinationController.text = destText;
      _passengerDestLat = destLat;
      _passengerDestLng = destLng;
      _selectedDestinationPosition = LatLng(destLat, destLng);
      _selectedDestinationAddress = destText;
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
    });

    if (_currentPosition == null) {
      setState(() => _isSearchingDrivers = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).waitingPassengerLocation),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      _lastRouteSearchOdMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        destLat,
        destLng,
      );
      final mapResult = await ActiveDriversService.getActiveDriversForMapResult(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
        city: _passengerCitySlugForGeoMatch,
      );

      if (mounted) {
        if (mapResult.allCandidatesFailedAtDirections) {
          setState(() {
            _isSearchingDrivers = false;
            _searchDriverFailed = false;
          });
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_directions_all_failed',
            searchMode: 'route_sheet',
          );
          await _showDirectionsAllFailedDialog();
          return;
        }
        setState(() {
          _foundDrivers = mapResult.drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false;
          if (mapResult.drivers.isNotEmpty) {
            _showNearbyModeHintBanner = false;
          }
        });

        if (_foundDrivers.isEmpty) {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_empty',
            driverCount: 0,
            searchMode: 'route_sheet',
          );
          _showNoRouteMatchSnackBarWithNearbyAction(
            odMeters: _lastRouteSearchOdMeters,
          );
        } else {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'route_search_ok',
            driverCount: mapResult.drivers.length,
            searchMode: 'route_sheet',
          );
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) {
            _scheduleDriverSearchSessionExpiry();
            _updateMapCameraForDrivers();
            _schedulePassengerMapDriverMarkersRefresh();
          }
        }
      }
    } catch (e, st) {
      logError('PenumpangScreen._onSearchFromSheet', e, st);
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
          _searchDriverFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TrakaL10n.of(context).searchDriverFailed}: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: TrakaL10n.of(context).retry,
              onPressed: () => _onSearchFromSheet(destText, destLat, destLng),
            ),
          ),
        );
      }
    }
  }

  /// Driver sekitar: tampilkan driver aktif dalam radius 40 km tanpa isi tujuan.
  /// [force]: lewati debounce (mis. dari snackbar "Driver sekitar").
  /// [fromRouteFallback]: dari snackbar/dialog setelah rute kosong — tampilkan banner penjelasan di peta.
  Future<void> _onDriverSekitarTap({
    bool force = false,
    bool fromRouteFallback = false,
  }) async {
    // Debounce 2 detik
    final now = DateTime.now();
    if (!force &&
        _lastDriverSekitarTapAt != null &&
        now.difference(_lastDriverSekitarTapAt!).inSeconds < 2) {
      return;
    }
    _lastDriverSekitarTapAt = now;
    _lastSearchWasNearby = true;
    final priorRouteOd = _lastRouteSearchOdMeters;
    _lastRouteSearchOdMeters = null;
    final nearbyRadius = ActiveDriversService.nearbySearchRadiusMetersForPriorOd(
      priorRouteOd,
    );
    AppAnalyticsService.logPassengerSearchDriver(mode: 'nearby');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (_abortSearchIfTravelHomeBlocked()) return;
    if (!mounted) return;
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).waitingPassengerLocation),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _cancelDriverSearchSessionTimer();
    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
      _showNearbyModeHintBanner = fromRouteFallback;
      _nearbyFilterRadiusMeters = nearbyRadius;
    });

    try {
      final all = await ActiveDriversService.getActiveDriverRoutes();
      final filtered = ActiveDriversService.filterByDistanceFromCenter(
        all,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        maxDistanceMeters: nearbyRadius,
      );
      // Urutkan jarak terdekat, batasi 15 driver
      filtered.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.driverLat,
          a.driverLng,
        );
        final distB = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.driverLat,
          b.driverLng,
        );
        return distA.compareTo(distB);
      });
      const maxDriversOnMap = 15;
      final drivers = filtered.take(maxDriversOnMap).toList();

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false;
        });

        if (drivers.isEmpty) {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'nearby_search_empty',
            driverCount: 0,
            searchMode: 'nearby',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TrakaL10n.of(context).noNearbyDriversWithinKm(
                  (nearbyRadius / 1000).round(),
                ),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          AppAnalyticsService.logPassengerDriverSearchOutcome(
            outcome: 'nearby_search_ok',
            driverCount: drivers.length,
            searchMode: 'nearby',
          );
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) {
            _scheduleDriverSearchSessionExpiry();
            _updateMapCameraForDrivers();
            _schedulePassengerMapDriverMarkersRefresh();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(TrakaL10n.of(context).tapDriverToSeeRouteAndBook),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e, st) {
      logError('PenumpangScreen._onDriverSekitarTap', e, st);
      if (mounted) {
        setState(() {
          _isSearchingDrivers = false;
          _searchDriverFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TrakaL10n.of(context).searchDriverFailed}: $e'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: TrakaL10n.of(context).retry,
              onPressed: () => _onDriverSekitarTap(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadPassengerBlueDotOnce() async {
    if (_passengerBlueDotIcon != null) return;
    if (!mounted) return;
    try {
      final sizePx = context.responsive.iconSize(34).round().clamp(28, 40);
      final icon =
          await DriverLocationIconService.loadBlueDotDescriptor(sizePx: sizePx);
      if (mounted) {
        setState(() => _passengerBlueDotIcon = icon);
      }
    } catch (_) {
      // Fallback: pin default di [_buildMarkers].
    }
  }

  void _onPassengerLocationPulseTick() {
    if (!mounted) return;
    if (!_passengerMapTabVisible || _currentPosition == null) {
      if (_passengerLocationPulseBucket != -1) {
        _passengerLocationPulseBucket = -1;
        setState(() {});
      }
      return;
    }
    final bucket =
        (_passengerLocationPulseController.value * 18).floor().clamp(0, 17);
    if (bucket == _passengerLocationPulseBucket) return;
    _passengerLocationPulseBucket = bucket;
    setState(() {});
  }

  Set<Circle> _buildPassengerLocationPulseCircles() {
    if (!_passengerMapTabVisible || _currentPosition == null) {
      return {};
    }
    final latLng = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    final t = _passengerLocationPulseController.value;
    final pulse = math.sin(t * math.pi * 2) * 0.5 + 0.5;
    final radiusM = 12.0 + pulse * 32.0;
    final strokeA = (70 + pulse * 160).round().clamp(0, 255);
    final fillA = (10 + pulse * 36).round().clamp(0, 255);
    return {
      Circle(
        circleId: const CircleId('passenger_blue_dot_pulse'),
        center: latLng,
        radius: radiusM,
        fillColor: Color.fromARGB(fillA, 66, 133, 244),
        strokeColor: Color.fromARGB(strokeA, 255, 255, 255),
        strokeWidth: 2,
        zIndex: 0,
      ),
    };
  }

  /// Build markers untuk map: lokasi penumpang + driver aktif
  Set<Marker> _buildMarkers({
    required bool profileIsComplete,
    required bool canUseOrderFeatures,
  }) {
    final markers = <Marker>{};

    // Marker lokasi penumpang — titik biru + cincin putih (gaya Google Maps), bukan pin default.
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: _passengerBlueDotIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 4,
          infoWindow: const InfoWindow(title: 'Lokasi Anda'),
        ),
      );
    }

    // Marker tujuan yang dipilih di map (bisa di-drag)
    if (_selectedDestinationPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_destination'),
          position: _selectedDestinationPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Tujuan',
            snippet: _selectedDestinationAddress ?? 'Memuat alamat...',
          ),
          draggable: true,
          onDragEnd: (newPosition) {
            _onDestinationMarkerDragged(newPosition);
          },
        ),
      );
    }

    // Marker driver: premium hijau/merah/biru atau legacy hijau/merah (isMoving)
    final recommendedUid = _recommendedDriverUidForMap();
    final android = defaultTargetPlatform == TargetPlatform.android;
    for (final driver in _foundDrivers) {
      if (!driver.driverLat.isFinite || !driver.driverLng.isFinite) continue;
      final state = _driverTrackStates[driver.driverUid];
      final pos = state?.displayed ?? LatLng(driver.driverLat, driver.driverLng);
      final lastUpdated = state?.lastUpdated;
      final isMoving = lastUpdated != null &&
          DateTime.now().difference(lastUpdated).inSeconds <=
              AppConstants.penumpangIsMovingThresholdSeconds;
      final icon = PassengerDriverMapCarIcon.pick(
        driver: driver,
        isMoving: isMoving,
        recommendedDriverUid: recommendedUid,
        premium: _premiumCarIcons,
        legacyGreen: _carIconGreen,
        legacyRed: _carIconRed,
      );

      final distanceText = _currentPosition != null
          ? _formatDistanceMeters(
              Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                pos.latitude,
                pos.longitude,
              ),
            )
          : null;

      final bearing = state?.smoothedBearing ?? state?.bearing ?? 0.0;
      final rotation = CarIconService.markerRotationDegrees(
        bearing,
        premiumAssetFrontUp: _premiumCarIcons?.assetFrontFacesNorth ?? false,
      );
      markers.add(
        Marker(
          markerId: MarkerId(driver.driverUid),
          position: pos,
          icon: icon,
          rotation: rotation,
          flat: defaultTargetPlatform != TargetPlatform.android,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: recommendedUid == driver.driverUid ? 3 : 2,
          // Android: tap marker tidak dipropagasikan ke peta (kurangi konflik dengan onTap map).
          consumeTapEvents: android,
          infoWindow: InfoWindow(
            title: driver.driverName ?? 'Driver',
            snippet: distanceText,
          ),
          onTap: () {
            if (!mounted) return;
            _showDriverDetailSheet(
              driver,
              profileIsComplete: profileIsComplete,
              canUseOrderFeatures: canUseOrderFeatures,
            );
          },
        ),
      );
    }

    return markers;
  }

  /// Polyline rute driver di map. Hanya tampilkan untuk driver yang di-tap (agar map tidak ramai saat banyak driver).
  Set<Polyline> _buildDriverPolylines() {
    final Set<Polyline> polylines = {};
    final selectedUid = _selectedDriverUidForPolyline;
    if (selectedUid == null) return polylines;
    final points = _driverPolylines[selectedUid];
    if (points != null && points.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: PolylineId('driver_route_$selectedUid'),
          points: points,
          color: Colors.blue.shade700,
          width: 5,
        ),
      );
    }
    return polylines;
  }

  /// Glow hanya jika rekomendasi punya kursi (sama dengan ikon biru).
  bool _shouldShowRecommendedDriverGlow() {
    if (_foundDrivers.isEmpty) return false;
    final uid = _recommendedDriverUidForMap();
    if (uid == null) return false;
    for (final d in _foundDrivers) {
      if (d.driverUid == uid) return d.hasPassengerCapacity;
    }
    return false;
  }

  LatLng? _recommendedDriverPositionForGlow() {
    final uid = _recommendedDriverUidForMap();
    if (uid == null) return null;
    final state = _driverTrackStates[uid];
    if (state != null) return state.displayed;
    for (final d in _foundDrivers) {
      if (d.driverUid == uid) return LatLng(d.driverLat, d.driverLng);
    }
    return null;
  }

  /// Driver terdekat dari lokasi penumpang → ikon biru (rekomendasi).
  String? _recommendedDriverUidForMap() {
    if (_foundDrivers.isEmpty) return null;
    if (_currentPosition == null) return _foundDrivers.first.driverUid;
    ActiveDriverRoute? best;
    var bestD = double.infinity;
    final plat = _currentPosition!.latitude;
    final plng = _currentPosition!.longitude;
    for (final d in _foundDrivers) {
      final dist = Geolocator.distanceBetween(
        plat,
        plng,
        d.driverLat,
        d.driverLng,
      );
      if (dist < bestD) {
        bestD = dist;
        best = d;
      }
    }
    return best?.driverUid;
  }

  /// Load icon mobil: traka_car_icons_premium (CarIconService / premium set).
  /// [baseSize] jangan terlalu kecil — area tap marker mengikuti bitmap (± seukuran ikon).
  /// Asset: mobil menghadap ke bawah (selatan) setelah pipeline.
  Future<void> _loadCarIcons() async {
    try {
      const passengerMapCarBaseSize = 34.0;
      const passengerMapCarPadding = 8.0;
      final premium = await CarIconService.loadPremiumPassengerCarIcons(
        context: context,
        baseSize: passengerMapCarBaseSize,
        padding: passengerMapCarPadding,
        mapZoom: _mapZoomForCarIcons,
      );
      if (!mounted) return;
      final result = await CarIconService.loadCarIcons(
        context: context,
        baseSize: passengerMapCarBaseSize,
        padding: passengerMapCarPadding,
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
      _carIconRed = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );
      _carIconGreen = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
      if (mounted) setState(() {});
    }
  }

  /// Format jarak dalam meter ke teks singkat (m atau km).
  String _formatDistanceMeters(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void _onPassengerCameraIdle() {
    _passengerMapUserGesturing = false;
    unawaited(_syncCarIconsZoomFromMap());
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

  /// Format tujuan hanya kecamatan dan kabupaten (dari teks alamat lengkap).
  /// Tampilkan profil driver dan opsi pesan travel (nama di atas, profil di bawah, tujuan kecamatan+kabupaten).
  /// Saat tap: polyline rute driver ditampilkan; saat sheet ditutup, polyline disembunyikan.
  void _showDriverDetailSheet(
    ActiveDriverRoute driver, {
    required bool profileIsComplete,
    required bool canUseOrderFeatures,
  }) {
    HapticFeedback.selectionClick();
    final recommended = _recommendedDriverUidForMap() == driver.driverUid;
    AppAnalyticsService.logPassengerDriverMarkerTap(
      driverUid: driver.driverUid,
      recommended: recommended,
    );
    final sheetOpenedAt = DateTime.now();
    setState(() => _selectedDriverUidForPolyline = driver.driverUid);
    // Fetch polyline on-demand jika belum ada (driver di luar 8 pertama)
    if (_driverPolylines[driver.driverUid] == null) {
      DirectionsService.getRoute(
        originLat: driver.routeOriginLat,
        originLng: driver.routeOriginLng,
        destLat: driver.routeDestLat,
        destLng: driver.routeDestLng,
      ).then((result) {
        if (!mounted) return;
        if (result != null && result.points.length >= 2) {
          _driverPolylines[driver.driverUid] = result.points;
          setState(() {});
        }
      });
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PenumpangDriverDetailSheet(
        driver: driver,
        isVerified: canUseOrderFeatures,
        driverDisplayLat: (_driverTrackStates[driver.driverUid]?.displayed ?? LatLng(driver.driverLat, driver.driverLng)).latitude,
        driverDisplayLng: (_driverTrackStates[driver.driverUid]?.displayed ?? LatLng(driver.driverLat, driver.driverLng)).longitude,
        passengerLat: _currentPosition?.latitude,
        passengerLng: _currentPosition?.longitude,
        isRecommended: recommended,
        onPesanTravel: () => _onPesanTravelOrCheck(
          driver,
          profileIsComplete,
          canUseOrderFeatures,
        ),
        onKirimBarang: () => _onKirimBarangOrCheck(
          driver,
          profileIsComplete,
          canUseOrderFeatures,
        ),
      ),
    ).then((_) {
      AppAnalyticsService.logPassengerDriverSheetClosed(
        durationMs: DateTime.now().difference(sheetOpenedAt).inMilliseconds,
      );
      if (mounted) setState(() => _selectedDriverUidForPolyline = null);
    });
  }

  /// Cek verifikasi sebelum pesan travel; jika belum lengkap tampilkan dialog.
  void _onPesanTravelOrCheck(
    ActiveDriverRoute driver,
    bool profileIsComplete,
    bool canUseOrderFeatures,
  ) {
    if (!canUseOrderFeatures) {
      if (!profileIsComplete) {
        _showLengkapiVerifikasiDialog();
      } else {
        _showAdminVerificationComplianceDialog();
      }
      return;
    }
    if (!_destinationCompleteForOrder()) {
      _showDestinationGateSheet(
        onDestinationReady: () => _showPilihanPesanTravel(driver),
      );
      return;
    }
    _showPilihanPesanTravel(driver);
  }

  /// Cek verifikasi sebelum kirim barang; jika belum lengkap tampilkan dialog.
  void _onKirimBarangOrCheck(
    ActiveDriverRoute driver,
    bool profileIsComplete,
    bool canUseOrderFeatures,
  ) {
    if (!canUseOrderFeatures) {
      if (!profileIsComplete) {
        _showLengkapiVerifikasiDialog();
      } else {
        _showAdminVerificationComplianceDialog();
      }
      return;
    }
    if (!_destinationCompleteForOrder()) {
      _showDestinationGateSheet(
        onDestinationReady: () => _onKirimBarang(driver),
      );
      return;
    }
    _onKirimBarang(driver);
  }

  void _showLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TrakaL10n.of(context).completeVerification),
        content: Text(
          TrakaL10n.of(context).completeDataVerificationPrompt,
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

  void _showAdminVerificationComplianceDialog() {
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
              setState(() => _currentIndex = 4);
            },
            child: const Text('Ke Profil'),
          ),
        ],
      ),
    );
  }

  /// Tampilkan pilihan: pesan travel sendiri atau dengan kerabat
  void _showPilihanPesanTravel(ActiveDriverRoute driver) {
    Navigator.pop(context); // Tutup bottom sheet profil driver
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(ctx.responsive.horizontalPadding),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pesan Travel',
                style: TextStyle(
                  fontSize: ctx.responsive.fontSize(18),
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: ctx.responsive.spacing(8)),
              Text(
                'Pilih jenis pemesanan',
                style: TextStyle(
                  fontSize: ctx.responsive.fontSize(14),
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  child: const Icon(Icons.person, color: AppTheme.primary),
                ),
                title: const Text('Pesan travel sendiri'),
                subtitle: const Text('Pesan untuk perjalanan Anda sendiri'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onPesanTravel(driver, withKerabat: false);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  child: const Icon(Icons.group, color: AppTheme.primary),
                ),
                title: const Text('Pesan travel dengan kerabat'),
                subtitle: const Text('Pesan untuk 2+ orang — Anda + keluarga/teman yang ikut'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  _showInputJumlahKerabat(driver);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog input jumlah kerabat lalu lanjut pesan travel dengan kerabat.
  /// Validasi pakai sisa kapasitas mobil (remainingPassengerCapacity), bukan kapasitas total.
  void _showInputJumlahKerabat(ActiveDriverRoute driver) {
    // Sisa kursi = yang masih bisa diisi (sesuai kapasitas mobil dikurangi penumpang yang sudah agreed/picked_up)
    final sisaKursi =
        driver.remainingPassengerCapacity ?? driver.maxPassengers ?? 10;
    final maxKerabat = (sisaKursi - 1).clamp(
      0,
      9,
    ); // minus 1 untuk pemesan sendiri, max 9 kerabat

    if (maxKerabat < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sisa kursi hanya 1. Silakan pilih "Pesan travel sendiri".',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final controller = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jumlah orang yang ikut'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Berapa orang yang ikut bersama Anda? (Sisa kursi mobil: $sisaKursi)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Jumlah orang yang ikut (selain Anda)',
                  hintText: '1',
                  border: const OutlineInputBorder(),
                  helperText:
                      'Contoh: Anda + 2 anak → isi 2 (total 3 penumpang). Maks. $maxKerabat (Anda + $maxKerabat orang = $sisaKursi penumpang)',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1) return 'Minimal 1 orang ikut';
                  if (n > maxKerabat) {
                    return 'Maksimal $maxKerabat (sisa kursi mobil $sisaKursi)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final n = int.tryParse(controller.text) ?? 1;
              Navigator.pop(ctx);
              _onPesanTravel(driver, withKerabat: true, jumlahKerabat: n);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }

  /// Fungsi untuk pesan travel ke driver
  Future<void> _onPesanTravel(
    ActiveDriverRoute driver, {
    bool withKerabat = false,
    int? jumlahKerabat,
    bool bypassDuplicatePendingTravel = false,
  }) async {
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
          surface: 'map_home',
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
          await _onPesanTravel(
            driver,
            withKerabat: withKerabat,
            jumlahKerabat: jumlahKerabat,
            bypassDuplicatePendingTravel: true,
          );
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

    final asal =
        _currentLocationText != 'Mengambil lokasi...' &&
            _currentLocationText.isNotEmpty
        ? _currentLocationText
        : 'Lokasi penjemputan';
    final tujuan = _destinationController.text.trim().isNotEmpty
        ? _destinationController.text.trim()
        : 'Tujuan';

    final oLat = _currentPosition?.latitude;
    final oLng = _currentPosition?.longitude;
    final dLat = _passengerDestLat;
    final dLng = _passengerDestLng;

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driver.driverUid,
      routeJourneyNumber: driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerAppLocale: passengerAppLocale,
      originText: asal,
      destText: tujuan,
      originLat: oLat,
      originLng: oLng,
      destLat: dLat,
      destLng: dLng,
      orderType: OrderModel.typeTravel,
      jumlahKerabat: withKerabat ? (jumlahKerabat ?? 1) : null,
      bypassDuplicatePendingTravel: bypassDuplicatePendingTravel,
    );

    if (!mounted) return;
    final l10n = TrakaL10n.of(context);

    final String driverName = driver.driverName ?? 'Driver';
    final String jenisPesanan = withKerabat
        ? 'Saya ingin memesan tiket travel untuk ${1 + (jumlahKerabat ?? 1)} orang (dengan kerabat).'
        : 'Saya ingin memesan tiket travel untuk 1 orang.';
    String? jarakKontribusiLines;
    if (oLat != null && oLng != null && dLat != null && dLng != null) {
      jarakKontribusiLines = await runWithEstimateLoading<String?>(
        context,
        l10n,
        () async {
          final preview = await OrderService.computeJarakKontribusiPreview(
            originLat: oLat,
            originLng: oLng,
            destLat: dLat,
            destLng: dLng,
            orderType: OrderModel.typeTravel,
            jumlahKerabat: withKerabat ? (jumlahKerabat ?? 1) : null,
          );
          if (preview != null) {
            return PassengerFirstChatMessage.formatJarakKontribusiLines(
                l10n, preview);
          }
          return l10n.chatPreviewEstimateUnavailable;
        },
      );
    }
    if (!mounted) return;
    final String jenisPesananMessage = PassengerFirstChatMessage.travel(
      driverName: driverName,
      jenisBaris: jenisPesanan,
      asal: asal,
      tujuan: tujuan,
      jarakKontribusiLines: jarakKontribusiLines,
    );

    AppAnalyticsService.logOrderCreated(
      orderType: OrderModel.typeTravel,
      success: orderId != null,
    );
    if (!mounted) return;
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
            sendJenisPesananMessage: jenisPesananMessage,
          ),
        ),
      );
      if (bypassDuplicatePendingTravel) {
        _showNewSplitOrderThreadSnack();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).failedToCreateOrder),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showNewSplitOrderThreadSnack() {
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

  /// Kirim Barang: pilih jenis (Dokumen/Kargo) → tautkan penerima → buat order, buka chat.
  Future<void> _onKirimBarang(ActiveDriverRoute driver) async {
    Navigator.pop(context); // Tutup bottom sheet profil driver
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    var bypassKbDuplicate = false;
    final pendingKb = await OrderService.getPassengerPendingKirimBarangWithDriver(
      user.uid,
      driver.driverUid,
    );
    if (!mounted) return;
    if (pendingKb != null) {
      final l10n = TrakaL10n.of(context);
      final choice = await showPassengerDuplicatePendingOrderDialog(
        context,
        title: l10n.passengerPendingKirimBarangDuplicateTitle,
        body: l10n.passengerPendingKirimBarangDuplicateBody,
      );
      if (!mounted) return;
      AppAnalyticsService.logPassengerDuplicatePendingDialog(
        orderKind: 'kirim_barang',
        choice: passengerDuplicatePendingChoiceAnalyticsValue(choice),
        surface: 'map_home',
      );
      if (choice == null || choice == PassengerDuplicatePendingChoice.cancel) {
        return;
      }
      if (choice == PassengerDuplicatePendingChoice.openExisting) {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ChatRoomPenumpangScreen(
              orderId: pendingKb.id,
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
        bypassKbDuplicate = true;
      }
    }

    final asal =
        _currentLocationText != 'Mengambil lokasi...' &&
            _currentLocationText.isNotEmpty
        ? _currentLocationText
        : 'Lokasi penjemputan';
    final tujuan = _destinationController.text.trim().isNotEmpty
        ? _destinationController.text.trim()
        : 'Tujuan';

    // Step 1: Pilih jenis barang (Dokumen / Kargo)
    final barangData = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => KirimBarangPilihJenisSheet(
        onSelected: (data) => Navigator.pop(ctx, data),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
    if (!mounted || barangData == null) return;

    // Step 2: Tautkan penerima
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => KirimBarangLinkReceiverSheet(
        driver: driver,
        asal: asal,
        tujuan: tujuan,
        originLat: _currentPosition?.latitude,
        originLng: _currentPosition?.longitude,
        destLat: _passengerDestLat,
        destLng: _passengerDestLng,
        barangCategory: barangData['barangCategory'] as String?,
        barangNama: barangData['barangNama'] as String?,
        barangBeratKg: (barangData['barangBeratKg'] as num?)?.toDouble(),
        barangPanjangCm: (barangData['barangPanjangCm'] as num?)?.toDouble(),
        barangLebarCm: (barangData['barangLebarCm'] as num?)?.toDouble(),
        barangTinggiCm: (barangData['barangTinggiCm'] as num?)?.toDouble(),
        barangFotoUrl: barangData['barangFotoUrl'] as String?,
        bypassDuplicatePendingKirimBarang: bypassKbDuplicate,
        onOrderCreated: (orderId, message, [barangFotoUrl]) {
          Navigator.pop(ctx);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ChatRoomPenumpangScreen(
                orderId: orderId,
                driverUid: driver.driverUid,
                driverName: driver.driverName ?? 'Driver',
                driverPhotoUrl: driver.driverPhotoUrl,
                driverVerified: driver.isVerified,
                sendJenisPesananMessage: message,
                sendJenisPesananImageUrl: barangFotoUrl,
              ),
            ),
          );
          if (bypassKbDuplicate) {
            _showNewSplitOrderThreadSnack();
          }
        },
        onError: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    unawaited(_onMapCreatedTraced(controller));
  }

  Future<void> _onMapCreatedTraced(GoogleMapController controller) async {
    await PerformanceTraceService.startPassengerMapReadyTrace();
    if (!mounted) return;
    _mapController = controller;
    _passengerMapCameraEngine.attach(controller);
    if (_currentPosition != null && mounted) {
      unawaited(_applyPassengerMapCamera(force: true));
    }
    unawaited(_syncCarIconsZoomFromMap());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PerformanceTraceService.stopPassengerMapReadyTrace());
    });
  }

  /// Beberapa perangkat Android tidak menggambar ulang marker custom setelah setState;
  /// dua frame tambahan memaksa sinkronisasi layer native (ikon bitmap + GoogleMap).
  void _schedulePassengerMapDriverMarkersRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
      });
    });
  }

  /// Update map camera ke area driver aktif (dan lokasi penumpang) dengan bounds + padding.
  /// Dipanggil setelah "Cari driver travel" berhasil menemukan driver.
  void _updateMapCameraForDrivers() {
    if (_foundDrivers.isEmpty) return;
    if (_currentPosition == null) return;

    if (_passengerMapFollowHeading) {
      _passengerHeadingPositionSub?.cancel();
      _passengerHeadingPositionSub = null;
      setState(() {
        _passengerMapFollowHeading = false;
      });
    }

    double minLat = _currentPosition!.latitude;
    double maxLat = _currentPosition!.latitude;
    double minLng = _currentPosition!.longitude;
    double maxLng = _currentPosition!.longitude;

    for (final driver in _foundDrivers) {
      if (!driver.driverLat.isFinite || !driver.driverLng.isFinite) continue;
      if (driver.driverLat < minLat) minLat = driver.driverLat;
      if (driver.driverLat > maxLat) maxLat = driver.driverLat;
      if (driver.driverLng < minLng) minLng = driver.driverLng;
      if (driver.driverLng > maxLng) maxLng = driver.driverLng;
    }

    // Beri margin agar bounds tidak nol (satu titik)
    final latMargin = (maxLat - minLat).abs() < 0.0001 ? 0.002 : 0.0;
    final lngMargin = (maxLng - minLng).abs() < 0.0001 ? 0.002 : 0.0;
    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latMargin, minLng - lngMargin),
      northeast: LatLng(maxLat + latMargin, maxLng + lngMargin),
    );

    void doAnimate() {
      if (!mounted) return;
      final c = _mapController;
      if (c == null) return;
      Future<void>(() async {
        try {
          await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
        } catch (_) {
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          try {
            await c.animateCamera(
              CameraUpdate.newLatLngZoom(LatLng(centerLat, centerLng), 11),
            );
          } catch (_) {}
        }
      });
    }

    if (_mapController != null && mounted) {
      doAnimate();
    } else {
      // Map belum siap; jadwalkan setelah controller tersedia
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (_mapController != null) doAnimate();
      });
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _registerTabVisit(index);
      _currentIndex = index;
    });

    // Jika kembali ke halaman beranda (index 0), cek ulang active travel order
    if (index == 0) {
      _checkActiveTravelOrder();
    }
  }

  Widget _buildHomeScreen({
    required bool profileIsComplete,
    required bool canUseOrderFeatures,
    required bool homeTabActive,
  }) {
    // Jika ada active travel order, tampilkan blocking overlay
    if (_hasActiveTravelOrder) {
      return Stack(
        children: [
          // Background blur
          TickerMode(
            enabled: homeTabActive,
            child: _buildActualHomeScreen(
              profileIsComplete: profileIsComplete,
              canUseOrderFeatures: canUseOrderFeatures,
            ),
          ),
          // Blocking overlay
          Container(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            child: Center(
              child: Padding(
                padding: context.responsive.cardMargin,
                child: Card(
                  child: Padding(
                    padding: context.responsive.cardPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: context.responsive.iconSize(64),
                        ),
                        SizedBox(height: context.responsive.spacing(16)),
                        Text(
                          TrakaL10n.of(context).activeTravelOrderTitle,
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(18),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(8)),
                        Text(
                          TrakaL10n.of(context).activeTravelOrderSubtitle,
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(14),
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(12)),
                        Text(
                          TrakaL10n.of(context).activeTravelOrderMessage,
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(14),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(12)),
                        Text(
                          TrakaL10n.of(context).activeTravelOrderHint,
                          style: TextStyle(
                            fontSize: context.responsive.fontSize(12),
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.responsive.spacing(20)),
                        FilledButton.icon(
                          onPressed: () {
                            AppAnalyticsService.logPassengerHomeTravelBlock(
                              action: 'open_orders',
                            );
                            setState(() {
                              _registerTabVisit(3);
                              _currentIndex = 3;
                            });
                          },
                          icon: Icon(Icons.receipt_long, color: AppTheme.onPrimary),
                          label: Text(
                            TrakaL10n.of(context).activeTravelOrderOpenOrders,
                            style: TextStyle(
                              color: AppTheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return TickerMode(
      enabled: homeTabActive,
      child: _buildActualHomeScreen(
        profileIsComplete: profileIsComplete,
        canUseOrderFeatures: canUseOrderFeatures,
      ),
    );
  }

  Widget _buildActualHomeScreen({
    required bool profileIsComplete,
    required bool canUseOrderFeatures,
  }) {
    return Stack(
      children: [
        // Google Maps — RepaintBoundary agar tidak rebuild saat overlay/control berubah
        RepaintBoundary(
          child: StyledGoogleMapBuilder(
            builder: (style, useDark) {
              final effectiveMapType = useDark ? MapType.normal : _mapType;
              return GoogleMap(
                buildingsEnabled: true,
                indoorViewEnabled: true,
                mapToolbarEnabled: false,
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: () {
                  _passengerMapUserGesturing = true;
                },
                initialCameraPosition: CameraPosition(
                  target: _currentPosition != null
                      ? LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        )
                      : const LatLng(
                          -3.3194,
                          114.5907,
                        ), // Default: Kalimantan Selatan
                  zoom: MapStyleService.defaultZoom,
                  tilt: MapStyleService.defaultTilt,
                ),
                mapType: effectiveMapType,
                style: style,
                trafficEnabled: _trafficEnabled,
                // Matikan titik lokasi sistem — pakai marker custom + denyut (selaras driver).
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _buildMarkers(
                  profileIsComplete: profileIsComplete,
                  canUseOrderFeatures: canUseOrderFeatures,
                ),
                circles: _buildPassengerLocationPulseCircles(),
                polylines: _buildDriverPolylines(),
                onCameraIdle: _onPassengerCameraIdle,
          onTap: _selectedDriverUidForPolyline != null
              ? (LatLng pos) {
                  setState(() => _selectedDriverUidForPolyline = null);
                }
              : null,
              );
            },
          ),
        ),

        RecommendedDriverGlowOverlay(
          mapController: _mapController,
          position: _recommendedDriverPositionForGlow(),
          visible: _shouldShowRecommendedDriverGlow(),
        ),

        const PromotionBannerWidget(role: 'penumpang'),

        if (_showNearbyModeHintBanner &&
            _lastSearchWasNearby &&
            _foundDrivers.isNotEmpty)
          Positioned(
            top: 0,
            left: 8,
            right: 8,
            child: SafeArea(
              bottom: false,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          TrakaL10n.of(context).mapNearbyModeBannerHint,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() => _showNearbyModeHintBanner = false);
                        },
                        tooltip: TrakaL10n.of(context).cancel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        ListenableBuilder(
          listenable: MapStyleService.themeNotifier,
          builder: (context, _) {
            final useDark = MapStyleService.themeNotifier.value == ThemeMode.dark;
            final effectiveMapType = useDark ? MapType.normal : _mapType;
            return MapTypeZoomControls(
              mapType: effectiveMapType,
              onToggleMapType: _toggleMapType,
              onZoomIn: () {
                if (mounted) _mapController?.animateCamera(CameraUpdate.zoomIn());
              },
              onZoomOut: () {
                if (mounted) _mapController?.animateCamera(CameraUpdate.zoomOut());
              },
              onToggleHeading: _onPassengerMapHeadingToggle,
              headingFollowEnabled: _passengerMapFollowHeading,
              headingTooltip: _passengerMapFollowHeading
                  ? TrakaL10n.of(context).mapHeadingTooltipFollow
                  : TrakaL10n.of(context).mapHeadingTooltipNorthUp,
              trafficEnabled: _trafficEnabled,
              onToggleTraffic: _togglePassengerTraffic,
            );
          },
        ),

        PenumpangQuickActionsRow(
          visible: _isFormVisible,
          onDriverSekitarTap: _onDriverSekitarTap,
          onPesanNantiTap: () => _onTabTapped(1),
          nearbyRadiusKm: _driverSekitarRadiusKmLabel,
          driverSekitarLoading: _isSearchingDrivers && _lastSearchWasNearby,
        ),
        PenumpangSearchBar(
          visible: _isFormVisible,
          currentLocationText: _currentLocationText,
          destinationText: _destinationController.text.trim(),
          onTap: _showSearchFormSheet,
        ),
        PenumpangSearchFailedBanner(
          visible: _searchDriverFailed && !_isSearchingDrivers,
          onRetry: () {
            setState(() => _searchDriverFailed = false);
            if (_lastSearchWasNearby) {
              _onDriverSekitarTap();
            } else {
              _onSearch();
            }
          },
        ),

        // Mencari driver: banner atas saja — tanpa scrim layar penuh (boleh pindah tab / pakai kontrol).
        if (_isSearchingDrivers)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      TrakaL10n.of(context).searchingDriver,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _lastSearchWasNearby
                                          ? TrakaL10n.of(context)
                                              .checkingNearbyDriversKm(
                                                _driverSekitarRadiusKmLabel,
                                              )
                                          : TrakaL10n.of(context)
                                              .checkingDriverRoutes,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    if (!_lastSearchWasNearby) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        TrakaL10n.of(context)
                                            .checkingDriverRoutesSub,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.25,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.9),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Tombol Ubah rute + Cari Ulang (muncul ketika form disembunyikan)
        if (!_isFormVisible)
          Positioned(
            bottom: 80,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_foundDrivers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FloatingActionButton.small(
                      heroTag: 'penumpang_map_reload',
                      onPressed: _isSearchingDrivers
                          ? null
                          : () {
                              if (_lastSearchWasNearby) {
                                _onDriverSekitarTap();
                              } else {
                                _onSearch();
                              }
                            },
                      backgroundColor: AppTheme.primary,
                      tooltip: TrakaL10n.of(context).reload,
                      child: _isSearchingDrivers
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.onPrimary,
                              ),
                            )
                          : Icon(Icons.refresh, color: AppTheme.onPrimary),
                    ),
                  ),
                FloatingActionButton(
                  heroTag: 'penumpang_map_ubah_rute',
                  onPressed: () {
                    setState(() {
                      _isFormVisible = true;
                      _searchDriverFailed = false; // Sembunyikan banner gagal
                    });
                  },
                  backgroundColor: AppTheme.primary,
                  tooltip: 'Ubah rute',
                  child: Icon(Icons.route, color: AppTheme.onPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }

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
      stream: penumpangUserShellStream(user.uid),
      builder: (context, profileSnap) {
        if (!profileSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = profileSnap.data!;
        final profileIsComplete = profile.isVerified;
        final canUseOrderFeatures = profileIsComplete &&
            !profile.adminVerificationBlocksFeatures;

        // Tab 1–4 lazy; tab 0 (Beranda) selalu di IndexedStack agar GoogleMap tidak di-dispose saat pindah tab.
        // _visitedTabIndices diisi di _onTabTapped / _registerTabVisit — bukan di sini.

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              RepaintBoundary(
                child: _buildHomeScreen(
                  profileIsComplete: profileIsComplete,
                  canUseOrderFeatures: canUseOrderFeatures,
                  homeTabActive: _currentIndex == 0,
                ),
              ),
              _visitedTabIndices.contains(1)
                  ? PesanScreen(
                      isVerified: canUseOrderFeatures,
                      profileIsComplete: profileIsComplete,
                      onVerificationRequired: () => setState(() {
                        _registerTabVisit(4);
                        _currentIndex = 4;
                      }),
                    )
                  : const SizedBox.shrink(),
              _visitedTabIndices.contains(2)
                  ? const ChatPenumpangScreen()
                  : const SizedBox.shrink(),
              _visitedTabIndices.contains(3)
                  ? const DataOrderScreen()
                  : const SizedBox.shrink(),
              _visitedTabIndices.contains(4)
                  ? const ProfilePenumpangScreen()
                  : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: TrakaMainBottomNavigationBar(
            currentIndex: _currentIndex,
            chatUnreadCount: _chatUnreadCount,
            onTap: _onTabTapped,
          ),
        );
      },
    );
  }
}

