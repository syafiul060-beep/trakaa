import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/order_model.dart';
import '../services/car_icon_service.dart';
import '../services/marker_icon_service.dart';
import '../services/chat_service.dart';
import '../theme/responsive.dart';
import '../widgets/traka_l10n_scope.dart';
import '../utils/app_logger.dart';
import '../services/driver_contribution_service.dart';
import '../services/map_style_service.dart';
import '../services/route_notification_service.dart';
import '../widgets/styled_google_map_builder.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/kirim_barang_driver_ongkos_banner.dart';
import '../widgets/pindah_jadwal_sheet.dart';
import '../services/driver_status_service.dart';
import '../models/driver_transfer_model.dart';
import '../services/driver_transfer_service.dart';
import '../services/app_config_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/order_service.dart';
import '../services/order_receipt_pdf_flow.dart';
import '../services/route_session_service.dart';
import '../services/violation_service.dart';
import '../services/sos_service.dart';
import '../widgets/sos_emergency_confirm_dialog.dart';
import 'chat_driver_screen.dart';
import 'contribution_driver_screen.dart';
import 'driver_earnings_screen.dart';
import 'payment_history_screen.dart';
import 'riwayat_rute_detail_screen.dart';
import 'scan_transfer_driver_screen.dart';

/// Halaman Data Order untuk driver dengan 4 menu:
/// 1. Pemesanan - pesanan aktif. Belum dikategorikan "pesan travel" sampai driver
///    klik Kesepakatan (masukkan harga) dan penumpang setuju. Sebelum itu = negoisasi di chat.
/// 2. Penumpang - penumpang yang sudah dijemput (setelah scan, diprogram nanti)
/// 3. Pemesanan Selesai - penumpang yang sudah menyelesaikan perjalanan
/// 4. Riwayat Rute Perjalanan - semua rute perjalanan (urut terakhir)
class DataOrderDriverScreen extends StatefulWidget {
  const DataOrderDriverScreen({
    super.key,
    /// Callback saat driver klik "Ya, arahkan" di modal Lokasi → pindah ke Beranda + mode navigasi ke penumpang.
    this.onNavigateToPassenger,
  });

  final void Function(OrderModel order)? onNavigateToPassenger;

  @override
  State<DataOrderDriverScreen> createState() => _DataOrderDriverScreenState();
}

