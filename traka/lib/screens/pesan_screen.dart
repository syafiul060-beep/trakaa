import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/geocoding_service.dart';

import '../theme/app_theme.dart';
import '../widgets/receiver_contact_picker.dart';
import '../widgets/kirim_barang_pilih_jenis_sheet.dart';
import '../utils/placemark_formatter.dart';
import '../utils/app_logger.dart';
import '../theme/responsive.dart';
import '../services/chat_service.dart';
import '../services/driver_schedule_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/scheduled_drivers_service.dart';
import '../services/recent_destination_service.dart';
import '../services/location_service.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/app_config_service.dart';
import '../services/jarak_kontribusi_schedule_estimate.dart';
import '../services/order_service.dart';
import '../services/passenger_first_chat_message.dart';
import '../services/performance_trace_service.dart';
import '../services/verification_service.dart';
import '../services/app_analytics_service.dart';
import '../models/order_model.dart';
import '../widgets/estimate_loading_dialog.dart';
import '../widgets/passenger_duplicate_pending_order_dialog.dart'
    show
        PassengerDuplicatePendingChoice,
        passengerDuplicatePendingChoiceAnalyticsValue,
        showPassengerDuplicatePendingOrderDialog;
import '../widgets/shimmer_loading.dart';
import '../widgets/lollipop_pin_widgets.dart';
import '../widgets/map_destination_picker_screen.dart';
import 'chat_room_penumpang_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Format alamat singkat: hanya kecamatan dan kabupaten.
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

class PesanScreen extends StatefulWidget {
  /// True jika penumpang boleh pesan (profil lengkap + tidak diblokir permintaan admin).
  final bool isVerified;
  /// Profil verifikasi dasar lengkap (KTP/wajah/HP). Untuk membedakan dialog admin vs lengkapi data.
  final bool profileIsComplete;

  final VoidCallback? onVerificationRequired;

  const PesanScreen({
    super.key,
    this.isVerified = false,
    this.profileIsComplete = true,
    this.onVerificationRequired,
  });

  @override
  State<PesanScreen> createState() => _PesanScreenState();
}

class _PesanScreenState extends State<PesanScreen> {
  /// 'rekomendasi' = tampilan default (jadwal rekomendasi hari ini); 'hasil' = setelah Cari Travel.
  String _viewMode = 'rekomendasi';
  String _searchOrigin = '';
  String _searchDest = '';
  double? _searchOriginLat;
  double? _searchOriginLng;
  double? _searchDestLat;
  double? _searchDestLng;
  /// Provinsi asal/tujuan penumpang (dari placemark) untuk filter kecocokan provinsi.
  String? _searchOriginProvince;
  String? _searchDestProvince;
  DateTime? _resultStartDate;
  final PageController _resultPageController = PageController();
  int _resultPageIndex = 0;
  static const int _resultDaysCount = 31;

  /// Rekomendasi: lokasi penumpang, tanggal, dan daftar jadwal.
  String _recommendationLocationText = 'Mengambil lokasi...';
  DateTime _recommendationDate = DriverScheduleService.todayDateOnlyWib;
  List<ScheduledDriverRoute>? _recommendationList;
  bool _recommendationLoading = true;
  double? _recommendationLat;
  double? _recommendationLng;

  /// Cache jadwal per tanggal. Key: "y-m-d".
  final Map<String, List<Map<String, dynamic>>> _scheduleCache = {};
  final Map<String, bool> _scheduleLoading = {};

  /// Cache driver dengan jadwal yang rutenya melewati (menggunakan logika baru).
  final Map<String, List<ScheduledDriverRoute>> _scheduledDriversCache = {};
  final Map<String, bool> _scheduledDriversLoading = {};

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  @override
  void dispose() {
    _resultPageController.dispose();
    super.dispose();
  }

