import 'package:flutter/material.dart';

import '../utils/safe_navigation_utils.dart';

/// Jenis dokumen untuk panduan foto.
enum DocumentCaptureType { ktp, sim, stnk }

/// Dialog panduan foto dokumen sebelum membuka kamera.
/// Menampilkan bingkai overlay dan instruksi agar hasil OCR lebih akurat.
class DocumentCaptureGuideDialog {
  DocumentCaptureGuideDialog._();

  static String _getTitle(DocumentCaptureType type) {
    switch (type) {
      case DocumentCaptureType.ktp:
        return 'Panduan foto KTP';
      case DocumentCaptureType.sim:
        return 'Panduan foto SIM';
      case DocumentCaptureType.stnk:
        return 'Panduan foto STNK';
    }
  }

  static String _getHint(DocumentCaptureType type) {
    switch (type) {
      case DocumentCaptureType.ktp:
        return 'Tips agar KTP terbaca dengan baik:\n'
            '• Cahaya cukup, hindari bayangan dan silau pada laminasi\n'
            '• Tahan HP tetap, tunggu fokus kamera sebelum memotret\n'
            '• Jika buram, coba sudut lain atau pencahayaan berbeda\n'
            '• Tutup aplikasi lain jika HP RAM terbatas';
      case DocumentCaptureType.sim:
        return 'Tips agar SIM terbaca dengan baik:\n'
            '• Cahaya cukup, hindari bayangan dan silau pada laminasi\n'
            '• Tahan HP tetap, tunggu fokus kamera sebelum memotret\n'
            '• Jika buram, coba sudut lain atau pencahayaan berbeda\n'
            '• Tutup aplikasi lain jika HP RAM terbatas';
      case DocumentCaptureType.stnk:
        return 'Pastikan STNK/nomor plat dalam bingkai, tidak buram, dan cahaya cukup. '
            'Tunggu fokus kamera sebelum memotret.';
    }
  }

  /// Tampilkan dialog panduan. Return true jika user tap "Ambil foto", false jika batal.
  static Future<bool> show(
    BuildContext context, {
    required DocumentCaptureType documentType,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_getTitle(documentType)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _getHint(documentType),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              // Bingkai visual sebagai panduan posisi dokumen
              Container(
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.6),
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.document_scanner_outlined,
                    size: 48,
                    color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => safePop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => safePop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 20),
            label: const Text('Ambil foto'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
