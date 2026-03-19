import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/car_icon_service.dart';
import '../services/geocoding_service.dart';

import '../utils/placemark_formatter.dart';
import '../utils/app_logger.dart';
import '../widgets/kirim_barang_pilih_jenis_sheet.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/app_constants.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
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
import '../services/passenger_proximity_notification_service.dart';
import '../services/receiver_proximity_notification_service.dart';
import '../services/verification_service.dart';
import '../services/auth_session_service.dart';
import '../services/violation_service.dart';
import '../services/low_ram_warning_service.dart';
import '../services/pending_purchase_recovery_service.dart';
import '../services/recent_destination_service.dart';
import '../services/notification_navigation_service.dart';
import '../services/directions_service.dart';
import '../services/map_style_service.dart';
import '../widgets/styled_google_map_builder.dart';
import '../services/route_utils.dart';
import '../widgets/map_type_zoom_controls.dart';
import '../widgets/penumpang_map_overlays.dart';
import '../widgets/kirim_barang_link_receiver_sheet.dart';
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
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _visitedTabIndices = {};
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal; // Default: peta jalan
  Position? _currentPosition;
  String _currentLocationText = 'Mengambil lokasi...';
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();
  final GlobalKey _formSectionKey = GlobalKey();
  String? _currentKabupaten; // subAdministrativeArea (kabupaten/kota)
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

  // Cache icon mobil: car_merah = diam, car_hijau = bergerak (satu sumber: real-time)
  BitmapDescriptor? _carIconRed;
  BitmapDescriptor? _carIconGreen;

  // Real-time + semut + snap-to-road untuk driver di map
  final Map<String, StreamSubscription<Map<String, dynamic>?>> _driverStreamSubs = {};
  final Map<String, DriverTrackState> _driverTrackStates = {};
  final Map<String, List<LatLng>> _driverPolylines = {};
  Timer? _interpolationTimer;
  /// Driver yang polyline-nya ditampilkan (hanya saat di-tap, agar map tidak ramai).
  String? _selectedDriverUidForPolyline;
  static const double _interpolationMinDistanceMeters = 0.5;
  /// Throttle setState: max ~10 fps agar map tetap responsif.
  DateTime? _lastInterpolationSetStateTime;

  // State untuk visibilitas form (disembunyikan setelah klik Cari)
  bool _isFormVisible = true;

  /// True jika pencarian terakhir via "Driver sekitar" (untuk retry & FAB Cari ulang).
  bool _lastSearchWasNearby = false;

  /// Debounce: waktu terakhir tap "Driver sekitar" (mencegah double tap).
  DateTime? _lastDriverSekitarTapAt;

  // State untuk tracking active travel order
  bool _hasActiveTravelOrder = false;

  // State untuk mode "Pilih di Map"
  bool _isMapSelectionMode = false;
  LatLng? _selectedDestinationPosition; // Posisi tujuan yang dipilih di map
  String? _selectedDestinationAddress; // Alamat dari reverse geocoding

  // Notifier untuk koordinasi form sheet dengan map (seperti driver)
  final ValueNotifier<bool> _formDestMapModeNotifier = ValueNotifier(false);
  final ValueNotifier<LatLng?> _formDestMapTapNotifier = ValueNotifier(null);

  // Badge unread chat penumpang
  StreamSubscription<List<OrderModel>>? _passengerOrdersSub;
  StreamSubscription<List<OrderModel>>? _receiverOrdersSub;
  List<OrderModel> _passengerOrdersForBadge = [];
  List<OrderModel> _receiverOrdersForBadge = [];
  int _chatUnreadCount = 0;
  void _onBadgeOptimisticChanged() {
    if (mounted) _updateChatUnreadCount();
  }

  @override
  void initState() {
    super.initState();
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
    _loadCarIcons();
    // Tampilkan lokasi cache dulu (cepat), lalu lokasi akurat di background
    Future.microtask(() async {
      if (!mounted) return;
      final cached = await LocationService.getCachedPosition();
      if (cached != null && mounted) {
        setState(() => _currentPosition = cached);
        _updateLocationText(cached);
        if (_mapController != null && mounted) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(cached.latitude, cached.longitude),
              15.0,
            ),
          );
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
      if (o.lastMessageAt != null &&
          o.lastMessageSenderUid != uid &&
          (o.passengerLastReadAt == null ||
              o.lastMessageAt!.isAfter(o.passengerLastReadAt!))) {
        count++;
      }
    }
    for (final o in _receiverOrdersForBadge) {
      if (o.isCompleted || o.status == OrderService.statusCancelled) continue;
      if (badgeService.isOptimisticRead(o.id)) continue;
      if (o.lastMessageAt != null &&
          o.lastMessageSenderUid != uid &&
          (o.receiverLastReadAt == null ||
              o.lastMessageAt!.isAfter(o.receiverLastReadAt!))) {
        count++;
      }
    }
    setState(() => _chatUnreadCount = count);
  }

  /// Cari driver aktif dengan origin dan destination yang sudah diisi dari pesan_screen.
  Future<void> _searchDriversWithPrefill() async {
    _lastSearchWasNearby = false;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'route');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
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
    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
    });

    try {
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: widget.originLat,
        passengerOriginLng: widget.originLng,
        passengerDestLat: widget.destLat,
        passengerDestLng: widget.destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).noActiveDriversForRoute),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          // Urutan: load icon dulu, baru setup stream (agar marker siap saat render).
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) _updateMapCameraForDrivers();
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

  /// Cek apakah penumpang memiliki active travel order (agreed atau picked_up).
  /// Hanya untuk order type travel (bukan kirim barang).
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
      final activeTravelOrder = orders.where((order) {
        // Hanya order type travel (bukan kirim barang)
        if (order.orderType != OrderModel.typeTravel) return false;
        // Status harus agreed atau picked_up
        return order.status == OrderService.statusAgreed ||
            order.status == OrderService.statusPickedUp;
      }).isNotEmpty;

      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = activeTravelOrder;
        });
        // Overlay sudah ditampilkan di _buildHomeScreen() saat _hasActiveTravelOrder true
      }
    } catch (e, st) {
      logError('PenumpangScreen._checkActiveTravelOrder', e, st);
      if (mounted) {
        setState(() {
          _hasActiveTravelOrder = false;
        });
      }
    }
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
    _destinationFocusNode.removeListener(_onDestinationFocusChange);
    _destinationFocusNode.dispose();
    _locationRefreshTimer?.cancel();
    _destinationController.dispose();
    _formDestMapModeNotifier.dispose();
    _formDestMapTapNotifier.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _disposeDriverTracking() {
    for (final sub in _driverStreamSubs.values) {
      sub.cancel();
    }
    _driverStreamSubs.clear();
    _driverTrackStates.clear();
    _driverPolylines.clear();
    _interpolationTimer?.cancel();
    _interpolationTimer = null;
  }

  Future<void> _setupDriverTracking() async {
    _disposeDriverTracking();
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

      _driverStreamSubs[driver.driverUid] = DriverStatusService
          .streamDriverStatusData(driver.driverUid)
          .listen((d) => _onDriverStatusUpdate(driver.driverUid, d));
    }

    _startInterpolationTimer();
    if (mounted) setState(() {});
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

    if (mounted) setState(() {});
  }

  void _startInterpolationTimer() {
    _interpolationTimer?.cancel();
    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      bool changed = false;
      for (final entry in _driverTrackStates.entries) {
        final state = entry.value;

        {
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
          } catch (_) {
            // Koordinat invalid: pertahankan bearing sebelumnya
          }
          changed = true;
        }
      }
      if (changed && mounted) {
        final now = DateTime.now();
        if (_lastInterpolationSetStateTime == null ||
            now.difference(_lastInterpolationSetStateTime!).inMilliseconds >= 100) {
          _lastInterpolationSetStateTime = now;
          setState(() {});
        }
      }
    });
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

    // Keluar dari mode map selection saat mulai mencari
    setState(() {
      _isMapSelectionMode = false;
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
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false; // Sembunyikan form setelah pencarian berhasil
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).noActiveDriversForRoute),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) _updateMapCameraForDrivers();
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
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(
                LatLng(position.latitude, position.longitude),
              ),
            );
          }
        } else if (_mapController != null && mounted) {
          // Jika ini pertama kali dapat lokasi, animate ke lokasi tersebut
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude),
              15.0,
            ),
          );
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

  /// Handler saat user tap di map untuk memilih lokasi tujuan
  void _onMapTapped(LatLng position) async {
    if (!_isMapSelectionMode) return;

    setState(() {
      _selectedDestinationPosition = position;
      _passengerDestLat = position.latitude;
      _passengerDestLng = position.longitude;
      _selectedDestinationAddress = 'Memuat alamat...';
    });

    // Reverse geocode untuk mendapatkan alamat
    await _reverseGeocodeDestination(position);
  }

  /// Handler saat marker tujuan di-drag
  void _onDestinationMarkerDragged(LatLng newPosition) async {
    setState(() {
      _selectedDestinationPosition = newPosition;
      _passengerDestLat = newPosition.latitude;
      _passengerDestLng = newPosition.longitude;
      _selectedDestinationAddress = 'Memuat alamat...';
    });

    // Reverse geocode untuk mendapatkan alamat baru
    await _reverseGeocodeDestination(newPosition);
  }

  /// Reverse geocode koordinat menjadi alamat dan update form
  Future<void> _reverseGeocodeDestination(LatLng position) async {
    try {
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final displayText = PlacemarkFormatter.formatDetail(placemark);

        if (mounted) {
          setState(() {
            _selectedDestinationAddress = displayText;
            _destinationController.text = displayText;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedDestinationAddress = 'Lokasi tidak ditemukan';
            _destinationController.text =
                '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          });
        }
      }
    } catch (e) {
      // Jika error, gunakan koordinat sebagai fallback
      if (mounted) {
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
        formDestMapModeNotifier: _formDestMapModeNotifier,
        formDestMapTapNotifier: _formDestMapTapNotifier,
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

  /// Handler Cari dari form sheet
  Future<void> _onSearchFromSheet(
    String destText,
    double destLat,
    double destLng,
  ) async {
    _lastSearchWasNearby = false;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'route');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    RecentDestinationService.add(destText, lat: destLat, lng: destLng);
    setState(() {
      _destinationController.text = destText;
      _passengerDestLat = destLat;
      _passengerDestLng = destLng;
      _selectedDestinationPosition = LatLng(destLat, destLng);
      _selectedDestinationAddress = destText;
      _isMapSelectionMode = false;
      _formDestMapModeNotifier.value = false;
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
      final drivers = await ActiveDriversService.getActiveDriversForMap(
        passengerOriginLat: _currentPosition!.latitude,
        passengerOriginLng: _currentPosition!.longitude,
        passengerDestLat: destLat,
        passengerDestLng: destLng,
      );

      if (mounted) {
        setState(() {
          _foundDrivers = drivers;
          _isSearchingDrivers = false;
          _searchDriverFailed = false;
          _isFormVisible = false;
        });

        if (_foundDrivers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).noActiveDriversForRoute),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) _updateMapCameraForDrivers();
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
  Future<void> _onDriverSekitarTap() async {
    // Debounce 2 detik
    final now = DateTime.now();
    if (_lastDriverSekitarTapAt != null &&
        now.difference(_lastDriverSekitarTapAt!).inSeconds < 2) {
      return;
    }
    _lastDriverSekitarTapAt = now;
    _lastSearchWasNearby = true;
    AppAnalyticsService.logPassengerSearchDriver(mode: 'nearby');
    if (await _checkAndRedirectIfOutstandingViolation()) return;
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).waitingPassengerLocation),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSearchingDrivers = true;
      _foundDrivers = [];
      _searchDriverFailed = false;
    });

    try {
      final all = await ActiveDriversService.getActiveDriverRoutes();
      final filtered = ActiveDriversService.filterByDistanceFromCenter(
        all,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TrakaL10n.of(context).noNearbyDrivers),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          await _loadCarIcons();
          await _setupDriverTracking();
          if (mounted) {
            _updateMapCameraForDrivers();
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

  /// Build markers untuk map: lokasi penumpang + driver aktif
  Set<Marker> _buildMarkers({bool isVerified = false}) {
    final markers = <Marker>{};

    // Marker lokasi penumpang
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
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

    // Marker driver aktif: icon mobil (car_merah = diam, car_hijau = bergerak)
    // Satu sumber isMoving: state.lastUpdated real-time dari stream
    for (final driver in _foundDrivers) {
      final state = _driverTrackStates[driver.driverUid];
      final pos = state?.displayed ?? LatLng(driver.driverLat, driver.driverLng);
      final lastUpdated = state?.lastUpdated;
      final isMoving = lastUpdated != null &&
          DateTime.now().difference(lastUpdated).inSeconds <=
              AppConstants.penumpangIsMovingThresholdSeconds;
      final icon = (isMoving ? _carIconGreen : _carIconRed) ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);

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

      // Rotasi: asset depan = selatan, rotation = (bearing + 180) % 360
      final bearing = state?.bearing ?? 0.0;
      final rotation = (((bearing.isFinite ? bearing : 0.0) + 180) % 360).toDouble();
      markers.add(
        Marker(
          markerId: MarkerId(driver.driverUid),
          position: pos,
          icon: icon,
          rotation: rotation,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: driver.driverName ?? 'Driver',
            snippet: distanceText,
          ),
          onTap: () => _showDriverDetailSheet(driver, isVerified),
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

  /// Load icon mobil dari assets (car_merah.png, car_hijau.png).
  /// Asset: mobil menghadap ke bawah (selatan).
  Future<void> _loadCarIcons() async {
    try {
      final result = await CarIconService.loadCarIcons(
        context: context,
        baseSize: 14,
        padding: 4,
        forPassenger: true,
      );
      if (mounted) {
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

  /// Format tujuan hanya kecamatan dan kabupaten (dari teks alamat lengkap).
  /// Tampilkan profil driver dan opsi pesan travel (nama di atas, profil di bawah, tujuan kecamatan+kabupaten).
  /// Saat tap: polyline rute driver ditampilkan; saat sheet ditutup, polyline disembunyikan.
  void _showDriverDetailSheet(ActiveDriverRoute driver, bool isVerified) {
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
        isVerified: isVerified,
        driverDisplayLat: (_driverTrackStates[driver.driverUid]?.displayed ?? LatLng(driver.driverLat, driver.driverLng)).latitude,
        driverDisplayLng: (_driverTrackStates[driver.driverUid]?.displayed ?? LatLng(driver.driverLat, driver.driverLng)).longitude,
        passengerLat: _currentPosition?.latitude,
        passengerLng: _currentPosition?.longitude,
        onPesanTravel: () => _onPesanTravelOrCheck(driver, isVerified),
        onKirimBarang: () => _onKirimBarangOrCheck(driver, isVerified),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedDriverUidForPolyline = null);
    });
  }

  /// Cek verifikasi sebelum pesan travel; jika belum lengkap tampilkan dialog.
  void _onPesanTravelOrCheck(ActiveDriverRoute driver, bool isVerified) {
    if (!isVerified) {
      _showLengkapiVerifikasiDialog();
      return;
    }
    _showPilihanPesanTravel(driver);
  }

  /// Cek verifikasi sebelum kirim barang; jika belum lengkap tampilkan dialog.
  void _onKirimBarangOrCheck(ActiveDriverRoute driver, bool isVerified) {
    if (!isVerified) {
      _showLengkapiVerifikasiDialog();
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
                  if (n > maxKerabat)
                    return 'Maksimal $maxKerabat (sisa kursi mobil $sisaKursi)';
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
  }) async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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

    final orderId = await OrderService.createOrder(
      passengerUid: user.uid,
      driverUid: driver.driverUid,
      routeJourneyNumber: driver.routeJourneyNumber,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerAppLocale: passengerAppLocale,
      originText: asal,
      destText: tujuan,
      originLat: _currentPosition?.latitude,
      originLng: _currentPosition?.longitude,
      destLat: _passengerDestLat,
      destLng: _passengerDestLng,
      orderType: OrderModel.typeTravel,
      jumlahKerabat: withKerabat ? (jumlahKerabat ?? 1) : null,
    );

    // Format pesan otomatis pertama ke driver (profesional & tegas).
    final String driverName = driver.driverName ?? 'Driver';
    final String jenisPesanan = withKerabat
        ? 'Saya ingin memesan tiket travel untuk ${1 + (jumlahKerabat ?? 1)} orang (dengan kerabat).'
        : 'Saya ingin memesan tiket travel untuk 1 orang.';
    final String jenisPesananMessage =
        'Halo Pak $driverName,\n\n'
        '$jenisPesanan\n\n'
        'Dari: $asal\n'
        'Tujuan: $tujuan\n\n'
        'Mohon informasi tarif untuk rute ini.';

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
            sendJenisPesananMessage: jenisPesananMessage,
          ),
        ),
      );
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

  /// Kirim Barang: pilih jenis (Dokumen/Kargo) → tautkan penerima → buat order, buka chat.
  Future<void> _onKirimBarang(ActiveDriverRoute driver) async {
    Navigator.pop(context); // Tutup bottom sheet profil driver
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

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
    _mapController = controller;
    if (_currentPosition != null && mounted) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          15.0,
        ),
      );
    }
  }

  /// Update map camera ke area driver aktif (dan lokasi penumpang) dengan bounds + padding.
  /// Dipanggil setelah "Cari driver travel" berhasil menemukan driver.
  void _updateMapCameraForDrivers() {
    if (_foundDrivers.isEmpty) return;
    if (_currentPosition == null) return;

    double minLat = _currentPosition!.latitude;
    double maxLat = _currentPosition!.latitude;
    double minLng = _currentPosition!.longitude;
    double maxLng = _currentPosition!.longitude;

    for (final driver in _foundDrivers) {
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
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
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
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });

    // Jika kembali ke halaman beranda (index 0), cek ulang active travel order
    if (index == 0) {
      _checkActiveTravelOrder();
    }
  }

  Widget _buildHomeScreen({
    Map<String, dynamic>? userData,
    bool isVerified = false,
  }) {
    // Jika ada active travel order, tampilkan blocking overlay
    if (_hasActiveTravelOrder) {
      return Stack(
        children: [
          // Background blur
          _buildActualHomeScreen(isVerified: isVerified),
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

    return _buildActualHomeScreen(isVerified: isVerified);
  }

  Widget _buildActualHomeScreen({bool isVerified = false}) {
    return Stack(
      children: [
        // Google Maps — RepaintBoundary agar tidak rebuild saat overlay/control berubah
        RepaintBoundary(
          child: StyledGoogleMapBuilder(
            builder: (style, useDark) {
              final effectiveMapType = useDark ? MapType.normal : _mapType;
              return GoogleMap(
                buildingsEnabled: true,
                onMapCreated: _onMapCreated,
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
                myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
                markers: _buildMarkers(isVerified: isVerified),
                polylines: _buildDriverPolylines(),
          onTap: (_isMapSelectionMode || _formDestMapModeNotifier.value || _selectedDriverUidForPolyline != null)
              ? (LatLng pos) {
                  if (_selectedDriverUidForPolyline != null && !_isMapSelectionMode && !_formDestMapModeNotifier.value) {
                    setState(() => _selectedDriverUidForPolyline = null);
                    return;
                  }
                  if (_formDestMapModeNotifier.value) {
                    _formDestMapTapNotifier.value = pos;
                  } else {
                    _onMapTapped(pos);
                  }
                }
              : null, // Aktif saat mode pilih di map, form dest map, atau untuk hilangkan polyline driver
              );
            },
          ),
        ),

        const PromotionBannerWidget(role: 'penumpang'),

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
            );
          },
        ),

        PenumpangQuickActionsRow(
          visible: _isFormVisible,
          onDriverSekitarTap: _onDriverSekitarTap,
          onPesanNantiTap: () => _onTabTapped(1),
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

        // Loading overlay saat mencari driver (blok interaksi)
        if (_isSearchingDrivers)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // Blok tap
              child: Container(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                child: Center(
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            TrakaL10n.of(context).searchingDriver,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _lastSearchWasNearby
                                ? TrakaL10n.of(context).checkingNearbyDrivers
                                : TrakaL10n.of(context).checkingDriverRoutes,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
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
            profileSnap.data!.data() as Map<String, dynamic>? ?? <String, dynamic>{};
        final isVerified = VerificationService.isPenumpangVerified(data);

        return Scaffold(
          body: _currentIndex == 0
              ? _buildHomeScreen(userData: data, isVerified: isVerified)
              : _buildOtherScreens(isVerified: isVerified),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
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
                  ? AppTheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: TrakaL10n.of(context).navHome,
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 1
                  ? Icons.calendar_month
                  : Icons.calendar_month_outlined,
              color: _currentIndex == 1
                  ? AppTheme.primary
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
                          ? AppTheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(
                    _currentIndex == 2
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    color: _currentIndex == 2
                        ? AppTheme.primary
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
                  ? AppTheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: TrakaL10n.of(context).navOrders,
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _currentIndex == 4 ? Icons.person : Icons.person_outline,
              color: _currentIndex == 4
                  ? AppTheme.primary
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

  Widget _buildOtherScreens({bool isVerified = false}) {
    final idx = _currentIndex;
    if (idx >= 1 && idx <= 4) _visitedTabIndices.add(idx);

    return IndexedStack(
      index: idx - 1,
      children: [
        _visitedTabIndices.contains(1)
            ? PesanScreen(
                isVerified: isVerified,
                onVerificationRequired: () => setState(() => _currentIndex = 4),
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
    );
  }
}