  static String _dateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadRecommendations({DateTime? forDate}) async {
    final targetDate = forDate ?? _recommendationDate;
    final useCachedLocation = forDate != null && _recommendationLat != null && _recommendationLng != null;

    setState(() {
      _recommendationLoading = true;
      _recommendationDate = targetDate;
      if (!useCachedLocation) {
        _recommendationLocationText = 'Mengambil lokasi...';
      }
      _recommendationList = null;
    });

    double? lat = useCachedLocation ? _recommendationLat : null;
    double? lng = useCachedLocation ? _recommendationLng : null;
    String locationText = _recommendationLocationText;

    if (!useCachedLocation) {
      try {
        final hasPermission = await LocationService.requestPermission();
        if (hasPermission) {
          final result = await LocationService.getCurrentPositionWithMockCheck();
          if (result.isFakeGpsDetected && mounted) {
            FakeGpsOverlayService.showOverlay();
          }
          final pos = result.position;
          if (pos != null) {
            lat = pos.latitude;
            lng = pos.longitude;
            try {
              final placemarks = await GeocodingService.placemarkFromCoordinates(
                lat,
                lng,
              );
              if (placemarks.isNotEmpty) {
                locationText = PlacemarkFormatter.formatDetail(placemarks.first);
              } else {
                locationText = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
              }
            } catch (_) {
              locationText = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
            }
          }
        }

        if (lat == null || lng == null) {
          final recent = await RecentDestinationService.getListForPesanSearch();
          if (recent.isNotEmpty && recent.first.text.trim().length >= 3) {
            final locs = await GeocodingService.locationFromAddress(
              '${recent.first.text}, Indonesia',
              appendIndonesia: false,
            );
            if (locs.isNotEmpty) {
              lat = locs.first.latitude;
              lng = locs.first.longitude;
              locationText = recent.first.text;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PesanScreen._loadRecommendations: $e');
        locationText = 'Gagal mengambil lokasi';
      }
    }

    if (lat != null && lng != null) {
      try {
        final list = await ScheduledDriversService.getRecommendedSchedulesForDate(
          passengerLat: lat,
          passengerLng: lng,
          forDate: targetDate,
          maxCount: 5,
        );
        if (mounted) {
          setState(() {
            _recommendationLocationText = locationText;
            _recommendationLat = lat;
            _recommendationLng = lng;
            _recommendationList = list;
            _recommendationLoading = false;
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('PesanScreen._loadRecommendations: $e');
        if (mounted) {
          setState(() {
            _recommendationList = [];
            _recommendationLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _recommendationLocationText = locationText;
          _recommendationList = [];
          _recommendationLoading = false;
        });
      }
    }
  }

  Future<void> _loadSchedulesForDate(DateTime date) async {
    final key = _dateKey(date);
    if (_scheduleCache.containsKey(key) || _scheduleLoading[key] == true) {
      return;
    }
    _scheduleLoading[key] = true;
    if (mounted) setState(() {});

    // Jika ada koordinat origin dan destination, gunakan logika baru (cek rute yang melewati)
    if (_searchOriginLat != null &&
        _searchOriginLng != null &&
        _searchDestLat != null &&
        _searchDestLng != null) {
      try {
        final scheduledDrivers =
            await ScheduledDriversService.getScheduledDriversForMap(
              date: date,
              passengerOriginLat: _searchOriginLat!,
              passengerOriginLng: _searchOriginLng!,
              passengerDestLat: _searchDestLat!,
              passengerDestLng: _searchDestLng!,
              passengerOriginProvince: _searchOriginProvince,
              passengerDestProvince: _searchDestProvince,
            );

        // Konversi ScheduledDriverRoute ke format Map untuk kompatibilitas dengan UI yang ada
        final list = scheduledDrivers.map((s) {
          return <String, dynamic>{
            'driverUid': s.driverUid,
            'origin': s.scheduleOriginText,
            'destination': s.scheduleDestText,
            'departureTime': Timestamp.fromDate(s.departureTime),
            'date': Timestamp.fromDate(s.scheduleDate),
            'driverName': s.driverName,
            'photoUrl': s.driverPhotoUrl,
            'maxPassengers': s.maxPassengers,
            'vehicleMerek': s.vehicleMerek,
            'vehicleType': s.vehicleType,
            'isVerified': s.isVerified,
          };
        }).toList();

        if (mounted) {
          var resultList = list;
          if (resultList.isEmpty) {
            resultList = await DriverScheduleService.getAllSchedulesForDate(date);
          }
          _scheduleCache[key] = resultList;
          _scheduleLoading[key] = false;
          setState(() {});
        }
      } catch (e) {
        // Jika error, fallback ke logika lama
        if (kDebugMode) debugPrint('PesanScreen._loadSchedulesForDate: Error menggunakan logika baru: $e');
        var list = await DriverScheduleService.getSchedulesByDateAndRoute(
          date,
          _searchOrigin,
          _searchDest,
        );
        if (list.isEmpty) {
          list = await DriverScheduleService.getAllSchedulesForDate(date);
        }
        if (mounted) {
          _scheduleCache[key] = list;
          _scheduleLoading[key] = false;
          setState(() {});
        }
      }
    } else {
      // Fallback: gunakan logika lama jika tidak ada koordinat
      var list = await DriverScheduleService.getSchedulesByDateAndRoute(
        date,
        _searchOrigin,
        _searchDest,
      );
      if (list.isEmpty) {
        list = await DriverScheduleService.getAllSchedulesForDate(date);
      }
      if (mounted) {
        _scheduleCache[key] = list;
        _scheduleLoading[key] = false;
        setState(() {});
      }
    }
  }

  Future<void> _onCariTravel({
    required DateTime selectedDate,
    required String origin,
    required String dest,
  }) async {
    double? originLat;
    double? originLng;
    double? destLat;
    double? destLng;
    String? originProvince;
    String? destProvince;

    try {
      // Geocode origin dan dest paralel agar lebih cepat
      final results = await Future.wait([
        GeocodingService.locationFromAddress(
          '$origin, Indonesia',
          appendIndonesia: false,
        ),
        GeocodingService.locationFromAddress(
          '$dest, Indonesia',
          appendIndonesia: false,
        ),
      ]);
      final originLocations = results[0];
      final destLocations = results[1];

      if (originLocations.isNotEmpty && destLocations.isNotEmpty) {
        originLat = originLocations.first.latitude;
        originLng = originLocations.first.longitude;
        destLat = destLocations.first.latitude;
        destLng = destLocations.first.longitude;
        try {
          // Placemarks paralel untuk provinsi
          final placemarkResults = await Future.wait([
            GeocodingService.placemarkFromCoordinates(originLat, originLng),
            GeocodingService.placemarkFromCoordinates(destLat, destLng),
          ]);
          if (placemarkResults[0].isNotEmpty) {
            originProvince =
                (placemarkResults[0].first.administrativeArea ?? '').trim();
          }
          if (placemarkResults[1].isNotEmpty) {
            destProvince =
                (placemarkResults[1].first.administrativeArea ?? '').trim();
          }
        } catch (_) {}
      }
    } catch (e, st) {
      logError('PesanScreen._onCariTravel geocode', e, st);
    }

    setState(() {
      _viewMode = 'hasil';
      _searchOrigin = origin.trim();
      _searchDest = dest.trim();
      _searchOriginLat = originLat;
      _searchOriginLng = originLng;
      _searchDestLat = destLat;
      _searchDestLng = destLng;
      _searchOriginProvince = originProvince;
      _searchDestProvince = destProvince;
      _resultStartDate = selectedDate;
      _resultPageIndex = 0;
      _scheduleCache.clear();
      _scheduleLoading.clear();
      _scheduledDriversCache.clear();
      _scheduledDriversLoading.clear();
    });
    _resultPageController.jumpToPage(0);
    // Load jadwal dulu; riwayat pencarian di-background (tidak blocking)
    await _loadSchedulesForDate(selectedDate);
  }

  Future<void> _prefetchSchedulesForForm(
    String origin,
    String dest,
    DateTime date,
  ) async {
    if (origin.trim().length < 3 || dest.trim().length < 3) return;
    try {
      final results = await Future.wait([
        GeocodingService.locationFromAddress(
          '$origin, Indonesia',
          appendIndonesia: false,
        ),
        GeocodingService.locationFromAddress(
          '$dest, Indonesia',
          appendIndonesia: false,
        ),
      ]);
      final originLocations = results[0];
      final destLocations = results[1];
      if (originLocations.isEmpty || destLocations.isEmpty) return;
      final originLat = originLocations.first.latitude;
      final originLng = originLocations.first.longitude;
      final destLat = destLocations.first.latitude;
      final destLng = destLocations.first.longitude;
      String? originProvince;
      String? destProvince;
      try {
        final placemarkResults = await Future.wait([
          GeocodingService.placemarkFromCoordinates(originLat, originLng),
          GeocodingService.placemarkFromCoordinates(destLat, destLng),
        ]);
        if (placemarkResults[0].isNotEmpty) {
          originProvince =
              (placemarkResults[0].first.administrativeArea ?? '').trim();
        }
        if (placemarkResults[1].isNotEmpty) {
          destProvince =
              (placemarkResults[1].first.administrativeArea ?? '').trim();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _searchOrigin = origin.trim();
        _searchDest = dest.trim();
        _searchOriginLat = originLat;
        _searchOriginLng = originLng;
        _searchDestLat = destLat;
        _searchDestLng = destLng;
        _searchOriginProvince = originProvince;
        _searchDestProvince = destProvince;
      });
      await _loadSchedulesForDate(date);
    } catch (_) {}
  }

  void _showGantiAsalTujuan() {
    final currentDate = _resultStartDate!.add(Duration(days: _resultPageIndex));
    _openCariRuteForm(initialDate: currentDate);
  }

  void _showCariRuteLain() {
    _openCariRuteForm(initialDate: DriverScheduleService.todayDateOnlyWib);
  }

  void _openCariRuteForm({required DateTime initialDate}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final mediaQuery = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: _FormCariTravel(
              selectedDate: initialDate,
              initialOrigin: _searchOrigin,
              initialDest: _searchDest,
              onCari: (origin, dest, date) async {
                Navigator.of(ctx).pop();
                await _onCariTravel(
                  selectedDate: date,
                  origin: origin,
                  dest: dest,
                );
              },
              onPrefetchRequested: (origin, dest) =>
                  _prefetchSchedulesForForm(origin, dest, initialDate),
            ),
          ),
        );
      },
    );
  }

  /// Satu-satunya pintu penumpang untuk sheet jadwal (rekomendasi + hasil Cari rute lain).
  Future<void> _onPesanJadwal(
    BuildContext context,
    Map<String, dynamic> item,
    String scheduleId,
    String scheduledDate,
    String origin,
    String dest,
  ) async {
    if (!widget.isVerified) {
      if (!widget.profileIsComplete) {
        _showLengkapiVerifikasiDialog();
      } else {
        _showAdminVerificationComplianceDialog();
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    var hasBlockingTravel = false;
    if (user != null) {
      try {
        final orders = await OrderService.getOrdersForPassenger(user.uid);
        hasBlockingTravel =
            OrderService.passengerOrdersContainBlockingTravel(orders);
      } catch (_) {}
    }
    if (!mounted) return;
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PesanJadwalSheet(
        item: item,
        scheduleId: scheduleId,
        scheduledDate: scheduledDate,
        origin: origin,
        dest: dest,
        hasBlockingTravelOrder: hasBlockingTravel,
        onCreated: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showLengkapiVerifikasiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TrakaL10n.of(context).completeVerification),
        content: Text(
          TrakaL10n.of(context).completeDataVerificationPromptPesan,
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
              widget.onVerificationRequired?.call();
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
              widget.onVerificationRequired?.call();
            },
            child: const Text('Ke Profil'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    final start = _resultStartDate!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: context.responsive.spacing(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formatResultDate(start.add(Duration(days: _resultPageIndex))),
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(16),
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showGantiAsalTujuan,
                icon: const Icon(Icons.edit_location_alt, size: 18),
                label: const Text('Ganti asal/tujuan'),
              ),
              TextButton.icon(
                onPressed: _showCariRuteLain,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: const Text('Ubah tanggal'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _resultPageController,
            itemCount: _resultDaysCount,
            onPageChanged: (i) {
              setState(() => _resultPageIndex = i);
              final date = start.add(Duration(days: i));
              _loadSchedulesForDate(date);
            },
            itemBuilder: (context, index) {
              final date = start.add(Duration(days: index));
              return _BuildJadwalListPage(
                date: date,
                origin: _searchOrigin,
                dest: _searchDest,
                scheduleCache: _scheduleCache,
                scheduleLoading: _scheduleLoading,
                loadSchedules: _loadSchedulesForDate,
                dateKey: _dateKey,
                onPesan: _onPesanJadwal,
                onCariTanggalLain: _showCariRuteLain,
                onGantiAsalTujuan: _showGantiAsalTujuan,
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatResultDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 8),
            Text(
              'Pesan Travel Terjadwal',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: _viewMode == 'rekomendasi'
            ? _buildRecommendationView()
            : _buildResultView(),
      ),
    );
  }

  String _formatRecommendationDateLabel(DateTime d) {
    final today = DriverScheduleService.todayDateOnlyWib;
    final dOnly = DateTime(d.year, d.month, d.day);
    final diff = dOnly.difference(today).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Besok';
    if (diff == 2) return 'Lusa';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${d.day} ${months[d.month - 1]}';
  }

  Widget _buildDateChip(DateTime date, String label) {
    final isSelected = _recommendationDate.year == date.year &&
        _recommendationDate.month == date.month &&
        _recommendationDate.day == date.day;
    final colorScheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (_) {
        _loadRecommendations(forDate: date);
      },
      selectedColor: colorScheme.primaryContainer,
      checkmarkColor: colorScheme.primary,
    );
  }

  Widget _buildRecommendationView() {
    final today = DriverScheduleService.todayDateOnlyWib;

    return Padding(
      padding: EdgeInsets.all(context.responsive.horizontalPadding),
      child: RefreshIndicator(
        onRefresh: () => _loadRecommendations(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recommendationLocationText,
                      style: TextStyle(
                        fontSize: context.responsive.fontSize(14),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _recommendationLoading ? null : () => _loadRecommendations(),
                    icon: const Icon(Icons.refresh, size: 22),
                    tooltip: 'Perbarui lokasi',
                  ),
                ],
              ),
              SizedBox(height: context.responsive.spacing(16)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildDateChip(today, 'Hari ini'),
                  _buildDateChip(today.add(const Duration(days: 1)), 'Besok'),
                  _buildDateChip(today.add(const Duration(days: 2)), 'Lusa'),
                ],
              ),
              SizedBox(height: context.responsive.spacing(16)),
              Text(
                'Jadwal rekomendasi ${_formatRecommendationDateLabel(_recommendationDate)}',
                style: TextStyle(
                  fontSize: context.responsive.fontSize(16),
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: context.responsive.spacing(12)),
              if (_recommendationLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: ShimmerLoading()),
                )
              else if (_recommendationList == null || _recommendationList!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tidak ada jadwal rekomendasi di dekat Anda',
                        style: TextStyle(
                          fontSize: context.responsive.fontSize(15),
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cari jadwal di rute atau tanggal lain.',
                        style: TextStyle(
                          fontSize: context.responsive.fontSize(13),
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ...(_recommendationList!.map((s) {
                  final item = <String, dynamic>{
                    'driverUid': s.driverUid,
                    'origin': s.scheduleOriginText,
                    'destination': s.scheduleDestText,
                    'departureTime': Timestamp.fromDate(s.departureTime),
                    'date': Timestamp.fromDate(s.scheduleDate),
                    'driverName': s.driverName,
                    'photoUrl': s.driverPhotoUrl,
                    'maxPassengers': s.maxPassengers,
                    'vehicleMerek': s.vehicleMerek,
                    'vehicleType': s.vehicleType,
                    'isVerified': s.isVerified,
                  };
                  final keyStr = _dateKey(DateTime(
                    _recommendationDate.year,
                    _recommendationDate.month,
                    _recommendationDate.day,
                  ));
                  final (scheduleId, legacyScheduleId) = ScheduleIdUtil.build(
                    s.driverUid,
                    keyStr,
                    s.departureTime.millisecondsSinceEpoch,
                    s.scheduleOriginText,
                    s.scheduleDestText,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildRecommendationCard(
                      item: item,
                      scheduleId: scheduleId,
                      legacyScheduleId: legacyScheduleId,
                      scheduledDate: keyStr,
                      origin: s.scheduleOriginText,
                      dest: s.scheduleDestText,
                    ),
                  );
                })),
              SizedBox(height: context.responsive.spacing(24)),
              FilledButton.tonalIcon(
                onPressed: _showCariRuteLain,
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Cari rute lain'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard({
    required Map<String, dynamic> item,
    required String scheduleId,
    required String legacyScheduleId,
    required String scheduledDate,
    required String origin,
    required String dest,
  }) {
    final depStamp = item['departureTime'] as Timestamp?;
    final timeStr = depStamp != null
        ? '${depStamp.toDate().hour.toString().padLeft(2, '0')}:${depStamp.toDate().minute.toString().padLeft(2, '0')}'
        : '–';
    final driverName = (item['driverName'] as String?) ?? 'Driver';
    final photoUrl = item['photoUrl'] as String?;
    final maxPassengers = (item['maxPassengers'] as num?)?.toInt();

    return FutureBuilder<({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
      future: OrderService.getScheduledBookingCounts(
        scheduleId,
        legacyScheduleId: legacyScheduleId,
      ),
      builder: (context, snap) {
        final counts = snap.data ??
            (totalPenumpang: 0, kirimBarangCount: 0, kargoCount: 0);
        final sisa = maxPassengers != null && maxPassengers > 0
            ? (maxPassengers - counts.totalPenumpang).clamp(0, maxPassengers)
            : null;

        return Card(
          child: InkWell(
            onTap: () => _onPesanJadwal(
              context,
              item,
              scheduleId,
              scheduledDate,
              origin,
              dest,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                driverName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item['isVerified'] == true)
                              Icon(Icons.verified, size: 18, color: Colors.green.shade700),
                            if (sisa != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sisa > 0
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  sisa > 0 ? '$sisa/$maxPassengers kursi' : 'Penuh',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: sisa > 0
                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                        : Theme.of(context).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                    Text(
                      '${_formatAlamatKecamatanKabupaten(origin)} → ${_formatAlamatKecamatanKabupaten(dest)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Jam: $timeStr',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

}

/// Form dalam bottom sheet: Tanggal (DatePicker), Awal tujuan, Tujuan travel, tombol Cari Jadwal.
class _FormCariTravel extends StatefulWidget {
  final DateTime selectedDate;
  final void Function(String origin, String dest, DateTime date) onCari;
  final String? initialOrigin;
  final String? initialDest;
  final void Function(String origin, String dest)? onPrefetchRequested;

  const _FormCariTravel({
    required this.selectedDate,
    required this.onCari,
    this.initialOrigin,
    this.initialDest,
    this.onPrefetchRequested,
  });

  @override
  State<_FormCariTravel> createState() => _FormCariTravelState();
}

class _FormCariTravelState extends State<_FormCariTravel> {
  late final TextEditingController _originController;
  late final TextEditingController _destController;
  late DateTime _pickedDate;
  bool _loadingLocation = false;
  List<Placemark> _originResults = [];
  bool _showOrigin = false;
  List<Placemark> _destResults = [];
  bool _showDest = false;
  Timer? _prefetchDebounce;

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(text: widget.initialOrigin ?? '');
    _destController = TextEditingController(text: widget.initialDest ?? '');
    _pickedDate = widget.selectedDate;
    _schedulePrefetch();
  }

  void _schedulePrefetch() {
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(const Duration(milliseconds: 800), () {
      final o = _originController.text.trim();
      final d = _destController.text.trim();
      if (o.length >= 3 && d.length >= 3 && widget.onPrefetchRequested != null) {
        widget.onPrefetchRequested!(o, d);
      }
    });
  }

  @override
  void dispose() {
    _prefetchDebounce?.cancel();
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  static String _formatPlacemark(Placemark p) =>
      PlacemarkFormatter.formatDetail(p);

  Future<void> _searchOrigin(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _originResults = [];
        _showOrigin = false;
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_originController.text.trim() != query) return;
    try {
      final locations = await GeocodingService.locationFromAddress(
        '$query, Indonesia',
        appendIndonesia: false,
      );
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 8; i++) {
        try {
          final list = await GeocodingService.placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (_originController.text.trim() != query) return;
      setState(() {
        _originResults = placemarks;
        _showOrigin = placemarks.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _originResults = [];
          _showOrigin = false;
        });
      }
    }
  }

  Future<void> _searchDest(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _destResults = [];
        _showDest = false;
      });
      return;
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_destController.text.trim() != query) return;
    try {
      final locations = await GeocodingService.locationFromAddress(
        '$query, Indonesia',
        appendIndonesia: false,
      );
      final placemarks = <Placemark>[];
      for (var i = 0; i < locations.length && i < 8; i++) {
        try {
          final list = await GeocodingService.placemarkFromCoordinates(
            locations[i].latitude,
            locations[i].longitude,
          );
          if (list.isNotEmpty) placemarks.add(list.first);
        } catch (_) {}
      }
      if (!mounted) return;
      if (_destController.text.trim() != query) return;
      setState(() {
        _destResults = placemarks;
        _showDest = placemarks.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _destResults = [];
          _showDest = false;
        });
      }
    }
  }

  Future<void> _fillCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final hasPermission = await LocationService.requestPermission();
      if (!hasPermission || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin lokasi diperlukan. Aktifkan di pengaturan.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _loadingLocation = false);
        return;
      }
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) FakeGpsOverlayService.showOverlay();
        setState(() => _loadingLocation = false);
        return;
      }
      final position = result.position;
      if (position == null || !mounted) {
        setState(() => _loadingLocation = false);
        return;
      }
      final placemarks = await GeocodingService.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[];
        if ((p.name ?? '').isNotEmpty) parts.add(p.name!);
        if ((p.thoroughfare ?? '').isNotEmpty) parts.add(p.thoroughfare!);
        if ((p.subLocality ?? '').isNotEmpty) parts.add(p.subLocality!);
        if ((p.administrativeArea ?? '').isNotEmpty) {
          parts.add(p.administrativeArea!);
        }
        if (parts.isNotEmpty) {
          _originController.text = parts.join(', ');
        } else {
          _originController.text =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      } else if (mounted) {
        _originController.text =
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      }
      if (mounted) _schedulePrefetch();
    } catch (e, st) {
      logError('PesanScreen._fillCurrentLocation', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TrakaL10n.of(context).failedToGetLocation),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _loadingLocation = false);
  }

  Future<void> _pickTujuanAwalOnMap() async {
    final t = _originController.text.trim();
    var initial = const LatLng(-6.2088, 106.8456);
    if (t.length >= 3) {
      try {
        final locs = await GeocodingService.locationFromAddress(
          '$t, Indonesia',
          appendIndonesia: false,
        );
        if (locs.isNotEmpty) {
          initial = LatLng(locs.first.latitude, locs.first.longitude);
        }
      } catch (_) {}
    }
    LatLng? device;
    try {
      final hasPermission = await LocationService.requestPermission();
      if (hasPermission) {
        final result = await LocationService.getCurrentPositionWithMockCheck();
        if (!result.isFakeGpsDetected && result.position != null) {
          device = LatLng(
            result.position!.latitude,
            result.position!.longitude,
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapDestinationPickerScreen(
          initialCameraTarget: initial,
          deviceLocation: device,
          title: TrakaL10n.of(context).pickOriginOnMapActionLabel,
          pinVariant: LollipopPinVariant.origin,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _originController.text = r.label;
      _originResults = [];
      _showOrigin = false;
    });
    _schedulePrefetch();
  }

  Future<void> _pickTujuanAkhirOnMap() async {
    final t = _destController.text.trim();
    var initial = const LatLng(-6.2088, 106.8456);
    if (t.length >= 3) {
      try {
        final locs = await GeocodingService.locationFromAddress(
          '$t, Indonesia',
          appendIndonesia: false,
        );
        if (locs.isNotEmpty) {
          initial = LatLng(locs.first.latitude, locs.first.longitude);
        }
      } catch (_) {}
    }
    LatLng? device;
    try {
      final hasPermission = await LocationService.requestPermission();
      if (hasPermission) {
        final result = await LocationService.getCurrentPositionWithMockCheck();
        if (!result.isFakeGpsDetected && result.position != null) {
          device = LatLng(
            result.position!.latitude,
            result.position!.longitude,
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapDestinationPickerScreen(
          initialCameraTarget: initial,
          deviceLocation: device,
          title: TrakaL10n.of(context).pickOnMapActionLabel,
          pinVariant: LollipopPinVariant.destination,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _destController.text = r.label;
      _destResults = [];
      _showDest = false;
    });
    _schedulePrefetch();
  }

  void _submit() {
    final origin = _originController.text.trim();
    final dest = _destController.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).fillOriginAndDestinationPesan),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onCari(origin, dest, _pickedDate);
  }

  Future<void> _pickDate() async {
    final first = DriverScheduleService.todayDateOnlyWib;
    final last = DriverScheduleService.lastScheduleDateInclusiveWib;
    var initial = DateTime(_pickedDate.year, _pickedDate.month, _pickedDate.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Tanggal keberangkatan (WIB, sesuai jendela jadwal driver)',
    );
    if (picked != null && mounted) {
      setState(() => _pickedDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxFormHeight = mediaQuery.size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxFormHeight),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            left: context.responsive.horizontalPadding,
            right: context.responsive.horizontalPadding,
            top: context.responsive.spacing(24),
            bottom: bottomInset + context.responsive.spacing(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Tanggal: ${_pickedDate.day} ${months[_pickedDate.month - 1]} ${_pickedDate.year}',
                        style: TextStyle(
                          fontSize: context.responsive.fontSize(16),
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.edit_calendar,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_showOrigin && _originResults.isNotEmpty)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: bottomInset > 0 ? 160 : 220,
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
                            _formatPlacemark(p),
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _originController.text = _formatPlacemark(p);
                            setState(() {
                              _originResults = [];
                              _showOrigin = false;
                            });
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
                  labelText: 'Awal tujuan',
                  hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 8, right: 4),
                    child: LollipopPinFormIcon(
                      variant: LollipopPinVariant.origin,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 40,
                  ),
                  suffixIcon: IconButton(
                    icon: _loadingLocation
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    onPressed: _loadingLocation ? null : _fillCurrentLocation,
                    tooltip: 'Gunakan lokasi saat ini',
                  ),
                ),
                onChanged: (v) {
                  _searchOrigin(v);
                  _schedulePrefetch();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickTujuanAwalOnMap,
                  icon: const Icon(Icons.map_outlined, size: 20),
                  label: Text(TrakaL10n.of(context).pickOriginOnMapActionLabel),
                ),
              ),
              const SizedBox(height: 12),
              if (_showDest && _destResults.isNotEmpty)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: bottomInset > 0 ? 160 : 220,
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
                            _formatPlacemark(p),
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            _destController.text = _formatPlacemark(p);
                            setState(() {
                              _destResults = [];
                              _showDest = false;
                            });
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
                  labelText: 'Tujuan travel',
                  hintText: 'Stasiun, Mall, Bandara, Rumah Sakit, Perumahan, Terminal, Pelabuhan, Alun-alun',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 8, right: 4),
                    child: LollipopPinFormIcon(
                      variant: LollipopPinVariant.destination,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 40,
                  ),
                ),
                onChanged: (v) {
                  _searchDest(v);
                  _schedulePrefetch();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickTujuanAkhirOnMap,
                  icon: const Icon(Icons.map_outlined, size: 20),
                  label: Text(TrakaL10n.of(context).pickOnMapActionLabel),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cari Jadwal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet pilihan: Pesan Travel Sendiri / dengan Kerabat / Kirim Barang (untuk jadwal).
class _PesanJadwalSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String scheduleId;
  final String scheduledDate;
  final String origin;
  final String dest;
  /// Travel `agreed`/`picked_up` — nonaktifkan opsi travel di sheet; kirim barang tetap.
  final bool hasBlockingTravelOrder;
  final VoidCallback onCreated;

  const _PesanJadwalSheet({
    required this.item,
    required this.scheduleId,
    required this.scheduledDate,
    required this.origin,
    required this.dest,
    this.hasBlockingTravelOrder = false,
    required this.onCreated,
  });

  @override
  State<_PesanJadwalSheet> createState() => _PesanJadwalSheetState();
}

class _PesanJadwalSheetState extends State<_PesanJadwalSheet> {
  bool _loading = false;

  static String _formatScheduledDate(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
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
    final d = int.tryParse(parts[2]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 1;
    final y = parts[0];
    if (m < 1 || m > 12) return ymd;
    return '$d ${months[m - 1]} $y';
  }

  Future<void> _createAndOpenChat({
    required String orderType,
    int? jumlahKerabat,
    bool bypassDuplicatePendingTravel = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_loading) return;

    if (widget.hasBlockingTravelOrder && orderType == OrderModel.typeTravel) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TrakaL10n.of(context).scheduleTravelBlockedWhileTravelAgreed,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final driverUidEarly = widget.item['driverUid'] as String? ?? '';

    if (orderType == OrderModel.typeTravel && !bypassDuplicatePendingTravel) {
      final pendingT = await OrderService.getPassengerPendingTravelWithDriver(
        user.uid,
        driverUidEarly,
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
          surface: 'scheduled_pesan',
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
                driverUid: driverUidEarly,
                driverName: (widget.item['driverName'] as String?) ?? 'Driver',
                driverPhotoUrl: widget.item['photoUrl'] as String?,
                driverVerified: widget.item['isVerified'] as bool? ?? false,
              ),
            ),
          );
          return;
        }
        if (choice == PassengerDuplicatePendingChoice.forceNew) {
          await _createAndOpenChat(
            orderType: orderType,
            jumlahKerabat: jumlahKerabat,
            bypassDuplicatePendingTravel: true,
          );
        }
        return;
      }
    }

    setState(() => _loading = true);

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
    final passengerNameResolved = passengerName ?? user.email ?? 'Penumpang';

    final driverUid = driverUidEarly;
    final driverName = (widget.item['driverName'] as String?) ?? 'Driver';
    final driverPhotoUrl = widget.item['photoUrl'] as String?;
    final dateLabel = _formatScheduledDate(widget.scheduledDate);

    final orderId = await PerformanceTraceService.traceOrderSubmit<String?>(
      () => OrderService.createOrder(
        passengerUid: user.uid,
        driverUid: driverUid,
        routeJourneyNumber: OrderService.routeJourneyNumberScheduled,
        passengerName: passengerNameResolved,
        passengerPhotoUrl: passengerPhotoUrl,
        passengerAppLocale: passengerAppLocale,
        originText: widget.origin,
        destText: widget.dest,
        originLat: null,
        originLng: null,
        destLat: null,
        destLng: null,
        orderType: orderType,
        jumlahKerabat: jumlahKerabat,
        scheduleId: widget.scheduleId,
        scheduledDate: widget.scheduledDate,
        bypassDuplicatePendingTravel:
            orderType == OrderModel.typeTravel && bypassDuplicatePendingTravel,
      ),
    );

    if (!mounted) return;
    AppAnalyticsService.logOrderCreated(
      orderType: orderType,
      success: orderId != null,
    );
    if (orderId == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).failedToCreateOrder),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = false);
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    final estimateLines = await runWithEstimateLoading<String>(
      context,
      l10n,
      () => JarakKontribusiScheduleEstimate.chatBlockFromAddressTexts(
        originText: widget.origin,
        destText: widget.dest,
        l10n: l10n,
        orderType: orderType,
        jumlahKerabat: jumlahKerabat,
      ),
    );
    if (!mounted) return;

    widget.onCreated();

    String jenisPesanan;
    if (orderType == OrderModel.typeKirimBarang) {
      jenisPesanan = 'Saya ingin mengirim barang (terjadwal).';
    } else if (jumlahKerabat == null || jumlahKerabat <= 0) {
      jenisPesanan = 'Saya ingin memesan tiket travel untuk 1 orang.';
    } else {
      jenisPesanan =
          'Saya ingin memesan tiket travel untuk ${1 + jumlahKerabat} orang (dengan kerabat).';
    }

    final message = PassengerFirstChatMessage.travel(
      driverName: driverName,
      jenisBaris: jenisPesanan,
      asal: widget.origin,
      tujuan: widget.dest,
      tanggalJadwalLabel: dateLabel,
      jarakKontribusiLines: estimateLines,
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPenumpangScreen(
          orderId: orderId,
          driverUid: driverUid,
          driverName: driverName,
          driverPhotoUrl: driverPhotoUrl,
          driverVerified: widget.item['isVerified'] as bool? ?? false,
          sendJenisPesananMessage: message,
        ),
      ),
    );
    if (orderType == OrderModel.typeTravel && bypassDuplicatePendingTravel) {
      _showNewSplitOrderThreadSnackJadwal();
    }
  }

  void _showNewSplitOrderThreadSnackJadwal() {
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

  void _showKirimBarangLinkReceiverSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final driverUid = widget.item['driverUid'] as String? ?? '';
    if (driverUid.isEmpty) return;

    var bypassKbDuplicate = false;
    final existing =
        await OrderService.getPassengerPendingKirimBarangWithDriver(
      user.uid,
      driverUid,
    );
    if (!mounted) return;
    if (existing != null) {
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
        surface: 'jadwal_kirim_sheet',
      );
      if (choice == null || choice == PassengerDuplicatePendingChoice.cancel) {
        return;
      }
      if (choice == PassengerDuplicatePendingChoice.openExisting) {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ChatRoomPenumpangScreen(
              orderId: existing.id,
              driverUid: driverUid,
              driverName: (widget.item['driverName'] as String?) ?? 'Driver',
              driverPhotoUrl: widget.item['photoUrl'] as String?,
              driverVerified: widget.item['isVerified'] as bool? ?? false,
            ),
          ),
        );
        return;
      }
      if (choice == PassengerDuplicatePendingChoice.forceNew) {
        bypassKbDuplicate = true;
      }
    }

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KirimBarangLinkReceiverSheetJadwal(
        driverUid: widget.item['driverUid'] as String? ?? '',
        driverName: (widget.item['driverName'] as String?) ?? 'Driver',
        driverPhotoUrl: widget.item['photoUrl'] as String?,
        scheduleId: widget.scheduleId,
        scheduledDate: widget.scheduledDate,
        origin: widget.origin,
        dest: widget.dest,
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
          widget.onCreated();
          _createAndOpenChatWithOrderId(
            orderId,
            message,
            barangFotoUrl,
            bypassKbDuplicate,
          );
        },
        onError: (msg) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _createAndOpenChatWithOrderId(
    String orderId,
    String message, [
    String? barangFotoUrl,
    bool showBypassSnack = false,
  ]) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomPenumpangScreen(
          orderId: orderId,
          driverUid: widget.item['driverUid'] as String? ?? '',
          driverName: (widget.item['driverName'] as String?) ?? 'Driver',
          driverPhotoUrl: widget.item['photoUrl'] as String?,
          driverVerified: widget.item['isVerified'] as bool? ?? false,
          sendJenisPesananMessage: message,
          sendJenisPesananImageUrl: barangFotoUrl,
        ),
      ),
    );
    if (showBypassSnack) {
      _showNewSplitOrderThreadSnackJadwal();
    }
  }

