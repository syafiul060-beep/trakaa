import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/order_model.dart';

/// PDF struk penumpang/penerima + QR verifikasi `profil.html?bukti=`.
class PassengerReceiptPdfService {
  PassengerReceiptPdfService._();

  static String _sanitize(String s) {
    return s.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), '?');
  }

  static String _fmtRp(double? n) {
    if (n == null) return '-';
    final v = n.round();
    return 'Rp ${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static Future<Uint8List> _qrPngBytes(String data, int size) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = Colors.white,
    );
    painter.paint(canvas, Size.square(size.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) {
      throw StateError('QR image');
    }
    return bd.buffer.asUint8List();
  }

  static Future<PdfDocument> buildDocument({
    required OrderModel order,
    required String verifyUrl,
    bool issuerIsDriver = false,
  }) async {
    final document = PdfDocument();
    final page = document.pages.add();
    final g = page.graphics;
    final pageW = page.getClientSize().width;
    const margin = 28.0;
    double y = margin;

    final brandBlue = PdfColor(37, 99, 235);
    g.drawRectangle(
      brush: PdfSolidBrush(brandBlue),
      bounds: Rect.fromLTWH(0, 0, pageW, 3),
    );

    final font = PdfStandardFont(PdfFontFamily.courier, 10);
    final fontBold = PdfStandardFont(PdfFontFamily.courier, 10, style: PdfFontStyle.bold);
    final fontTitle = PdfStandardFont(PdfFontFamily.courier, 13, style: PdfFontStyle.bold);
    final fontSmall = PdfStandardFont(PdfFontFamily.courier, 8);
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final grey = PdfSolidBrush(PdfColor(90, 90, 90));

    y = margin + 8;
    g.drawString(
      issuerIsDriver
          ? 'BUKTI PERJALANAN / KIRIM BARANG — TRAKA (DRIVER)'
          : 'BUKTI PERJALANAN / KIRIM BARANG — TRAKA',
      fontTitle,
      brush: black,
      bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 22),
    );
    y += 26;

    if (issuerIsDriver) {
      g.drawString(
        'Penerbit: driver — verifikasi URL sama dengan struk penumpang/penerima.',
        fontSmall,
        brush: grey,
        bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 22),
      );
      y += 20;
    }

    final jenis = order.isKirimBarang
        ? 'Kirim barang'
        : (order.totalPenumpang > 1
            ? 'Travel (${order.totalPenumpang} orang)'
            : 'Travel (1 orang)');

    void line(String label, String value) {
      g.drawString(
        '$label: ${_sanitize(value)}',
        font,
        brush: black,
        bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 14),
      );
      y += 13;
    }

    line('No. pesanan', order.orderNumber ?? order.id);
    line('Jenis', jenis);
    line('Selesai', _fmtDate(order.completedAt));
    line('Asal', order.originText);
    line('Tujuan', order.destText);
    if (order.tripDistanceKm != null && order.tripDistanceKm! >= 0) {
      line('Jarak', '${order.tripDistanceKm!.toStringAsFixed(1)} km');
    }
    if (order.agreedPrice != null && order.agreedPrice! >= 0) {
      line('Harga kesepakatan', _fmtRp(order.agreedPrice));
    }
    if (order.tripFareRupiah != null && order.tripFareRupiah! > 0) {
      line('Tarif jarak (referensi)', _fmtRp(order.tripFareRupiah));
    }
    if (order.tripBarangFareRupiah != null && order.tripBarangFareRupiah! > 0) {
      line('Tarif kirim (referensi)', _fmtRp(order.tripBarangFareRupiah));
    }

    y += 8;
    g.drawString(
      'Traka bukan pemegang dana. Nominal di atas mencerminkan data tercatat di aplikasi.',
      fontSmall,
      brush: grey,
      bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 28),
    );
    y += 30;

    g.drawString(
      'Verifikasi online (scan QR) — berlaku 6 hari sejak diterbitkan:',
      fontBold,
      brush: black,
      bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 14),
    );
    y += 16;

    final qrBytes = await _qrPngBytes(verifyUrl, 200);
    final qrBmp = PdfBitmap(qrBytes);
    const qrSize = 120.0;
    g.drawImage(
      qrBmp,
      Rect.fromLTWH(margin, y, qrSize, qrSize),
    );
    y += qrSize + 10;

    g.drawString(
      _sanitize(verifyUrl),
      fontSmall,
      brush: grey,
      bounds: Rect.fromLTWH(margin, y, pageW - 2 * margin, 36),
    );

    return document;
  }

  static Future<File> savePdfToFile(PdfDocument document, {required String name}) async {
    final bytes = await document.save();
    document.dispose();
    final tempDir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^\w\-.]+'), '_');
    final file = File('${tempDir.path}/$safe');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<OpenResult> openPdfFile(File file) => OpenFilex.open(file.path);

  static Future<void> sharePdfFile(
    File file, {
    String subject = 'Struk Traka',
    String text = 'Bukti perjalanan Traka — verifikasi lewat QR pada PDF.',
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: subject,
        text: text,
      ),
    );
  }
}
