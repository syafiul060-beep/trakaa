import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'driver_earnings_service.dart';

/// Service untuk generate PDF laporan pendapatan driver.
/// Format profesional untuk bukti pendapatan.
class DriverEarningsPdfService {
  static const List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  static String _fmtRupiah(double rp) =>
      'Rp ${rp.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  /// Sanitasi teks untuk PDF (font Helvetica tidak mendukung semua Unicode).
  /// Izinkan ASCII + Latin-1 (nama Indonesia) untuk mengurangi karakter ?.
  static String _sanitize(String s) {
    return s.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), '?');
  }

  static String _fmtDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    return '$d/$m/$y';
  }

  static String _fmtDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min WIB';
  }

  /// Generate PDF laporan pendapatan driver untuk bulan tertentu.
  static Future<PdfDocument> generateReport({
    required String driverName,
    required int year,
    required int month,
    required List<DriverEarningsOrderItem> earnings,
    required List<DriverContributionItem> contributions,
    required List<DriverViolationItem> violations,
  }) async {
    final document = PdfDocument();
    final now = DateTime.now();
    final monthName = _monthNames[month - 1];
    final periodText = '$monthName $year';

    final totalEarnings = earnings.fold<double>(0, (s, e) => s + e.amountRupiah);
    final totalContributions = contributions.fold<double>(0, (s, c) => s + c.amountRupiah);
    final totalViolations = violations.fold<double>(0, (s, v) => s + v.amountRupiah);
    final totalDeductions = totalContributions + totalViolations;

    final page = document.pages.add();
    final pageWidth = page.getClientSize().width;
    final pageHeight = page.getClientSize().height;
    PdfPage currentPage = page;
    PdfGraphics currentGraphics = page.graphics;

    // Aksen merek (biru Traka) — strip tipis di atas halaman pertama
    final brandBlue = PdfColor(37, 99, 235);
    currentGraphics.drawRectangle(
      brush: PdfSolidBrush(brandBlue),
      bounds: Rect.fromLTWH(0, 0, pageWidth, 3),
    );
    // Font mesin ketik (Courier) agar ringkas dan profesional
    final font = PdfStandardFont(PdfFontFamily.courier, 10);
    final fontBold = PdfStandardFont(PdfFontFamily.courier, 10, style: PdfFontStyle.bold);
    final fontTitle = PdfStandardFont(PdfFontFamily.courier, 14, style: PdfFontStyle.bold);
    final fontSmall = PdfStandardFont(PdfFontFamily.courier, 9);
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final grey = PdfSolidBrush(PdfColor(100, 100, 100));
    const logoTop = 6.0;
    double y = logoTop;

    // Logo Traka - ukuran lebih besar, jarak dekat ke nama driver
    const logoSize = 130.0;
    const logoToNameGap = 4.0;
    try {
      final data = await rootBundle.load('assets/images/pdf.png');
      final bytes = data.buffer.asUint8List();
      final image = PdfBitmap(bytes);
      currentGraphics.drawImage(image, Rect.fromLTWH(0, logoTop, logoSize, logoSize));
      y = logoTop + logoSize + logoToNameGap;
    } catch (_) {
      try {
        final data = await rootBundle.load('assets/images/logo_traka.png');
        final bytes = data.buffer.asUint8List();
        final image = PdfBitmap(bytes);
        currentGraphics.drawImage(image, Rect.fromLTWH(0, logoTop, logoSize, logoSize));
        y = logoTop + logoSize + logoToNameGap;
      } catch (_) {
        y = 50;
      }
    }

    // Header
    currentGraphics.drawString(
      'LAPORAN PENDAPATAN DRIVER',
      fontTitle,
      brush: black,
      bounds: Rect.fromLTWH(pageWidth - 200, logoTop, 200, 20),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    currentGraphics.drawString(
      'Aplikasi Traka - Travel & Kirim Barang Kalimantan',
      fontSmall,
      brush: grey,
      bounds: Rect.fromLTWH(pageWidth - 200, logoTop + 22, 200, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    if (y < 50) y = 50; // Tanpa logo: mulai info driver di y=50

    // Info driver
    currentGraphics.drawString('Nama Driver: ${_sanitize(driverName)}', fontBold, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 14));
    y += 16;
    currentGraphics.drawString('Periode: $periodText', font, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
    y += 14;
    currentGraphics.drawString('Tanggal Cetak: ${_fmtDateTime(now)}', fontSmall, brush: grey, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
    y += 24;

    // A. Pendapatan
    currentGraphics.drawString('A. PENDAPATAN DARI PERJALANAN', fontBold, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 14));
    y += 18;

    if (earnings.isEmpty) {
      currentGraphics.drawString('Tidak ada pendapatan pada periode ini.', font, brush: grey, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
      y += 20;
    } else {
      // Tabel: jenis order (travel / kirim barang) untuk kejelasan bukti
      final grid = PdfGrid();
      grid.columns.add(count: 5);
      grid.headers.add(1);
      final headerRow = grid.headers[0];
      headerRow.cells[0].value = 'No';
      headerRow.cells[1].value = 'Tanggal';
      headerRow.cells[2].value = 'Jenis';
      headerRow.cells[3].value = 'No. Pesanan';
      headerRow.cells[4].value = 'Nominal';
      headerRow.style.backgroundBrush = PdfSolidBrush(PdfColor(220, 220, 220));

      for (var i = 0; i < earnings.length; i++) {
        final o = earnings[i];
        final row = grid.rows.add();
        row.cells[0].value = '${i + 1}';
        row.cells[1].value = _fmtDate(o.completedAt);
        row.cells[2].value = _sanitize(o.typeLabel);
        row.cells[3].value = _sanitize(o.orderNumber);
        row.cells[4].value = _fmtRupiah(o.amountRupiah);
      }
      final subtotalRow = grid.rows.add();
      subtotalRow.cells[0].value = 'Subtotal';
      subtotalRow.cells[1].value = '';
      subtotalRow.cells[2].value = '';
      subtotalRow.cells[3].value = '';
      subtotalRow.cells[4].value = _fmtRupiah(totalEarnings);
      subtotalRow.style.backgroundBrush = PdfSolidBrush(PdfColor(240, 240, 240));
      subtotalRow.style.font = fontBold;

      final layoutFormat = PdfLayoutFormat(
        layoutType: PdfLayoutType.paginate,
        breakType: PdfLayoutBreakType.fitColumnsToPage,
        paginateBounds: Rect.fromLTWH(0, 0, pageWidth, pageHeight - 150),
      );
      final result = grid.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(0, y, pageWidth, pageHeight - y - 150),
        format: layoutFormat,
      );
      if (result != null) {
        currentPage = result.page;
        currentGraphics = result.page.graphics;
        y = result.bounds.bottom + 15;
      } else {
        y += 15;
      }
    }

    // B. Potongan
    currentGraphics.drawString('B. POTONGAN (Kontribusi & Pelanggaran)', fontBold, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 14));
    y += 18;

    if (contributions.isNotEmpty) {
      currentGraphics.drawString('Kontribusi:', fontBold, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
      y += 14;
      currentGraphics.drawString(
        '(Kontribusi = gabungan travel [jarak x tarif/km] + kirim barang + pelanggaran)',
        fontSmall,
        brush: grey,
        bounds: Rect.fromLTWH(0, y, pageWidth, 10),
      );
      y += 12;
      final grid = PdfGrid();
      grid.columns.add(count: 3);
      grid.headers.add(1);
      final h = grid.headers[0];
      h.cells[0].value = 'Tanggal Bayar';
      h.cells[1].value = 'Ref';
      h.cells[2].value = 'Nominal';
      h.style.backgroundBrush = PdfSolidBrush(PdfColor(220, 220, 220));
      for (final c in contributions) {
        final row = grid.rows.add();
        row.cells[0].value = _fmtDate(c.paidAt);
        row.cells[1].value = _sanitize(c.orderId ?? '-');
        row.cells[2].value = _fmtRupiah(c.amountRupiah);
      }
      final layoutFormat = PdfLayoutFormat(
        layoutType: PdfLayoutType.paginate,
        breakType: PdfLayoutBreakType.fitColumnsToPage,
        paginateBounds: Rect.fromLTWH(0, 0, pageWidth, pageHeight - 150),
      );
      final result = grid.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(0, y, pageWidth, pageHeight - y - 150),
        format: layoutFormat,
      );
      if (result != null) {
        currentPage = result.page;
        currentGraphics = result.page.graphics;
        y = result.bounds.bottom + 15;
      } else {
        y += 15;
      }
    }

    if (violations.isNotEmpty) {
      currentGraphics.drawString('Pelanggaran:', fontBold, brush: black, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
      y += 14;
      final grid = PdfGrid();
      grid.columns.add(count: 3);
      grid.headers.add(1);
      final h = grid.headers[0];
      h.cells[0].value = 'Tanggal Bayar';
      h.cells[1].value = 'No. Pesanan';
      h.cells[2].value = 'Nominal';
      h.style.backgroundBrush = PdfSolidBrush(PdfColor(220, 220, 220));
      for (final v in violations) {
        final row = grid.rows.add();
        row.cells[0].value = _fmtDate(v.paidAt);
        row.cells[1].value = _sanitize(v.orderId ?? '-');
        row.cells[2].value = _fmtRupiah(v.amountRupiah);
      }
      final layoutFormat = PdfLayoutFormat(
        layoutType: PdfLayoutType.paginate,
        breakType: PdfLayoutBreakType.fitColumnsToPage,
        paginateBounds: Rect.fromLTWH(0, 0, pageWidth, pageHeight - 150),
      );
      final result = grid.draw(
        page: currentPage,
        bounds: Rect.fromLTWH(0, y, pageWidth, pageHeight - y - 150),
        format: layoutFormat,
      );
      if (result != null) {
        currentPage = result.page;
        currentGraphics = result.page.graphics;
        y = result.bounds.bottom + 15;
      } else {
        y += 15;
      }
    }

    if (contributions.isEmpty && violations.isEmpty) {
      currentGraphics.drawString('Tidak ada potongan pada periode ini.', font, brush: grey, bounds: Rect.fromLTWH(0, y, pageWidth, 12));
      y += 20;
    } else {
      currentGraphics.drawString('Total Potongan: ${_fmtRupiah(totalDeductions)}', fontBold, brush: black, bounds: Rect.fromLTWH(pageWidth - 150, y, 150, 14), format: PdfStringFormat(alignment: PdfTextAlignment.right));
      y += 24;
    }

    // Ringkasan + Verifikasi: pastikan muat di halaman, jika tidak buat halaman baru
    const verificationBoxHeight = 130.0;
    if (y + 70 + verificationBoxHeight > pageHeight - 20) {
      currentPage = document.pages.add();
      currentGraphics = currentPage.graphics;
      y = 20;
    }
    currentGraphics.drawRectangle(brush: PdfSolidBrush(PdfColor(245, 245, 245)), bounds: Rect.fromLTWH(0, y, pageWidth, 70));
    currentGraphics.drawString('Total Pendapatan Kotor: ${_fmtRupiah(totalEarnings)}', font, brush: black, bounds: Rect.fromLTWH(10, y + 8, pageWidth - 20, 14));
    currentGraphics.drawString('Total Potongan: ${_fmtRupiah(totalDeductions)}', font, brush: black, bounds: Rect.fromLTWH(10, y + 24, pageWidth - 20, 14));
    currentGraphics.drawString('Pendapatan Bersih: ${_fmtRupiah(totalEarnings - totalDeductions)}', fontBold, brush: black, bounds: Rect.fromLTWH(10, y + 44, pageWidth - 20, 16));
    y += 90;

    // Bagian verifikasi (dengan cap pdf1.png)
    final blueBg = PdfSolidBrush(PdfColor(230, 240, 255));
    final blueBorder = PdfPen(PdfColor(100, 150, 220), width: 1.5);
    currentGraphics.drawRectangle(brush: blueBg, pen: blueBorder, bounds: Rect.fromLTWH(0, y, pageWidth, verificationBoxHeight));
    // Cap/Stempel verifikasi (assets/images/pdf1.png) - gambar memanjang (lebar > tinggi)
    try {
      final stampData = await rootBundle.load('assets/images/pdf1.png');
      final stampBytes = stampData.buffer.asUint8List();
      final stampImage = PdfBitmap(stampBytes);
      const stampWidth = 140.0;
      const stampHeight = 40.0;
      final stampX = (pageWidth - stampWidth) / 2;
      currentGraphics.drawImage(stampImage, Rect.fromLTWH(stampX, y + 6, stampWidth, stampHeight));
    } catch (_) {
      currentGraphics.drawString(
        '[CAP VERIFIKASI]',
        fontSmall,
        brush: PdfSolidBrush(PdfColor(100, 120, 160)),
        bounds: Rect.fromLTWH(0, y + 18, pageWidth, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }
    currentGraphics.drawString(
      'DIVERIFIKASI OLEH APLIKASI TRAKA',
      PdfStandardFont(PdfFontFamily.courier, 12, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(PdfColor(0, 50, 120)),
      bounds: Rect.fromLTWH(10, y + 52, pageWidth - 20, 16),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    currentGraphics.drawString(
      'Dokumen ini merupakan bukti resmi yang diterbitkan secara otomatis oleh sistem Aplikasi Traka. '
      'Data pendapatan dan potongan di atas bersumber dari transaksi yang tercatat dalam database Traka. '
      'Dapat digunakan sebagai bukti pendapatan.',
      fontSmall,
      brush: PdfSolidBrush(PdfColor(0, 60, 100)),
      bounds: Rect.fromLTWH(15, y + 68, pageWidth - 30, 30),
      format: PdfStringFormat(alignment: PdfTextAlignment.center, lineSpacing: 2),
    );
    currentGraphics.drawString(
      'Diterbitkan pada: ${_fmtDateTime(now)}',
      fontBold,
      brush: PdfSolidBrush(PdfColor(0, 50, 120)),
      bounds: Rect.fromLTWH(10, y + 98, pageWidth - 20, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );
    currentGraphics.drawString(
      'Traka - Aplikasi Travel & Pengiriman Barang Terpercaya di Kalimantan',
      PdfStandardFont(PdfFontFamily.courier, 8),
      brush: PdfSolidBrush(PdfColor(80, 100, 140)),
      bounds: Rect.fromLTWH(10, y + 112, pageWidth - 20, 10),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    _drawPageFooters(document);
    return document;
  }

  static void _drawPageFooters(PdfDocument document) {
    final footerFont = PdfStandardFont(PdfFontFamily.courier, 8);
    final brush = PdfSolidBrush(PdfColor(110, 110, 110));
    final total = document.pages.count;
    for (var i = 0; i < total; i++) {
      final page = document.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      final text = 'Halaman ${i + 1} / $total';
      g.drawString(
        text,
        footerFont,
        brush: brush,
        bounds: Rect.fromLTWH(0, size.height - 22, size.width, 14),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }
  }

  /// Simpan PDF ke file sementara dan [dispose] dokumen.
  static Future<File> savePdfToFile(PdfDocument document, {String? name}) async {
    final bytes = await document.save();
    document.dispose();
    final filename = name ?? 'laporan_pendapatan_traka.pdf';
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Buka PDF dengan aplikasi pembaca default (viewer sistem).
  static Future<OpenResult> openPdfFile(File file) => OpenFilex.open(file.path);

  /// Bagikan file PDF lewat sheet sistem.
  static Future<void> sharePdfFile(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Laporan Pendapatan Traka',
        text: 'Laporan pendapatan driver dari Aplikasi Traka. Diverifikasi oleh Traka.',
      ),
    );
  }

  /// Simpan lalu buka sheet share (alur lama; prefer [savePdfToFile] + [sharePdfFile]).
  static Future<void> sharePdf(PdfDocument document, {String? name}) async {
    final file = await savePdfToFile(document, name: name);
    await sharePdfFile(file);
  }
}
