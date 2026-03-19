import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../utils/placemark_formatter.dart';
import '../services/location_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/driver_schedule_service.dart';
import '../services/route_category_service.dart';
import '../services/order_service.dart';
import '../models/order_model.dart';
import '../widgets/oper_driver_sheet.dart';
import '../widgets/pindah_jadwal_sheet.dart';
import '../widgets/driver_map_overlays.dart';
import '../widgets/styled_google_map_builder.dart';
import '../services/map_style_service.dart';
import '../services/route_utils.dart';
import '../services/recent_destination_service.dart';
import '../services/schedule_reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import 'package:geolocator/geolocator.dart';

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

class _DriverJadwalRuteScreenState extends State<DriverJadwalRuteScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final List<_JadwalItem> _items = [];
  bool _loading = true;
  /// Tampilkan spinner hanya jika loading > 200ms (terasa lebih responsif)
  bool _showLoadingSpinner = false;
  Timer? _loadingDelayTimer;

  /// PageView jadwal per tanggal: geser kiri = tanggal berikutnya, geser kanan = kembali.
  final PageController _jadwalPageController = PageController();

  /// Halaman PageView yang sedang aktif (untuk chip, dots).
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadJadwal();
    _jadwalPageController.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _loadingDelayTimer?.cancel();
    _jadwalPageController.removeListener(_onPageChanged);
    _jadwalPageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (!_jadwalPageController.hasClients) return;
    final page = _jadwalPageController.page?.round() ?? 0;
    final grouped = _groupedByDate();
    if (page >= 0 && page < grouped.length && mounted && page != _currentPageIndex) {
      setState(() => _currentPageIndex = page);
    }
  }

  Future<void> _loadJadwal({bool forceFromServer = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    _loadingDelayTimer?.cancel();
    _loadingDelayTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _loading) {
        setState(() => _showLoadingSpinner = true);
      }
    });
    try {
      final kept = await DriverScheduleService.cleanupPastSchedules(
        user.uid,
        forceFromServer: forceFromServer,
      );
      _items.clear();
      for (final map in kept) {
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
        _items.add(
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
      if (mounted) {
        _loadingDelayTimer?.cancel();
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
          _currentPageIndex = 0;
        });
        unawaited(ScheduleReminderService.scheduleRemindersForDriver(user.uid));
      }
    } catch (_) {
      if (mounted) {
        _loadingDelayTimer?.cancel();
        setState(() {
          _loading = false;
          _showLoadingSpinner = false;
        });
      }
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Parse routePolyline dari Firestore: [{lat, lng}, ...] → List<LatLng>.
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

  /// Hari ini (untuk bandingan terlewat/belum).
  static DateTime get _today => _dateOnly(DateTime.now());

  /// Cek apakah tanggal sudah lewat (sebelum hari ini).
  bool _isPast(DateTime d) {
    return _dateOnly(d).isBefore(_today);
  }

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

  /// Icon rute berfungsi hanya jika: tanggal jadwal = hari ini dan dalam 4 jam sebelum keberangkatan.
  bool _isRuteAvailableForJadwal(_JadwalItem item) {
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
    final now = DateTime.now();
    final windowStart = departure.subtract(const Duration(hours: 4));
    return (now.isAfter(windowStart) || now.isAtSameMomentAs(windowStart)) &&
        (now.isBefore(departure) || now.isAtSameMomentAs(departure));
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: _dateOnly(now),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pilih tanggal jadwal',
    );
    if (picked == null || !mounted) return;
    final date = _dateOnly(picked);
    if (_isPast(date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tanggal yang belum lewat.'),
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
    _showAturJadwalForm(date);
  }

  /// Duplikat jadwal ke tanggal lain (rute rutin).
  Future<void> _onDuplikatJadwalTapped(_JadwalItem item) async {
    if (!widget.isDriverVerified) {
      widget.onVerificationRequired?.call();
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(item.tanggal).add(const Duration(days: 7)),
      firstDate: _dateOnly(now),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pilih tanggal untuk duplikat jadwal',
    );
    if (picked == null || !mounted) return;
    final date = _dateOnly(picked);
    if (_isPast(date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tanggal yang belum lewat.'),
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
    showModalBottomSheet<void>(
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
        onSaved: (_JadwalItem? newItem, {int? deletedIndex, int? editIndex, Map<String, dynamic>? deletedMapForUndo}) async {
          // Optimistic update: hapus, edit, atau tambah item agar UI langsung responsif
          if (deletedIndex != null && deletedIndex >= 0 && deletedIndex < _items.length) {
            _items.removeAt(deletedIndex);
            if (mounted) setState(() {});
          }
          if (deletedMapForUndo != null && mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Jadwal dihapus'),
                backgroundColor: Colors.green,
                persist: false,
                action: SnackBarAction(
                  label: 'Batalkan',
                  textColor: Colors.white,
                  onPressed: () => _undoDeleteJadwal(deletedMapForUndo),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
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
          await _loadJadwal(forceFromServer: true);
          // Merge: jika server belum punya (eventual consistency), pertahankan item
          if (newItem != null && mounted) {
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
        },
        editScheduleIndex: editIndex,
        initialOrigin: editItem?.tujuanAwal ?? duplicateFromItem?.tujuanAwal,
        initialDest: editItem?.tujuanAkhir ?? duplicateFromItem?.tujuanAkhir,
        initialJam: editItem?.jam ?? duplicateFromItem?.jam,
        initialRoutePolyline: editItem?.routePolyline ?? duplicateFromItem?.routePolyline,
        initialRouteCategory: editItem?.routeCategory ?? duplicateFromItem?.routeCategory,
        isDriverVerified: widget.isDriverVerified,
        onVerificationRequired: widget.onVerificationRequired,
        otherScheduleTimesOnDate: otherTimes,
      ),
    ).then((_) {
      formSaving.dispose();
    });
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onFabTambahJadwalTapped(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah jadwal'),
      ),
      body: SafeArea(
        child: _showLoadingSpinner
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
                                  const SizedBox(height: 48),
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 64,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _loading ? 'Memuat jadwal...' : 'Belum ada jadwal tersimpan',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Text(
                                      'Tap tombol + di bawah untuk menambah jadwal rute travel. Maksimal 4 jadwal per tanggal.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await _loadJadwal(forceFromServer: true);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Jadwal lewat telah dibersihkan'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                                    label: const Text('Bersihkan jadwal lewat'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Ringkasan jadwal
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.summarize_outlined,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _countJadwalHariIni() > 0
                                              ? '${_countJadwalHariIni()} jadwal hari ini'
                                              : '${_countJadwalMingguIni()} jadwal minggu ini',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Pengingat: jadwal dalam 2 jam
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
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.orange.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.notifications_active, color: Colors.orange.shade700, size: 24),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Pengingat: Jadwal $timeLabel lagi',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.orange.shade900,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${_formatTime(upcoming.jam)} • ${upcoming.tujuanAwal} → ${upcoming.tujuanAkhir}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.orange.shade800,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  // Chip tanggal untuk loncat cepat
                                  SizedBox(
                                    height: 40,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _groupedByDate().length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.swipe_rounded,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Geser untuk pindah tanggal',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.only(
                                            bottom: 24,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                  bottom: 16,
                                                ),
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
                                                        borderRadius:
                                                            BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        _formatDateWithDay(date),
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w600,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .primary,
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
                                  // Page dots
                                  if (_groupedByDate().length > 1) ...[
                                    const SizedBox(height: 12),
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
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      shadowColor: colorScheme.onSurface.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baris 1: Jam menonjol + badge status + edit
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: timePassed
                          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.2)
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
                FutureBuilder<
                    ({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
                  future: () {
                    final (id, legacy) = _scheduleIdPairForItem(item);
                    return OrderService.getScheduledBookingCounts(
                      id,
                      legacyScheduleId: legacy,
                    );
                  }(),
                  builder: (context, snap) {
                    final counts = snap.data;
                    final hasBookings =
                        ((counts?.totalPenumpang ?? 0) +
                            (counts?.kirimBarangCount ?? 0)) >
                        0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!timePassed && !hasBookings)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            tooltip: 'Hapus jadwal',
                            onPressed: () => _onHapusJadwalFromCard(item, index),
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
                          tooltip: hasBookings
                              ? 'Pada tanggal ini sudah ada yang pesan. Batalkan pesanan dulu untuk mengubah jadwal.'
                              : 'Edit jadwal',
                          onPressed: () =>
                              _onEditJadwalTapped(item, index, hasBookings),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                      ],
                    );
                  },
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
                final disableByHomeRoute =
                    widget.disableRouteIconForToday &&
                    _dateOnly(item.tanggal) == _today;
                final routeAvailable = _isRuteAvailableForJadwal(item);
                final bool routeEnabled = !timePassed;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRuteButton(
                        enabled: routeEnabled,
                        routeAvailable: routeAvailable,
                        disableByHomeRoute: disableByHomeRoute,
                        timePassed: timePassed,
                        item: item,
                      ),
                      const SizedBox(width: 8),
                      _buildPemesanChip(item: item, timePassed: timePassed),
                      const SizedBox(width: 6),
                      _buildBarangChip(item: item, timePassed: timePassed),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuteButton({
    required bool enabled,
    required bool routeAvailable,
    required bool disableByHomeRoute,
    required bool timePassed,
    required _JadwalItem item,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: enabled && routeAvailable && !disableByHomeRoute
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled
            ? () {
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
                if (routeAvailable) {
                  widget.onOpenRuteFromJadwal?.call(
                    item.tujuanAwal,
                    item.tujuanAkhir,
                    _scheduleIdForItem(item),
                    item.routePolyline,
                    item.routeCategory,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Rute tersedia mulai 4 jam sebelum jam keberangkatan (${_formatTime(item.jam)}) pada hari H.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_rounded,
                size: 18,
                color: enabled && routeAvailable && !disableByHomeRoute
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Rute',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled && routeAvailable && !disableByHomeRoute
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPemesanChip({
    required _JadwalItem item,
    required bool timePassed,
  }) {
    final (scheduleId, legacyScheduleId) = _scheduleIdPairForItem(item);
    return FutureBuilder<
        ({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
      future: OrderService.getScheduledBookingCounts(
        scheduleId,
        legacyScheduleId: legacyScheduleId,
      ),
      builder: (context, snap) {
        final n = snap.data?.totalPenumpang ?? 0;
        final hasBadge = n > 0;
        return _buildBaris3Chip(
          icon: Icons.people_outline_rounded,
          label: 'Pemesan',
          enabled: !timePassed,
          onTap: () => _showPemesanSheet(scheduleId),
          badgeCount: hasBadge ? n : null,
        );
      },
    );
  }

  Widget _buildBarangChip({
    required _JadwalItem item,
    required bool timePassed,
  }) {
    final (scheduleId, legacyScheduleId) = _scheduleIdPairForItem(item);
    return FutureBuilder<
        ({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
      future: OrderService.getScheduledBookingCounts(
        scheduleId,
        legacyScheduleId: legacyScheduleId,
      ),
      builder: (context, snap) {
        final n = snap.data?.kirimBarangCount ?? 0;
        final hasBadge = n > 0;
        return _buildBaris3Chip(
          icon: Icons.inventory_2_outlined,
          label: 'Barang',
          enabled: !timePassed,
          onTap: () => _showBarangSheet(scheduleId),
          badgeCount: hasBadge ? n : null,
        );
      },
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = _auth.currentUser;
    if (user == null) return;
    const timeout = Duration(seconds: 20);
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get(GetOptions(source: Source.server))
          .timeout(timeout, onTimeout: () => throw TimeoutException('Koneksi timeout.'));
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
      final targetDate = DateTime(item.tanggal.year, item.tanggal.month, item.tanggal.day);
      int? docIndex;
      for (var i = 0; i < schedules.length; i++) {
        final m = schedules[i] as Map<String, dynamic>;
        final dateStamp = m['date'] as Timestamp?;
        final depStamp = m['departureTime'] as Timestamp?;
        if (dateStamp == null || depStamp == null) continue;
        final d = dateStamp.toDate();
        final scheduleDate = DateTime(d.year, d.month, d.day);
        if (scheduleDate != targetDate) continue;
        final dep = depStamp.toDate();
        if (dep.hour == item.jam.hour &&
            dep.minute == item.jam.minute &&
            (m['origin'] as String? ?? '').trim() == item.tujuanAwal &&
            (m['destination'] as String? ?? '').trim() == item.tujuanAkhir) {
          docIndex = i;
          break;
        }
      }
      if (docIndex == null && index >= 0 && index < schedules.length) {
        docIndex = index;
      }
      if (docIndex != null && docIndex >= 0 && docIndex < schedules.length) {
        final deletedMap = Map<String, dynamic>.from(schedules[docIndex] as Map<dynamic, dynamic>);
        schedules.removeAt(docIndex);
        await _firestore.collection('driver_schedules').doc(user.uid).set({
          'schedules': schedules,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(timeout, onTimeout: () => throw TimeoutException('Hapus timeout.'));
        if (mounted) {
          _items.removeAt(index);
          setState(() {});
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          scaffoldMessenger.clearSnackBars();
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: const Text('Jadwal dihapus'),
              backgroundColor: Colors.green,
              persist: false,
              action: SnackBarAction(
                label: 'Batalkan',
                textColor: Colors.white,
                onPressed: () => _undoDeleteJadwal(deletedMap),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Jadwal tidak ditemukan. Coba refresh.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException ? 'Koneksi timeout. Cek jaringan.' : 'Gagal hapus: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _undoDeleteJadwal(Map<String, dynamic> deletedMap) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get(GetOptions(source: Source.server));
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
      schedules.add(deletedMap);
      await _firestore.collection('driver_schedules').doc(user.uid).set({
        'schedules': schedules,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        await _loadJadwal(forceFromServer: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Jadwal dikembalikan'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengembalikan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onEditJadwalTapped(_JadwalItem item, int index, bool hasBookings) {
    if (hasBookings) {
      final scheduleId = _scheduleIdForItem(item);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tidak dapat mengubah jadwal'),
          content: const Text(
            'Pada tanggal ini sudah ada yang pesan. Jika ingin mengubah jadwal, pesanan di tanggal tersebut dengan penumpang dibatalkan dulu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showPemesanSheet(scheduleId);
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

  void _showPemesanSheet(String scheduleId) {
    final uid = _auth.currentUser?.uid ?? '';
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
        driverUid: uid,
        title: 'Penumpang yang sudah pesan',
        travelOnly: true,
      ),
    );
  }

  void _showBarangSheet(String scheduleId) {
    final uid = _auth.currentUser?.uid ?? '';
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ScheduledPassengersSheet(
        scheduleId: scheduleId,
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
class _ScheduledPassengersSheet extends StatelessWidget {
  final String scheduleId;
  final String driverUid;
  final String title;
  final bool? travelOnly;
  final bool? kirimBarangOnly;

  const _ScheduledPassengersSheet({
    required this.scheduleId,
    required this.driverUid,
    required this.title,
    this.travelOnly,
    this.kirimBarangOnly,
  });

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
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<OrderModel>>(
              future: OrderService.getScheduledOrdersForSchedule(
                scheduleId,
                travelOnly: travelOnly,
                kirimBarangOnly: kirimBarangOnly,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Belum ada yang pesan',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                final pickedUpTravel = travelOnly == true
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
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                                currentScheduleId: scheduleId,
                                driverUid: driverUid,
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

  @override
  void initState() {
    super.initState();
    _routeButtonKeys = List.generate(
      widget.alternatives.length,
      (_) => GlobalKey(),
    );
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
    _fitBounds();
  }

  void _fitBounds() {
    if (widget.alternatives.isEmpty || _mapController == null) return;
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final r in widget.alternatives) {
      for (final p in r.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    if (minLat == double.infinity) return;
    final spanLat = maxLat - minLat;
    final spanLng = maxLng - minLng;
    const minZoom = 10.0;
    if (spanLat > 0.1 || spanLng > 0.1) {
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
          80,
        ),
      );
    }
  }

  void _onMapTap(LatLng position) {
    if (widget.alternatives.isEmpty) return;
    double minDistance = double.infinity;
    int closestIndex = -1;
    const threshold = 500000.0;
    for (int i = 0; i < widget.alternatives.length; i++) {
      final d = RouteUtils.distanceToPolyline(
        position,
        widget.alternatives[i].points,
      );
      if (d < minDistance && d < threshold) {
        minDistance = d;
        closestIndex = i;
      }
    }
    if (closestIndex >= 0 && mounted) {
      setState(() {
        _selectedIndex = closestIndex;
        _scrollToSelectedRoute();
      });
    }
  }

  void _selectRoute(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _scrollToSelectedRoute();
    });
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};
    for (int i = 0; i < widget.alternatives.length; i++) {
      final r = widget.alternatives[i];
      if (r.points.isEmpty) continue;
      final color = routeColorForIndex(i);
      polylines.add(
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: r.points,
          color: color,
          width: _selectedIndex == i ? 7 : 5,
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alternatives.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pilih rute')),
        body: const Center(child: Text('Rute tidak ditemukan.')),
      );
    }
    final first = widget.alternatives.first;
    final origin = first.points.isNotEmpty ? first.points.first : const LatLng(0, 0);
    final dest = first.points.isNotEmpty ? first.points.last : origin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih rute'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          StyledGoogleMapBuilder(
            builder: (style, _) => GoogleMap(
              initialCameraPosition: CameraPosition(
                target: origin,
                zoom: MapStyleService.defaultZoom,
                tilt: MapStyleService.defaultTilt,
              ),
              onMapCreated: _onMapCreated,
              mapType: MapType.normal,
              style: style,
              mapToolbarEnabled: false,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              polylines: _buildPolylines(),
              markers: {
                Marker(
                  markerId: const MarkerId('origin'),
                  position: origin,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                ),
                Marker(
                  markerId: const MarkerId('dest'),
                  position: dest,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                ),
              },
            ),
          ),
          // Tombol zoom in/out (di atas)
          Positioned(
            top: 80,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
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
              ],
            ),
          ),
          // Tombol Lokasi saya
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
          // Overlay tap: bypass Polyline.onTap yang bermasalah di Android/iOS
          if (_mapController != null)
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
          // Petunjuk + tombol konfirmasi (tombol rute di dalam card)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tombol pilih rute (Rute 1, 2, 3) di dalam card - geser kanan/kiri jika banyak
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
                                  color: Colors.transparent,
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
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Rute ${i + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        r.distanceText,
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
                        // Gradient edge kanan - hint ada rute lain di sebelah kanan
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
                      'Tap tombol atau garis di peta untuk ganti rute.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            child: const Text('Kembali', overflow: TextOverflow.ellipsis, maxLines: 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _selectedIndex >= 0
                                ? () => Navigator.pop(
                                      context,
                                      widget.alternatives[_selectedIndex].points,
                                    )
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
        ],
      ),
    );
  }
}

/// Form isi jadwal: tujuan awal (dengan icon lokasi + autocomplete), tujuan akhir (autocomplete), jam, simpan.
/// Jika [editScheduleIndex] != null, form untuk edit dan simpan akan update jadwal di index tersebut.
class _AturJadwalFormContent extends StatefulWidget {
  final DateTime date;
  final String Function(DateTime) formatDateWithDay;
  final String Function(TimeOfDay) formatTime;
  final Future<String?> Function() getCurrentLocationText;
  final String Function(Placemark) formatPlacemark;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final ValueNotifier<bool> formSaving;
  final Future<void> Function(_JadwalItem? newItem, {int? deletedIndex, int? editIndex, Map<String, dynamic>? deletedMapForUndo}) onSaved;
  final int? editScheduleIndex;
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
    this.editScheduleIndex,
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
  List<RecentDestination> _recentDestinations = [];
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
    _loadRecentDestinations();
    _schedulePrefetch();
  }

  void _schedulePrefetch() {
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(const Duration(milliseconds: 800), () {
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

  Future<void> _loadRecentDestinations() async {
    final list = await RecentDestinationService.getListForDriverJadwal();
    if (mounted) setState(() => _recentDestinations = list);
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
            padding: const EdgeInsets.all(20),
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
                if (_recentDestinations.isNotEmpty) ...[
                  Text(
                    'Riwayat cepat',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _recentDestinations.take(5).map((r) {
                      final colorScheme = Theme.of(context).colorScheme;
                      return ActionChip(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
                        label: Text(
                          r.text,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          if (_originController.text.trim().isEmpty) {
                            _originController.text = r.text;
                          } else if (_destController.text.trim().isEmpty) {
                            _destController.text = r.text;
                          } else {
                            _destController.text = r.text;
                          }
                          setState(() {});
                          _invalidatePrefetch();
                          _schedulePrefetch();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
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
                        separatorBuilder: (_, __) =>
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
                  decoration: InputDecoration(
                    labelText: 'Tujuan awal *',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: const OutlineInputBorder(),
                    isDense: true,
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
                        separatorBuilder: (_, __) =>
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
                  decoration: InputDecoration(
                    labelText: 'Tujuan akhir *',
                    hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                    isDense: true,
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _routeCategory,
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
                            style: FilledButton.styleFrom(
                              backgroundColor: canSave
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.5),
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
      final selected = await Navigator.push<List<LatLng>>(
        context,
        MaterialPageRoute(
          builder: (ctx) => _JadwalRoutePreviewScreen(
            alternatives: _prefetchedAlternatives!,
          ),
        ),
      );
      if (mounted && selected != null) {
        setState(() => _selectedRoutePolyline = selected);
      }
      return;
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
            alternatives: alternatives,
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.formSaving.value = true;
    const timeout = Duration(seconds: 20);
    try {
      final doc = await widget.firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get(GetOptions(source: Source.server))
          .timeout(timeout, onTimeout: () => throw TimeoutException('Koneksi timeout.'));
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
      // Cari index yang cocok: by date, time, origin, dest (robust terhadap cache/urutan)
      final origin = (widget.initialOrigin ?? '').trim();
      final dest = (widget.initialDest ?? '').trim();
      final targetDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
      final targetJam = widget.initialJam;
      int? docIndex;
      for (var i = 0; i < schedules.length; i++) {
        final m = schedules[i] as Map<String, dynamic>;
        final dateStamp = m['date'] as Timestamp?;
        final depStamp = m['departureTime'] as Timestamp?;
        if (dateStamp == null || depStamp == null) continue;
        final d = dateStamp.toDate();
        final scheduleDate = DateTime(d.year, d.month, d.day);
        if (scheduleDate != targetDate) continue;
        final dep = depStamp.toDate();
        if (targetJam != null &&
            dep.hour == targetJam.hour &&
            dep.minute == targetJam.minute &&
            (m['origin'] as String? ?? '').trim() == origin &&
            (m['destination'] as String? ?? '').trim() == dest) {
          docIndex = i;
          break;
        }
      }
      if (docIndex == null && editIdx >= 0 && editIdx < schedules.length) {
        docIndex = editIdx;
      }
      if (docIndex != null && docIndex >= 0 && docIndex < schedules.length) {
        final deletedMap = Map<String, dynamic>.from(schedules[docIndex] as Map<dynamic, dynamic>);
        schedules.removeAt(docIndex);
        await widget.firestore.collection('driver_schedules').doc(user.uid).set({
          'schedules': schedules,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(timeout, onTimeout: () => throw TimeoutException('Hapus timeout.'));
        if (mounted) Navigator.pop(context);
        try {
          await widget.onSaved(null, deletedIndex: editIdx, deletedMapForUndo: deletedMap);
        } catch (e) {
          if (kDebugMode) debugPrint('DriverJadwal onSaved after delete: $e');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Jadwal tidak ditemukan. Coba refresh.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e is TimeoutException ? 'Koneksi timeout. Cek jaringan.' : 'Gagal hapus: $e';
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
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (widget.editScheduleIndex == null && scheduleDateStart.isBefore(todayStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa menambah jadwal untuk tanggal yang sudah lewat.'),
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
    if (scheduleDateStart == todayStart && dt.isBefore(DateTime.now())) {
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
    const conflictThresholdMinutes = 120;
    for (final other in widget.otherScheduleTimesOnDate) {
      final otherMin = other.hour * 60 + other.minute;
      final newMin = _jam.hour * 60 + _jam.minute;
      if ((newMin - otherMin).abs() < conflictThresholdMinutes) {
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
    widget.formSaving.value = true;
    const timeout = Duration(seconds: 20);
    try {
      final doc = await widget.firestore
          .collection('driver_schedules')
          .doc(user.uid)
          .get(GetOptions(source: Source.server))
          .timeout(timeout, onTimeout: () => throw TimeoutException('Koneksi timeout. Cek jaringan dan coba lagi.'));
      final List<dynamic> schedules =
          (doc.data()?['schedules'] as List<dynamic>?)
              ?.map(
                (e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
              )
              .toList() ??
          [];
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
      if (editIdx != null && editIdx >= 0 && editIdx < schedules.length) {
        docIndex = editIdx;
      }
      if (docIndex == null && editIdx != null) {
        final targetDate = DateTime(widget.date.year, widget.date.month, widget.date.day);
        final targetJam = widget.initialJam;
        for (var i = 0; i < schedules.length; i++) {
          final m = schedules[i] as Map<String, dynamic>;
          final dateStamp = m['date'] as Timestamp?;
          final depStamp = m['departureTime'] as Timestamp?;
          if (dateStamp == null || depStamp == null) continue;
          final d = dateStamp.toDate();
          final scheduleDate = DateTime(d.year, d.month, d.day);
          if (scheduleDate != targetDate) continue;
          final dep = depStamp.toDate();
          if (targetJam != null &&
              dep.hour == targetJam.hour &&
              dep.minute == targetJam.minute &&
              (m['origin'] as String? ?? '').trim() == origin &&
              (m['destination'] as String? ?? '').trim() == dest) {
            docIndex = i;
            break;
          }
        }
      }
      if (docIndex != null && docIndex >= 0 && docIndex < schedules.length) {
        final existing = schedules[docIndex] as Map<String, dynamic>;
        if (existing['hiddenAt'] != null) {
          newMap['hiddenAt'] = existing['hiddenAt'];
        }
        schedules[docIndex] = newMap;
      } else {
        schedules.add(newMap);
      }
      await widget.firestore.collection('driver_schedules').doc(user.uid).set({
        'schedules': schedules,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(timeout, onTimeout: () => throw TimeoutException('Simpan timeout. Cek jaringan dan coba lagi.'));
      unawaited(RecentDestinationService.addForDriverJadwal(origin));
      unawaited(RecentDestinationService.addForDriverJadwal(dest));
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
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      if (mounted) Navigator.pop(context);
      try {
        await widget.onSaved(newItem, editIndex: editIdx);
      } catch (e) {
        if (kDebugMode) debugPrint('DriverJadwal onSaved after save: $e');
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            docIndex != null
                ? 'Jadwal berhasil diubah.'
                : 'Jadwal berhasil disimpan.',
          ),
          backgroundColor: Colors.green,
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
