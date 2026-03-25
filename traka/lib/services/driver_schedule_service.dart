import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'driver_hybrid_diagnostics.dart';
import 'order_service.dart';
import 'schedule_id_util.dart';

export 'schedule_id_util.dart' show ScheduleIdUtil;

/// Service untuk jadwal keberangkatan driver (driver_schedules).
/// - Menyembunyikan jadwal hari ini ketika driver klik "Mulai Rute ini" (agar tidak tampil ke penumpang).
/// - Menghapus jadwal yang tanggal+jam keberangkatannya sudah lewat, hanya jika tidak ada pesanan aktif.
/// - Batas pemesanan tanggal: **7 hari kalender ke depan (inklusif hari ini)** menurut **WIB (UTC+7)**.
/// - Cloud Function `onDriverScheduleWritten` (sanitize) menyelaraskan dokumen bila klien di-bypass.
class DriverScheduleService {
  static final _firestore = FirebaseFirestore.instance;

  /// WIB tidak pakai DST; dipakai satu aturan untuk seluruh Indonesia.
  static const int _wibOffsetHours = 7;

  /// Tanggal hari ini 00:00:00 di WIB (hanya komponen y/m/d yang dipakai).
  static DateTime get todayDateOnlyWib {
    final utc = DateTime.now().toUtc();
    final wibWall = utc.add(const Duration(hours: _wibOffsetHours));
    return DateTime(wibWall.year, wibWall.month, wibWall.day);
  }

  /// Inklusif hari ini: total 7 tanggal kalender (hari ini + 6 hari berikutnya).
  static const int scheduleBookingWindowDays = 7;

  /// Tanggal terakhir yang masih boleh diisi jadwal (satu zona WIB).
  static DateTime get lastScheduleDateInclusiveWib {
    final t = todayDateOnlyWib;
    return t.add(Duration(days: scheduleBookingWindowDays - 1));
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Tanggal [date] (bagian kalender saja) dalam jendela 7 hari WIB.
  static bool isScheduleDateInBookingWindow(DateTime date) {
    final only = dateOnly(date);
    final first = todayDateOnlyWib;
    final last = lastScheduleDateInclusiveWib;
    return !only.isBefore(first) && !only.isAfter(last);
  }

  /// Untuk filter tampilan / kompatibilitas kode lama.
  static DateTime get _todayStartWib => todayDateOnlyWib;

  /// Cek apakah tanggal schedule sudah lewat (sebelum hari ini WIB).
  static bool _isPast(DateTime? date) {
    if (date == null) return true;
    final d = DateTime(date.year, date.month, date.day);
    return d.isBefore(_todayStartWib);
  }

  /// Jadwal di luar jendela 7 hari WIB (terlalu jauh ke depan atau tanggal kalender sebelum hari ini WIB).
  static bool _isCalendarOutsideBookingWindowFromMap(Map<String, dynamic> map) {
    final dateStamp = map['date'] as Timestamp?;
    if (dateStamp == null) return false;
    final dt = dateStamp.toDate();
    final only = DateTime(dt.year, dt.month, dt.day);
    return only.isBefore(todayDateOnlyWib) ||
        only.isAfter(lastScheduleDateInclusiveWib);
  }

  /// Sembunyikan jadwal yang tanggalnya hari ini. Dipanggil saat driver klik "Mulai Rute ini".
  /// Jadwal yang hidden tidak ditampilkan ke penumpang saat mencari travel.
  static Future<void> markTodaySchedulesHidden(String driverUid) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final list = data['schedules'] as List<dynamic>?;
      if (list == null || list.isEmpty) return;

      final now = FieldValue.serverTimestamp();
      bool changed = false;
      final updated = <Map<String, dynamic>>[];

      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
        final dateStamp = map['date'] as Timestamp?;
        final hiddenAt = map['hiddenAt'];
        if (hiddenAt != null) {
          updated.add(map);
          continue;
        }
        final date = dateStamp?.toDate();
        if (date == null) {
          updated.add(map);
          continue;
        }
        final scheduleDate = DateTime(date.year, date.month, date.day);
        if (scheduleDate == _todayStartWib) {
          map['hiddenAt'] = now;
          changed = true;
        }
        updated.add(map);
      }

