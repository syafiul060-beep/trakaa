/// Format waktu untuk tampilan user (format 12 jam, Indonesia).
class TimeFormatter {
  TimeFormatter._();

  /// Format DateTime ke format 12 jam dengan periode (pagi/siang/sore/malam).
  /// Contoh: 14:30 → "02.30 siang", 09:15 → "09.15 pagi"
  static String format12h(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final minuteStr = m.toString().padLeft(2, '0');
    String period;
    int displayHour;
    if (h == 0) {
      displayHour = 12;
      period = 'tengah malam';
    } else if (h < 12) {
      displayHour = h;
      period = 'pagi';
    } else if (h == 12) {
      displayHour = 12;
      period = 'siang';
    } else if (h < 18) {
      displayHour = h - 12;
      period = 'sore';
    } else {
      displayHour = h - 12;
      period = 'malam';
    }
    return '$displayHour.$minuteStr $period';
  }
}
