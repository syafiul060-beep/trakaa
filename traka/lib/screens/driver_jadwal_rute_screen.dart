import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../utils/placemark_formatter.dart';
import '../services/location_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/driver_schedule_service.dart';
import '../services/driver_schedule_items_store.dart';
import '../services/route_category_service.dart';
import '../services/order_service.dart';
import '../models/order_model.dart';
import '../widgets/oper_driver_sheet.dart';
import '../widgets/pindah_jadwal_sheet.dart';
import '../widgets/driver_map_overlays.dart';
import '../widgets/styled_google_map_builder.dart';
import '../services/map_style_service.dart';
import '../services/route_utils.dart';
import '../services/schedule_reminder_service.dart';
import '../services/driver_jadwal_route_category_prefs.dart';
import '../services/hybrid_foreground_recovery.dart';
import '../services/driver_hybrid_diagnostics.dart';
import '../services/app_analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_interaction_styles.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/traka_empty_state.dart';
import '../widgets/traka_bottom_sheet.dart';
import '../widgets/traka_l10n_scope.dart';
import '../widgets/traka_pin_widgets.dart';
import '../widgets/map_destination_picker_screen.dart';
import '../services/traka_pin_bitmap_service.dart';
import 'package:geolocator/geolocator.dart';

/// Batas waktu tunggu hapus jadwal dari sisi UI (batalkan tunggu, tutup overlay).
const Duration _kDeleteScheduleOverallTimeout = Duration(seconds: 60);

/// Kurangi titik polyline (tampilan peta / penyimpanan). Rute nasional bisa >15k titik → dokumen Firestore >1 MiB → `invalid-argument`.
List<LatLng> _samplePolylineForJadwalPreview(List<LatLng> pts, {int maxPoints = 420}) {
  if (pts.length <= maxPoints) {
    return pts
        .where((p) => p.latitude.isFinite && p.longitude.isFinite)
        .toList();
  }
  final finite = pts
      .where((p) => p.latitude.isFinite && p.longitude.isFinite)
      .toList();
  if (finite.isEmpty) return [];
  if (finite.length <= maxPoints) return finite;
  final out = <LatLng>[];
  final step = (finite.length / maxPoints).ceil().clamp(1, finite.length);
  for (var i = 0; i < finite.length; i += step) {
    out.add(finite[i]);
  }
  if (out.isEmpty ||
      out.last.latitude != finite.last.latitude ||
      out.last.longitude != finite.last.longitude) {
    out.add(finite.last);
  }
  return out;
}

/// Rute tanpa garis valid bisa bikin [LatLngBounds] / peta bermasalah; filter sebelum buka layar pilih rute.
List<DirectionsResult> _onlyDrawableRouteAlternatives(
  List<DirectionsResult> alts,
) {
  return alts
      .where((r) {
        final n = r.points
            .where((p) => p.latitude.isFinite && p.longitude.isFinite)
            .length;
        return n >= 2;
      })
      .toList();
}

/// Plafon titik polyline per entri jadwal saat tulis ke Firestore (aman untuk batas ~1 MiB per dokumen).
/// Dikecilkan agar dokumen `driver_schedules` tidak memblokir klien Firestore (antre → profil putih, Siap Kerja macet).
/// Garis di peta dari jadwal tetap cukup untuk bentuk umum; halus dari Directions hanya jika belum ada polyline.
const int _kMaxFirestoreRoutePolylinePoints = 320;

List<LatLng> _parsePolylineLatLngFromFirestoreRaw(dynamic raw) {
  if (raw == null) return [];
  final list = raw as List<dynamic>?;
  if (list == null || list.isEmpty) return [];
  final result = <LatLng>[];
  for (final e in list) {
    final m = e as Map<dynamic, dynamic>?;
    if (m == null) continue;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite) {
      result.add(LatLng(lat, lng));
    }
  }
  return result;
}

