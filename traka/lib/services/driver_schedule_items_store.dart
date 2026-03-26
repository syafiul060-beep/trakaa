import 'package:cloud_firestore/cloud_firestore.dart';

import 'schedule_id_util.dart';

/// Jadwal per dokumen di `driver_schedules/{uid}/schedule_items/{docId}`
/// (mengurangi dokumen induk besar + last-write-wins pada array).
class DriverScheduleItemsStore {
  DriverScheduleItemsStore._();

  static const String subcollectionName = 'schedule_items';

  /// Field pada dokumen induk: setelah migrasi tulis ke subkoleksi.
  static const String parentStorageModeField = 'scheduleStorage';
  static const String parentStorageModeItemsV1 = 'items_v1';

  static CollectionReference<Map<String, dynamic>> itemsCol(
    FirebaseFirestore fs,
    String driverUid,
  ) =>
      fs.collection('driver_schedules').doc(driverUid).collection(subcollectionName);

  /// ID dokumen aman untuk Firestore (tanpa `/`).
  static String entryDocumentId(Map<String, dynamic> map, String driverUid) {
    final sid = (map['scheduleId'] as String?)?.trim();
    if (sid != null && sid.isNotEmpty) {
      return sid.replaceAll('/', '_');
    }
    final dateStamp = map['date'] as Timestamp?;
    final depStamp = map['departureTime'] as Timestamp?;
    if (dateStamp == null || depStamp == null) {
      return 'noid_${map.hashCode.abs()}';
    }
    final d = dateStamp.toDate();
    final dep = depStamp.toDate();
    final dateKey =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final origin = (map['origin'] as String?) ?? '';
    final dest = (map['destination'] as String?) ?? '';
    final (id, _) = ScheduleIdUtil.build(
      driverUid,
      dateKey,
      dep.millisecondsSinceEpoch,
      origin,
      dest,
    );
    return id.replaceAll('/', '_');
  }

  /// Baca semua slot dari subkoleksi `schedule_items`.
  static Future<List<Map<String, dynamic>>> loadScheduleMaps(
    FirebaseFirestore fs,
    String driverUid, {
    GetOptions options = const GetOptions(source: Source.serverAndCache),
  }) async {
    final itemsSnap = await itemsCol(fs, driverUid).get(options);
    return [
      for (final d in itemsSnap.docs) Map<String, dynamic>.from(d.data()),
    ];
  }

  /// Ganti seluruh jadwal driver: hapus dokumen subkoleksi yang tidak ada di [schedules],
  /// set tiap entri, hapus field `schedules` di induk, tandai [parentStorageModeItemsV1].
  static Future<void> persistReplaceAll(
    FirebaseFirestore fs,
    String driverUid,
    List<Map<String, dynamic>> schedules,
  ) async {
    final parentRef = fs.collection('driver_schedules').doc(driverUid);
    final col = itemsCol(fs, driverUid);
    final existing = await col.get(const GetOptions(source: Source.serverAndCache));
    final newIds = schedules.map((m) => entryDocumentId(m, driverUid)).toSet();

    const maxOps = 450;
    WriteBatch batch = fs.batch();
    var opCount = 0;

    Future<void> commitBatch() async {
      if (opCount == 0) return;
      await batch.commit();
      batch = fs.batch();
      opCount = 0;
    }

    for (final d in existing.docs) {
      if (!newIds.contains(d.id)) {
        batch.delete(d.reference);
        opCount++;
        if (opCount >= maxOps) await commitBatch();
      }
    }
    for (final m in schedules) {
      final id = entryDocumentId(m, driverUid);
      batch.set(col.doc(id), m);
      opCount++;
      if (opCount >= maxOps) await commitBatch();
    }
    batch.set(
      parentRef,
      <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        parentStorageModeField: parentStorageModeItemsV1,
        'schedules': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    opCount++;
    if (opCount >= maxOps) await commitBatch();
    await batch.commit();
  }
}