class _DataOrderDriverScreenState extends State<DataOrderDriverScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _routeJourneyNumber;
  String? _scheduleId;
  StreamSubscription<List<OrderModel>>? _ordersSubscription;
  /// Cache stream agar StreamBuilder tidak re-subscribe tiap rebuild (cegah kedip).
  Stream<List<OrderModel>>? _cachedOrdersStream;
  String? _cachedOrdersStreamKey;

  /// Cache stream untuk tab Pesanan Terjadwal (cegah kedip).
  Stream<List<OrderModel>>? _cachedAllOrdersStream;
  String? _cachedAllOrdersStreamKey;

  /// Cache stream untuk tab Oper ke Saya (cegah kedip).
  Stream<List<DriverTransferModel>>? _cachedTransfersStream;

  /// Cache stream untuk tab Riwayat Rute (cegah kedip).
  Stream<List<OrderModel>>? _cachedCompletedOrdersStream;
  Stream<List<RouteSessionModel>>? _cachedSessionsStream;

  /// Posisi driver untuk cek "dekat penumpang" (nonaktifkan Batal, tombol Konfirmasi dijemput). Di-load sekali saat tab Pemesanan.
  Position? _positionForCancel;
  bool _loadingPositionForCancel = false;

  /// Waktu dan posisi pertama driver berdekatan (≤30 m) dengan penumpang untuk auto-confirm.
  /// Konfirmasi otomatis jika: 15 menit berdekatan ATAU perpindahan 1 km dari titik penjemputan (tanpa tombol).
  final Map<String, DateTime> _firstTimeInRadiusForAutoConfirm = {};
  final Map<String, (double, double)> _firstPositionWhenCloseForAutoConfirm = {};
  static const Duration _autoConfirmAfterDuration = Duration(minutes: 15);
  static const double _autoConfirmDistanceMeters = 1000; // 1 km
  Timer? _autoConfirmTimer;
  Timer? _autoCompleteTimer;
  String? _loadingReceiptPdfOrderId;

  /// Tanggal terpilih di tab Pesanan Terjadwal (format y-m-d).
  String? _selectedScheduledDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadActiveRoute();
    _tabController.addListener(_onTabChanged);
    _startAutoConfirmTimer();
  }

  void _startAutoConfirmTimer() {
    _autoConfirmTimer?.cancel();
    _autoConfirmTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _checkAutoConfirmPickup();
    });
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _checkAutoCompleteWhenFarApart();
    });
  }

  /// Jika HP driver dan penumpang berdekatan (≤30 m) selama 15 menit ATAU perpindahan 1 km dari titik penjemputan → konfirmasi otomatis (tanpa tombol). Kirim barang: tidak auto-confirm.
  Future<void> _checkAutoConfirmPickup() async {
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck(
        forTracking: true,
      );
      if (result.isFakeGpsDetected || result.position == null) return;
      final pos = result.position!;
      final orders = await OrderService.getAgreedOrdersForDriver();
      if (!mounted || orders.isEmpty) {
        if (orders.isEmpty) if (kDebugMode) debugPrint('[Traka AutoConfirm] Cek penjemputan: 0 order agreed.');
        return;
      }

      final now = DateTime.now();
      final driverLat = pos.latitude;
      final driverLng = pos.longitude;
      if (kDebugMode) debugPrint('[Traka AutoConfirm] Cek penjemputan: ${orders.length} order, driver @ ($driverLat, $driverLng)');

      for (final order in orders) {
        final passCoords = order.coordsForDriverPickupProximity;
        if (passCoords == null) {
          if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: skip - lokasi penumpang belum ada');
          continue;
        }
        final passLat = passCoords.$1;
        final passLng = passCoords.$2;

        final distM = Geolocator.distanceBetween(
          driverLat,
          driverLng,
          passLat,
          passLng,
        );
        if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: jarak ke penumpang ${distM.round()} m (perlu ≤${OrderService.radiusBerdekatanMeter} m)');

        // Driver dan penumpang berdekatan (≤30 m): set driverArrivedAtPickupAt sekali. Travel → 15 menit ATAU 1 km auto-confirm; kirim barang: harus scan.
        if (distM <= OrderService.radiusBerdekatanMeter) {
          final firstTime = _firstTimeInRadiusForAutoConfirm.putIfAbsent(
            order.id,
            () => now,
          );
          _firstPositionWhenCloseForAutoConfirm.putIfAbsent(
            order.id,
            () => (driverLat, driverLng),
          );
          if (firstTime == now) {
            await OrderService.setDriverArrivedAtPickupAt(order.id);
          }
          if (order.isKirimBarang) {
            if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: kirim barang - tidak auto-confirm');
            _firstTimeInRadiusForAutoConfirm.remove(order.id);
            _firstPositionWhenCloseForAutoConfirm.remove(order.id);
            continue;
          }
          final firstPos = _firstPositionWhenCloseForAutoConfirm[order.id];
          final distFromStart = firstPos != null
              ? Geolocator.distanceBetween(
                  firstPos.$1,
                  firstPos.$2,
                  driverLat,
                  driverLng,
                )
              : 0.0;
          final durationReached =
              now.difference(firstTime) >= _autoConfirmAfterDuration;
          final oneKmReached = distFromStart >= _autoConfirmDistanceMeters;
          if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: berdekatan sejak ${firstTime.toIso8601String()}, durasi ${now.difference(firstTime).inMinutes} menit, perpindahan ${distFromStart.round()} m → durationOk=$durationReached (15 min), oneKmOk=$oneKmReached (1 km)');

          if (durationReached || oneKmReached) {
            if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: TRIGGER auto-confirm penjemputan');
            _firstTimeInRadiusForAutoConfirm.remove(order.id);
            _firstPositionWhenCloseForAutoConfirm.remove(order.id);
            final (ok, _) = await OrderService.driverConfirmPickupNoScan(
              order.id,
              driverLat,
              driverLng,
            );
            if (!mounted) return;
            if (ok) {
              if (kDebugMode) debugPrint('[Traka AutoConfirm] Order ${order.id}: sukses - chat, notifikasi, SnackBar');
              await ChatService.sendMessage(
                order.id,
                'Anda telah tercatat dijemput oleh driver (konfirmasi otomatis – tanpa scan barcode).',
              );
              if (!mounted) return;
              await RouteNotificationService.showAutoConfirmPickupNotification();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Penumpang (travel) dikonfirmasi dijemput otomatis. Notifikasi dikirim ke penumpang.',
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 4),
                ),
              );
              // StreamBuilder akan rebuild otomatis saat Firestore emit; hindari setState (cegah kedip)
            }
            break;
          }
          continue;
        }
        _firstTimeInRadiusForAutoConfirm.remove(order.id);
        _firstPositionWhenCloseForAutoConfirm.remove(order.id);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka AutoConfirm] Error: $e\n$st');
    }
  }

  /// Jika status picked_up dan jarak driver–penumpang > 500 m → selesai otomatis (tanpa tombol). Kirim barang: tidak.
  Future<void> _checkAutoCompleteWhenFarApart() async {
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck(
        forTracking: true,
      );
      if (result.isFakeGpsDetected || result.position == null) return;
      final pos = result.position!;
      final orders = await OrderService.getPickedUpTravelOrdersForDriver();
      if (!mounted || orders.isEmpty) {
        if (orders.isEmpty) if (kDebugMode) debugPrint('[Traka AutoComplete] Driver: 0 order picked_up.');
        return;
      }

      final driverLat = pos.latitude;
      final driverLng = pos.longitude;
      if (kDebugMode) debugPrint('[Traka AutoComplete] Driver: cek ${orders.length} order picked_up, driver @ ($driverLat, $driverLng)');

      for (final order in orders) {
        final passCoords = order.coordsForDriverPickupProximity;
        if (passCoords == null) {
          if (kDebugMode) debugPrint('[Traka AutoComplete] Driver order ${order.id}: skip - lokasi penumpang belum ada');
          continue;
        }
        final (passLat, passLng) = passCoords;

        final distM = Geolocator.distanceBetween(
          driverLat,
          driverLng,
          passLat,
          passLng,
        );
        if (kDebugMode) debugPrint('[Traka AutoComplete] Driver order ${order.id}: jarak ke penumpang ${distM.round()} m (perlu >${OrderService.radiusMenjauhMeter} m)');
        if (distM <= OrderService.radiusMenjauhMeter) continue;

        if (kDebugMode) debugPrint('[Traka AutoComplete] Driver order ${order.id}: TRIGGER auto-complete (menjauh)');
        final (ok, err) = await OrderService.completeOrderWhenFarApart(
          order.id,
          driverLat,
          driverLng,
          true,
        );
        if (!mounted) return;
        if (ok) {
          if (kDebugMode) debugPrint('[Traka AutoComplete] Driver order ${order.id}: sukses - chat, notifikasi, SnackBar');
          await ChatService.sendMessage(
            order.id,
            'Pesanan selesai (konfirmasi otomatis – driver dan penumpang sudah menjauh).',
          );
          if (!mounted) return;
          await RouteNotificationService.showAutoCompleteNotification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pesanan selesai otomatis. Notifikasi telah dikirim ke penumpang dan driver.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
          // StreamBuilder akan rebuild otomatis saat Firestore emit; hindari setState (cegah kedip)
        } else {
          if (kDebugMode) debugPrint('[Traka AutoComplete] Driver order ${order.id}: gagal - $err');
        }
        break;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka AutoComplete] Driver error: $e\n$st');
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.index == 0 &&
        _positionForCancel == null &&
        !_loadingPositionForCancel) {
      _loadPositionForCancel();
    }
  }

  Future<void> _loadPositionForCancel() async {
    if (_loadingPositionForCancel) return;
    setState(() => _loadingPositionForCancel = true);
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck(
        forTracking: true,
      );
      if (mounted) {
        setState(() {
          _positionForCancel = result.isFakeGpsDetected ? null : result.position;
          _loadingPositionForCancel = false;
        });
      }
    } catch (e, st) {
      logError('DataOrderDriverScreen._loadPositionForCancel', e, st);
      if (mounted) setState(() => _loadingPositionForCancel = false);
    }
  }

  Stream<List<OrderModel>> get _ordersStream {
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      return Stream.value([]);
    }
    final key = '${_routeJourneyNumber}_${_scheduleId ?? ""}';
    if (_cachedOrdersStream != null && _cachedOrdersStreamKey == key) {
      return _cachedOrdersStream!;
    }
    _cachedOrdersStreamKey = key;
    if (_routeJourneyNumber == OrderService.routeJourneyNumberScheduled &&
        _scheduleId != null &&
        _scheduleId!.isNotEmpty) {
      _cachedOrdersStream =
          OrderService.streamOrdersForDriverBySchedule(
          _scheduleId!,
          legacyScheduleId: ScheduleIdUtil.toLegacy(_scheduleId!),
        );
    } else {
      _cachedOrdersStream =
          OrderService.streamOrdersForDriverByRoute(_routeJourneyNumber!);
    }
    return _cachedOrdersStream!;
  }

  Future<void> _loadActiveRoute() async {
    // Prioritaskan rute dari order aktif driver agar pemesan yang sudah ada tetap muncul di Data Order.
    // Baru pakai driver_status jika driver belum punya order agreed/picked_up.
    var journeyNumber =
        await OrderService.getRouteJourneyNumberFromDriverActiveOrders();
    String? scheduleId;
    if (journeyNumber == null || journeyNumber.isEmpty) {
      final route = await DriverStatusService.getActiveRouteFromFirestore();
      if (!mounted) return;
      journeyNumber = route?.routeJourneyNumber;
      scheduleId = route?.scheduleId;
      // Fallback: jika masih null, cek pesanan terjadwal yang sudah agreed (tanpa perlu Siap Kerja).
      if ((journeyNumber == null || journeyNumber.isEmpty) &&
          (scheduleId == null || scheduleId.isEmpty)) {
        final scheduledAgreed =
            await OrderService.getDriverScheduledOrdersWithAgreed();
        if (!mounted) return;
        if (scheduledAgreed.isNotEmpty) {
          journeyNumber = OrderService.routeJourneyNumberScheduled;
          scheduleId = null; // Pakai streamOrdersForDriverByRoute('scheduled')
        }
      }
    } else if (journeyNumber == OrderService.routeJourneyNumberScheduled) {
      final route = await DriverStatusService.getActiveRouteFromFirestore();
      if (!mounted) return;
      scheduleId = route?.scheduleId;
    }
    if (!mounted) return;
    setState(() {
      _routeJourneyNumber = journeyNumber;
      _scheduleId = scheduleId;
      _cachedOrdersStream = null;
      _cachedOrdersStreamKey = null;
    });
    _ordersSubscription?.cancel();
    if (journeyNumber != null && journeyNumber.isNotEmpty) {
      final stream =
          (journeyNumber == OrderService.routeJourneyNumberScheduled &&
              scheduleId != null &&
              scheduleId.isNotEmpty)
          ? OrderService.streamOrdersForDriverBySchedule(
              scheduleId,
              legacyScheduleId: ScheduleIdUtil.toLegacy(scheduleId),
            )
          : OrderService.streamOrdersForDriverByRoute(journeyNumber);
      _ordersSubscription = stream.listen((orders) async {
        final kargoSlot = await AppConfigService.getKargoSlotPerOrder();
        int count = 0;
        for (final o in orders) {
          if (o.status != OrderService.statusAgreed &&
              o.status != OrderService.statusPickedUp) {
            continue;
          }
          if (o.orderType == OrderModel.typeTravel) {
            count += o.totalPenumpang;
          } else if (o.orderType == OrderModel.typeKirimBarang &&
              (o.barangCategory == OrderModel.barangCategoryKargo ||
                  o.barangCategory == null)) {
            count += (kargoSlot.ceil()).clamp(1, 10);
          }
        }
        if (mounted) {
          DriverStatusService.updateCurrentPassengerCount(count);
        }
      });
    }
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    _autoCompleteTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _ordersSubscription?.cancel();
    _tabController.dispose();
    _cachedAllOrdersStream = null;
    _cachedAllOrdersStreamKey = null;
    _cachedTransfersStream = null;
    _cachedCompletedOrdersStream = null;
    _cachedSessionsStream = null;
    super.dispose();
  }

  /// Daftar di TabBarView: ruang bawah untuk inset sistem.
  EdgeInsets _listPaddingWithSafeBottom(
    BuildContext context, {
    double top = 16,
  }) {
    const h = 16.0;
    const bottomBase = 16.0;
    return EdgeInsets.fromLTRB(
      h,
      top,
      h,
      bottomBase + MediaQuery.paddingOf(context).bottom,
    );
  }

  /// Stream untuk tab Pesanan Terjadwal (cached).
  Stream<List<OrderModel>> get _allOrdersStreamForScheduled {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);
    final key = user.uid;
    if (_cachedAllOrdersStream != null && _cachedAllOrdersStreamKey == key) {
      return _cachedAllOrdersStream!;
    }
    _cachedAllOrdersStreamKey = key;
    _cachedAllOrdersStream = OrderService.streamOrdersForDriver(user.uid);
    return _cachedAllOrdersStream!;
  }

  /// Stream untuk tab Oper ke Saya (cached).
  Stream<List<DriverTransferModel>> get _transfersStream {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    _cachedTransfersStream ??= DriverTransferService.streamTransfersForDriver(uid);
    return _cachedTransfersStream!;
  }

  /// Stream completed orders untuk tab Riwayat Rute (cached).
  Stream<List<OrderModel>> get _completedOrdersStream {
    _cachedCompletedOrdersStream ??= OrderService.streamCompletedOrdersForDriver();
    return _cachedCompletedOrdersStream!;
  }

  /// Stream sessions untuk tab Riwayat Rute (cached).
  Stream<List<RouteSessionModel>> get _sessionsStream {
    _cachedSessionsStream ??= RouteSessionService.streamSessionsForDriver();
    return _cachedSessionsStream!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TrakaL10n.of(context).dataOrder),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: TrakaL10n.of(context).tabOrders),
            Tab(text: TrakaL10n.of(context).tabScheduledOrders),
            Tab(text: TrakaL10n.of(context).penumpang),
            Tab(text: TrakaL10n.of(context).tabOperToMe),
            Tab(text: TrakaL10n.of(context).tabOrdersComplete),
            Tab(text: TrakaL10n.of(context).tabRouteHistory),
          ],
        ),
      ),
      body: Column(
        children: [
          // Banner kontribusi: StreamBuilder terpisah agar TabBarView tidak ikut rebuild (cegah kedip)
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
                    Icon(Icons.info_outline, color: Colors.orange.shade800, size: 22),
                    SizedBox(width: context.responsive.spacing(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            total > 0
                                ? 'Estimasi bayar: Rp ${fmt(total)}'
                                : 'Bayar kontribusi untuk menerima order baru.',
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
                            'Bayar via Google Play untuk menerima order baru.',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PaymentHistoryScreen(isDriver: true),
                              ),
                            );
                          },
                          child: Text(TrakaL10n.of(context).paymentHistory),
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
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPemesananTab(),
                _buildPesananTerjadwalTab(),
                _buildPenumpangTab(),
                _buildOperKeSayaTab(),
                _buildPemesananSelesaiTab(),
                _buildRiwayatRuteTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tab Pesanan Terjadwal: pesanan dari jadwal yang belum dijalankan (exclude jadwal aktif).
  /// Chip tanggal horizontal + list pesanan per tanggal.
  Widget _buildPesananTerjadwalTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Belum login.'));
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _allOrdersStreamForScheduled,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final allOrders = snapshot.data ?? [];
        final scheduledOrders = allOrders
            .where((o) => o.isScheduledOrder)
            .where((o) => !o.isCompleted && !o.isCancelled)
            .where((o) {
              if (_activeRouteScheduleIdMatchesOrder(o.scheduleId)) {
                return false;
              }
              return true;
            })
            .toList();
        final dates = scheduledOrders
            .map((o) => o.scheduledDate ?? '')
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (dates.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada pesanan terjadwal',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pesanan terjadwal dari Jadwal & Rute akan muncul di sini.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        final selectedDate = (_selectedScheduledDate != null &&
                dates.contains(_selectedScheduledDate))
            ? _selectedScheduledDate!
            : dates.first;
        if (_selectedScheduledDate != selectedDate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedScheduledDate = selectedDate);
          });
        }
        final ordersForDate = scheduledOrders
            .where((o) => (o.scheduledDate ?? '') == selectedDate)
            .toList()
          ..sort((a, b) {
            final at = a.createdAt ?? a.updatedAt;
            final bt = b.createdAt ?? b.updatedAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: dates.map((ymd) {
                    final isSelected = ymd == selectedDate;
                    final label = _formatScheduledDateChip(ymd);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedScheduledDate = ymd);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: _listPaddingWithSafeBottom(context, top: 0),
                itemCount: ordersForDate.length,
                itemBuilder: (context, index) {
                  final order = ordersForDate[index];
                  return RepaintBoundary(
                    child: _buildScheduledOrderCard(order),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static String _formatScheduledDateChip(String ymd) {
    if (ymd.length != 10 || ymd[4] != '-' || ymd[7] != '-') return ymd;
    final todayYmd = DriverScheduleService.todayYmdWibString;
    if (ymd == todayYmd) return 'Hari ini';
    final tomorrowYmd = DriverScheduleService.ymdWibStringAfterDays(1);
    if (ymd == tomorrowYmd) return 'Besok';
    final dayAfterYmd = DriverScheduleService.ymdWibStringAfterDays(2);
    if (ymd == dayAfterYmd) return '2 hari lagi';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final d = ymd.substring(8, 10);
    final m = int.tryParse(ymd.substring(5, 7)) ?? 1;
    if (m < 1 || m > 12) return ymd;
    return '$d ${months[m - 1]}';
  }

  static Color _scheduledDateBadgeColor(String ymd) {
    if (ymd.length != 10 || ymd[4] != '-' || ymd[7] != '-') return Colors.blue;
    final todayYmd = DriverScheduleService.todayYmdWibString;
    if (ymd == todayYmd) return Colors.green;
    final tomorrowYmd = DriverScheduleService.ymdWibStringAfterDays(1);
    if (ymd == tomorrowYmd) return Colors.orange;
    return Colors.blue;
  }

  Widget _buildScheduledOrderCard(OrderModel order) {
    final scheduleId = order.scheduleId ?? '';
    final driverUid = FirebaseAuth.instance.currentUser?.uid ?? order.driverUid;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatDriverScreen(orderId: order.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _scheduledDateBadgeColor(order.scheduledDate ?? '')
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: _scheduledDateBadgeColor(order.scheduledDate ?? ''),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatScheduledDateChip(order.scheduledDate ?? ''),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _scheduledDateBadgeColor(order.scheduledDate ?? ''),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage: (order.passengerPhotoUrl != null &&
                            order.passengerPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                        : null,
                    child: (order.passengerPhotoUrl == null ||
                            order.passengerPhotoUrl!.isEmpty)
                        ? Icon(
                            order.isKirimBarang ? Icons.inventory_2 : Icons.person,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.passengerName.isEmpty
                              ? (order.isKirimBarang ? 'Kirim barang' : 'Penumpang')
                              : order.passengerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (order.originText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (order.destText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          order.status == OrderService.statusAgreed ||
                                  order.status == OrderService.statusPickedUp
                              ? 'Sudah kesepakatan'
                              : 'Menunggu kesepakatan',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: order.status == OrderService.statusAgreed ||
                                    order.status == OrderService.statusPickedUp
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                        if (order.isKirimBarang) ...[
                          const SizedBox(height: 4),
                          Text(
                            order.effectiveTravelFarePaidBy ==
                                    OrderModel.travelFarePaidByReceiver
                                ? 'Ongkos ke driver: penerima'
                                : 'Ongkos ke driver: pengirim',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (scheduleId.isNotEmpty &&
                      driverUid.isNotEmpty &&
                      (order.status == OrderService.statusAgreed ||
                          order.status == OrderService.statusPickedUp))
                    IconButton(
                      icon: const Icon(Icons.event_available),
                      tooltip: 'Pindah ke jadwal lain',
                      onPressed: () {
                        showPindahJadwalSheet(
                          context,
                          order: order,
                          currentScheduleId: scheduleId,
                          driverUid: driverUid,
                        );
                      },
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Pemesanan: hanya tampilkan pesanan yang sudah terjadi kesepakatan (agreed/picked_up).
  /// Pesanan yang belum kesepakatan (pending_agreement) tidak ditampilkan.
  Widget _buildPemesananTab() {
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Belum ada rute aktif',
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Aktifkan rute dari Beranda (Siap Kerja) agar pesanan penumpang muncul di sini. Setelah ganti project Firebase, buka Beranda > Siap Kerja lalu kembali ke sini.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  setState(() => _routeJourneyNumber = null);
                  await _loadActiveRoute();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Muat ulang'),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<List<OrderModel>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final allOrders = snapshot.data ?? [];

        // Filter 1: Hanya pesanan status agreed (belum di-scan / belum pindah ke Penumpang)
        final agreedOrders = allOrders
            .where((order) => order.status == OrderService.statusAgreed)
            .toList();

        // Filter 2: Untuk rute yang sama dan penumpang yang sama, ambil hanya yang terbaru
        final Map<String, OrderModel> latestOrdersMap = {};
        for (final order in agreedOrders) {
          // Key: kombinasi routeJourneyNumber + passengerUid
          final key = '${order.routeJourneyNumber}_${order.passengerUid}';
          final existing = latestOrdersMap[key];

          if (existing == null) {
            latestOrdersMap[key] = order;
          } else {
            // Bandingkan waktu: ambil yang lebih baru (createdAt atau updatedAt)
            final existingTime = existing.createdAt ?? existing.updatedAt;
            final currentTime = order.createdAt ?? order.updatedAt;

            if (existingTime != null && currentTime != null) {
              if (currentTime.isAfter(existingTime)) {
                latestOrdersMap[key] = order; // Ganti dengan yang lebih baru
              }
            } else if (currentTime != null && existingTime == null) {
              latestOrdersMap[key] =
                  order; // Current punya waktu, existing tidak
            }
          }
        }

        final orders = latestOrdersMap.values.toList();
        // Urutkan berdasarkan waktu terbaru
        orders.sort((a, b) {
          final aTime = a.createdAt ?? a.updatedAt;
          final bTime = b.createdAt ?? b.updatedAt;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime); // Terbaru di atas
        });
        if (orders.isNotEmpty &&
            _positionForCancel == null &&
            !_loadingPositionForCancel) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _loadPositionForCancel(),
          );
        }
        if (orders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada pesanan',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pesanan dari penumpang akan muncul di sini setelah penumpang mengirim permintaan.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return FutureBuilder<int>(
          future: ViolationService.getViolationFeeRupiah(),
          builder: (context, feeSnap) {
            final feeStr = feeSnap.hasData
                ? feeSnap.data!.toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (m) => '${m[1]}.',
                  )
                : '5.000';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tunjukkan barcode ke penumpang untuk di-scan saat penjemputan. Penumpang scan barcode Anda. Jika tidak scan, akan terkonfirmasi otomatis (15 menit berdekatan atau 1 km) dan dikenakan denda Rp $feeStr.',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                TrakaL10n.of(context).pickupOperationalDriverNavigateLive,
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _loadPositionForCancel();
                      _loadActiveRoute();
                      await Future.delayed(const Duration(milliseconds: 400));
                    },
                    child: ListView.builder(
                      padding: _listPaddingWithSafeBottom(context),
                      itemCount: orders.length,
                      cacheExtent: 200,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return RepaintBoundary(
                          child: _buildOrderCard(order, forPenumpangTab: false),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Format alamat: hanya kecamatan dan kabupaten, tanpa provinsi.
  String _formatAlamatKecamatanKabupaten(String alamat) {
    if (alamat.isEmpty) return alamat;
    final parts = alamat
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return alamat;

    String? kecamatan;
    String? kabupaten;

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (lower.contains('kecamatan') || lower.contains('kec.')) {
        kecamatan = part;
      } else if (lower.contains('kabupaten') ||
          lower.contains('kab.') ||
          lower.contains('kota ') ||
          (lower.contains('kota') && !lower.contains('kabupaten'))) {
        kabupaten = part;
      }
    }

    if (kecamatan == null && kabupaten == null && parts.length >= 2) {
      kecamatan = parts[0];
      kabupaten = parts[1];
    } else if (kecamatan == null && parts.isNotEmpty) {
      kecamatan = parts[0];
    }

    final result = <String>[];
    if (kecamatan != null) result.add(kecamatan);
    if (kabupaten != null && kabupaten != kecamatan) result.add(kabupaten);

    return result.isEmpty ? alamat : result.join(', ');
  }

  Widget _buildOrderCard(
    OrderModel order, {
    bool forPenumpangTab = false,
    bool selesai = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No. Pesanan dengan icon salin
            if (order.orderNumber != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'No. Pesanan: ${order.orderNumber}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: order.orderNumber!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Nomor pesanan disalin'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            KirimBarangDriverOngkosBanner(order: order),
            // Foto profil dan nama: kirim_barang di tab Pemesanan = Pengirim + Penerima + lokasi; di tab Penumpang = Penerima (tunjukkan barcode)
            if (order.isKirimBarang && forPenumpangTab) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (order.receiverPhotoUrl != null &&
                                order.receiverPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(order.receiverPhotoUrl!)
                        : null,
                    child: (order.receiverPhotoUrl == null ||
                            order.receiverPhotoUrl!.isEmpty)
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Penerima: ${order.receiverName ?? "–"}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tunjukkan barcode driver ke penerima untuk terima barang',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (order.isKirimBarang && !forPenumpangTab) ...[
              _buildKirimBarangPengirimPenerimaRow(order),
              const SizedBox(height: 8),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (order.passengerPhotoUrl != null &&
                            order.passengerPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                        : null,
                    child:
                        (order.passengerPhotoUrl == null ||
                            order.passengerPhotoUrl!.isEmpty)
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: ChatService.getUserInfo(order.passengerUid),
                      builder: (context, snap) {
                        final verified = snap.data?['verified'] == true;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.verified,
                                    size: 18,
                                    color: Colors.green.shade700,
                                  ),
                                ],
                                if (order.isPassengerEnglish) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      TrakaL10n.of(context).touristBadge,
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
                            const SizedBox(height: 4),
                            Text(
                              order.originText.isNotEmpty
                                  ? 'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}'
                                  : 'Dari: -',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              order.destText.isNotEmpty
                                  ? 'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}'
                                  : 'Tujuan: -',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            if (order.isKirimBarang) ...[
              Text(
                order.originText.isNotEmpty
                    ? 'Dari: ${_formatAlamatKecamatanKabupaten(order.originText)}'
                    : 'Dari: -',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                order.destText.isNotEmpty
                    ? 'Tujuan: ${_formatAlamatKecamatanKabupaten(order.destText)}'
                    : 'Tujuan: -',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            // Action cards: Pemesanan Selesai = tidak ada tombol (hanya info + jarak); Penumpang = hanya Barcode; Pemesanan = 4 kartu
            if (selesai) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.tripDistanceKm != null && order.tripDistanceKm! >= 0
                          ? 'Jarak: ${order.tripDistanceKm!.toStringAsFixed(1)} km'
                          : 'Jarak: - km',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (order.tripFareRupiah != null &&
                        order.tripFareRupiah! >= 0) ...[
                      const SizedBox(height: 2),
                      ..._buildKontribusiAplikasiRincian(order),
                    ],
                  ],
                ),
              ),
              if (OrderReceiptPdfFlow.canDriverIssue(order)) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _loadingReceiptPdfOrderId == order.id
                        ? null
                        : () => OrderReceiptPdfFlow.issueAsDriver(
                              host: this,
                              order: order,
                              setLoadingOrderId: (id) => setState(
                                () => _loadingReceiptPdfOrderId = id,
                              ),
                            ),
                    icon: _loadingReceiptPdfOrderId == order.id
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      TrakaL10n.of(context).onlineReceiptAndPdfButton,
                    ),
                  ),
                ),
              ],
            ] else if (forPenumpangTab)
              // Menu Penumpang: penumpang sudah dijemput, hanya tombol Barcode (tunjukkan ke penumpang)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _onSOS(context, order),
                      icon: const Icon(Icons.emergency, size: 20),
                      label: const Text('SOS Darurat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: _buildBarcodeDriverCard(order))]),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _onSOS(context, order),
                      icon: const Icon(Icons.emergency, size: 20),
                      label: const Text('SOS Darurat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildBatalkanCardWithDekatCheck(order)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionCard(
                          icon: Icons.chat_bubble_outline,
                          label: 'Chat',
                          color: Theme.of(context).colorScheme.primary,
                          onTap: () => _onChat(order),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPesananBarcodeCard(order)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildLokasiCard(order),
                      ),
                    ],
                  ),
            // Penumpang yang scan barcode. Driver hanya tunjukkan barcode.
                  ],
                ),
            ],
        ),
      ),
    );
  }

  /// Rincian Kontribusi Aplikasi: travel = jarak × tarif/km; kirim barang = jarak × tarif/km.
  List<Widget> _buildKontribusiAplikasiRincian(OrderModel order) {
    if (order.orderType == OrderModel.typeKirimBarang) {
      final total = (order.tripBarangFareRupiah ?? 0).round();
      final totalStr = total.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      return [
        Text(
          total > 0
              ? 'Kontribusi Aplikasi : Rp $totalStr'
              : 'Kontribusi Aplikasi : (Dihitung saat barang diterima)',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '(Jarak × tarif per km, tier provinsi. Bayar via Google Play)',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    // Travel
    final contrib = (order.tripTravelContributionRupiah ?? 0).round();
    final totalPenumpang = order.totalPenumpang;
    // Order lama: tripTravelContributionRupiah = 0 → hitung dari jarak (totalPenumpang × (jarak × tarif, min Rp 5.000))
    if (contrib == 0 && totalPenumpang > 0) {
      return [
        FutureBuilder<int?>(
          future: OrderService.getTripTravelContributionForDisplay(order),
          builder: (context, snap) {
            final c = snap.data ?? 0;
            final cStr = c.toString().replaceAllMapped(
                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kontribusi Aplikasi : Rp $cStr',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    c > 0
                        ? '(totalPenumpang × (jarak × tarif per km, min Rp 5.000). Bayar via Google Play)'
                        : '(Dihitung saat order selesai: totalPenumpang × (jarak × tarif, min Rp 5.000))',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (c > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Rincian: $totalPenumpang penumpang × (jarak × tarif, min Rp 5.000) = Rp $cStr',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ];
    }
    final contribStr = contrib.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    final widgets = <Widget>[
      Text(
        'Kontribusi Aplikasi : Rp $contribStr',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          contrib > 0
              ? '(totalPenumpang × (jarak × tarif per km, min Rp 5.000). Bayar via Google Play)'
              : '(Dihitung saat order selesai: totalPenumpang × (jarak × tarif, min Rp 5.000))',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
    if (contrib > 0 && totalPenumpang > 0) {
      final basePerPenumpang = (contrib / totalPenumpang).round();
      final baseStr = basePerPenumpang.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Rincian: $totalPenumpang penumpang × Rp $baseStr (dari jarak) = Rp $contribStr',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  /// Tombol Lokasi. Untuk pesanan terjadwal: disabled jika jadwal driver belum aktif atau belum hari ini.
  Widget _buildLokasiCard(OrderModel order) {
    final disabled = _isLokasiDisabledForScheduledOrder(order);
    return Tooltip(
      message: disabled
          ? 'Lokasi belum tersedia. Jadwal driver belum aktif atau belum saatnya hari ini.'
          : '',
      child: _buildActionCard(
        icon: Icons.location_on,
        label: 'Lokasi',
        color: disabled ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.green,
        onTap: disabled ? () {} : () => _onLokasi(order),
      ),
    );
  }

  /// Barcode yang ditampilkan driver: PICKUP saat agreed, COMPLETE saat picked_up.
  String? _getDriverBarcodeToShow(OrderModel order) {
    if (order.isPickedUp) return order.driverBarcodePayload;
    if (order.isAgreed) return order.driverBarcodePickupPayload;
    return null;
  }

  /// Sinkron dengan beranda: jadwal aktif vs `scheduleId` di order (format `_h…` / legacy).
  bool _activeRouteScheduleIdMatchesOrder(String? orderScheduleId) {
    final cur = _scheduleId;
    if (cur == null || cur.isEmpty) return false;
    final oid = orderScheduleId ?? '';
    if (oid.isEmpty) return false;
    if (cur == oid) return true;
    return ScheduleIdUtil.toLegacy(cur) == ScheduleIdUtil.toLegacy(oid);
  }

  /// Pesanan terjadwal: Lokasi disabled jika driver belum mulai rute dari jadwal itu atau tanggal bukan hari ini (WIB).
  bool _isLokasiDisabledForScheduledOrder(OrderModel order) {
    if (!order.isScheduledOrder) return false;
    if ((order.scheduledDate ?? '') !=
        DriverScheduleService.todayYmdWibString) {
      return true;
    }
    if (!_activeRouteScheduleIdMatchesOrder(order.scheduleId)) return true;
    return false;
  }

  /// Tombol Batalkan; dinonaktifkan jika driver dan penumpang dalam radius 300 m atau dibatalkan admin.
  Widget _buildBatalkanCardWithDekatCheck(OrderModel order) {
    final isAdminCancelled = order.adminCancelled;
    if (_positionForCancel == null) {
      return _buildActionCard(
        icon: Icons.cancel_outlined,
        label: _getBatalkanLabel(order),
        color: Colors.red,
        onTap: isAdminCancelled ? () {} : () => _onBatalkanPesanan(order),
        enabled: !isAdminCancelled,
        disabledHint: isAdminCancelled ? 'Pesanan telah dibatalkan oleh admin' : null,
      );
    }
    return FutureBuilder<bool>(
      future: OrderService.isDriverPenumpangDekatForCancel(
        order: order,
        currentLat: _positionForCancel!.latitude,
        currentLng: _positionForCancel!.longitude,
        isDriver: true,
      ),
      builder: (context, snap) {
        final disable = snap.data == true || order.adminCancelled;
        return _buildActionCard(
          icon: Icons.cancel_outlined,
          label: _getBatalkanLabel(order),
          color: Colors.red,
          enabled: !disable,
          disabledHint: disable && !order.adminCancelled
              ? 'Tidak bisa dibatalkan saat dalam radius ${OrderService.radiusDekatMeter} m dari penumpang'
              : (order.adminCancelled ? 'Pesanan telah dibatalkan oleh admin' : null),
          onTap: disable
              ? () {
                  if (!order.adminCancelled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Tidak bisa dibatalkan saat dekat dengan penumpang (radius ${OrderService.radiusDekatMeter} m).',
                        ),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              : () => _onBatalkanPesanan(order),
        );
      },
    );
  }

  /// Kartu Barcode: tampil barcode untuk driver tunjukkan ke penumpang (PICKUP atau COMPLETE).
  Widget _buildPesananBarcodeCard(OrderModel order) {
    final payload = _getDriverBarcodeToShow(order);
    final hasBarcode = payload != null;
    final label = order.isPickedUp ? 'Barcode selesai' : (order.isAgreed ? 'Tunjukkan barcode' : 'Menunggu');
    final title = order.isPickedUp
        ? 'Barcode selesai (scan saat sampai tujuan)'
        : 'Barcode penjemputan (scan saat dijemput)';
    return _buildActionCard(
      icon: Icons.qr_code_2,
      label: label,
      color: hasBarcode ? Colors.orange : Theme.of(context).colorScheme.onSurfaceVariant,
      onTap: () {
        if (payload != null) {
          _showBarcodeFullScreen(context, payload, title);
        }
      },
    );
  }

  void _showBarcodeFullScreen(
    BuildContext context,
    String payload,
    String title,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kartu Barcode driver (menu Penumpang): tampil barcode driver untuk ditunjukkan ke penumpang; tap = full.
  Widget _buildBarcodeDriverCard(OrderModel order) {
    final hasBarcode = order.hasDriverBarcode;
    final payload = order.driverBarcodePayload;
    return _buildActionCard(
      icon: Icons.qr_code_2,
      label: hasBarcode ? 'Barcode' : 'Barcode',
      color: hasBarcode ? Colors.deepPurple : Theme.of(context).colorScheme.onSurfaceVariant,
      onTap: hasBarcode && payload != null
          ? () => _showBarcodeFullScreen(
              context,
              payload,
              'Barcode driver (tunjukkan ke penumpang)',
            )
          : () {},
    );
  }

  /// Label tombol Batalkan: "Batalkan", "Konfirmasi", atau "Dibatalkan oleh admin".
  String _getBatalkanLabel(OrderModel order) {
    if (order.adminCancelled) return 'Dibatalkan oleh admin';
    if (order.passengerCancelled && !order.driverCancelled) return 'Konfirmasi';
    if (order.status == OrderService.statusCancelled) return 'Dibatalkan';
    return 'Batalkan';
  }

  /// Tombol Batalkan: konfirmasi, jika salah satu klik maka tombol lawan berubah jadi "Konfirmasi".
  Future<void> _onBatalkanPesanan(OrderModel order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Cek apakah ini konfirmasi (lawan sudah klik batalkan)
    final isConfirming = order.passengerCancelled && !order.driverCancelled;

    final title = isConfirming ? 'Konfirmasi Pembatalan' : 'Batalkan Pesanan';
    final content = isConfirming
        ? 'Penumpang telah membatalkan pesanan. Apakah anda mengkonfirmasi pembatalan ini?'
        : 'Apakah anda membatalkan pesanan?';

    final policyText = 'Kebijakan: Pembatalan tidak dapat dilakukan saat Anda dalam radius ${OrderService.radiusDekatMeter} m dari penumpang. '
        'Refund (jika ada pembayaran di muka) mengikuti kebijakan Google Play.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(content),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(policyText, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isConfirming ? 'Konfirmasi' : 'Iya'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Set flag cancellation untuk driver
    final ok = await OrderService.setCancellationFlag(order.id, true);
    if (!mounted) return;
    if (ok) {
      final message = isConfirming
          ? TrakaL10n.of(context).cancellationConfirmed
          : TrakaL10n.of(context).cancellationRequestSentPassenger;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).failedToCancel),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Tombol Chat: navigasi ke chat room dengan driver/penumpang.
  Future<void> _onSOS(BuildContext context, OrderModel order) async {
    final confirmed = await showSosEmergencyConfirmDialog(context);
    if (confirmed != true || !context.mounted) return;
    await SosService.triggerSOSWithLocation(order: order, isDriver: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).sosSent),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onChat(OrderModel order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDriverScreen(orderId: order.id),
      ),
    );
  }

  /// Baris Pengirim + Penerima untuk order kirim_barang (dengan icon lokasi).
  Widget _buildKirimBarangPengirimPenerimaRow(OrderModel order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  (order.passengerPhotoUrl != null &&
                          order.passengerPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                      : null,
              child: (order.passengerPhotoUrl == null ||
                      order.passengerPhotoUrl!.isEmpty)
                  ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Pengirim: ${order.passengerName}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (order.isPassengerEnglish) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        TrakaL10n.of(context).touristBadge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary, size: 24),
              tooltip: 'Cek lokasi pengirim',
              onPressed: () => _onLokasiKirimBarang(order, isPengirim: true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage:
                  (order.receiverPhotoUrl != null &&
                          order.receiverPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(order.receiverPhotoUrl!)
                      : null,
              child: (order.receiverPhotoUrl == null ||
                      order.receiverPhotoUrl!.isEmpty)
                  ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Penerima: ${order.receiverName ?? "–"}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.location_on, color: Colors.green.shade700, size: 24),
              tooltip: 'Cek lokasi penerima',
              onPressed: () => _onLokasiKirimBarang(order, isPengirim: false),
            ),
          ],
        ),
        if (order.barangFotoUrl != null && order.barangFotoUrl!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: order.barangFotoUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  errorWidget: (_, url, error) => Container(
                    width: 56,
                    height: 56,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Foto barang',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Map untuk kirim barang: pengirim atau penerima + posisi driver.
  Future<void> _onLokasiKirimBarang(OrderModel order, {required bool isPengirim}) async {
    double? pointLat;
    double? pointLng;
    String pointLabel;
    if (isPengirim) {
      pointLat = order.passengerLat;
      pointLng = order.passengerLng;
      pointLabel = order.passengerName;
    } else {
      pointLat = order.receiverLat;
      pointLng = order.receiverLng;
      pointLabel = order.receiverName ?? 'Penerima';
    }
    if (pointLat == null || pointLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPengirim
                ? 'Lokasi pengirim tidak tersedia.'
                : 'Lokasi penerima belum diisi.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final pointLatLng = LatLng(pointLat, pointLng);
    Position? driverPosition;
    try {
      driverPosition = await LocationService.getCurrentPosition();
    } catch (_) {
      driverPosition = null;
    }
    final driverLatLng = driverPosition != null
        ? LatLng(driverPosition.latitude, driverPosition.longitude)
        : pointLatLng;
    final driverMarkerIcon = await _createDriverMarkerIcon();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isPengirim ? 'Lokasi pengirim & driver' : 'Lokasi penerima & driver',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StyledGoogleMapBuilder(
                builder: (style, _) => GoogleMap(
                  buildingsEnabled: true,
                  indoorViewEnabled: true,
                  mapToolbarEnabled: false,
                  initialCameraPosition: CameraPosition(
                    target: driverPosition != null
                        ? LatLng(
                            (driverLatLng.latitude + pointLatLng.latitude) / 2,
                            (driverLatLng.longitude + pointLatLng.longitude) / 2,
                          )
                        : pointLatLng,
                    zoom: MapStyleService.defaultZoom,
                    tilt: MapStyleService.defaultTilt,
                  ),
                  style: style,
                  markers: {
                      Marker(
                        markerId: MarkerId(isPengirim ? 'pengirim' : 'penerima'),
                        position: pointLatLng,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          isPengirim ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueViolet,
                        ),
                        infoWindow: InfoWindow(
                          title: isPengirim ? 'Pengirim' : 'Penerima',
                          snippet: pointLabel,
                        ),
                      ),
                      Marker(
                        markerId: const MarkerId('driver'),
                        position: driverLatLng,
                        icon: driverMarkerIcon,
                        infoWindow: const InfoWindow(title: 'Driver', snippet: 'Posisi Anda'),
                      ),
                    },
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol Lokasi: tampilkan map dengan posisi driver dan penumpang.
  Future<void> _onLokasi(OrderModel order) async {
    if (order.passengerLat == null || order.passengerLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi penumpang tidak tersedia.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Ambil posisi driver saat ini
    Position? driverPosition;
    try {
      driverPosition = await LocationService.getCurrentPosition();
    } catch (e) {
      // Jika gagal ambil posisi driver, gunakan posisi penumpang sebagai center
      driverPosition = null;
    }

    final passengerLatLng = LatLng(order.passengerLat!, order.passengerLng!);
    final driverLatLng = driverPosition != null
        ? LatLng(driverPosition.latitude, driverPosition.longitude)
        : passengerLatLng;

    // Buat custom marker untuk penumpang (pin + foto profil)
    BitmapDescriptor? passengerMarkerIcon;
    try {
      passengerMarkerIcon = await MarkerIconService.createProfilePhotoMarker(
        name: order.passengerName.trim().isEmpty ? 'Penumpang' : order.passengerName,
        photoUrl: order.passengerPhotoUrl,
        ribbonColor: Colors.blue,
        fallbackCircleColor: Colors.blue.shade300,
      );
    } catch (e) {
      passengerMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueBlue,
      );
    }

    // Buat custom marker untuk driver (icon mobil)
    BitmapDescriptor? driverMarkerIcon;
    try {
      driverMarkerIcon = await _createDriverMarkerIcon();
    } catch (e) {
      driverMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Foto penumpang
                  if (order.passengerPhotoUrl != null &&
                      order.passengerPhotoUrl!.isNotEmpty)
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: CachedNetworkImageProvider(
                        order.passengerPhotoUrl!,
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: ChatService.getUserInfo(order.passengerUid),
                      builder: (context, snap) {
                        final verified = snap.data?['verified'] == true;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lokasi Driver & Penumpang',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    order.passengerName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.verified,
                                    size: 16,
                                    color: Colors.green.shade700,
                                  ),
                                ],
                                if (order.isPassengerEnglish) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      TrakaL10n.of(context).touristBadge,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              'Driver: ${driverPosition != null ? "Terdeteksi" : "Tidak terdeteksi"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            if (widget.onNavigateToPassenger != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onNavigateToPassenger!(order);
                    },
                    icon: const Icon(Icons.directions, size: 20),
                    label: const Text('Ya, arahkan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: StyledGoogleMapBuilder(
                  builder: (style, _) => GoogleMap(
                    buildingsEnabled: true,
                    indoorViewEnabled: true,
                    mapToolbarEnabled: false,
                    initialCameraPosition: CameraPosition(
                      target: driverPosition != null
                          ? LatLng(
                              (driverLatLng.latitude + passengerLatLng.latitude) / 2,
                              (driverLatLng.longitude + passengerLatLng.longitude) / 2,
                            )
                          : passengerLatLng,
                      zoom: MapStyleService.defaultZoom,
                      tilt: MapStyleService.defaultTilt,
                    ),
                    style: style,
                    markers: {
                        // Marker penumpang (pin + foto profil)
                        Marker(
                          markerId: const MarkerId('penumpang'),
                          position: passengerLatLng,
                          icon: passengerMarkerIcon!,
                          anchor: const Offset(0.5, 1.0),
                          infoWindow: InfoWindow(
                            title: order.passengerName,
                            snippet: 'Penumpang',
                          ),
                        ),
                        // Marker driver (jika posisi tersedia)
                        if (driverPosition != null)
                          Marker(
                            markerId: const MarkerId('driver'),
                            position: driverLatLng,
                            icon: driverMarkerIcon!,
                            infoWindow: const InfoWindow(
                              title: 'Driver',
                              snippet: 'Posisi Anda',
                            ),
                          ),
                      },
                      myLocationEnabled: driverPosition == null,
                      myLocationButtonEnabled: driverPosition == null,
                    ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Buat custom marker icon untuk driver (icon mobil).
  Future<BitmapDescriptor> _createDriverMarkerIcon() async {
    try {
      final result = await CarIconService.loadCarIcons(
        context: context,
        baseSize: 30,
        padding: 12,
      );
      return result.green; // Driver aktif = hijau
    } catch (_) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
  }

  /// Widget untuk action card yang modern (bukan tombol).
  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    String? disabledHint,
  }) {
    final effectiveColor = enabled ? color : Colors.grey;
    final opacity = enabled ? 1.0 : 0.6;
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: enabled ? 0.1 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveColor.withValues(alpha: enabled ? 0.3 : 0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: effectiveColor.withValues(alpha: opacity)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: effectiveColor.withValues(alpha: opacity),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
    if (!enabled && disabledHint != null && disabledHint.isNotEmpty) {
      return Tooltip(
        message: disabledHint,
        child: child,
      );
    }
    return child;
  }

  /// 2. Penumpang: penumpang yang sudah dijemput (status picked_up).
  Widget _buildPenumpangTab() {
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Belum ada rute aktif',
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Aktifkan rute dari Beranda (Siap Kerja) agar pesanan muncul.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  setState(() => _routeJourneyNumber = null);
                  await _loadActiveRoute();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Muat ulang'),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final allOrders = snapshot.data ?? [];
        final pickedUpOrders = allOrders
            .where((o) => o.status == OrderService.statusPickedUp)
            .toList();
        final Map<String, OrderModel> latest = {};
        for (final order in pickedUpOrders) {
          final key = '${order.routeJourneyNumber}_${order.passengerUid}';
          final existing = latest[key];
          if (existing == null ||
              (order.updatedAt ?? order.createdAt) != null &&
                  (existing.updatedAt ?? existing.createdAt) != null &&
                  (order.updatedAt ?? order.createdAt)!.isAfter(
                    existing.updatedAt ?? existing.createdAt!,
                  )) {
            latest[key] = order;
          }
        }
        final orders = latest.values.toList();
        orders.sort((a, b) {
          final at = a.updatedAt ?? a.createdAt;
          final bt = b.updatedAt ?? b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        if (orders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada penumpang dijemput',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Setelah Anda scan barcode penumpang, pesanan akan pindah ke sini.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: _listPaddingWithSafeBottom(context),
          itemCount: orders.length,
          cacheExtent: 200,
          itemBuilder: (context, index) => RepaintBoundary(
            child: _buildOrderCard(orders[index], forPenumpangTab: true),
          ),
        );
      },
    );
  }

  /// Oper ke Saya: transfer dari driver lain yang menunggu scan.
  Widget _buildOperKeSayaTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Sesi tidak valid'));

    return StreamBuilder<List<DriverTransferModel>>(
      stream: _transfersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final transfers = snapshot.data ?? [];
        if (transfers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Tidak ada oper menunggu',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Driver lain akan mengirim notifikasi saat ingin mengoper penumpang ke Anda.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: _listPaddingWithSafeBottom(context),
          itemCount: transfers.length,
          itemBuilder: (context, index) {
            final t = transfers[index];
            return _buildOperTransferCard(t);
          },
        );
      },
    );
  }

  Widget _buildOperTransferCard(DriverTransferModel transfer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: DriverTransferService.getTransferDisplayInfo(transfer),
              builder: (context, snap) {
                final fromName = snap.data?['fromName'] ?? 'Driver';
                final passengerName = snap.data?['passengerName'] ?? '-';
                final destText = snap.data?['destText'] ?? '-';
                final totalPenumpang = (snap.data?['totalPenumpang'] as int?) ?? 1;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          child: Icon(Icons.directions_car, color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fromName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Ingin mengoper penumpang ke Anda',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Penumpang: $passengerName',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.place, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tujuan: $destText',
                                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.people, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '$totalPenumpang orang',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScanTransferDriverScreen(),
                    ),
                  );
                  if (ok == true && mounted) setState(() {});
                },
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('Scan Barcode & Verifikasi'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Pesanan Selesai: penumpang yang sudah menyelesaikan perjalanan (status completed).
  Widget _buildPemesananSelesaiTab() {
    if (_routeJourneyNumber == null || _routeJourneyNumber!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Belum ada rute aktif',
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Aktifkan rute dari Beranda (Siap Kerja) agar pesanan muncul.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  setState(() => _routeJourneyNumber = null);
                  await _loadActiveRoute();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Muat ulang'),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final allOrders = snapshot.data ?? [];
        final completedOrders = allOrders
            .where((o) => o.status == OrderService.statusCompleted)
            .toList();
        if (completedOrders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada pesanan selesai',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Setelah penumpang scan barcode driver, pesanan akan pindah ke sini.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          padding: _listPaddingWithSafeBottom(context),
          itemCount: completedOrders.length,
          cacheExtent: 200,
          itemBuilder: (context, index) => RepaintBoundary(
            child: _buildOrderCard(
              completedOrders[index],
              forPenumpangTab: false,
              selesai: true,
            ),
          ),
        );
      },
    );
  }

  /// 4. Riwayat Rute: daftar rute yang sudah selesai; tap rute → daftar order completed.
  /// Sumber utama: completed orders (tidak filter chatHiddenByDriver) agar riwayat tetap tampil
  /// walau chat disembunyikan/dihapus. Route_sessions dipakai untuk metadata jika ada.
  Widget _buildRiwayatRuteTab() {
    return StreamBuilder<List<OrderModel>>(
      stream: _completedOrdersStream,
      builder: (context, orderSnap) {
        if (orderSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: ShimmerLoading());
        }
        final completedOrders = orderSnap.data ?? [];
        if (completedOrders.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada riwayat rute',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pesanan yang sudah selesai (penumpang scan barcode di tujuan) akan muncul di sini.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PaymentHistoryScreen(isDriver: true),
                            ),
                          );
                        },
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: Text(TrakaL10n.of(context).paymentHistory),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverEarningsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.account_balance_wallet, size: 18),
                        label: Text(TrakaL10n.of(context).driverEarningsTitle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return StreamBuilder<List<RouteSessionModel>>(
          stream: _sessionsStream,
          builder: (context, sessionSnap) {
            final sessions = sessionSnap.data ?? [];
            // Key -> list of sessions (rute terjadwal bisa punya beberapa sesi per scheduleId)
            final sessionsByRoute = <String, List<RouteSessionModel>>{};
            for (final s in sessions) {
              final key = s.routeJourneyNumber.isNotEmpty
                  ? '${s.routeJourneyNumber}_${s.scheduleId ?? ""}'
                  : '_empty_${s.endedAt.toIso8601String().substring(0, 10)}';
              sessionsByRoute.putIfAbsent(key, () => []).add(s);
            }
            final groups = <String, List<OrderModel>>{};
            for (final o in completedOrders) {
              final dt = o.completedAt ?? o.updatedAt ?? o.createdAt;
              final key = o.routeJourneyNumber.isNotEmpty
                  ? '${o.routeJourneyNumber}_${o.scheduleId ?? ""}'
                  : '_empty_${dt?.toIso8601String().substring(0, 10) ?? ""}';
              groups.putIfAbsent(key, () => []).add(o);
            }
            final entries = groups.entries.toList()
              ..sort((a, b) {
                final aLast = a.value.last;
                final bLast = b.value.last;
                final at = aLast.completedAt ?? aLast.updatedAt ?? aLast.createdAt;
                final bt = bLast.completedAt ?? bLast.updatedAt ?? bLast.createdAt;
                if (at == null && bt == null) return 0;
                if (at == null) return 1;
                if (bt == null) return -1;
                return bt.compareTo(at);
              });
            return ListView.builder(
              padding: _listPaddingWithSafeBottom(context),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final first = entry.value.first;
                final last = entry.value.last;
                final lastOrderTime = last.completedAt ?? last.updatedAt ?? last.createdAt;
                final candidates = sessionsByRoute[entry.key] ?? [];
                // Pilih session yang endedAt paling dekat dengan completedAt order terakhir
                final session = candidates.isEmpty
                    ? null
                    : candidates.length == 1
                        ? candidates.first
                        : candidates.reduce((a, b) {
                            if (lastOrderTime == null) return a;
                            final da = (a.endedAt.difference(lastOrderTime)).inSeconds.abs();
                            final db = (b.endedAt.difference(lastOrderTime)).inSeconds.abs();
                            return da <= db ? a : b;
                          });
                final originText = session?.routeOriginText.isNotEmpty == true
                    ? session!.routeOriginText
                    : (first.originText.trim().isNotEmpty
                        ? first.originText
                        : 'Lokasi awal');
                final destText = session?.routeDestText.isNotEmpty == true
                    ? session!.routeDestText
                    : (last.destText.trim().isNotEmpty
                        ? last.destText
                        : 'Tujuan');
                final endAt = session?.endedAt ??
                    (last.completedAt ?? last.updatedAt ?? last.createdAt);
                final endStr = endAt != null ? _formatRiwayatDate(endAt) : '';
                final count = entry.value.length;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      child: Icon(Icons.route, color: Colors.orange.shade700),
                    ),
                    title: Text(
                      originText,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          destText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (endStr.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            endStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (count > 1) ...[
                          const SizedBox(height: 2),
                          Text(
                            '$count pesanan',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        // Status kontribusi: Lunas (sudah bayar), Belum bayar, atau Tidak ada kontribusi
                        _buildContributionStatus(session, entry.value),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildContributionTrailingIcon(session, entry.value),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => RiwayatRuteDetailScreen(
                            routeOriginText: originText,
                            routeDestText: destText,
                            routeJourneyNumber: first.routeJourneyNumber,
                            scheduleId: first.scheduleId,
                            endedAt: endAt,
                            orders: entry.value,
                            isContributionPaid: session?.isContributionPaid ?? false,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatRiwayatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Status kontribusi: Lunas (sudah bayar), Belum bayar, atau Tidak ada kontribusi.
  /// Lunas HANYA jika contributionPaidAt != null (bukan karena contributionRupiah == 0).
  /// Jika session.contributionRupiah == 0, hitung ulang dari orders (order lama bisa punya nilai di display).
  Widget _buildContributionStatus(RouteSessionModel? session, List<OrderModel> orders) {
    if (session != null) {
      if (session.isContributionPaid) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text(
                'Lunas',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700),
              ),
            ],
          ),
        );
      }
      // contributionRupiah == 0 di session bisa salah untuk order lama; hitung ulang dari orders
      if (session.contributionRupiah > 0) {
        return _buildStatusBelumBayar();
      }
      return FutureBuilder<int>(
        future: OrderService.getTotalContributionRupiahForOrdersDisplay(orders),
        builder: (context, snap) {
          final contrib = snap.data ?? 0;
          if (contrib > 0) return _buildStatusBelumBayar();
          return _buildStatusTidakAdaKontribusi();
        },
      );
    }
    // session == null: hitung dari orders (rute lama tanpa route_session)
    return FutureBuilder<int>(
      future: OrderService.getTotalContributionRupiahForOrdersDisplay(orders),
      builder: (context, snap) {
        final contrib = snap.data ?? 0;
        if (contrib > 0) return _buildStatusBelumBayar();
        return _buildStatusTidakAdaKontribusi();
      },
    );
  }

  Widget _buildStatusBelumBayar() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.pending_actions, size: 14, color: Colors.orange.shade700),
          const SizedBox(width: 4),
          Text(
            'Belum bayar kontribusi',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTidakAdaKontribusi() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.remove_circle_outline, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            'Tidak ada kontribusi',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildContributionTrailingIcon(RouteSessionModel? session, List<OrderModel> orders) {
    if (session != null) {
      if (session.isContributionPaid) {
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: 'Lunas',
            child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
          ),
        );
      }
      if (session.contributionRupiah > 0) {
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: 'Belum bayar kontribusi',
            child: Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 24),
          ),
        );
      }
      // contributionRupiah == 0: hitung ulang untuk order lama
      return FutureBuilder<int>(
        future: OrderService.getTotalContributionRupiahForOrdersDisplay(orders),
        builder: (context, snap) {
          final contrib = snap.data ?? 0;
          if (contrib > 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Belum bayar kontribusi',
                child: Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 24),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      );
    }
    // session == null: hitung dari orders
    return FutureBuilder<int>(
      future: OrderService.getTotalContributionRupiahForOrdersDisplay(orders),
      builder: (context, snap) {
        final contrib = snap.data ?? 0;
        if (contrib > 0) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Belum bayar kontribusi',
              child: Icon(Icons.pending_actions, color: Colors.orange.shade700, size: 24),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