      if (changed) {
        await _firestore.collection('driver_schedules').doc(driverUid).update({
          'schedules': updated,
          'updatedAt': now,
        });
      }
    } catch (_) {}
  }

  /// Hapus jadwal yang **tanggal + jam keberangkatan** sudah lewat, hanya jika tidak ada pesanan
  /// travel/kirim barang yang masih aktif (bukan selesai/dibatalkan). Dipanggil saat load jadwal.
  ///
  /// [persistPruned]: jika `false`, hitung daftar yang dipertahankan tetapi **jangan** `update` dokumen
  /// (dipakai saat membuka sheet pindah jadwal — sama secara logika, tanpa menulis prune ke Firestore).
  ///
  /// [schedulesSnapshot]: jika diisi, lewati GET [Source.server] dan pakai daftar ini (biasanya dari
  /// [readSchedulesRawFromServer]) — mengurangi round-trip ganda saat sortir logika sama dengan prune.
  static const Duration _getSchedulesTimeout = Duration(seconds: 35);
  /// Baca cepat setelah simpan jadwal: `serverAndCache` + plafon pendek (hindari antrean `Source.server` 10+ menit).
  static const Duration _readSchedulesRawTimeout = Duration(seconds: 14);
  static const Duration _updateSchedulesTimeout = Duration(seconds: 25);

  /// True jika waktu keberangkatan efektif sudah sebelum [DateTime.now()] (timezone lokal).
  static bool isScheduleDepartureInThePast(Map<String, dynamic> map) {
    final depStamp = map['departureTime'] as Timestamp?;
    if (depStamp != null) {
      return depStamp.toDate().isBefore(DateTime.now());
    }
    final dateStamp = map['date'] as Timestamp?;
    if (dateStamp == null) return false;
    final d = dateStamp.toDate();
    final endOfDay = DateTime(d.year, d.month, d.day, 23, 59, 59);
    return endOfDay.isBefore(DateTime.now());
  }

  /// Baca `schedules` — tanpa query order / penghapusan otomatis.
  /// [Source.serverAndCache] + timeout pendek: setelah simpan jadwal, baca murni `server` sering mengantre lama.
  static Future<List<Map<String, dynamic>>> readSchedulesRawFromServer(
    String driverUid,
  ) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(_readSchedulesRawTimeout);

      if (!doc.exists || doc.data() == null) return [];

      final list = doc.data()!['schedules'] as List<dynamic>?;
      if (list == null || list.isEmpty) return [];

      return [
        for (final e in list)
          Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
      ];
    } on TimeoutException {
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DriverScheduleService.readSchedulesRawFromServer: $e\n$st');
      }
      rethrow;
    }
  }

  /// Baca jadwal mentah untuk sheet pindah: satu retry pendek jika timeout (sama ide dengan layar jadwal).
  static Future<List<Map<String, dynamic>>> _readSchedulesRawForPindahWithRetry(
    String driverUid,
  ) async {
    try {
      return await readSchedulesRawFromServer(driverUid);
    } on TimeoutException {
      DriverHybridDiagnostics.breadcrumb('schedule.pindah.read.retry_after_timeout');
      await Future<void>.delayed(const Duration(milliseconds: 480));
      return readSchedulesRawFromServer(driverUid);
    }
  }

  /// Aturan prune in-memory (sama dengan langkah sortir di [cleanupPastSchedules], tanpa I/O).
  static List<Map<String, dynamic>> applySchedulePruneInMemory({
    required List<Map<String, dynamic>> mapsList,
    required String driverUid,
    required Set<String>? activeScheduleIds,
  }) {
    final kept = <Map<String, dynamic>>[];
    for (final raw in mapsList) {
      final map = Map<String, dynamic>.from(raw);
      final prune = isScheduleDepartureInThePast(map) ||
          _isCalendarOutsideBookingWindowFromMap(map);
      if (!prune) {
        kept.add(map);
        continue;
      }
      final dateStamp = map['date'] as Timestamp?;
      final depStamp = map['departureTime'] as Timestamp?;
      if (dateStamp == null || depStamp == null) {
        kept.add(map);
        continue;
      }
      if (activeScheduleIds == null) {
        kept.add(map);
        continue;
      }
      final d = dateStamp.toDate();
      final dep = depStamp.toDate();
      final dateKey =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final origin = (map['origin'] as String?) ?? '';
      final dest = (map['destination'] as String?) ?? '';
      final (scheduleId, legacyScheduleId) = ScheduleIdUtil.build(
        driverUid,
        dateKey,
        dep.millisecondsSinceEpoch,
        origin,
        dest,
      );
      final storedSid = map['scheduleId'] as String?;
      final hasOrders = (storedSid != null &&
              storedSid.isNotEmpty &&
              OrderService.scheduledOrderMatchesActiveIds(
                activeScheduleIds,
                storedSid,
                ScheduleIdUtil.toLegacy(storedSid),
              )) ||
          OrderService.scheduledOrderMatchesActiveIds(
            activeScheduleIds,
            scheduleId,
            legacyScheduleId,
          );
      if (hasOrders) {
        kept.add(map);
      }
    }
    return kept;
  }

  static Future<List<Map<String, dynamic>>> cleanupPastSchedules(
    String driverUid, {
    bool persistPruned = true,
    List<Map<String, dynamic>>? schedulesSnapshot,
  }) async {
    Stopwatch? sw;
    if (kDebugMode) sw = Stopwatch()..start();
    void trace(String m) {
      if (kDebugMode) {
        debugPrint('[JadwalCleanup] +${sw!.elapsedMilliseconds}ms $m');
      }
    }

    try {
      late final List<Map<String, dynamic>> mapsList;
      if (schedulesSnapshot != null) {
        trace('start (schedulesSnapshot count=${schedulesSnapshot.length})');
        mapsList = schedulesSnapshot;
      } else {
        trace('start (driver_schedules server read)');
        // Selalu server: cache sering bikin daftar jadwal “nyangkut” (hybrid / multi-perangkat).
        final doc = await _firestore
            .collection('driver_schedules')
            .doc(driverUid)
            .get(const GetOptions(source: Source.server))
            .timeout(_getSchedulesTimeout);

        if (!doc.exists || doc.data() == null) {
          trace('get: no doc → []');
          return [];
        }

        final data = doc.data()!;
        final list = data['schedules'] as List<dynamic>?;
        if (list == null || list.isEmpty) {
          trace('get: empty schedules → []');
          return [];
        }
        mapsList = [
          for (final e in list)
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
        ];
      }
      if (mapsList.isEmpty) {
        trace('empty schedules → []');
        return [];
      }
      trace('rawCount=${mapsList.length}');

      Set<String>? activeScheduleIds;
      try {
        activeScheduleIds = await OrderService.activeScheduleIdsForDriverOrders(driverUid);
        trace('orders: activeScheduleIds=${activeScheduleIds.length}');
      } catch (e) {
        activeScheduleIds = null;
        trace('orders: FAILED ($e) → past schedules kept if ambiguous');
      }

      final kept = applySchedulePruneInMemory(
        mapsList: mapsList,
        driverUid: driverUid,
        activeScheduleIds: activeScheduleIds,
      );

      if (kept.length < mapsList.length) {
        if (persistPruned) {
          trace('firestore update: removing ${mapsList.length - kept.length} stale/out-of-window slot(s)');
          await _firestore.collection('driver_schedules').doc(driverUid).update({
            'schedules': kept,
            'updatedAt': FieldValue.serverTimestamp(),
          }).timeout(_updateSchedulesTimeout);
          trace('firestore update: ok');
        } else if (kDebugMode) {
          trace(
            'skip firestore update (would remove ${mapsList.length - kept.length} slot(s); persistPruned=false)',
          );
        }
      } else {
        trace('no doc update (kept all ${kept.length})');
      }

      trace('done → kept=${kept.length}');
      return kept;
    } on TimeoutException {
      rethrow;
    } catch (e, st) {
      // Jangan kembalikan [] diam-diam: UI akan menganggap tidak ada jadwal padahal gagal baca server.
      if (kDebugMode) {
        debugPrint('DriverScheduleService.cleanupPastSchedules: $e\n$st');
      }
      rethrow;
    }
  }

  /// Cek apakah jam keberangkatan sudah lewat (untuk jadwal tanggal hari ini).
  static bool _isDepartureTimePassed(Map<String, dynamic> map) {
    final depStamp = map['departureTime'] as Timestamp?;
    if (depStamp == null) return false;
    return depStamp.toDate().isBefore(DateTime.now());
  }

  /// Daftar jadwal yang masih tampil ke penumpang: tanggal >= hari ini, belum hidden,
  /// dan jam keberangkatan belum lewat (tanggal hari ini + jam lewat = disembunyikan).
  static Future<List<Map<String, dynamic>>> getVisibleSchedulesForDriver(
    String driverUid,
  ) async {
    try {
      final doc = await _firestore
          .collection('driver_schedules')
          .doc(driverUid)
          .get();

      if (!doc.exists || doc.data() == null) return [];

      final list = doc.data()!['schedules'] as List<dynamic>?;
      if (list == null) return [];

      final result = <Map<String, dynamic>>[];
      for (final e in list) {
        final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
        final dateStamp = map['date'] as Timestamp?;
        if (_isPast(dateStamp?.toDate())) continue;
        if (dateStamp != null &&
            dateOnly(dateStamp.toDate()).isAfter(lastScheduleDateInclusiveWib)) {
          continue;
        }
        if (map['hiddenAt'] != null) continue;
        if (_isDepartureTimePassed(map)) continue;
        result.add(map);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Semua jadwal dari semua driver untuk tanggal tertentu (tanpa filter rute).
  /// Dipakai sebagai fallback di penumpang agar jadwal driver tetap muncul saat filter rute kosong.
  static Future<List<Map<String, dynamic>>> getAllSchedulesForDate(
    DateTime date,
  ) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final snap = await _firestore.collection('driver_schedules').get();
      final result = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;
          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;
          if (scheduleDateOnly == _todayStartWib && _isDepartureTimePassed(map)) {
            continue;
          }
          result.add({...map, 'driverUid': driverUid});
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Daftar jadwal driver untuk pindah pesanan: semua jadwal yang masih valid,
  /// kecuali [excludeScheduleId]. Setiap item punya scheduleId, scheduledDate, label.
  /// Cleanup logika sama dengan [cleanupPastSchedules] tetapi tanpa menulis prune ke Firestore.
  /// Satu baca [readSchedulesRawFromServer] + sortir (tanpa GET [Source.server] kedua).
  static Future<List<Map<String, dynamic>>> getOtherSchedulesForPindah(
    String driverUid, {
    required String excludeScheduleId,
  }) async {
    try {
      final maps = await _readSchedulesRawForPindahWithRetry(driverUid);
      final kept = await cleanupPastSchedules(
        driverUid,
        persistPruned: false,
        schedulesSnapshot: maps,
      );
      final result = <Map<String, dynamic>>[];
      for (final map in kept) {
        final dateStamp = map['date'] as Timestamp?;
        final depStamp = map['departureTime'] as Timestamp?;
        if (dateStamp == null || depStamp == null) continue;
        final date = dateStamp.toDate();
        final dep = depStamp.toDate();
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final origin = (map['origin'] as String?) ?? '';
        final dest = (map['destination'] as String?) ?? '';
        final (scheduleId, legacyScheduleId) = ScheduleIdUtil.build(
          driverUid,
          dateKey,
          dep.millisecondsSinceEpoch,
          origin,
          dest,
        );
        if (scheduleId == excludeScheduleId) continue;
        if (legacyScheduleId == excludeScheduleId) continue;
        if (map['hiddenAt'] != null) continue;
        if (_isPast(date)) continue;
        if (DateTime(date.year, date.month, date.day) == _todayStartWib &&
            _isDepartureTimePassed(map)) {
          continue;
        }
        result.add({
          'scheduleId': scheduleId,
          'scheduledDate': dateKey,
          'origin': map['origin'] as String? ?? '',
          'destination': map['destination'] as String? ?? '',
          'departureTime': dep,
        });
      }
      result.sort((a, b) {
        final ad = a['departureTime'] as DateTime;
        final bd = b['departureTime'] as DateTime;
        return ad.compareTo(bd);
      });
      return result;
    } catch (e, st) {
      DriverHybridDiagnostics.recordError('jadwal.pindah.targets', e, st);
      return [];
    }
  }

  /// Jadwal dari semua driver untuk tanggal dan rute (awal tujuan + tujuan) tertentu.
  /// Cocok jika teks awal/tujuan mengandung kata kunci (case-insensitive).
  /// Setiap item berisi schedule map + driverUid.
  static Future<List<Map<String, dynamic>>> getSchedulesByDateAndRoute(
    DateTime date,
    String originKeyword,
    String destinationKeyword,
  ) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final snap = await _firestore.collection('driver_schedules').get();
      final result = <Map<String, dynamic>>[];
      final o = originKeyword.trim().toLowerCase();
      final d = destinationKeyword.trim().toLowerCase();
      if (o.isEmpty && d.isEmpty) return result;

      for (final doc in snap.docs) {
        final driverUid = doc.id;
        final list = doc.data()['schedules'] as List<dynamic>?;
        if (list == null) continue;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map<dynamic, dynamic>);
          final dateStamp = map['date'] as Timestamp?;
          if (dateStamp == null) continue;
          final scheduleDate = dateStamp.toDate();
          final scheduleDateOnly = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );
          if (scheduleDateOnly != dateStart) continue;
          if (map['hiddenAt'] != null) continue;
          if (scheduleDateOnly == _todayStartWib && _isDepartureTimePassed(map))
            continue;
          final origin = (map['origin'] as String?)?.trim().toLowerCase() ?? '';
          final dest =
              (map['destination'] as String?)?.trim().toLowerCase() ?? '';
          final matchOrigin = o.isEmpty || origin.contains(o);
          final matchDest = d.isEmpty || dest.contains(d);
          if (!matchOrigin || !matchDest) continue;
          result.add({...map, 'driverUid': driverUid});
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}