  void _showKerabatDialog(int sisaKursi) {
    if (widget.hasBlockingTravelOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TrakaL10n.of(context).scheduleTravelBlockedWhileTravelAgreed,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (sisaKursi < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada kursi tersisa. Pilih "Pesan travel sendiri" atau tunggu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final maxKerabat = (sisaKursi - 1).clamp(0, 9);
    if (maxKerabat < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sisa kursi hanya 1. Silakan pilih "Pesan travel sendiri".'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    int jumlah = 1;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateD) => AlertDialog(
          title: const Text('Jumlah orang yang ikut'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Berapa orang yang ikut bersama Anda? (Sisa kursi: $sisaKursi)',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () =>
                        setStateD(() => jumlah = jumlah > 1 ? jumlah - 1 : 1),
                  ),
                  Text(
                    '$jumlah',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: maxKerabat < 1
                        ? null
                        : () => setStateD(() =>
                            jumlah = jumlah < maxKerabat ? jumlah + 1 : jumlah),
                  ),
                ],
              ),
              Text(
                'Total: ${1 + jumlah} penumpang (Anda + $jumlah orang)',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                'Contoh: Anda + 2 anak → pilih 2 (total 3 penumpang)',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (jumlah > maxKerabat) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Maksimal $maxKerabat orang (sisa kursi $sisaKursi).',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx);
                _createAndOpenChat(
                  orderType: OrderModel.typeTravel,
                  jumlahKerabat: jumlah,
                );
              },
              child: const Text('Pesan'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxPassengers = (widget.item['maxPassengers'] as num?)?.toInt() ?? 0;
    final dateLabel = _formatScheduledDate(widget.scheduledDate);

    return FutureBuilder<
        ({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
      future: OrderService.getScheduledBookingCounts(widget.scheduleId),
      builder: (context, snap) {
        final counts =
            snap.data ?? (totalPenumpang: 0, kirimBarangCount: 0, kargoCount: 0);
        return FutureBuilder<double>(
          future: AppConfigService.getKargoSlotPerOrder(),
          builder: (context, slotSnap) {
            final kargoSlot = slotSnap.data ?? 1.0;
            final sisaKursi = (maxPassengers -
                    counts.totalPenumpang -
                    (counts.kargoCount * kargoSlot).ceil())
                .clamp(0, maxPassengers);
            final travelBlocked = widget.hasBlockingTravelOrder;
            return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(context.responsive.horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pesan untuk tanggal $dateLabel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Kapasitas: $maxPassengers penumpang. Sisa $sisaKursi kursi. Sudah dipesan: ${counts.totalPenumpang} penumpang. Sudah ${counts.kirimBarangCount} pesanan kirim barang${counts.kargoCount > 0 ? ' (${counts.kargoCount} kargo mengurangi kapasitas)' : ''}.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 4),
                Text(
                  'Jumlah penumpang sesuai kapasitas mobil driver.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (travelBlocked) ...[
                  SizedBox(height: 12),
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              TrakaL10n.of(context).scheduleTravelBlockedWhileTravelAgreed,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 24),
                ListTile(
                  enabled: !travelBlocked && !_loading,
                  leading: const Icon(Icons.person),
                  title: const Text('Pesan Travel Sendiri'),
                  subtitle: const Text(
                    'Pesan untuk perjalanan Anda sendiri (1 orang)',
                  ),
                  onTap: _loading
                      ? null
                      : () => _createAndOpenChat(
                          orderType: OrderModel.typeTravel,
                        ),
                ),
                ListTile(
                  enabled: !travelBlocked && !_loading,
                  leading: const Icon(Icons.group),
                  title: const Text('Pesan Travel dengan Kerabat'),
                  subtitle: const Text(
                    'Pesan untuk 2+ orang — Anda + keluarga/teman yang ikut',
                  ),
                  onTap: _loading ? null : () => _showKerabatDialog(sisaKursi),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Kirim Barang'),
                  subtitle: const Text(
                    'Pesan untuk mengirim barang (tidak dihitung penumpang)',
                  ),
                  onTap: _loading ? null : _showKirimBarangLinkReceiverSheet,
                ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }
}

/// Bottom sheet tautkan penerima untuk Kirim Barang dari Pesan nanti (jadwal).
class _KirimBarangLinkReceiverSheetJadwal extends StatefulWidget {
  final String driverUid;
  final String driverName;
  final String? driverPhotoUrl;
  final String scheduleId;
  final String scheduledDate;
  final String origin;
  final String dest;
  final String? barangCategory;
  final String? barangNama;
  final double? barangBeratKg;
  final double? barangPanjangCm;
  final double? barangLebarCm;
  final double? barangTinggiCm;
  final String? barangFotoUrl;
  final void Function(String orderId, String message, [String? barangFotoUrl]) onOrderCreated;
  final void Function(String message) onError;
  final bool bypassDuplicatePendingKirimBarang;

  const _KirimBarangLinkReceiverSheetJadwal({
    required this.driverUid,
    required this.driverName,
    this.driverPhotoUrl,
    required this.scheduleId,
    required this.scheduledDate,
    required this.origin,
    required this.dest,
    this.barangCategory,
    this.barangNama,
    this.barangBeratKg,
    this.barangPanjangCm,
    this.barangLebarCm,
    this.barangTinggiCm,
    this.barangFotoUrl,
    this.bypassDuplicatePendingKirimBarang = false,
    required this.onOrderCreated,
    required this.onError,
  });

  @override
  State<_KirimBarangLinkReceiverSheetJadwal> createState() =>
      _KirimBarangLinkReceiverSheetJadwalState();
}

class _KirimBarangLinkReceiverSheetJadwalState
    extends State<_KirimBarangLinkReceiverSheetJadwal> {
  final _controller = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _receiver;
  String? _notFound;
  String _travelFarePaidBy = OrderModel.travelFarePaidBySender;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cari() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      widget.onError('Masukkan no. telepon penerima.');
      return;
    }
    setState(() {
      _loading = true;
      _receiver = null;
      _notFound = null;
    });
    final result = await OrderService.findUserByEmailOrPhone(input);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _receiver = result;
      _notFound = result == null ? 'User tidak ditemukan.' : null;
    });
  }

  Future<void> _kirimKeDriver() async {
    final receiver = _receiver;
    if (receiver == null) return;
    final uid = receiver['uid'] as String?;
    if (uid == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (uid == user.uid) {
      widget.onError('Penerima tidak boleh sama dengan pengirim.');
      return;
    }
    // Validasi ulang: pastikan penerima masih terdaftar
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) {
        widget.onError('Penerima tidak ditemukan. Pilih ulang dari kontak.');
        setState(() => _receiver = null);
        return;
      }
    } catch (_) {
      widget.onError('Gagal memverifikasi penerima. Coba lagi.');
      return;
    }
    if (!widget.bypassDuplicatePendingKirimBarang) {
      final pendingKb =
          await OrderService.getPassengerPendingKirimBarangWithDriver(
        user.uid,
        widget.driverUid,
      );
      if (!mounted) return;
      if (pendingKb != null) {
        widget.onError(
          TrakaL10n.of(context).passengerPendingKirimBarangDuplicateShort,
        );
        return;
      }
    }
    setState(() => _loading = true);
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
    final passengerNameResolved = passengerName ?? user.email ?? 'Penumpang';
    final receiverName = (receiver['displayName'] as String?) ?? 'Penerima';
    final receiverPhotoUrl = receiver['photoUrl'] as String?;
    final orderId = await PerformanceTraceService.traceOrderSubmit<String?>(
      () => OrderService.createOrder(
        passengerUid: user.uid,
        driverUid: widget.driverUid,
        routeJourneyNumber: OrderService.routeJourneyNumberScheduled,
        passengerName: passengerNameResolved,
        passengerPhotoUrl: passengerPhotoUrl,
        passengerAppLocale: passengerAppLocale,
        originText: widget.origin,
        destText: widget.dest,
        originLat: null,
        originLng: null,
        destLat: null,
        destLng: null,
        orderType: OrderModel.typeKirimBarang,
        receiverUid: uid,
        receiverName: receiverName,
        receiverPhotoUrl: receiverPhotoUrl,
        scheduleId: widget.scheduleId,
        scheduledDate: widget.scheduledDate,
        barangCategory: widget.barangCategory ?? OrderModel.barangCategoryKargo,
        barangNama: widget.barangNama,
        barangBeratKg: widget.barangBeratKg,
        barangPanjangCm: widget.barangPanjangCm,
        barangLebarCm: widget.barangLebarCm,
        barangTinggiCm: widget.barangTinggiCm,
        barangFotoUrl: widget.barangFotoUrl,
        travelFarePaidBy: _travelFarePaidBy,
        bypassDuplicatePendingKirimBarang:
            widget.bypassDuplicatePendingKirimBarang,
      ),
    );
    if (!mounted) return;
    AppAnalyticsService.logOrderCreated(
      orderType: OrderModel.typeKirimBarang,
      success: orderId != null,
    );
    if (orderId == null) {
      setState(() => _loading = false);
      widget.onError(TrakaL10n.of(context).failedToCreateOrder);
      return;
    }
    setState(() => _loading = false);
    if (!mounted) return;
    final l10n = TrakaL10n.of(context);
    final estimateLines = await runWithEstimateLoading<String>(
      context,
      l10n,
      () => JarakKontribusiScheduleEstimate.chatBlockFromAddressTexts(
        originText: widget.origin,
        destText: widget.dest,
        l10n: l10n,
        orderType: OrderModel.typeKirimBarang,
        barangCategory:
            widget.barangCategory ?? OrderModel.barangCategoryKargo,
      ),
    );
    if (!mounted) return;
    final jenisLabel = widget.barangCategory == OrderModel.barangCategoryDokumen
        ? 'Dokumen (surat, amplop, paket kecil)'
        : 'Kargo';
    String barangDetail = '';
    if (widget.barangCategory == OrderModel.barangCategoryKargo &&
        widget.barangNama != null &&
        widget.barangNama!.trim().isNotEmpty) {
      final parts = <String>[widget.barangNama!.trim()];
      if (widget.barangBeratKg != null && widget.barangBeratKg! > 0) {
        parts.add('${widget.barangBeratKg!.toStringAsFixed(1)} kg');
      }
      if (widget.barangPanjangCm != null &&
          widget.barangLebarCm != null &&
          widget.barangPanjangCm! > 0 &&
          widget.barangLebarCm! > 0) {
        final dim = widget.barangTinggiCm != null && widget.barangTinggiCm! > 0
            ? '${widget.barangPanjangCm!.toInt()}×${widget.barangLebarCm!.toInt()}×${widget.barangTinggiCm!.toInt()} cm'
            : '${widget.barangPanjangCm!.toInt()}×${widget.barangLebarCm!.toInt()} cm';
        parts.add(dim);
      }
      barangDetail = '\nBarang: ${parts.join(' • ')}\n';
    }
    final message = PassengerFirstChatMessage.kirimBarang(
      driverName: widget.driverName,
      isScheduled: true,
      jenisLabel: jenisLabel,
      barangDetailSuffix: barangDetail,
      receiverName: receiverName,
      asal: widget.origin,
      tujuan: widget.dest,
      jarakKontribusiLines: estimateLines,
      travelFarePaidBy: _travelFarePaidBy,
    );
    widget.onOrderCreated(orderId, message, widget.barangFotoUrl);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        mediaQuery.viewPadding.bottom + mediaQuery.viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text(
              'Kirim Barang – Tautkan Penerima',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan no. telepon penerima (harus terdaftar di Traka). Penerima harus setuju agar pesanan masuk ke driver.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'No. telepon',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
                hintText: '08123456789',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.contacts_outlined),
                  tooltip: 'Buka kontak HP',
                  onPressed: () {
                    showReceiverContactPicker(
                      context: context,
                      onSelect: (phone, receiverData) {
                        _controller.text = phone;
                        setState(() {
                          _receiver = receiverData;
                          _notFound = receiverData == null
                              ? 'Kontak belum terdaftar di Traka.'
                              : null;
                        });
                      },
                    );
                  },
                ),
              ),
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _cari(),
            ),
            if (_notFound != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _notFound!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            if (_receiver != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage:
                        (_receiver!['photoUrl'] as String?) != null &&
                                (_receiver!['photoUrl'] as String).isNotEmpty
                            ? CachedNetworkImageProvider(
                                _receiver!['photoUrl'] as String,
                              )
                            : null,
                    child:
                        (_receiver!['photoUrl'] as String?) == null ||
                                (_receiver!['photoUrl'] as String).isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (_receiver!['displayName'] as String?) ?? 'Penerima',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Ongkos travel ke driver',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Ditanggung pengirim'),
                    selected:
                        _travelFarePaidBy == OrderModel.travelFarePaidBySender,
                    onSelected: (_) => setState(() =>
                        _travelFarePaidBy = OrderModel.travelFarePaidBySender),
                  ),
                  ChoiceChip(
                    label: const Text('Ditanggung penerima'),
                    selected: _travelFarePaidBy ==
                        OrderModel.travelFarePaidByReceiver,
                    onSelected: (_) => setState(() => _travelFarePaidBy =
                        OrderModel.travelFarePaidByReceiver),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _travelFarePaidBy == OrderModel.travelFarePaidByReceiver
                    ? 'Penerima mengisi konfirmasi bayar (hybrid) di app sebelum scan terima barang.'
                    : 'Anda (pengirim) mengisi konfirmasi bayar sebelum scan jemput barang.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading
                  ? null
                  : () async {
                      if (_receiver != null) {
                        await _kirimKeDriver();
                      } else {
                        await _cari();
                      }
                    },
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_receiver != null ? 'Iya, kirim ke driver' : 'Cari'),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Satu halaman daftar jadwal untuk satu tanggal (digunakan di PageView).
class _BuildJadwalListPage extends StatelessWidget {
  final DateTime date;
  final String origin;
  final String dest;
  final Map<String, List<Map<String, dynamic>>> scheduleCache;
  final Map<String, bool> scheduleLoading;
  final Future<void> Function(DateTime) loadSchedules;
  final String Function(DateTime) dateKey;
  final Future<void> Function(
    BuildContext,
    Map<String, dynamic>,
    String,
    String,
    String,
    String,
  )
  onPesan;
  final VoidCallback? onCariTanggalLain;
  final VoidCallback? onGantiAsalTujuan;

  const _BuildJadwalListPage({
    required this.date,
    required this.origin,
    required this.dest,
    required this.scheduleCache,
    required this.scheduleLoading,
    required this.loadSchedules,
    required this.dateKey,
    required this.onPesan,
    this.onCariTanggalLain,
    this.onGantiAsalTujuan,
  });

  @override
  Widget build(BuildContext context) {
    final key = dateKey(date);
    final loading = scheduleLoading[key] == true;
    final list = scheduleCache[key];

    if (list == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => loadSchedules(date));
      return const Center(child: CircularProgressIndicator());
    }
    if (loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Tidak ada driver untuk tanggal ini',
                style: TextStyle(
                  fontSize: context.responsive.fontSize(16),
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Coba ubah tanggal atau asal/tujuan untuk mencari driver lain.',
                style: TextStyle(
                  fontSize: context.responsive.fontSize(13),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (onCariTanggalLain != null)
                FilledButton.icon(
                  onPressed: onCariTanggalLain,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: const Text('Cari tanggal lain'),
                ),
              if (onCariTanggalLain != null && onGantiAsalTujuan != null)
                const SizedBox(height: 12),
              if (onGantiAsalTujuan != null)
                OutlinedButton.icon(
                  onPressed: onGantiAsalTujuan,
                  icon: const Icon(Icons.edit_location_alt, size: 18),
                  label: const Text('Ganti asal/tujuan'),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        context.responsive.horizontalPadding,
        context.responsive.spacing(8),
        context.responsive.horizontalPadding,
        context.responsive.spacing(8) + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final driverUid = item['driverUid'] as String? ?? '';
        final originText = (item['origin'] as String?) ?? '';
        final destText = (item['destination'] as String?) ?? '';
        final depStamp = item['departureTime'] as Timestamp?;
        final keyStr = dateKey(date);
        final depMillis = depStamp?.millisecondsSinceEpoch ?? 0;
        final (scheduleId, legacyScheduleId) = ScheduleIdUtil.build(
          driverUid,
          keyStr,
          depMillis,
          originText,
          destText,
        );
        final scheduledDate = keyStr;

        // Gunakan data yang sudah tersedia dari ScheduledDriverRoute jika ada
        final driverNameFromData = item['driverName'] as String?;
        final photoUrlFromData = item['photoUrl'] as String?;

        String timeStr = '–';
        if (depStamp != null) {
          final dt = depStamp.toDate();
          timeStr =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }

        final maxPassengers = (item['maxPassengers'] as num?)?.toInt() ?? 0;

        Widget buildCard(String driverName, String? photoUrl, {bool? verified}) {
          return FutureBuilder<
              ({int totalPenumpang, int kirimBarangCount, int kargoCount})>(
            future: OrderService.getScheduledBookingCounts(
              scheduleId,
              legacyScheduleId: legacyScheduleId,
            ),
            builder: (context, snapCounts) {
              final counts = snapCounts.data ??
                  (totalPenumpang: 0, kirimBarangCount: 0, kargoCount: 0);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? CachedNetworkImageProvider(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              driverName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (verified ?? item['isVerified'] == true) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 18,
                              color: Colors.green.shade700,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Dari: ${_formatAlamatKecamatanKabupaten(originText)}',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tujuan: ${_formatAlamatKecamatanKabupaten(destText)}',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Jam: $timeStr',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(13),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.responsive.spacing(16),
                        0,
                        context.responsive.spacing(16),
                        context.responsive.spacing(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kapasitas: $maxPassengers penumpang. Sudah dipesan: ${counts.totalPenumpang} penumpang. Sudah ${counts.kirimBarangCount} pesanan kirim barang.',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(12),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: context.responsive.spacing(4)),
                          Text(
                            'Jumlah penumpang sesuai kapasitas mobil driver.',
                            style: TextStyle(
                              fontSize: context.responsive.fontSize(11),
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.responsive.spacing(16),
                        0,
                        context.responsive.spacing(16),
                        context.responsive.spacing(12),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => onPesan(
                            context,
                            item,
                            scheduleId,
                            scheduledDate,
                            origin,
                            dest,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('Pesan'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        if (driverNameFromData != null && driverNameFromData.isNotEmpty) {
          return buildCard(
            driverNameFromData,
            photoUrlFromData,
            verified: item['isVerified'] == true,
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: ChatService.getUserInfo(driverUid),
          builder: (context, snap) {
            final info = snap.data;
            final driverName =
                (info?['displayName'] as String?)?.isNotEmpty == true
                ? (info!['displayName'] as String)
                : 'Driver';
            final photoUrl = info?['photoUrl'] as String?;
            final verified = info?['verified'] == true;
            return buildCard(driverName, photoUrl, verified: verified);
          },
        );
      },
    );
  }
}
