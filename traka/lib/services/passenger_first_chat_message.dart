import '../l10n/app_localizations.dart';
import '../models/jarak_kontribusi_preview.dart';
import '../models/order_model.dart';

/// Teks pesan otomatis pertama penumpang → driver (gaya seragam: salam netral, emoji ringan, permintaan ongkos konsisten).
///
/// Chat menyimpan plain text; emoji berfungsi sebagai penanda visual tanpa mengubah pipeline pesan.
class PassengerFirstChatMessage {
  PassengerFirstChatMessage._();

  static const String _closing = '\n\nTerima kasih 🙏';

  /// Salam tanpa "Pak/Bu"; emoji 👋 supaya ramah di layar kecil.
  static String greetingLine(String? driverDisplayName) {
    final n = (driverDisplayName ?? '').trim();
    if (n.isEmpty || n == 'Driver') return 'Halo 👋';
    return 'Halo $n 👋';
  }

  /// Travel (Beranda atau terjadwal). [jenisBaris] = kalimat jenis pesanan (1 orang / kerabat).
  /// [tanggalJadwalLabel] non-null untuk pesanan terjadwal (mis. dari [_formatScheduledDate]).
  /// [jarakKontribusiLines] = hasil [formatJarakKontribusiLines], [AppLocalizations.chatScheduledEstimateNote], atau fallback.
  static String travel({
    required String? driverName,
    required String jenisBaris,
    required String asal,
    required String tujuan,
    String? tanggalJadwalLabel,
    String? jarakKontribusiLines,
  }) {
    final buf = StringBuffer()
      ..writeln(greetingLine(driverName))
      ..writeln()
      ..writeln('🚐 $jenisBaris');
    if (tanggalJadwalLabel != null && tanggalJadwalLabel.trim().isNotEmpty) {
      buf
        ..writeln()
        ..writeln('📅 Untuk tanggal ${tanggalJadwalLabel.trim()}');
    }
    buf
      ..writeln()
      ..writeln('📍 Dari: $asal')
      ..writeln('📍 Tujuan: $tujuan');
    final extra = jarakKontribusiLines?.trim();
    if (extra != null && extra.isNotEmpty) {
      buf.writeln();
      buf.writeln(extra);
    }
    buf
      ..writeln()
      ..writeln('💰 Mohon informasi ongkos untuk rute ini.')
      ..write(_closing);
    return buf.toString();
  }

  /// Kirim barang (instant dari peta atau terjadwal dari jadwal).
  /// [barangDetailSuffix] sama seperti sebelumnya: bisa `'\nBarang: ...\n'` untuk kargo.
  /// [jarakKontribusiLines] = hasil [formatJarakKontribusiLines], [AppLocalizations.chatScheduledEstimateNote], atau fallback.
  static String kirimBarang({
    required String? driverName,
    required bool isScheduled,
    required String jenisLabel,
    String barangDetailSuffix = '',
    required String receiverName,
    required String asal,
    required String tujuan,
    String? jarakKontribusiLines,
    String travelFarePaidBy = OrderModel.travelFarePaidBySender,
  }) {
    final intro = isScheduled
        ? 'Saya ingin mengirim barang (terjadwal).'
        : 'Saya ingin mengirim barang.';
    final buf = StringBuffer()
      ..writeln(greetingLine(driverName))
      ..writeln()
      ..writeln('📦 $intro')
      ..writeln()
      ..writeln('📋 Jenis: $jenisLabel$barangDetailSuffix')
      ..writeln('👤 Penerima: $receiverName')
      ..writeln('📍 Dari: $asal')
      ..writeln('📍 Tujuan: $tujuan');
    final extra = jarakKontribusiLines?.trim();
    if (extra != null && extra.isNotEmpty) {
      buf.writeln();
      buf.writeln(extra);
    }
    if (travelFarePaidBy == OrderModel.travelFarePaidByReceiver) {
      buf
        ..writeln()
        ..writeln(
          '💳 Ongkos travel ke driver ditanggung penerima (bukan pengirim).',
        );
    }
    buf
      ..writeln()
      ..writeln('💰 Mohon informasi ongkos untuk rute ini.')
      ..write(_closing);
    return buf.toString();
  }

  /// Format [preview] dari [OrderService.computeJarakKontribusiPreview] sesuai bahasa [l10n].
  static String formatJarakKontribusiLines(
    AppLocalizations l10n,
    JarakKontribusiPreview preview,
  ) {
    final kmStr = preview.kmStraight >= 10
        ? preview.kmStraight.toStringAsFixed(1)
        : preview.kmStraight.toStringAsFixed(2);
    final buf = StringBuffer()..writeln(l10n.chatPreviewDistanceStraightKm(kmStr));
    if (preview.ferryKm > 0.001) {
      final fStr = preview.ferryKm >= 1
          ? preview.ferryKm.toStringAsFixed(1)
          : preview.ferryKm.toStringAsFixed(2);
      buf.writeln(l10n.chatPreviewFerrySegmentKm(fStr));
    }
    buf.writeln(
      l10n.chatPreviewDriverContributionRupiah(
        _formatRupiahDots(preview.contributionRp),
      ),
    );
    return buf.toString().trimRight();
  }

  static String _formatRupiahDots(int n) {
    final s = n.toString();
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }
}
