import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_category_service.dart';

/// Preferensi chip kategori rute di halaman Jadwal driver (per tanggal + default daftar kosong).
/// Disimpan lokal ([SharedPreferences]) dan disinkronkan ke Firestore (`driver_schedules` / `jadwalRouteCategoryPrefs`).
class DriverJadwalRouteCategoryPrefs {
  DriverJadwalRouteCategoryPrefs._();

  static String _key(String uid) => 'driver_jadwal_route_cat_v1_$uid';

  /// Field di dokumen `driver_schedules/{uid}` (merge; tidak mengganti array `schedules`).
  static const String firestoreField = 'jadwalRouteCategoryPrefs';

  static bool _isValidCategory(String? c) {
    if (c == null || c.isEmpty) return false;
    return c == RouteCategoryService.categoryDalamKota ||
        c == RouteCategoryService.categoryAntarKabupaten ||
        c == RouteCategoryService.categoryAntarProvinsi ||
        c == RouteCategoryService.categoryNasional;
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static ({Map<DateTime, String> byDate, String empty, int writtenAtMs})
      _parseDecodedMap(Map<String, dynamic> decoded) {
    var empty = RouteCategoryService.categoryAntarProvinsi;
    final e = decoded['empty'];
    if (e is String && _isValidCategory(e)) empty = e;

    final byDate = <DateTime, String>{};
    final byDateRaw = decoded['byDate'];
    if (byDateRaw is Map) {
      for (final entry in byDateRaw.entries) {
        final keyStr = entry.key.toString();
        final parts = keyStr.split('-');
        if (parts.length != 3) continue;
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (y == null || m == null || day == null) continue;
        final cat = entry.value?.toString();
        if (cat == null || !_isValidCategory(cat)) continue;
        byDate[_dateOnly(DateTime(y, m, day))] = cat;
      }
    }
    final w = decoded['writtenAtMs'];
    final writtenAtMs = w is int
        ? w
        : (w is num ? w.toInt() : 0);
    return (byDate: byDate, empty: empty, writtenAtMs: writtenAtMs);
  }

  /// Muat dari disk. Jika tidak ada / rusak → map kosong + default + writtenAtMs 0.
  static Future<({Map<DateTime, String> byDate, String empty, int writtenAtMs})>
      load(String uid) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(uid));
    if (raw == null || raw.isEmpty) {
      return (
        byDate: <DateTime, String>{},
        empty: RouteCategoryService.categoryAntarProvinsi,
        writtenAtMs: 0,
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return (
          byDate: <DateTime, String>{},
          empty: RouteCategoryService.categoryAntarProvinsi,
          writtenAtMs: 0,
        );
      }
      final p = _parseDecodedMap(decoded);
      return (
        byDate: p.byDate,
        empty: p.empty,
        writtenAtMs: p.writtenAtMs,
      );
    } catch (_) {
      return (
        byDate: <DateTime, String>{},
        empty: RouteCategoryService.categoryAntarProvinsi,
        writtenAtMs: 0,
      );
    }
  }

  /// Baca dari Firestore. `null` jika dokumen/field tidak ada (belum pernah sinkron).
  static Future<
          ({
            Map<DateTime, String> byDate,
            String empty,
            int writtenAtMs,
          })?>
      loadFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('driver_schedules')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!doc.exists) return null;
      final raw = doc.data()?[firestoreField];
      if (raw == null) return null;
      if (raw is! Map) return null;
      final decoded = Map<String, dynamic>.from(raw);
      final p = _parseDecodedMap(decoded);
      return (
        byDate: p.byDate,
        empty: p.empty,
        writtenAtMs: p.writtenAtMs,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _buildPayload(
    Map<DateTime, String> byDate,
    String emptyNew,
    int writtenAtMs,
  ) {
    final byDateJson = <String, String>{};
    for (final e in byDate.entries) {
      final d = e.key;
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      if (!_isValidCategory(e.value)) continue;
      byDateJson['$y-$m-$day'] = e.value;
    }
    return <String, dynamic>{
      'empty': emptyNew,
      'byDate': byDateJson,
      'writtenAtMs': writtenAtMs,
    };
  }

  /// Simpan ke SharedPreferences + timestamp.
  static Future<void> save(
    String uid,
    Map<DateTime, String> byDate,
    String emptyNew, {
    int? writtenAtMs,
  }) async {
    if (!_isValidCategory(emptyNew)) return;
    final ts = writtenAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key(uid),
      jsonEncode(_buildPayload(byDate, emptyNew, ts)),
    );
  }

  /// Merge ke `driver_schedules/{uid}` (tidak menghapus `schedules`).
  static Future<void> saveToFirestore(
    String uid,
    Map<DateTime, String> byDate,
    String emptyNew, {
    int? writtenAtMs,
  }) async {
    if (!_isValidCategory(emptyNew)) return;
    final ts = writtenAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await FirebaseFirestore.instance.collection('driver_schedules').doc(uid).set(
      <String, dynamic>{
        firestoreField: _buildPayload(byDate, emptyNew, ts),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Gabungkan lokal vs remote: yang lebih baru menurut [writtenAtMs]. Jika lokal lebih baru, dorong ke server.
  static Future<({Map<DateTime, String> byDate, String empty, int writtenAtMs})>
      mergeLocalAndRemote(
    String uid,
  ) async {
    final local = await load(uid);
    final remote = await loadFromFirestore(uid);
    if (remote == null) {
      return (
        byDate: local.byDate,
        empty: local.empty,
        writtenAtMs: local.writtenAtMs,
      );
    }
    if (local.writtenAtMs > remote.writtenAtMs) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      await save(uid, local.byDate, local.empty, writtenAtMs: ts);
      await saveToFirestore(uid, local.byDate, local.empty, writtenAtMs: ts);
      return (
        byDate: local.byDate,
        empty: local.empty,
        writtenAtMs: ts,
      );
    }
    await save(uid, remote.byDate, remote.empty, writtenAtMs: remote.writtenAtMs);
    return (
      byDate: remote.byDate,
      empty: remote.empty,
      writtenAtMs: remote.writtenAtMs,
    );
  }
}
