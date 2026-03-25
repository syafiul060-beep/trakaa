/// Helper untuk format scheduleId yang unik per jadwal (menghindari tabrakan saat jam sama, rute beda).
class ScheduleIdUtil {
  ScheduleIdUtil._();

  /// Format: {driverUid}_{dateKey}_{depMillis}_h{hash(origin,dest)}
  /// [legacyScheduleId] = format lama tanpa hash, untuk backward compat dengan order yang sudah ada.
  static (String scheduleId, String legacyScheduleId) build(
    String driverUid,
    String dateKey,
    int depMillis,
    String origin,
    String dest,
  ) {
    final legacy = '${driverUid}_${dateKey}_$depMillis';
    final o = (origin).trim().toLowerCase();
    final d = (dest).trim().toLowerCase();
    final hash = Object.hash(o, d).abs().toRadixString(36);
    return ('${legacy}_h$hash', legacy);
  }

  /// Ekstrak legacyScheduleId dari scheduleId (format baru). Untuk backward compat saat hanya punya scheduleId.
  static String toLegacy(String scheduleId) {
    final idx = scheduleId.indexOf('_h');
    if (idx > 0) return scheduleId.substring(0, idx);
    return scheduleId;
  }
}