/// Kecilkan [routePolyline] tiap entri agar dokumen `driver_schedules` tidak melewati batas ukuran.
List<Map<String, dynamic>> _shrunkSchedulesForFirestoreDocument(
  List<Map<String, dynamic>> schedules,
) {
  return schedules.map((e) {
    final copy = Map<String, dynamic>.from(e);
    final raw = copy['routePolyline'];
    if (raw == null) return copy;
    final pts = _parsePolylineLatLngFromFirestoreRaw(raw);
    if (pts.isEmpty) {
      copy.remove('routePolyline');
      return copy;
    }
    final slim = _samplePolylineForJadwalPreview(
      pts,
      maxPoints: _kMaxFirestoreRoutePolylinePoints,
    );
    if (slim.isEmpty) {
      copy.remove('routePolyline');
      return copy;
    }
    copy['routePolyline'] = slim
        .map((p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
        .toList();
    return copy;
  }).toList();
}

/// Satu item jadwal dari Firebase: tujuan awal, tujuan akhir, jam, tanggal, rute (opsional), kategori rute.
class _JadwalItem {
  final String tujuanAwal;
  final String tujuanAkhir;
  final TimeOfDay jam;
  final DateTime tanggal;
  /// Polyline rute yang dipilih driver. Null = jadwal lama atau belum dipilih.
  final List<LatLng>? routePolyline;
  /// Kategori rute: dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  final String routeCategory;

  _JadwalItem({
    required this.tujuanAwal,
    required this.tujuanAkhir,
    required this.jam,
    required this.tanggal,
    this.routePolyline,
    this.routeCategory = RouteCategoryService.categoryAntarProvinsi,
  });
}

String _normJadwalAlamat(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Cari index entri di array Firestore [schedules] yang sama dengan satu jadwal di UI.
/// Array mentah bisa masih berisi jadwal yang sudah lewat (belum dipangkas) — jangan pakai index UI sebagai index array.
int? _indexOfScheduleInFirestoreList({
  required List<Map<String, dynamic>> schedules,
  required String driverUid,
  required DateTime itemDate,
  required TimeOfDay itemJam,
  required String originTrimmed,
  required String destTrimmed,
  String? scheduleId,
  String? legacyScheduleId,
}) {
  bool idsEqual(String? a, String? b) {
    if (a == null || a.isEmpty || b == null || b.isEmpty) return false;
    if (a == b) return true;
    return ScheduleIdUtil.toLegacy(a) == ScheduleIdUtil.toLegacy(b);
  }

  final hasId = (scheduleId != null && scheduleId.isNotEmpty) ||
      (legacyScheduleId != null && legacyScheduleId.isNotEmpty);

  if (hasId) {
    for (var i = 0; i < schedules.length; i++) {
      final m = schedules[i];
      final stored = m['scheduleId'] as String?;
      if (stored != null && stored.isNotEmpty) {
        if (idsEqual(stored, scheduleId) || idsEqual(stored, legacyScheduleId)) {
          return i;
        }
      }
    }
    for (var i = 0; i < schedules.length; i++) {
      final m = schedules[i];
      final dateStamp = m['date'] as Timestamp?;
      final depStamp = m['departureTime'] as Timestamp?;
      if (dateStamp == null || depStamp == null) continue;
      final d = dateStamp.toDate();
      final dep = depStamp.toDate();
      final dateKey =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final (sid, leg) = ScheduleIdUtil.build(
        driverUid,
        dateKey,
        dep.millisecondsSinceEpoch,
        (m['origin'] as String?) ?? '',
        (m['destination'] as String?) ?? '',
      );
      if (idsEqual(sid, scheduleId) ||
          idsEqual(sid, legacyScheduleId) ||
          idsEqual(leg, scheduleId) ||
          idsEqual(leg, legacyScheduleId)) {
        return i;
      }
    }
  }

  final targetDay = DateTime(itemDate.year, itemDate.month, itemDate.day);
  for (var i = 0; i < schedules.length; i++) {
    final m = schedules[i];
    final dateStamp = m['date'] as Timestamp?;
    final depStamp = m['departureTime'] as Timestamp?;
    if (dateStamp == null || depStamp == null) continue;
    final d = dateStamp.toDate();
    final scheduleDate = DateTime(d.year, d.month, d.day);
    if (scheduleDate != targetDay) continue;
    final dep = depStamp.toDate();
    if (dep.hour != itemJam.hour || dep.minute != itemJam.minute) continue;
    if (_normJadwalAlamat(m['origin'] as String? ?? '') ==
            _normJadwalAlamat(originTrimmed) &&
        _normJadwalAlamat(m['destination'] as String? ?? '') ==
            _normJadwalAlamat(destTrimmed)) {
      return i;
    }
  }
  // Satu-satunya entri di tanggal + jam yang sama (alamat di Firestore bisa beda format dari UI).
  final sameDayTime = <int>[];
  for (var i = 0; i < schedules.length; i++) {
    final m = schedules[i];
    final dateStamp = m['date'] as Timestamp?;
    final depStamp = m['departureTime'] as Timestamp?;
    if (dateStamp == null || depStamp == null) continue;
    final d = dateStamp.toDate();
    final scheduleDate = DateTime(d.year, d.month, d.day);
    if (scheduleDate != targetDay) continue;
    final dep = depStamp.toDate();
    if (dep.hour != itemJam.hour || dep.minute != itemJam.minute) continue;
    sameDayTime.add(i);
  }
  if (sameDayTime.length == 1) return sameDayTime.single;
  return null;
}

/// Hapus satu slot: baca subkoleksi → [persistReplaceAll].
Future<bool> _deleteScheduleFromFirestore({
  required FirebaseFirestore firestore,
  required String driverUid,
  required DateTime itemDate,
  required TimeOfDay itemJam,
  required String originTrimmed,
  required String destTrimmed,
  required String scheduleId,
  required String legacyScheduleId,
}) async {
  final sw = Stopwatch()..start();
  const readTimeout = Duration(seconds: 60);
  try {
    final merged = await DriverScheduleItemsStore.loadScheduleMaps(
      firestore,
      driverUid,
      options: const GetOptions(source: Source.server),
    ).timeout(readTimeout);
    final docIndex = _indexOfScheduleInFirestoreList(
      schedules: merged,
      driverUid: driverUid,
      itemDate: itemDate,
      itemJam: itemJam,
      originTrimmed: originTrimmed,
      destTrimmed: destTrimmed,
      scheduleId: scheduleId,
      legacyScheduleId: legacyScheduleId,
    );
    if (docIndex == null) {
      DriverHybridDiagnostics.recordScheduleOp(
        'delete',
        outcome: 'already_gone',
        ms: sw.elapsedMilliseconds,
      );
      return true;
    }
    final next = List<Map<String, dynamic>>.from(merged);
    next.removeAt(docIndex);
    await DriverScheduleItemsStore.persistReplaceAll(
      firestore,
      driverUid,
      _shrunkSchedulesForFirestoreDocument(next),
    ).timeout(readTimeout);
    DriverHybridDiagnostics.recordScheduleOp(
      'delete',
      outcome: 'persist_ok',
      ms: sw.elapsedMilliseconds,
    );
    return true;
  } catch (e, st) {
    DriverHybridDiagnostics.recordScheduleOp(
      'delete',
      outcome: 'persist_fail',
      ms: sw.elapsedMilliseconds,
      detail: e.toString(),
    );
    DriverHybridDiagnostics.recordError('jadwal.delete.persist', e, st);
    rethrow;
  }
}

class DriverJadwalRuteScreen extends StatefulWidget {
  /// Dipanggil saat user tap icon rute di card: beralih ke Beranda dan muat rute dari jadwal.
  /// [scheduleId] untuk sinkron pesanan terjadwal. [routePolyline] rute tersimpan (jika ada).
  /// [routeCategory] kategori rute: dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  final void Function(String origin, String dest, String? scheduleId, List<LatLng>? routePolyline, String? routeCategory)?
  onOpenRuteFromJadwal;
  final bool disableRouteIconForToday;
  /// Jika false, blokir tambah jadwal dan tampilkan dialog lengkapi verifikasi.
  final bool isDriverVerified;
  /// Dipanggil saat user coba tambah jadwal tapi belum terverifikasi.
  final VoidCallback? onVerificationRequired;

  const DriverJadwalRuteScreen({
    super.key,
    this.onOpenRuteFromJadwal,
    this.disableRouteIconForToday = false,
    this.isDriverVerified = true,
    this.onVerificationRequired,
  });

  @override
  State<DriverJadwalRuteScreen> createState() => _DriverJadwalRuteScreenState();
}

class _DriverJadwalRuteScreenState extends State<DriverJadwalRuteScreen>
    with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final List<_JadwalItem> _items = [];
  bool _loading = true;
  /// Tampilkan spinner hanya jika loading > 200ms (terasa lebih responsif)
  bool _showLoadingSpinner = false;
  Timer? _loadingDelayTimer;
  /// Setelah muat pertama: bar atas saat sinkron dari server (tambah/edit/hapus/refresh).
  bool _syncingWithServer = false;
  /// Beberapa `_loadJadwal` bisa berjalan berurutan/bersamaan; jangan matikan bar saat masih ada yang aktif.
  int _serverSyncBarrierCount = 0;
  /// Cegah `finally` load lawas menutup indikator sinkron saat ada load baru.
  int _loadJadwalGen = 0;
  /// Penyegaran halus dari [HybridForegroundRecovery] (tidak bentrok dengan [_loadJadwalGen]).
  int _silentJadwalGen = 0;
  /// Hapus jadwal dari kartu: overlay agar jelas ada proses ke server.
  bool _firestoreCardBusy = false;

  /// Tulis `driver_schedules` setelah UI optimistik — satu per satu (hindari tabrakan saat jaringan buruk).
  Future<void> _jadwalPersistWriteChain = Future<void>.value();
  bool _jadwalPersistWriteActive = false;

  /// Gabung beberapa permintaan baca `driver_schedules` setelah tulis — kurangi antrean klien Firestore.
  Timer? _debouncedJadwalSyncTimer;
  _JadwalItem? _debouncedJadwalSyncMergeHint;

  /// Terakhir `cleanupPastSchedules` sukses (muat penuh atau background). Kurangi GET+query order berulang setelah simpan.
  static const Duration _minIntervalBetweenScheduleCleanups = Duration(minutes: 2);
  DateTime? _lastJadwalCleanupAt;

  void _markJadwalCleanupDone() {
    _lastJadwalCleanupAt = DateTime.now();
  }

  bool _shouldSkipDeferredCleanup() {
    final t = _lastJadwalCleanupAt;
    if (t == null) return false;
    return DateTime.now().difference(t) < _minIntervalBetweenScheduleCleanups;
  }

  /// PageView jadwal per tanggal: geser kiri = tanggal berikutnya, geser kanan = kembali.
  final PageController _jadwalPageController = PageController();

  /// Halaman PageView yang sedang aktif (untuk chip, dots).
  int _currentPageIndex = 0;

  /// Kategori rute yang dipilih per tanggal (halaman ini); dipakai saat Tambah jadwal / FAB.
  final Map<DateTime, String> _routeCategoryByDate = {};
  /// Saat belum ada jadwal: kategori untuk jadwal baru berikutnya (FAB).
  String _categoryForEmptyListNew = RouteCategoryService.categoryAntarProvinsi;

  /// Preferensi chip per uid sudah dimuat dari [SharedPreferences].
  String? _prefsLoadedForUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HybridForegroundRecovery.tick.addListener(_onHybridForegroundRecoveryTick);
    _loadJadwal();
    _jadwalPageController.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HybridForegroundRecovery.tick.removeListener(_onHybridForegroundRecoveryTick);
    _debouncedJadwalSyncTimer?.cancel();
    _loadingDelayTimer?.cancel();
    _jadwalPageController.removeListener(_onPageChanged);
    _jadwalPageController.dispose();
    _serverSyncBarrierCount = 0;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Setelah lama di background, indikator simpan/sinkron bisa tetap ON walau request sudah selesai/terputus
    // (antrean Firestore). Tanpa ini, seluruh tab terasa lambat sampai app ditutup — lihat [HybridForegroundRecovery].
    if (HybridForegroundRecovery.lastBackgroundDuration >= const Duration(seconds: 3)) {
      _releaseStuckScheduleUi();
    }
    unawaited(_silentResyncJadwalFromServer());
  }

  /// Matikan spinner/overlay jadwal yang “nyangkut” tanpa menutup app.
  void _releaseStuckScheduleUi() {
    if (!mounted) return;
    _loadingDelayTimer?.cancel();
    _loadingDelayTimer = null;
    final stuck = _loading ||
        _showLoadingSpinner ||
        _syncingWithServer ||
        _firestoreCardBusy ||
        _serverSyncBarrierCount != 0;
    _serverSyncBarrierCount = 0;
    if (!stuck) return;
    setState(() {
      _loading = false;
      _showLoadingSpinner = false;
      _syncingWithServer = false;
      _firestoreCardBusy = false;
      _jadwalPersistWriteActive = false;
    });
  }

  void _onHybridForegroundRecoveryTick() {
    // Jangan [_releaseStuckScheduleUi] di sini: tick juga dipicu saat ganti tab; [lastBackgroundDuration]
    // bisa masih nilai lama dan memutus progres yang sah.
    unawaited(_silentResyncJadwalFromServer());
  }

  /// Setelah kembali dari background (hybrid): samakan daftar dengan server tanpa spinner/snackbar.
  Future<void> _silentResyncJadwalFromServer() async {
    final user = _auth.currentUser;
    if (user == null || !mounted) return;
    final gen = ++_silentJadwalGen;
    try {
      final maps = await DriverScheduleService.readSchedulesRawFromServer(
        user.uid,
      );
      if (!mounted || gen != _silentJadwalGen) return;
      final next = _jadwalItemsFromFirestoreMaps(maps);
      final unchanged = _items.length == next.length &&
          _jadwalListsContentEqual(_items, next);
      if (!unchanged) {
        if (mounted) {
          setState(() {
            _items
              ..clear()
              ..addAll(next);
            _seedRouteCategoryPreferencesFromItems();
          });
        }
      }
    } catch (_) {}
  }

  bool _jadwalListsContentEqual(List<_JadwalItem> a, List<_JadwalItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.tujuanAwal != y.tujuanAwal || x.tujuanAkhir != y.tujuanAkhir) {
        return false;
      }
      if (x.jam.hour != y.jam.hour || x.jam.minute != y.jam.minute) return false;
      if (_dateOnly(x.tanggal) != _dateOnly(y.tanggal)) return false;
    }
    return true;
  }

  void _beginServerSyncIndicator() {
    if (!mounted) return;
    _serverSyncBarrierCount++;
    if (_serverSyncBarrierCount == 1) {
      setState(() => _syncingWithServer = true);
    }
  }

  void _endServerSyncIndicator() {
    if (_serverSyncBarrierCount <= 0) return;
    _serverSyncBarrierCount--;
    if (!mounted) return;
    if (_serverSyncBarrierCount == 0) {
      setState(() => _syncingWithServer = false);
    }
  }

  /// Hindari rentetan read Firestore (reminder + cleanup + stream chat/orders) langsung setelah simpan jadwal.
  static const Duration _deferRemindersDelay = Duration(seconds: 4);
  /// Jeda agar `cleanup` tidak tabrak `driver_schedules` saat driver langsung hapus jadwal baru.
  static const Duration _deferCleanupDelay = Duration(milliseconds: 4200);

  void _deferScheduleReminders(String uid) {
    unawaited(Future<void>.delayed(_deferRemindersDelay, () async {
      if (!mounted) return;
      if (_auth.currentUser?.uid != uid) return;
      await ScheduleReminderService.scheduleRemindersForDriver(uid);
    }));
  }

  Future<void> _deferCleanupPastSchedules(String uid) async {
    await Future<void>.delayed(_deferCleanupDelay);
    if (!mounted) return;
    if (_auth.currentUser?.uid != uid) return;
    try {
      await DriverScheduleService.cleanupPastSchedules(uid);
      if (mounted) _markJadwalCleanupDone();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DriverJadwal background cleanup: $e\n$st');
      }
    }
  }

  void _onPageChanged() {
    if (!_jadwalPageController.hasClients) return;
    final page = _jadwalPageController.page?.round() ?? 0;
    final grouped = _groupedByDate();
    if (page >= 0 && page < grouped.length && mounted && page != _currentPageIndex) {
      setState(() => _currentPageIndex = page);
    }
  }

  /// Alur muat (untuk pelacakan bug):
  /// 1. [initState] / RefreshIndicator / tombol bersihkan / snackbar Coba lagi → [_loadJadwal].
  /// 2. Simpan form → optimistik update → [_syncJadwalListAfterMutation]: baca cepat [readSchedulesRawFromServer] + cleanup di background.
  /// 3. Muat penuh: paralel [_ensurePrefsLoaded] (timeout 25s) + [cleanupPastSchedules]
  ///    (get server 35s, query order aktif 25s, mungkin update 25s).
  /// 4. Jika [gen] tidak lagi [_loadJadwalGen] setelah await → load ini dibatalkan (ada load lebih baru).
  /// 5. Snackbar error hanya dari catch: timeout per langkah di atas atau error Firestore.
  /// Log debug: cari prefix `[JadwalLoad]` dan `[JadwalCleanup]` (hanya mode debug).
  Future<void> _loadJadwal({
    /// Set false setelah tambah/edit/hapus: daftar sudah di-update optimistik; hindari bar biru + race gen.
    bool showSyncBarIfApplicable = true,
    /// Satu percobaan ulang otomatis (~2,8 s) setelah kegagalan pertama.
    bool isAutoRetry = false,
  }) async {
    final gen = ++_loadJadwalGen;
    final sw = Stopwatch()..start();
    void trace(String m) {
      if (kDebugMode) {
        debugPrint('[JadwalLoad] gen=$gen +${sw.elapsedMilliseconds}ms $m');
      }
    }

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _prefsLoadedForUid = null;
        _routeCategoryByDate.clear();
        _categoryForEmptyListNew = RouteCategoryService.categoryAntarProvinsi;
      });
      return;
    }
    final showSyncIndicator = showSyncBarIfApplicable && !_loading;
    if (showSyncIndicator) {
      _beginServerSyncIndicator();
    }
    _loadingDelayTimer?.cancel();
    _loadingDelayTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _loading) {
        setState(() => _showLoadingSpinner = true);
      }
    });
    // Tanpa timeout membungkus seluruh rangkaian: `.timeout` di Dart tidak men-cancel async di dalam,
    // sehingga sering muncul snackbar "terlalu lama" padahal data beberapa detik lagi sukses.
    // Batas waktu per langkah sudah ada di prefs (25s), get jadwal (35s), query order (25s), update (25s).
    try {
      trace('begin parallel prefs+cleanup syncBar=$showSyncIndicator');
      final parallel = await Future.wait<dynamic>([
        _ensurePrefsLoaded(user.uid),
        DriverScheduleService.cleanupPastSchedules(user.uid),
      ]);
      if (!mounted || gen != _loadJadwalGen) {
        trace('stale after parallel mounted=$mounted currentGen=$_loadJadwalGen');
        return;
      }
      final kept = parallel[1] as List<Map<String, dynamic>>;
      trace('parallel ok firestoreItems=${kept.length} rebuild list');
      _items
        ..clear()
        ..addAll(_jadwalItemsFromFirestoreMaps(kept));
      if (mounted && gen == _loadJadwalGen) {
        _loadingDelayTimer?.cancel();
        // Jangan clearSnackBars: biarkan snackbar sukses simpan/error tetap terlihat.
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
          _currentPageIndex = 0;
          _seedRouteCategoryPreferencesFromItems();
        });
        _markJadwalCleanupDone();
        trace('SUCCESS uiItems=${_items.length}');
        DriverHybridDiagnostics.recordScheduleOp(
          'load',
          outcome: isAutoRetry ? 'ok_after_retry' : 'ok',
          ms: sw.elapsedMilliseconds,
        );
        _deferScheduleReminders(user.uid);
      } else {
        trace('skip setState success mounted=$mounted gen=$gen current=$_loadJadwalGen');
      }
    } catch (e, st) {
      trace('FAIL ${e.runtimeType} $e');
      if (kDebugMode) {
        debugPrint('DriverJadwal _loadJadwal: $e\n$st');
      }
      if (mounted && gen == _loadJadwalGen) {
        _loadingDelayTimer?.cancel();
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
        });
        if (!isAutoRetry) {
          DriverHybridDiagnostics.recordScheduleOp(
            'load',
            outcome: 'fail_retry_scheduled',
            ms: sw.elapsedMilliseconds,
            detail: e.toString(),
          );
          DriverHybridDiagnostics.recordError('jadwal.load', e, st);
          unawaited(Future<void>.delayed(const Duration(milliseconds: 2800), () {
            if (!mounted) return;
            _loadJadwal(
              showSyncBarIfApplicable: showSyncBarIfApplicable,
              isAutoRetry: true,
            );
          }));
        } else {
          DriverHybridDiagnostics.recordScheduleOp(
            'load',
            outcome: 'fail',
            ms: sw.elapsedMilliseconds,
            detail: e.toString(),
          );
          final msg = e is TimeoutException
              ? 'Permintaan ke server habis waktu. Tunggu sebentar lalu ketuk Coba lagi.'
              : 'Tidak dapat memuat jadwal. Jika jaringan oke, coba lagi atau buka halaman lain lalu kembali.';
          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'Coba lagi',
                textColor: Colors.white,
                onPressed: () => _loadJadwal(),
              ),
            ),
          );
        }
      }
    } finally {
      if (showSyncIndicator) {
        _endServerSyncIndicator();
      }
    }
  }

  List<_JadwalItem> _jadwalItemsFromFirestoreMaps(List<Map<String, dynamic>> maps) {
    final out = <_JadwalItem>[];
    for (final map in maps) {
      final timeStamp = map['departureTime'] as Timestamp?;
      final dateStamp = map['date'] as Timestamp?;
      TimeOfDay jam = TimeOfDay.now();
      if (timeStamp != null) {
        final d = timeStamp.toDate();
        jam = TimeOfDay(hour: d.hour, minute: d.minute);
      }
      final date = dateStamp?.toDate() ?? DateTime.now();
      final origin = (map['origin'] as String?) ?? '';
      final dest = (map['destination'] as String?) ?? '';
      final routePolyline = _parseRoutePolyline(map['routePolyline']);
      final routeCategory = (map['routeCategory'] as String?) ??
          RouteCategoryService.categoryAntarProvinsi;
      out.add(
        _JadwalItem(
          tujuanAwal: origin,
          tujuanAkhir: dest,
          jam: jam,
          tanggal: date,
          routePolyline: routePolyline,
          routeCategory: routeCategory,
        ),
      );
    }
    return out;
  }

  /// Tunda baca ~2,8s — setelah tulis `driver_schedules` besar, antrean klien butuh waktu sebelum baca aman.
  void _scheduleDebouncedJadwalServerSync({_JadwalItem? mergeIfMissing}) {
    _debouncedJadwalSyncMergeHint = mergeIfMissing;
    _debouncedJadwalSyncTimer?.cancel();
    _debouncedJadwalSyncTimer = Timer(const Duration(milliseconds: 2800), () {
      _debouncedJadwalSyncTimer = null;
      if (!mounted) return;
      final merge = _debouncedJadwalSyncMergeHint;
      _debouncedJadwalSyncMergeHint = null;
      unawaited(_syncJadwalListAfterMutation(newItem: merge));
    });
  }

  /// Sinkron dari server setelah simpan: **satu baca** dokumen jadwal (cepat), tanpa prefs/query order/cleanup —
  /// hindari snackbar timeout padahal simpan sudah sukses. Cleanup jadwal lewat jalan di background.
  Future<void> _syncJadwalListAfterMutation({_JadwalItem? newItem}) async {
    if (kDebugMode) {
      debugPrint('[JadwalLoad] syncAfterMutation fast read (no full cleanup/prefs)');
    }
    final user = _auth.currentUser;
    if (user == null) return;
    final gen = ++_loadJadwalGen;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || gen != _loadJadwalGen) return;
    try {
      List<Map<String, dynamic>> maps;
      final fromLocal =
          await DriverScheduleService.tryReadSchedulesRawFromCache(user.uid);
      if (fromLocal != null) {
        maps = fromLocal;
      } else {
        try {
          maps = await DriverScheduleService.readSchedulesRawFromServer(user.uid);
        } on TimeoutException {
          await Future<void>.delayed(const Duration(milliseconds: 480));
          if (!mounted || gen != _loadJadwalGen) return;
          maps = await DriverScheduleService.readSchedulesRawFromServer(user.uid);
        }
      }
      if (!mounted || gen != _loadJadwalGen) return;
      _items
        ..clear()
        ..addAll(_jadwalItemsFromFirestoreMaps(maps));
      if (mounted && gen == _loadJadwalGen) {
        _loadingDelayTimer?.cancel();
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
          _seedRouteCategoryPreferencesFromItems();
        });
        _deferScheduleReminders(user.uid);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DriverJadwal _syncJadwalListAfterMutation: $e\n$st');
      }
      if (mounted && gen == _loadJadwalGen) {
        _loadingDelayTimer?.cancel();
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
        });
      }
    }
    if (!_shouldSkipDeferredCleanup()) {
      unawaited(_deferCleanupPastSchedules(user.uid));
    } else {
      final sinceSec =
          DateTime.now().difference(_lastJadwalCleanupAt!).inSeconds;
      DriverHybridDiagnostics.breadcrumb(
        'schedule.cleanup.skip_deferred secs_since_last=$sinceSec window_min=${_minIntervalBetweenScheduleCleanups.inMinutes}',
      );
    }
    if (!mounted) return;
    if (newItem != null) {
      final exists = _items.any((i) =>
          i.tujuanAwal == newItem.tujuanAwal &&
          i.tujuanAkhir == newItem.tujuanAkhir &&
          _dateOnly(i.tanggal) == _dateOnly(newItem.tanggal) &&
          i.jam.hour == newItem.jam.hour &&
          i.jam.minute == newItem.jam.minute);
      if (!exists) {
        _items.add(newItem);
        _items.sort((a, b) {
          final da = _dateOnly(a.tanggal);
          final db = _dateOnly(b.tanggal);
          if (da != db) return da.compareTo(db);
          return (a.jam.hour * 60 + a.jam.minute)
              .compareTo(b.jam.hour * 60 + b.jam.minute);
        });
      }
    }
    if (mounted) setState(() {});
  }

  /// Antre tulisan ke Firestore agar tidak paralel (beban jaringan / race pada dokumen yang sama).
  Future<void> _persistSchedulesAfterOptimisticUi({
    required String driverUid,
    required List<Map<String, dynamic>> schedulesToWrite,
    required _JadwalItem newItem,
  }) {
    final run = _jadwalPersistWriteChain.then(
      (_) => _runPersistSchedulesAfterOptimisticUi(
        driverUid: driverUid,
        schedulesToWrite: schedulesToWrite,
        newItem: newItem,
      ),
    );
    _jadwalPersistWriteChain = run.catchError((Object e, StackTrace _) {
      if (kDebugMode) {
        debugPrint('DriverJadwal persist chain error (lanjut antrean): $e');
      }
    });
    return run;
  }

  Future<void> _runPersistSchedulesAfterOptimisticUi({
    required String driverUid,
    required List<Map<String, dynamic>> schedulesToWrite,
    required _JadwalItem newItem,
  }) async {
    if (!mounted) return;
    setState(() => _jadwalPersistWriteActive = true);
    final persistCount = schedulesToWrite.length;
    AppAnalyticsService.logDriverJadwalPersistStart(scheduleCount: persistCount);
    const writeTimeout = Duration(seconds: 32);
    try {
      await DriverScheduleItemsStore.persistReplaceAll(
        _firestore,
        driverUid,
        schedulesToWrite,
      ).timeout(
        writeTimeout,
        onTimeout: () => throw TimeoutException('Simpan timeout. Cek jaringan dan coba lagi.'),
      );
      AppAnalyticsService.logDriverJadwalPersistSuccess(scheduleCount: persistCount);
      if (!mounted) return;
      _scheduleDebouncedJadwalServerSync(mergeIfMissing: newItem);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DriverJadwal optimistic persist failed: $e\n$st');
      }
      AppAnalyticsService.logDriverJadwalPersistFail(
        failureKind: e is TimeoutException ? 'timeout' : 'error',
        scheduleCount: persistCount,
      );
      if (!mounted) return;
      try {
        await _syncJadwalListAfterMutation();
      } catch (_) {}
      if (!mounted) return;
      final msg = e is TimeoutException
          ? 'Jaringan timeout — jadwal tidak tersimpan. Cek koneksi lalu tambah/ubah lagi.'
          : 'Gagal simpan ke server: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 12),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _jadwalPersistWriteActive = false);
      }
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Parse routePolyline dari Firestore: daftar map `lat`/`lng` menjadi `List<LatLng>`.
  static List<LatLng>? _parseRoutePolyline(dynamic raw) {
    if (raw == null) return null;
    final list = raw as List<dynamic>?;
    if (list == null || list.isEmpty) return null;
    final result = <LatLng>[];
    for (final e in list) {
      final m = e as Map<dynamic, dynamic>?;
      if (m == null) continue;
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) result.add(LatLng(lat, lng));
    }
    return result.isEmpty ? null : result;
  }

  static DateTime _dateOnly(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  /// Format singkat tanggal untuk chip: "17 Mar" atau "Hari ini".
  String _formatDateChip(DateTime d) {
    final today = _today;
    final dOnly = _dateOnly(d);
    if (dOnly == today) return 'Hari ini';
    final tomorrow = _dateOnly(today.add(const Duration(days: 1)));
    if (dOnly == tomorrow) return 'Besok';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${d.day} ${months[d.month - 1]}';
  }

  /// Ruang di ujung kanan scroll chip tanggal: FAB + margin Scaffold + inset sistem + napas (teks diperbesar).
  double _horizontalEndPaddingForDateChips(BuildContext context) {
    final mq = MediaQuery.of(context);
    const fab = 56.0;
    const fabMargin = 16.0;
    const breathing = 16.0;
    final systemEnd = mq.viewPadding.right;
    final scale = mq.textScaler.scale(1.0);
    final scaleBump = scale > 1.0 ? 14.0 * (scale - 1.0) : 0.0;
    return (fab + fabMargin + breathing + systemEnd + scaleBump).clamp(96.0, 168.0);
  }

  /// Jumlah jadwal hari ini.
  int _countJadwalHariIni() =>
      _items.where((i) => _dateOnly(i.tanggal) == _today).length;

  /// Jadwal hari ini yang keberangkatannya dalam 2 jam ke depan (untuk pengingat).
  _JadwalItem? _getUpcomingScheduleWithin2Hours() {
    final now = DateTime.now();
    final today = _today;
    for (final item in _items) {
      if (_dateOnly(item.tanggal) != today) continue;
      if (_isScheduleTimePassed(item)) continue;
      final dep = DateTime(
        item.tanggal.year,
        item.tanggal.month,
        item.tanggal.day,
        item.jam.hour,
        item.jam.minute,
      );
      final diff = dep.difference(now);
      if (diff.inMinutes >= 0 && diff.inMinutes <= 120) return item;
    }
    return null;
  }

  /// Jumlah jadwal minggu ini (Sen–Minggu).
  int _countJadwalMingguIni() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final monday = _dateOnly(now.subtract(Duration(days: weekday - 1)));
    final sunday = monday.add(const Duration(days: 6));
    return _items
        .where((i) {
          final d = _dateOnly(i.tanggal);
          return !d.isBefore(monday) && !d.isAfter(sunday);
        })
        .length;
  }

  /// Hari ini menurut kalender WIB (satu aturan untuk batas jadwal).
  static DateTime get _today => DriverScheduleService.todayDateOnlyWib;

  /// Jadwal sudah lewat: tanggal = hari ini tapi jam keberangkatan sudah lewat.
  /// (Jadwal dengan tanggal kemarin sudah terhapus dari Firebase.)
  bool _isScheduleTimePassed(_JadwalItem item) {
    final today = _today;
    final scheduleDate = _dateOnly(item.tanggal);
    if (scheduleDate != today) return false;
    final departure = DateTime(
      item.tanggal.year,
      item.tanggal.month,
      item.tanggal.day,
      item.jam.hour,
      item.jam.minute,
    );
    return DateTime.now().isAfter(departure);
  }

  /// Tombol **Rute** hanya untuk jadwal **tanggal hari ini** (WIB) dan jam keberangkatan belum lewat.
  /// Jadwal besok/lusa (beda tanggal di chip) tidak aktif — beda hari; setelah jam lewat pada hari yang sama juga nonaktif.
  bool _isRuteAvailableForJadwal(_JadwalItem item) {
    final scheduleDate = _dateOnly(item.tanggal);
    if (scheduleDate != _today) return false;
    return !_isScheduleTimePassed(item);
  }

  /// ID jadwal (sama dengan format di Pesan nanti penumpang) untuk sinkron pesanan terjadwal.
  /// Mengembalikan (scheduleId, legacyScheduleId) untuk backward compat.
  (String, String) _scheduleIdPairForItem(_JadwalItem item) {
    final uid = _auth.currentUser?.uid ?? '';
    final d = item.tanggal;
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final departure = DateTime(
      d.year,
      d.month,
      d.day,
      item.jam.hour,
      item.jam.minute,
    );
    return ScheduleIdUtil.build(
      uid,
      dateKey,
      departure.millisecondsSinceEpoch,
      item.tujuanAwal,
      item.tujuanAkhir,
    );
  }

  String _scheduleIdForItem(_JadwalItem item) =>
      _scheduleIdPairForItem(item).$1;

  /// Jumlah jadwal yang sudah tersimpan untuk tanggal [d] (maks 4 per tanggal).
  static const int _maxSchedulesPerDate = 4;

  int _scheduleCountForDate(DateTime d) {
    final key = _dateOnly(d);
    return _items.where((i) => _dateOnly(i.tanggal) == key).length;
  }

  String _categoryForDate(DateTime d) {
    final key = _dateOnly(d);
    return _routeCategoryByDate[key] ?? RouteCategoryService.categoryAntarProvinsi;
  }

  Future<void> _persistRouteCategoryPrefs() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    await DriverJadwalRouteCategoryPrefs.save(
      uid,
      _routeCategoryByDate,
      _categoryForEmptyListNew,
      writtenAtMs: ts,
    );
    try {
      await DriverJadwalRouteCategoryPrefs.saveToFirestore(
        uid,
        _routeCategoryByDate,
        _categoryForEmptyListNew,
        writtenAtMs: ts,
      );
    } catch (_) {}
  }

  Future<void> _ensurePrefsLoaded(String uid) async {
    if (_prefsLoadedForUid == uid) return;
    final data = await DriverJadwalRouteCategoryPrefs.mergeLocalAndRemote(uid)
        .timeout(const Duration(seconds: 25));
    if (!mounted) return;
    setState(() {
      _routeCategoryByDate
        ..clear()
        ..addAll(data.byDate);
      _categoryForEmptyListNew = data.empty;
      _prefsLoadedForUid = uid;
    });
  }

  void _setCategoryForDate(DateTime d, String category) {
    setState(() {
      _routeCategoryByDate[_dateOnly(d)] = category;
    });
    unawaited(_persistRouteCategoryPrefs());
  }

  void _setCategoryForEmptyList(String category) {
    setState(() => _categoryForEmptyListNew = category);
    unawaited(_persistRouteCategoryPrefs());
  }

  /// Isi preferensi dari jadwal yang sudah tersimpan (hanya jika belum ada pilihan chip).
  void _seedRouteCategoryPreferencesFromItems() {
    final grouped = _groupedByDate();
    for (final e in grouped) {
      final date = e.key;
      if (_routeCategoryByDate.containsKey(date)) continue;
      final firstIdx = e.value.first;
      _routeCategoryByDate[date] = _items[firstIdx].routeCategory;
    }
  }

  static const List<String> _routeCategoryOrder = [
    RouteCategoryService.categoryDalamKota,
    RouteCategoryService.categoryAntarKabupaten,
    RouteCategoryService.categoryAntarProvinsi,
    RouteCategoryService.categoryNasional,
  ];

  Widget _buildRouteCategoryChipsRow(DateTime dateKey) {
    final selected = _categoryForDate(dateKey);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _routeCategoryOrder.map((c) {
        final isSel = selected == c;
        return FilterChip(
          showCheckmark: false,
          label: Text(RouteCategoryService.getLabel(c)),
          selected: isSel,
          onSelected: (_) => _setCategoryForDate(dateKey, c),
        );
      }).toList(),
    );
  }

  Widget _buildRouteCategoryChipsEmptyList() {
    final selected = _categoryForEmptyListNew;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _routeCategoryOrder.map((c) {
        final isSel = selected == c;
        return FilterChip(
          showCheckmark: false,
          label: Text(RouteCategoryService.getLabel(c)),
          selected: isSel,
          onSelected: (_) => _setCategoryForEmptyList(c),
        );
      }).toList(),
    );
  }

  /// Daftar tanggal yang punya jadwal, masing-masing berisi list index jadwal (urutan isi = urutan tampil).
  List<MapEntry<DateTime, List<int>>> _groupedByDate() {
    final map = <DateTime, List<int>>{};
    for (var i = 0; i < _items.length; i++) {
      final key = _dateOnly(_items[i].tanggal);
      map.putIfAbsent(key, () => []).add(i);
    }
    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted;
  }

  static const List<String> _dayNames = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  static String _formatPlacemark(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  /// Ambil teks lokasi driver saat ini (untuk isi tujuan awal).
  Future<String?> _getCurrentLocationText() async {
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck(
        forTracking: true,
      );
      if (result.isFakeGpsDetected || result.position == null) return null;
      final pos = result.position!;
      final list = await GeocodingService.placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (list.isEmpty) return null;
      return _formatPlacemark(list.first);
    } catch (_) {
      return null;
    }
  }

  String _formatDateWithDay(DateTime d) {
    final dayName = _dayNames[d.weekday % 7];
    return '$dayName, ${d.day}/${d.month}/${d.year}';
  }

  /// FAB Tambah jadwal: tampilkan date picker, lalu form.
  Future<void> _onFabTambahJadwalTapped() async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final wibFirst = DriverScheduleService.todayDateOnlyWib;
    final wibLast = DriverScheduleService.lastScheduleDateInclusiveWib;
    var initialDate = wibFirst;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: wibFirst,
      lastDate: wibLast,
      helpText: 'Pilih tanggal jadwal (maks. 7 hari ke depan, WIB)',
    );
    if (picked == null || !mounted) return;
    final date = _dateOnly(picked);
    if (!DriverScheduleService.isScheduleDateInBookingWindow(date)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jadwal hanya untuk 7 hari ke depan dari hari ini (zona waktu WIB).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final count = _scheduleCountForDate(date);
    if (count >= _maxSchedulesPerDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maksimal 4 jadwal per tanggal. Gunakan icon pensil untuk edit.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final preferred = _items.isEmpty
        ? _categoryForEmptyListNew
        : _categoryForDate(date);
    _showAturJadwalForm(date, preferredRouteCategoryForNew: preferred);
  }

  /// Duplikat jadwal ke tanggal lain (rute rutin).
  Future<void> _onDuplikatJadwalTapped(_JadwalItem item) async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final wibFirst = DriverScheduleService.todayDateOnlyWib;
    final wibLast = DriverScheduleService.lastScheduleDateInclusiveWib;
    var initialDup = _dateOnly(item.tanggal).add(const Duration(days: 7));
    if (initialDup.isBefore(wibFirst)) initialDup = wibFirst;
    if (initialDup.isAfter(wibLast)) initialDup = wibLast;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDup,
      firstDate: wibFirst,
      lastDate: wibLast,
      helpText: 'Pilih tanggal untuk duplikat jadwal (maks. 7 hari, WIB)',
    );
    if (picked == null || !mounted) return;
    final date = _dateOnly(picked);
    if (!DriverScheduleService.isScheduleDateInBookingWindow(date)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tanggal duplikat harus dalam 7 hari ke depan (WIB).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final count = _scheduleCountForDate(date);
    if (count >= _maxSchedulesPerDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maksimal 4 jadwal per tanggal.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _showAturJadwalForm(date, duplicateFromItem: item);
  }

  void _showAturJadwalForm(
    DateTime selectedDate, {
    int? editIndex,
    _JadwalItem? editItem,
    _JadwalItem? duplicateFromItem,
    /// Hanya untuk jadwal baru (bukan edit/duplikat): isi dropdown kategori di form.
    String? preferredRouteCategoryForNew,
  }) {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final date = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final otherTimes = <TimeOfDay>[];
    for (final entry in _groupedByDate()) {
      if (_dateOnly(entry.key) != _dateOnly(date)) continue;
      for (final idx in entry.value) {
        if (editIndex != null && idx == editIndex) continue;
        otherTimes.add(_items[idx].jam);
      }
      break;
    }
    final formSaving = ValueNotifier<bool>(false);
    String? editScheduleId;
    String? editLegacyScheduleId;
    if (editItem != null) {
      final pair = _scheduleIdPairForItem(editItem);
      editScheduleId = pair.$1;
      editLegacyScheduleId = pair.$2;
    }
    showTrakaModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AturJadwalFormContent(
        date: date,
        formatDateWithDay: _formatDateWithDay,
        formatTime: _formatTime,
        getCurrentLocationText: _getCurrentLocationText,
        formatPlacemark: _formatPlacemark,
        auth: _auth,
        firestore: _firestore,
        formSaving: formSaving,
        editScheduleId: editScheduleId,
        editLegacyScheduleId: editLegacyScheduleId,
        onSaved:
            (_JadwalItem? newItem, {int? deletedIndex, int? editIndex, bool skipServerSync = false}) async {
          // Optimistic update: hapus, edit, atau tambah item agar UI langsung responsif
          if (deletedIndex != null && deletedIndex >= 0 && deletedIndex < _items.length) {
            _items.removeAt(deletedIndex);
            if (mounted) setState(() {});
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Jadwal dihapus'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
          if (newItem != null && editIndex != null && editIndex >= 0 && editIndex < _items.length) {
            _items[editIndex] = newItem;
            if (mounted) setState(() {});
          } else if (newItem != null) {
            _items.add(newItem);
            _items.sort((a, b) {
              final da = _dateOnly(a.tanggal);
              final db = _dateOnly(b.tanggal);
              if (da != db) return da.compareTo(db);
              return (a.jam.hour * 60 + a.jam.minute)
                  .compareTo(b.jam.hour * 60 + b.jam.minute);
            });
            if (mounted) setState(() {});
          }
          if (!skipServerSync) {
            _scheduleDebouncedJadwalServerSync(mergeIfMissing: newItem);
          }
        },
        editScheduleIndex: editIndex,
        initialOrigin: editItem?.tujuanAwal ?? duplicateFromItem?.tujuanAwal,
        initialDest: editItem?.tujuanAkhir ?? duplicateFromItem?.tujuanAkhir,
        initialJam: editItem?.jam ?? duplicateFromItem?.jam,
        initialRoutePolyline: editItem?.routePolyline ?? duplicateFromItem?.routePolyline,
        initialRouteCategory: editItem?.routeCategory ??
            duplicateFromItem?.routeCategory ??
            preferredRouteCategoryForNew,
        isDriverVerified: widget.isDriverVerified,
        onVerificationRequired: widget.onVerificationRequired,
        otherScheduleTimesOnDate: otherTimes,
        persistSchedulesAfterOptimisticUi: ({
          required List<Map<String, dynamic>> schedulesToWrite,
          required _JadwalItem newItem,
        }) {
          final u = _auth.currentUser;
          if (u == null) return Future.value();
          return _persistSchedulesAfterOptimisticUi(
            driverUid: u.uid,
            schedulesToWrite: schedulesToWrite,
            newItem: newItem,
          );
        },
      ),
    ).then((_) {
      formSaving.dispose();
    });
  }

  /// Kategori rute per tanggal: dari AppBar agar layar utama tidak penuh.
  void _showKategoriRuteSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _groupedByDate();
    showTrakaModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 4,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.alt_route, color: cs.primary, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kategori rute',
                              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              grouped.isEmpty
                                  ? 'Pilihan untuk jadwal baru (tombol +). Bisa diubah lagi di form.'
                                  : 'Untuk tanggal terpilih. Dipakai saat Tambah jadwal; bisa diubah di form.',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (grouped.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateWithDay(
                            grouped[_currentPageIndex.clamp(0, grouped.length - 1)].key,
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRouteCategoryChipsRow(
                      grouped[_currentPageIndex.clamp(0, grouped.length - 1)].key,
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.add_circle_outline, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Jadwal baru berikutnya',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRouteCategoryChipsEmptyList(),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: Theme.of(context).colorScheme.onSurface, size: 24),
            const SizedBox(width: 8),
            Text(
              'Jadwal dan rute Travel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        elevation: 0,
        actions: [
          if (!_showLoadingSpinner)
            IconButton(
              icon: const Icon(Icons.alt_route_outlined),
              tooltip: 'Kategori rute',
              onPressed: (_firestoreCardBusy || _jadwalPersistWriteActive)
                  ? null
                  : () => _showKategoriRuteSheet(context),
            ),
        ],
      ),
      floatingActionButton: Padding(
        // Angkat FAB sedikit agar tidak menutupi chip tanggal yang digulir ke kanan.
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton(
          tooltip: _jadwalPersistWriteActive
              ? 'Menunggu penyimpanan jadwal ke server…'
              : 'Tambah jadwal',
          onPressed: (_firestoreCardBusy || _jadwalPersistWriteActive)
              ? null
              : () => _onFabTambahJadwalTapped(),
          child: const Icon(Icons.add),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _showLoadingSpinner
                ? const Center(child: ShimmerLoading())
                : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadJadwal,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  TrakaEmptyState(
                                    icon: Icons.calendar_month_rounded,
                                    title: _loading
                                        ? 'Memuat jadwal...'
                                        : TrakaL10n.of(context).noScheduleYet,
                                    subtitle:
                                        'Tap tombol + untuk menambah jadwal. Maks. 4 jadwal per tanggal; tanggal hanya 7 hari ke depan (WIB).',
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Text(
                                      TrakaL10n.of(context).driverScheduleNetworkSerializeHint,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.9),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.alt_route_outlined,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Kategori rute untuk jadwal baru (juga lewat ikon di AppBar)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildRouteCategoryChipsEmptyList(),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Pilihan ini dipakai saat Tambah jadwal (bisa diubah lagi di form).',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await _loadJadwal();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Jadwal lewat telah dibersihkan'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                    },
                                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                                    label: const Text('Bersihkan jadwal lewat'),
                                    style: AppInteractionStyles.textFromTheme(
                                      context,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Ringkasan + pengingat (ringkas di atas)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.summarize_outlined,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _countJadwalHariIni() > 0
                                                ? '${_countJadwalHariIni()} jadwal hari ini'
                                                : '${_countJadwalMingguIni()} jadwal minggu ini',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final upcoming = _getUpcomingScheduleWithin2Hours();
                                      if (upcoming == null) return const SizedBox.shrink();
                                      final dep = DateTime(
                                        upcoming.tanggal.year,
                                        upcoming.tanggal.month,
                                        upcoming.tanggal.day,
                                        upcoming.jam.hour,
                                        upcoming.jam.minute,
                                      );
                                      final mins = dep.difference(DateTime.now()).inMinutes;
                                      final timeLabel = mins >= 60
                                          ? '${mins ~/ 60} jam ${mins % 60} menit'
                                          : '$mins menit';
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.orange.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.notifications_active, color: Colors.orange.shade700, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Dalam $timeLabel: ${_formatTime(upcoming.jam)} • ${upcoming.tujuanAwal} → ${upcoming.tujuanAkhir}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.orange.shade900,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  // Utama: daftar jadwal (maks. ruang layar)
                                  Expanded(
                                    child: PageView.builder(
                                      controller: _jadwalPageController,
                                      itemCount: _groupedByDate().length,
                                      itemBuilder: (context, pageIndex) {
                                        final grouped = _groupedByDate();
                                        if (pageIndex >= grouped.length) {
                                          return const SizedBox.shrink();
                                        }
                                        final entry = grouped[pageIndex];
                                        final date = entry.key;
                                        final indices = entry.value;
                                        return SingleChildScrollView(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2, bottom: 12),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        _formatDateWithDay(date),
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w600,
                                                          color: Theme.of(context).colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              ...indices.map(
                                                (index) => _buildJadwalCard(
                                                  index,
                                                  _items[index],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // Navigasi tanggal + kategori di bawah daftar jadwal
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 44,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                        4,
                                        0,
                                        _horizontalEndPaddingForDateChips(
                                          context,
                                        ),
                                        0,
                                      ),
                                      itemCount: _groupedByDate().length,
                                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                                      itemBuilder: (context, i) {
                                        final entry = _groupedByDate()[i];
                                        final date = entry.key;
                                        final count = entry.value.length;
                                        final isSelected = i == _currentPageIndex;
                                        return FilterChip(
                                          showCheckmark: false,
                                          label: Text(
                                            '${_formatDateChip(date)}${count > 1 ? ' ($count)' : ''}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                            ),
                                          ),
                                          selected: isSelected,
                                          onSelected: (_) {
                                            if (_jadwalPageController.hasClients) {
                                              _jadwalPageController.animateToPage(
                                                i,
                                                duration: const Duration(milliseconds: 300),
                                                curve: Curves.easeOutCubic,
                                              );
                                              setState(() => _currentPageIndex = i);
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  if (_groupedByDate().length > 1) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(
                                        _groupedByDate().length,
                                        (i) => Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 3),
                                          width: i == _currentPageIndex ? 10 : 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(3),
                                            color: i == _currentPageIndex
                                                ? Theme.of(context).colorScheme.primary
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  Padding(
                                    padding: EdgeInsetsDirectional.fromSTEB(
                                      8,
                                      4,
                                      _horizontalEndPaddingForDateChips(
                                        context,
                                      ),
                                      4,
                                    ),
                                    child: Text(
                                      'Geser kiri/kanan atau pilih chip • kategori: ikon rute di AppBar',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_syncingWithServer || _jadwalPersistWriteActive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            if (_firestoreCardBusy)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 20,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(strokeWidth: 3),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Memproses jadwal…',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pastikan koneksi stabil',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
          ],
        ),
      ),
    );
  }

  String? _statusBadgeForItem(_JadwalItem item) {
    final today = _today;
    final scheduleDate = _dateOnly(item.tanggal);
    if (_isScheduleTimePassed(item)) return 'Lewat';
    if (scheduleDate == today) return 'Hari ini';
    final tomorrow = _dateOnly(today.add(const Duration(days: 1)));
    if (scheduleDate == tomorrow) return 'Besok';
    return null;
  }

  Widget _buildJadwalCard(int index, _JadwalItem item) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusBadge = _statusBadgeForItem(item);
    final timePassed = _isScheduleTimePassed(item);
    final (scheduleId, legacyScheduleId) = _scheduleIdPairForItem(item);
    const String kScheduleMutationBlockedHint =
        'Tidak bisa mengubah atau menghapus: masih ada pesanan pada jadwal ini (menunggu persetujuan, sudah disepakati/kesepakatan, atau sedang berjalan). Selesaikan atau batalkan pesanan dulu.';

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shadowColor: colorScheme.onSurface.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: FutureBuilder<
          ({
            int totalPenumpang,
            int kirimBarangCount,
            int kargoCount,
            bool hasNonTerminalOrders,
            int pendingTravelCount,
            int pendingBarangCount,
          })>(
        future: OrderService.getScheduleSlotBookingSnapshot(
          scheduleId,
          legacyScheduleId: legacyScheduleId,
        ),
        builder: (context, snap) {
          final booking = snap.data;
          final locksSchedule = !snap.hasData ||
              snap.hasError ||
              (booking?.hasNonTerminalOrders ?? true);
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(item.jam),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (statusBadge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: timePassed
                              ? colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.2)
                              : statusBadge == 'Hari ini'
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : statusBadge == 'Besok'
                                      ? Colors.orange.withValues(alpha: 0.15)
                                      : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusBadge,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: timePassed
                                ? colorScheme.onSurfaceVariant
                                : statusBadge == 'Hari ini'
                                    ? Colors.green.shade700
                                    : statusBadge == 'Besok'
                                        ? Colors.orange.shade700
                                        : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (!timePassed)
                      IconButton(
                        icon: Icon(
                          Icons.copy_outlined,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        tooltip: 'Duplikat ke tanggal lain',
                        onPressed: () => _onDuplikatJadwalTapped(item),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!timePassed && !locksSchedule)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            tooltip: 'Hapus jadwal',
                            onPressed: () =>
                                _onHapusJadwalFromCard(item, index),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: locksSchedule
                              ? kScheduleMutationBlockedHint
                              : 'Edit jadwal',
                          onPressed: () => _onEditJadwalTapped(
                              item, index, locksSchedule),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            const SizedBox(height: 4),
            Text(
              _formatDateWithDay(item.tanggal),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            // Rute: Tujuan awal dan akhir diperjelas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.trip_origin_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tujuan awal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.tujuanAwal.isEmpty ? '–' : item.tujuanAwal,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tujuan akhir',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.tujuanAkhir.isEmpty ? '–' : item.tujuanAkhir,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Baris 3: Tombol Rute (utama) + Pemesan + Barang
            Builder(
              builder: (context) {
                final timePassed = _isScheduleTimePassed(item);
                final scheduleDate = _dateOnly(item.tanggal);
                final wrongDay = scheduleDate != _today;
                final disableByHomeRoute =
                    widget.disableRouteIconForToday &&
                    scheduleDate == _today;
                final routeEnabled = _isRuteAvailableForJadwal(item);
                String? ruteDisabledHint;
                if (!routeEnabled) {
                  if (wrongDay) {
                    ruteDisabledHint = scheduleDate.isAfter(_today)
                        ? 'Tombol Rute aktif pada tanggal keberangkatan. Pilih chip tanggal yang sama di atas.'
                        : 'Jadwal ini bukan hari ini; buka rute pada tanggal keberangkatan.';
                  } else if (_isScheduleTimePassed(item)) {
                    ruteDisabledHint =
                        'Jam keberangkatan untuk hari ini sudah lewat.';
                  }
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRuteButton(
                        enabled: routeEnabled,
                        disableByHomeRoute: disableByHomeRoute,
                        item: item,
                        disabledHint: ruteDisabledHint,
                      ),
                      const SizedBox(width: 8),
                      _buildPemesanChip(
                        scheduleId: scheduleId,
                        legacyScheduleId: legacyScheduleId,
                        timePassed: timePassed,
                        totalPenumpang: booking?.totalPenumpang ?? 0,
                        pendingTravelCount: booking?.pendingTravelCount ?? 0,
                      ),
                      const SizedBox(width: 6),
                      _buildBarangChip(
                        scheduleId: scheduleId,
                        legacyScheduleId: legacyScheduleId,
                        timePassed: timePassed,
                        kirimBarangCount: booking?.kirimBarangCount ?? 0,
                        pendingBarangCount: booking?.pendingBarangCount ?? 0,
                      ),
                    ],
                  ),
                );
              },
            ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRuteButton({
    required bool enabled,
    required bool disableByHomeRoute,
    required _JadwalItem item,
    String? disabledHint,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final highlight = enabled && !disableByHomeRoute;
    Widget button = Material(
      color: highlight ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          if (!enabled) {
            final msg = disabledHint;
            if (msg != null &&
                msg.isNotEmpty &&
                context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
          if (disableByHomeRoute) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Rute aktif berasal dari Beranda. Selesaikan rute tersebut terlebih dahulu.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          widget.onOpenRuteFromJadwal?.call(
            item.tujuanAwal,
            item.tujuanAkhir,
            _scheduleIdForItem(item),
            item.routePolyline,
            item.routeCategory,
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_rounded,
                size: 18,
                color: highlight ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Rute',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: highlight ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!enabled &&
        disabledHint != null &&
        disabledHint.isNotEmpty) {
      button = Tooltip(message: disabledHint, child: button);
    }
    return button;
  }

  Widget _buildPemesanChip({
    required String scheduleId,
    required String? legacyScheduleId,
    required bool timePassed,
    required int totalPenumpang,
    required int pendingTravelCount,
  }) {
    final n = totalPenumpang + pendingTravelCount;
    final hasBadge = n > 0;
    return _buildBaris3Chip(
      icon: Icons.people_outline_rounded,
      label: 'Pemesan',
      enabled: !timePassed,
      onTap: () => _showPemesanSheet(
            scheduleId,
            legacyScheduleId: legacyScheduleId,
          ),
      badgeCount: hasBadge ? n : null,
    );
  }

  Widget _buildBarangChip({
    required String scheduleId,
    required String? legacyScheduleId,
    required bool timePassed,
    required int kirimBarangCount,
    required int pendingBarangCount,
  }) {
    final n = kirimBarangCount + pendingBarangCount;
    final hasBadge = n > 0;
    return _buildBaris3Chip(
      icon: Icons.inventory_2_outlined,
      label: 'Barang',
      enabled: !timePassed,
      onTap: () => _showBarangSheet(
        scheduleId,
        legacyScheduleId: legacyScheduleId,
      ),
      badgeCount: hasBadge ? n : null,
    );
  }

  /// Hapus jadwal dari card (tanpa buka form).
  Future<void> _onHapusJadwalFromCard(_JadwalItem item, int index) async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus jadwal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yakin ingin menghapus jadwal ini?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateWithDay(item.tanggal),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(item.jam)} • ${item.tujuanAwal} → ${item.tujuanAkhir}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: AppInteractionStyles.destructive(Theme.of(ctx).colorScheme),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = _auth.currentUser;
    if (user == null) return;
    if (mounted) setState(() => _firestoreCardBusy = true);
    final busyGuard = Timer(
      _kDeleteScheduleOverallTimeout + const Duration(seconds: 8),
      () {
        if (!mounted) return;
        if (!_firestoreCardBusy) return;
        setState(() => _firestoreCardBusy = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Hapus jadwal terlalu lama — overlay ditutup. Cek jaringan lalu coba lagi.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      },
    );
    try {
      final (sid, leg) = _scheduleIdPairForItem(item);
      final lockSnap = await OrderService.getScheduleSlotBookingSnapshot(
        sid,
        legacyScheduleId: leg,
      );
      if (lockSnap.hasNonTerminalOrders) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Jadwal tidak bisa dihapus: masih ada pesanan aktif. Selesaikan, batalkan, atau pindahkan pesanan dulu.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final ok = await _deleteScheduleFromFirestore(
        firestore: _firestore,
        driverUid: user.uid,
        itemDate: item.tanggal,
        itemJam: item.jam,
        originTrimmed: item.tujuanAwal.trim(),
        destTrimmed: item.tujuanAkhir.trim(),
        scheduleId: sid,
        legacyScheduleId: leg,
      ).timeout(
        _kDeleteScheduleOverallTimeout,
        onTimeout: () => throw TimeoutException(
          'Hapus jadwal terlalu lama. Periksa jaringan lalu coba lagi.',
        ),
      );
      if (!mounted) return;
      if (ok) {
        if (index >= 0 && index < _items.length) {
          _items.removeAt(index);
        }
        setState(() {});
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Jadwal dihapus'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        _scheduleDebouncedJadwalServerSync(mergeIfMissing: null);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Jadwal tidak ditemukan di server. Tarik ke bawah untuk muat ulang lalu coba lagi.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException
            ? 'Hapus jadwal habis waktu. Coba lagi atau muat ulang daftar.'
            : 'Gagal hapus: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      busyGuard.cancel();
      _firestoreCardBusy = false;
      if (mounted) setState(() {});
    }
  }

  void _onEditJadwalTapped(_JadwalItem item, int index, bool scheduleLocked) {
    if (scheduleLocked) {
      final (sid, leg) = _scheduleIdPairForItem(item);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tidak dapat mengubah jadwal'),
          content: const Text(
            'Masih ada pesanan pada jadwal ini (menunggu persetujuan, sudah disepakati/kesepakatan, atau sedang berjalan). Ubah jadwal hanya setelah pesanan selesai, dibatalkan, atau dipindah ke slot lain.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showPemesanSheet(sid, legacyScheduleId: leg);
              },
              child: const Text('Lihat pemesan'),
            ),
          ],
        ),
      );
      return;
    }
    _showAturJadwalForm(item.tanggal, editIndex: index, editItem: item);
  }

  void _showPemesanSheet(
    String scheduleId, {
    String? legacyScheduleId,
  }) {
    final uid = _auth.currentUser?.uid ?? '';
    showTrakaModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
        legacyScheduleId: legacyScheduleId,
        driverUid: uid,
        title: 'Penumpang yang sudah pesan',
        travelOnly: true,
      ),
    );
  }

  void _showBarangSheet(
    String scheduleId, {
    String? legacyScheduleId,
  }) {
    final uid = _auth.currentUser?.uid ?? '';
    showTrakaModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
        legacyScheduleId: legacyScheduleId,
        driverUid: uid,
        title: 'Pesanan kirim barang',
        kirimBarangOnly: true,
      ),
    );
  }

  Widget _buildBaris3Chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? labelColor,
    bool enabled = true,
    int? badgeCount,
  }) {
    const double iconSize = 16;
    const double fontSize = 12;
    final colorScheme = Theme.of(context).colorScheme;
    final grey = colorScheme.onSurfaceVariant;
    final iconC = !enabled ? grey : (iconColor ?? colorScheme.onSurfaceVariant);
    final labelC = !enabled ? grey : (labelColor ?? colorScheme.onSurface);
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: iconC),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: labelC),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}

/// Bottom sheet daftar penumpang yang sudah pesan (nama + foto) untuk satu jadwal.
/// Tombol Pindah ke jadwal lain dan Oper Driver (hanya travel, picked_up).
class _ScheduledPassengersSheet extends StatefulWidget {
  final String scheduleId;
  final String? legacyScheduleId;
  final String driverUid;
  final String title;
  final bool? travelOnly;
  final bool? kirimBarangOnly;

  const _ScheduledPassengersSheet({
    required this.scheduleId,
    this.legacyScheduleId,
    required this.driverUid,
    required this.title,
    this.travelOnly,
    this.kirimBarangOnly,
  });

  @override
  State<_ScheduledPassengersSheet> createState() =>
      _ScheduledPassengersSheetState();
}

class _ScheduledPassengersSheetState extends State<_ScheduledPassengersSheet> {
  late Future<List<OrderModel>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  Future<List<OrderModel>> _loadOrders() => OrderService.getScheduledOrdersForSchedule(
        widget.scheduleId,
        legacyScheduleId: widget.legacyScheduleId,
        travelOnly: widget.travelOnly,
        kirimBarangOnly: widget.kirimBarangOnly,
      );

  /// Penjelasan singkat aturan pindah jadwal vs Oper (hindari kebingungan driver).
  Widget _buildAturanHint(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    String? text;
    if (widget.travelOnly == true) {
      text =
          'Setelah kesepakatan, Anda bisa memindah penumpang ke jadwal lain (ikon kalender). '
          'Oper Driver hanya muncul untuk penumpang travel yang sudah dijemput.';
    } else if (widget.kirimBarangOnly == true) {
      text =
          'Setelah kesepakatan, Anda bisa memindah pesanan ke jadwal lain (ikon kalender). '
          'Oper Driver tidak berlaku untuk kirim barang.';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            _buildAturanHint(context),
            const SizedBox(height: 16),
            FutureBuilder<List<OrderModel>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Gagal memuat daftar. Periksa jaringan lalu coba lagi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _ordersFuture = _loadOrders();
                          }),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: TrakaEmptyState(
                        icon: Icons.people_outline,
                        title: 'Belum ada yang pesan',
                      ),
                    ),
                  );
                }
                final pickedUpTravel = widget.travelOnly == true
                    ? orders
                        .where((o) =>
                            o.status == OrderService.statusPickedUp &&
                            o.orderType == OrderModel.typeTravel)
                        .toList()
                    : <OrderModel>[];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pickedUpTravel.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: () {
                          showOperDriverSheet(
                            context,
                            orders: pickedUpTravel,
                            onTransfersCreated: (transfers) =>
                                showOperDriverBarcodeDialog(
                              context,
                              transfers: transfers,
                            ),
                          );
                        },
                        icon: const Icon(Icons.swap_horiz, size: 20),
                        label: const Text('Oper Driver'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final o = orders[i];
                        final photoUrl = o.passengerPhotoUrl;
                        final subtitle = o.orderType == OrderModel.typeKirimBarang
                            ? 'Kirim Barang'
                            : (o.jumlahKerabat == null || o.jumlahKerabat! <= 0)
                                ? '1 orang'
                                : '${1 + o.jumlahKerabat!} orang';
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(photoUrl)
                                : null,
                            child: photoUrl == null || photoUrl.isEmpty
                                ? Icon(Icons.person,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)
                                : null,
                          ),
                          title: Text(o.passengerName),
                          subtitle: Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.event_available),
                            tooltip: 'Pindah ke jadwal lain',
                            onPressed: () {
                              showPindahJadwalSheet(
                                context,
                                order: o,
                                currentScheduleId: widget.scheduleId,
                                driverUid: widget.driverUid,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}

/// Full-screen map dengan semua rute. Driver pilih rute via tombol atau tap garis di peta.
class _JadwalRoutePreviewScreen extends StatefulWidget {
  final List<DirectionsResult> alternatives;

  const _JadwalRoutePreviewScreen({
    required this.alternatives,
  });

  @override
  State<_JadwalRoutePreviewScreen> createState() =>
      _JadwalRoutePreviewScreenState();
}

class _JadwalRoutePreviewScreenState extends State<_JadwalRoutePreviewScreen> {
  GoogleMapController? _mapController;
  int _selectedIndex = 0; // Default pilih Rute 1
  late final List<GlobalKey> _routeButtonKeys;
  /// Titik diperkaya untuk gambar di peta (lebih sedikit → lebih responsif).
  late final List<List<LatLng>> _mapDrawPoints;
  /// Titik sangat ringan untuk hit-test tap (hindari jank).
  late final List<List<LatLng>> _hitTestPoints;
  Set<Polyline>? _polylinesCache;
  int _polylinesCacheForIndex = -999;

  @override
  void initState() {
    super.initState();
    _routeButtonKeys = List.generate(
      widget.alternatives.length,
      (_) => GlobalKey(),
    );
    _mapDrawPoints = widget.alternatives
        .map((r) => _samplePolylineForJadwalPreview(r.points, maxPoints: 420))
        .toList();
    _hitTestPoints = widget.alternatives
        .map((r) => _samplePolylineForJadwalPreview(r.points, maxPoints: 96))
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureTrakaMapPins());
    });
  }

  Future<void> _ensureTrakaMapPins() async {
    await TrakaPinBitmapService.ensureLoaded(context);
    if (mounted) setState(() {});
  }

  Set<Marker> _buildEndpointMarkers(LatLng origin, LatLng dest) {
    final o = TrakaPinBitmapService.mapAwal ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    final d = TrakaPinBitmapService.mapAhir ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    return {
      Marker(
        markerId: const MarkerId('origin'),
        position: origin,
        icon: o,
        anchor: const Offset(0.5, 1.0),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: dest,
        icon: d,
        anchor: const Offset(0.5, 1.0),
      ),
    };
  }

  void _scrollToSelectedRoute() {
    if (_selectedIndex < 0 || _selectedIndex >= _routeButtonKeys.length) return;
    final ctx = _routeButtonKeys[_selectedIndex].currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (_mapController != null && mounted) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(pos.latitude, pos.longitude),
            15,
          ),
        );
      }
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Jangan panggil animateCamera di frame yang sama dengan create — di beberapa perangkat
    // memicu native error saat peta Beranda driver masih hidup (dua GoogleMap).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitBounds();
    });
  }

  void _fitBounds() {
    if (widget.alternatives.isEmpty || _mapController == null || !mounted) return;
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final pts in _mapDrawPoints) {
      for (final p in pts) {
        if (!p.latitude.isFinite || !p.longitude.isFinite) continue;
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    if (minLat == double.infinity || !minLat.isFinite || !maxLat.isFinite ||
        !minLng.isFinite || !maxLng.isFinite) {
      return;
    }
    // Bounds nol/terlalu kecil → newLatLngBounds bisa gagal atau bikin native crash.
    const minSpan = 0.012;
    if ((maxLat - minLat).abs() < minSpan) {
      final m = (minLat + maxLat) / 2;
      minLat = m - minSpan / 2;
      maxLat = m + minSpan / 2;
    }
    if ((maxLng - minLng).abs() < minSpan) {
      final m = (minLng + maxLng) / 2;
      minLng = m - minSpan / 2;
      maxLng = m + minSpan / 2;
    }
    if (minLat > maxLat) {
      final t = minLat;
      minLat = maxLat;
      maxLat = t;
    }
    if (minLng > maxLng) {
      final t = minLng;
      minLng = maxLng;
      maxLng = t;
    }
    // Padding lebih besar + area bawah untuk card agar semua alternatif kelihatan
    // (bukan zoom tetap 10 yang sering memotong rute panjang).
    final mq = MediaQuery.of(context);
    final pad = 100.0 + mq.padding.top + mq.padding.bottom;
    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          pad,
        ),
      );
    } catch (_) {
      try {
        final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(center, 10));
      } catch (_) {}
    }
  }

  void _onMapTap(LatLng position) {
    if (widget.alternatives.isEmpty) return;
    double minDistance = double.infinity;
    int closestIndex = -1;
    // Lebih longgar agar tap di layar mudah kena jalur (pedesaan / jari besar).
    const thresholdMeters = 420.0;
    for (int i = 0; i < _hitTestPoints.length; i++) {
      final pts = _hitTestPoints[i];
      if (pts.isEmpty) continue;
      final d = RouteUtils.distanceToPolyline(position, pts);
      if (d < minDistance && d < thresholdMeters) {
        minDistance = d;
        closestIndex = i;
      }
    }
    if (closestIndex >= 0 && mounted) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedIndex = closestIndex;
        _polylinesCache = null;
      });
      _scrollToSelectedRoute();
    }
  }

  void _selectRoute(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
      _polylinesCache = null;
    });
    _scrollToSelectedRoute();
  }

  Set<Polyline> _buildPolylines() {
    if (_polylinesCache != null && _polylinesCacheForIndex == _selectedIndex) {
      return _polylinesCache!;
    }
    final polylines = <Polyline>{};
    for (int i = 0; i < widget.alternatives.length; i++) {
      final pts = i < _mapDrawPoints.length ? _mapDrawPoints[i] : widget.alternatives[i].points;
      if (pts.isEmpty) continue;
      final base = routeColorForIndex(i);
      final isSel = _selectedIndex == i;
      final color = isSel ? base : base.withValues(alpha: 0.38);
      polylines.add(
        Polyline(
          polylineId: PolylineId('jadwal_route_$i'),
          points: pts,
          color: color,
          width: isSel ? 9 : 5,
          zIndex: isSel ? 12 : 2 + i,
        ),
      );
    }
    _polylinesCache = polylines;
    _polylinesCacheForIndex = _selectedIndex;
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alternatives.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pilih rute')),
        body: const Center(
          child: TrakaEmptyState(
            icon: Icons.map_outlined,
            title: 'Rute tidak ditemukan',
            subtitle:
                'Tutup lalu coba buat ulang rute atau periksa asal dan tujuan.',
          ),
        ),
      );
    }
    final firstPts = _mapDrawPoints.isNotEmpty ? _mapDrawPoints.first : widget.alternatives.first.points;
    final origin = firstPts.isNotEmpty ? firstPts.first : const LatLng(0, 0);
    final dest = firstPts.isNotEmpty ? firstPts.last : origin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih rute'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    color: routeColorForIndex(_selectedIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.alt_route, color: Colors.white.withValues(alpha: 0.95), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Rute ${_selectedIndex + 1} dipilih',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '${widget.alternatives[_selectedIndex].distanceText} • ${widget.alternatives[_selectedIndex].durationText}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'AKTIF',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: StyledGoogleMapBuilder(
                    builder: (style, _) => GoogleMap(
                      buildingsEnabled: false,
                      indoorViewEnabled: false,
                      initialCameraPosition: CameraPosition(
                        target: origin,
                        zoom: MapStyleService.defaultZoom,
                        tilt: MapStyleService.defaultTilt,
                      ),
                      onMapCreated: _onMapCreated,
                      onTap: _onMapTap,
                      mapType: MapType.normal,
                      style: style,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      polylines: _buildPolylines(),
                      markers: _buildEndpointMarkers(origin, dest),
                    ),
                  ),
                ),
                Positioned(
                  top: 80,
                  right: 16,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface, size: 22),
                          ),
                        ),
                        Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        InkWell(
                          onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: Icon(Icons.remove, color: Theme.of(context).colorScheme.onSurface, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 80,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _goToMyLocation,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.my_location,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Di luar area GoogleMap (bukan Stack di atas platform view) agar tombol Rute 1/2/3
          // tetap dapat sentuhan di Android.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(widget.alternatives.length, (i) {
                                final r = widget.alternatives[i];
                                final color = routeColorForIndex(i);
                                final isSelected = i == _selectedIndex;
                                return Padding(
                                  key: _routeButtonKeys[i],
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: InkWell(
                                      onTap: () => _selectRoute(i),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: isSelected ? 1 : 0.85),
                                          borderRadius: BorderRadius.circular(12),
                                          border: isSelected
                                              ? Border.all(color: Colors.white, width: 3)
                                              : null,
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: color.withValues(alpha: 0.55),
                                                    blurRadius: 14,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isSelected) ...[
                                                  const Icon(Icons.check_circle, color: Colors.white, size: 14),
                                                  const SizedBox(width: 4),
                                                ],
                                                Text(
                                                  'Rute ${i + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              isSelected ? '${r.distanceText} · dipilih' : r.distanceText,
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.9),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                          if (widget.alternatives.length >= 3)
                            Positioned(
                              top: 0,
                              right: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [
                                        Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                                        Theme.of(context).colorScheme.surface,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (widget.alternatives.length == 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Hanya tersedia 1 rute untuk rute ini.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (_selectedIndex >= 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${widget.alternatives[_selectedIndex].distanceText} • ${widget.alternatives[_selectedIndex].durationText}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Garis tebal = rute aktif. Tap dekat garis kuning/hijau di peta atau tombol di bawah untuk ganti.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _mapController == null ? null : _fitBounds,
                          icon: const Icon(Icons.fit_screen, size: 18),
                          label: const Text('Tampilkan semua rute'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: AppInteractionStyles.outlinedFromTheme(
                                context,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Kembali', overflow: TextOverflow.ellipsis, maxLines: 1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _selectedIndex >= 0
                                  ? () {
                                      HapticFeedback.mediumImpact();
                                      final pts =
                                          widget.alternatives[_selectedIndex].points;
                                      Navigator.pop(context, pts);
                                    }
                                  : null,
                              icon: const Icon(Icons.check, size: 20),
                              label: const Text('Pilih rute ini'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form isi jadwal: tujuan awal (dengan icon lokasi + autocomplete), tujuan akhir (autocomplete), jam, simpan.
  /// Jika [editScheduleIndex] != null, form untuk edit; simpan mengganti entri yang sama di Firestore (bukan index mentah).
class _AturJadwalFormContent extends StatefulWidget {
  final DateTime date;
  final String Function(DateTime) formatDateWithDay;
  final String Function(TimeOfDay) formatTime;
  final Future<String?> Function() getCurrentLocationText;
  final String Function(Placemark) formatPlacemark;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final ValueNotifier<bool> formSaving;
  final Future<void> Function(
    _JadwalItem? newItem, {
    int? deletedIndex,
    int? editIndex,
    bool skipServerSync,
  }) onSaved;
  /// Setelah simpan optimistik (sheet sudah tutup): tulis [schedules] ke Firestore.
  final Future<void> Function({
    required List<Map<String, dynamic>> schedulesToWrite,
    required _JadwalItem newItem,
  })
  persistSchedulesAfterOptimisticUi;
  final int? editScheduleIndex;
  /// Identity jadwal yang diedit (computed, sama seperti penumpang/driver status).
  final String? editScheduleId;
  final String? editLegacyScheduleId;
  final String? initialOrigin;
  final String? initialDest;
  final TimeOfDay? initialJam;
  /// Rute tersimpan (untuk edit). Null = belum dipilih atau jadwal lama.
  final List<LatLng>? initialRoutePolyline;
  /// Kategori rute: dalam_kota, antar_kabupaten, antar_provinsi, nasional.
  final String? initialRouteCategory;
  final bool isDriverVerified;
  final VoidCallback? onVerificationRequired;
  /// Jam jadwal lain di tanggal yang sama (untuk validasi konflik). Exclude jadwal yang sedang diedit.
  final List<TimeOfDay> otherScheduleTimesOnDate;

  const _AturJadwalFormContent({
    required this.date,
    required this.formatDateWithDay,
    required this.formatTime,
    required this.getCurrentLocationText,
    required this.formatPlacemark,
    required this.auth,
    required this.firestore,
    required this.formSaving,
    required this.onSaved,
    required this.persistSchedulesAfterOptimisticUi,
    this.editScheduleIndex,
    this.editScheduleId,
    this.editLegacyScheduleId,
    this.initialOrigin,
    this.initialDest,
    this.initialJam,
    this.initialRoutePolyline,
    this.initialRouteCategory,
    this.isDriverVerified = true,
    this.onVerificationRequired,
    this.otherScheduleTimesOnDate = const [],
  });

  @override
  State<_AturJadwalFormContent> createState() => _AturJadwalFormContentState();
}

class _AturJadwalFormContentState extends State<_AturJadwalFormContent> {
  late final TextEditingController _originController;
  late final TextEditingController _destController;
  late TimeOfDay _jam;
  List<Placemark> _originResults = [];
  List<Placemark> _destResults = [];
  bool _showOrigin = false;
  bool _showDest = false;
  bool _loadingLocation = false;
  /// Rute yang dipilih driver. Null = belum dipilih.
  List<LatLng>? _selectedRoutePolyline;
  /// Kategori rute yang dilayani driver.
  late String _routeCategory;
  bool _loadingRoutes = false;
  /// Prefetch: load rute di background saat origin & dest terisi agar map buka cepat.
  Timer? _prefetchDebounce;
  String? _prefetchedOrigin;
  String? _prefetchedDest;
  List<DirectionsResult>? _prefetchedAlternatives;
  bool _prefetching = false;

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(text: widget.initialOrigin ?? '');
    _destController = TextEditingController(text: widget.initialDest ?? '');
    _jam = widget.initialJam ?? TimeOfDay.now();
    _selectedRoutePolyline = widget.initialRoutePolyline;
    _routeCategory = widget.initialRouteCategory ?? RouteCategoryService.categoryAntarProvinsi;
    _schedulePrefetch();
  }

  void _schedulePrefetch() {
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(const Duration(milliseconds: 450), () {
      _doPrefetch();
    });
  }

  void _invalidatePrefetch() {
    _prefetchedOrigin = null;
    _prefetchedDest = null;
    _prefetchedAlternatives = null;
  }

  Future<void> _doPrefetch() async {
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty || origin.length < 3 || dest.length < 3) {
      _invalidatePrefetch();
      return;
    }
    if (_prefetching) return;
    _prefetching = true;
    if (mounted) setState(() {});
    const apiTimeout = Duration(seconds: 20);
    try {
      final originLocs = await GeocodingService.locationFromAddress(
        '$origin, Indonesia',
        appendIndonesia: false,
      ).timeout(apiTimeout);
      final destLocs = await GeocodingService.locationFromAddress(
        '$dest, Indonesia',
        appendIndonesia: false,
      ).timeout(apiTimeout);
      if (!mounted) return;
      if (originLocs.isEmpty || destLocs.isEmpty) {
        _invalidatePrefetch();
        return;
      }
      final alternatives = await DirectionsService.getAlternativeRoutes(
        originLat: originLocs.first.latitude,
        originLng: originLocs.first.longitude,
        destLat: destLocs.first.latitude,
        destLng: destLocs.first.longitude,
      ).timeout(apiTimeout);
      if (!mounted) return;
      if (alternatives.isNotEmpty) {
        _prefetchedOrigin = origin;
        _prefetchedDest = dest;
        _prefetchedAlternatives = alternatives;
      } else {
        _invalidatePrefetch();
      }
    } catch (_) {
      _invalidatePrefetch();
    } finally {
      _prefetching = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _prefetchDebounce?.cancel();
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _fillCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final text = await widget.getCurrentLocationText();
      if (text != null && mounted) {
        _originController.text = text;
        setState(() {
          _originResults = [];
          _showOrigin = false;
        });
        _invalidatePrefetch();
        _schedulePrefetch();
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingLocation = false);
  }

  Future<void> _searchLocation(String value, bool isOrigin) async {
    if (value.trim().isEmpty) {
      setState(() {
        if (isOrigin) {
          _originResults = [];
          _showOrigin = false;
        } else {
          _destResults = [];
          _showDest = false;
        }
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (isOrigin && _originController.text.trim() != value.trim()) return;
    if (!isOrigin && _destController.text.trim() != value.trim()) return;
    try {
      final locations = await GeocodingService.locationFromAddress(
        '$value, Indonesia',
        appendIndonesia: false,
      );
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 10; i++) {
        try {
          final list = await GeocodingService.placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (isOrigin && _originController.text.trim() != value.trim()) return;
      if (!isOrigin && _destController.text.trim() != value.trim()) return;
      setState(() {
        if (isOrigin) {
          _originResults = placemarks;
          _showOrigin = placemarks.isNotEmpty;
        } else {
          _destResults = placemarks;
          _showDest = placemarks.isNotEmpty;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isOrigin) {
            _originResults = [];
            _showOrigin = false;
          } else {
            _destResults = [];
            _showDest = false;
          }
        });
      }
    }
  }

  Future<void> _pickTujuanAwalOnMap() async {
    final t = _originController.text.trim();
    LatLng? device;
    try {
      final pos = await Geolocator.getCurrentPosition();
      device = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
    if (!mounted) return;
    final initial = await initialTargetForDestinationMapPickerWithLoading(
      context: context,
      destText: t,
      userLocation: device,
    );
    if (!mounted) return;
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapDestinationPickerScreen(
          initialCameraTarget: initial,
          deviceLocation: device,
          title: TrakaL10n.of(context).pickOriginOnMapActionLabel,
          pinVariant: TrakaRoutePinVariant.origin,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _originController.text = r.label;
      _originResults = [];
      _showOrigin = false;
    });
    _invalidatePrefetch();
    _schedulePrefetch();
  }

  Future<void> _pickTujuanAkhirOnMap() async {
    final t = _destController.text.trim();
    LatLng? device;
    try {
      final pos = await Geolocator.getCurrentPosition();
      device = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
    if (!mounted) return;
    final initial = await initialTargetForDestinationMapPickerWithLoading(
      context: context,
      destText: t,
      userLocation: device,
    );
    if (!mounted) return;
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
    setState(() {
      _destController.text = r.label;
      _destResults = [];
      _showDest = false;
    });
    _invalidatePrefetch();
    _schedulePrefetch();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.formSaving,
      builder: (context, saving, _) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.editScheduleIndex != null
                      ? 'Edit jadwal — ${widget.formatDateWithDay(widget.date)}'
                      : 'Jadwal ${widget.formatDateWithDay(widget.date)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _routeCategory,
                  decoration: InputDecoration(
                    labelText: 'Kategori rute',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: RouteCategoryService.categoryDalamKota, child: Text('Dalam Kota')),
                    DropdownMenuItem(value: RouteCategoryService.categoryAntarKabupaten, child: Text('Antar Kabupaten')),
                    DropdownMenuItem(value: RouteCategoryService.categoryAntarProvinsi, child: Text('Antar Provinsi')),
                    DropdownMenuItem(value: RouteCategoryService.categoryNasional, child: Text('Nasional')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _routeCategory = v);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Penumpang dapat memfilter driver berdasarkan kategori ini saat mencari travel.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tujuan awal + icon lokasi
                if (_showOrigin && _originResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 160
                          : 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _originResults.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        itemBuilder: (context, i) {
                          final p = _originResults[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              widget.formatPlacemark(p),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _originController.text = widget.formatPlacemark(p);
                              setState(() {
                                _originResults = [];
                                _showOrigin = false;
                              });
                              _invalidatePrefetch();
                              _schedulePrefetch();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                TextField(
                  controller: _originController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Tujuan awal *',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 8, right: 4),
                      child: TrakaPinFormIcon(
                        variant: TrakaRoutePinVariant.origin,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 40,
                    ),
                    suffixIcon: _loadingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.my_location,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            tooltip: 'Gunakan lokasi saat ini',
                            onPressed: _loadingLocation
                                ? null
                                : _fillCurrentLocation,
                          ),
                  ),
                  onChanged: (value) {
                    _searchLocation(value, true);
                    if (widget.initialOrigin != null &&
                        value.trim() != widget.initialOrigin!.trim()) {
                      setState(() => _selectedRoutePolyline = null);
                    } else {
                      setState(() {});
                    }
                    _invalidatePrefetch();
                    _schedulePrefetch();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: saving ? null : _pickTujuanAwalOnMap,
                    icon: const Icon(Icons.map_outlined, size: 20),
                    label: Text(
                      TrakaL10n.of(context).pickOriginOnMapActionLabel,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tujuan akhir + autocomplete
                if (_showDest && _destResults.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 160
                          : 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _destResults.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Theme.of(context).colorScheme.outline),
                        itemBuilder: (context, i) {
                          final p = _destResults[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.place_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              widget.formatPlacemark(p),
                              style: const TextStyle(fontSize: 13, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _destController.text = widget.formatPlacemark(p);
                              setState(() {
                                _destResults = [];
                                _showDest = false;
                              });
                              _invalidatePrefetch();
                              _schedulePrefetch();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                TextField(
                  controller: _destController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Tujuan akhir *',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    isDense: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 8, right: 4),
                      child: TrakaPinFormIcon(
                        variant: TrakaRoutePinVariant.destination,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 40,
                    ),
                  ),
                  onChanged: (value) {
                    _searchLocation(value, false);
                    if (widget.initialDest != null &&
                        value.trim() != widget.initialDest!.trim()) {
                      setState(() => _selectedRoutePolyline = null);
                    } else {
                      setState(() {});
                    }
                    _invalidatePrefetch();
                    _schedulePrefetch();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: saving ? null : _pickTujuanAkhirOnMap,
                    icon: const Icon(Icons.map_outlined, size: 20),
                    label: Text(TrakaL10n.of(context).pickOnMapActionLabel),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _jam,
                    );
                    if (picked != null && mounted) {
                      setState(() => _jam = picked);
                    }
                  },
                  icon: const Icon(Icons.access_time, size: 20),
                  label: Text(widget.formatTime(_jam)),
                  style: AppInteractionStyles.outlinedFromTheme(
                    context,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loadingRoutes
                      ? null
                      : () => _showRoutePickerSheet(),
                  icon: _loadingRoutes
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _selectedRoutePolyline != null
                              ? Icons.check_circle
                              : Icons.route,
                          size: 20,
                          color: _selectedRoutePolyline != null
                              ? Colors.green
                              : Theme.of(context).colorScheme.primary,
                        ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _loadingRoutes
                            ? 'Mencari rute...'
                            : _selectedRoutePolyline != null
                                ? 'Rute sudah dipilih (tap untuk ubah)'
                                : 'Lihat dan pilih rute',
                      ),
                      if (_prefetching && !_loadingRoutes) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ] else if (_prefetchedAlternatives != null &&
                          _prefetchedAlternatives!.isNotEmpty &&
                          !_loadingRoutes &&
                          _prefetchedOrigin == _originController.text.trim() &&
                          _prefetchedDest == _destController.text.trim()) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green,
                        ),
                      ],
                    ],
                  ),
                  style: AppInteractionStyles.outlinedFromTheme(
                    context,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_selectedRoutePolyline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Pencarian penumpang akan sesuai rute yang dipilih.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (widget.editScheduleIndex != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving ? null : _onHapus,
                      icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                      label: Text(
                        'Hapus jadwal',
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Builder(
                        builder: (context) {
                          final origin = _originController.text.trim();
                          final dest = _destController.text.trim();
                          final canSave = origin.isNotEmpty &&
                              dest.isNotEmpty &&
                              _selectedRoutePolyline != null;
                          return FilledButton(
                            onPressed: (saving || !canSave) ? null : _onSimpan,
                            style: AppInteractionStyles.filledFromTheme(
                              context,
                            ).copyWith(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                final p =
                                    Theme.of(context).colorScheme.primary;
                                if (states.contains(WidgetState.disabled)) {
                                  if (canSave) {
                                    return p;
                                  }
                                  return p.withValues(alpha: 0.5);
                                }
                                return p;
                              }),
                            ),
                            child: saving
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Simpan'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRoutePickerSheet() async {
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi tujuan awal dan tujuan akhir terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // Gunakan data prefetch jika valid → map buka langsung
    if (_prefetchedOrigin == origin &&
        _prefetchedDest == dest &&
        _prefetchedAlternatives != null &&
        _prefetchedAlternatives!.isNotEmpty) {
      final drawablePref =
          _onlyDrawableRouteAlternatives(_prefetchedAlternatives!);
      if (drawablePref.isNotEmpty) {
        final selected = await Navigator.push<List<LatLng>>(
          context,
          MaterialPageRoute(
            builder: (ctx) => _JadwalRoutePreviewScreen(
              alternatives: drawablePref,
            ),
          ),
        );
        if (mounted && selected != null) {
          setState(() => _selectedRoutePolyline = selected);
        }
        return;
      }
    }
    setState(() => _loadingRoutes = true);
    const apiTimeout = Duration(seconds: 20);
    try {
      final originLocs = await GeocodingService.locationFromAddress(
        '$origin, Indonesia',
        appendIndonesia: false,
      ).timeout(apiTimeout);
      final destLocs = await GeocodingService.locationFromAddress(
        '$dest, Indonesia',
        appendIndonesia: false,
      ).timeout(apiTimeout);
      if (!mounted) return;
      if (originLocs.isEmpty || destLocs.isEmpty) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Lokasi tidak ditemukan. Periksa alamat.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _showRoutePickerSheet(),
            ),
          ),
        );
        return;
      }
      final alternatives = await DirectionsService.getAlternativeRoutes(
        originLat: originLocs.first.latitude,
        originLng: originLocs.first.longitude,
        destLat: destLocs.first.latitude,
        destLng: destLocs.first.longitude,
      ).timeout(apiTimeout);
      if (!mounted) return;
      if (alternatives.isEmpty) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Rute tidak ditemukan.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _showRoutePickerSheet(),
            ),
          ),
        );
        return;
      }
      final drawable = _onlyDrawableRouteAlternatives(alternatives);
      if (drawable.isEmpty) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Data rute tidak valid (tanpa garis di peta). Coba alamat lain atau lagi nanti.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _showRoutePickerSheet(),
            ),
          ),
        );
        return;
      }
      final selected = await Navigator.push<List<LatLng>>(
        context,
        MaterialPageRoute(
          builder: (ctx) => _JadwalRoutePreviewScreen(
            alternatives: drawable,
          ),
        ),
      );
      if (mounted && selected != null) {
        setState(() {
          _selectedRoutePolyline = selected;
          _loadingRoutes = false;
        });
      } else if (mounted) {
        setState(() => _loadingRoutes = false);
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Memuat terlalu lama. Periksa koneksi dan coba lagi.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _showRoutePickerSheet(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat rute: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _showRoutePickerSheet(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _onHapus() async {
    final user = widget.auth.currentUser;
    if (user == null) return;
    final editIdx = widget.editScheduleIndex;
    if (editIdx == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus jadwal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yakin ingin menghapus jadwal ini?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.formatDateWithDay(widget.date),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.formatTime(widget.initialJam ?? TimeOfDay.now())} • ${(widget.initialOrigin ?? '').trim()} → ${(widget.initialDest ?? '').trim()}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: AppInteractionStyles.destructive(Theme.of(ctx).colorScheme),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.formSaving.value = true;
    final origin = (widget.initialOrigin ?? '').trim();
    final dest = (widget.initialDest ?? '').trim();
    final targetJam = widget.initialJam;
    final sid = widget.editScheduleId ?? '';
    final leg = widget.editLegacyScheduleId ?? '';
    try {
      if (targetJam == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak ada jam jadwal untuk dihapus.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final dateKey =
          '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';
      final depMs = DateTime(
        widget.date.year,
        widget.date.month,
        widget.date.day,
        targetJam.hour,
        targetJam.minute,
      ).millisecondsSinceEpoch;
      final (effectiveSid, effectiveLeg) = (sid.isNotEmpty && leg.isNotEmpty)
          ? (sid, leg)
          : sid.isNotEmpty
              ? (sid, ScheduleIdUtil.toLegacy(sid))
              : ScheduleIdUtil.build(user.uid, dateKey, depMs, origin, dest);
      final lockSnap = await OrderService.getScheduleSlotBookingSnapshot(
        effectiveSid,
        legacyScheduleId: effectiveLeg,
      );
      if (lockSnap.hasNonTerminalOrders) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Jadwal tidak bisa dihapus: masih ada pesanan aktif. Selesaikan, batalkan, atau pindahkan pesanan dulu.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        widget.formSaving.value = false;
        return;
      }
      final ok = await _deleteScheduleFromFirestore(
        firestore: widget.firestore,
        driverUid: user.uid,
        itemDate: widget.date,
        itemJam: targetJam,
        originTrimmed: origin,
        destTrimmed: dest,
        scheduleId: effectiveSid,
        legacyScheduleId: effectiveLeg,
      ).timeout(
        _kDeleteScheduleOverallTimeout,
        onTimeout: () => throw TimeoutException(
          'Hapus jadwal terlalu lama. Periksa jaringan lalu coba lagi.',
        ),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        widget.formSaving.value = false;
        try {
          await widget.onSaved(null, deletedIndex: editIdx);
        } catch (e) {
          if (kDebugMode) debugPrint('DriverJadwal onSaved after delete: $e');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Jadwal tidak ditemukan di server. Tutup form dan muat ulang daftar.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException
            ? 'Hapus jadwal habis waktu. Coba lagi.'
            : 'Gagal hapus: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      widget.formSaving.value = false;
    }
  }

  Widget _buildSummaryRow(BuildContext ctx, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(ctx).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onSimpan() async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tujuan awal dan tujuan akhir wajib diisi.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedRoutePolyline == null || _selectedRoutePolyline!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih rute terlebih dahulu dengan tombol Lihat dan pilih rute.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final scheduleDateStart = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final todayWib = DriverScheduleService.todayDateOnlyWib;
    final isEdit = widget.editScheduleIndex != null && widget.initialJam != null;
    if (!isEdit && !DriverScheduleService.isScheduleDateInBookingWindow(scheduleDateStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tanggal jadwal hanya boleh dalam 7 hari ke depan (WIB).',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!isEdit && scheduleDateStart.isBefore(todayWib)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa menambah jadwal untuk tanggal yang sudah lewat (WIB).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final dt = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      _jam.hour,
      _jam.minute,
    );
    if (scheduleDateStart == todayWib && dt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jam keberangkatan tidak boleh di masa lalu untuk tanggal hari ini.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi jadwal'),
        content: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Simpan jadwal berikut?',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _buildSummaryRow(ctx, Icons.calendar_today, 'Tanggal', widget.formatDateWithDay(widget.date)),
              const SizedBox(height: 8),
              _buildSummaryRow(ctx, Icons.access_time, 'Jam', widget.formatTime(_jam)),
              const SizedBox(height: 8),
              _buildSummaryRow(ctx, Icons.trip_origin, 'Tujuan awal', origin),
              const SizedBox(height: 8),
              _buildSummaryRow(ctx, Icons.location_on, 'Tujuan akhir', dest),
              const SizedBox(height: 8),
              _buildSummaryRow(ctx, Icons.route, 'Rute', 'Sudah dipilih'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    const conflictThresholdMinutes = 120;
    for (final other in widget.otherScheduleTimesOnDate) {
      final otherMin = other.hour * 60 + other.minute;
      final newMin = _jam.hour * 60 + _jam.minute;
      if ((newMin - otherMin).abs() < conflictThresholdMinutes) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Jadwal berdekatan'),
            content: Text(
              'Jam ${widget.formatTime(_jam)} berdekatan dengan jadwal lain (${widget.formatTime(other)}) pada tanggal yang sama. Lanjutkan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        break;
      }
    }
    if (!mounted) return;
    final user = widget.auth.currentUser;
    if (user == null) return;
    final isEditFlow =
        widget.editScheduleIndex != null && widget.initialJam != null;
    if (isEditFlow) {
      final sid = widget.editScheduleId ?? '';
      if (sid.isNotEmpty) {
        final lock = await OrderService.getScheduleSlotBookingSnapshot(
          sid,
          legacyScheduleId: widget.editLegacyScheduleId,
        );
        if (lock.hasNonTerminalOrders) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Tidak bisa menyimpan perubahan: masih ada pesanan aktif pada jadwal ini. Selesaikan, batalkan, atau pindahkan pesanan dulu.',
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 12),
              ),
            );
          }
          return;
        }
      }
    }
    widget.formSaving.value = true;
    const readTimeout = Duration(seconds: 16);
    try {
      final schedules =
          await DriverScheduleItemsStore.loadScheduleMaps(
        widget.firestore,
        user.uid,
        options: const GetOptions(source: Source.serverAndCache),
      ).timeout(
        readTimeout,
        onTimeout: () => throw TimeoutException(
          'Koneksi timeout. Cek jaringan dan coba lagi.',
        ),
      );
      final newMap = <String, dynamic>{
        'origin': origin,
        'destination': dest,
        'departureTime': Timestamp.fromDate(dt),
        'date': Timestamp.fromDate(widget.date),
        'routeCategory': _routeCategory,
      };
      if (_selectedRoutePolyline != null && _selectedRoutePolyline!.isNotEmpty) {
        newMap['routePolyline'] = _selectedRoutePolyline!
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList();
      }
      final editIdx = widget.editScheduleIndex;
      int? docIndex;
      final isEdit = editIdx != null && widget.initialJam != null;
      if (isEdit) {
        docIndex = _indexOfScheduleInFirestoreList(
          schedules: schedules,
          driverUid: user.uid,
          itemDate: widget.date,
          itemJam: widget.initialJam!,
          originTrimmed: (widget.initialOrigin ?? '').trim(),
          destTrimmed: (widget.initialDest ?? '').trim(),
          scheduleId: widget.editScheduleId,
          legacyScheduleId: widget.editLegacyScheduleId,
        );
      }
      if (docIndex != null && docIndex >= 0 && docIndex < schedules.length) {
        final existing = schedules[docIndex];
        if (existing['hiddenAt'] != null) {
          newMap['hiddenAt'] = existing['hiddenAt'];
        }
        final sid = existing['scheduleId'];
        if (sid is String && sid.isNotEmpty) {
          newMap['scheduleId'] = sid;
        }
        schedules[docIndex] = newMap;
      } else {
        schedules.add(newMap);
      }
      final schedulesToWrite = _shrunkSchedulesForFirestoreDocument(schedules);
      final newItem = _JadwalItem(
        tujuanAwal: origin,
        tujuanAkhir: dest,
        jam: TimeOfDay(hour: dt.hour, minute: dt.minute),
        tanggal: widget.date,
        routePolyline: _selectedRoutePolyline != null &&
                _selectedRoutePolyline!.isNotEmpty
            ? _selectedRoutePolyline
            : null,
        routeCategory: _routeCategory,
      );
      // Simpan optimistik: tutup sheet + snackbar segera; Firestore di background.
      if (!mounted) return;
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      widget.formSaving.value = false;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            docIndex != null
                ? 'Jadwal berhasil diubah.'
                : 'Jadwal berhasil disimpan.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      try {
        await widget.onSaved(newItem, editIndex: editIdx, skipServerSync: true);
      } catch (e) {
        if (kDebugMode) debugPrint('DriverJadwal onSaved after save: $e');
      }
      unawaited(
        widget.persistSchedulesAfterOptimisticUi(
          schedulesToWrite: schedulesToWrite,
          newItem: newItem,
        ),
      );
    } catch (e) {
      final msg = e is TimeoutException
          ? 'Koneksi timeout. Cek jaringan dan coba lagi.'
          : 'Gagal simpan: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 12),
            action: SnackBarAction(
              label: 'Coba lagi',
              textColor: Colors.white,
              onPressed: () => _onSimpan(),
            ),
          ),
        );
      }
    } finally {
      widget.formSaving.value = false;
    }
  }
}
