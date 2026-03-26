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

  /// `yyyy-MM-dd` dari [scheduleId] bila mengikuti [build] / [toLegacy]; null jika tidak terbaca.
  static String? tryParseDateKey(String scheduleId) {
    if (scheduleId.isEmpty) return null;
    final legacy = toLegacy(scheduleId);
    final parts = legacy.split('_');
    if (parts.length < 3) return null;
    final dateKey = parts[1];
    if (dateKey.length != 10 || dateKey[4] != '-' || dateKey[7] != '-') {
      return null;
    }
    return dateKey;
  }

  /// True jika tanggal di [scheduleId] sama [todayYmdWib], atau tanggal tidak bisa diparse (backward compat).
  static bool scheduleIdDateMatchesTodayWib(
    String scheduleId,
    String todayYmdWib,
  ) {
    if (scheduleId.isEmpty) return true;
    final key = tryParseDateKey(scheduleId);
    if (key == null) return true;
    return key == todayYmdWib;
  }
}
