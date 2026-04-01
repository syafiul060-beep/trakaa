import 'package:flutter/material.dart';

import '../services/app_analytics_service.dart';
import 'traka_bottom_sheet.dart';

/// Konteks penjelasan lokasi & lacak (dipakai analytics + teks).
enum LacakTrackingAudience {
  lacakDriverMap,
  lacakBarangMap,
  profilePenumpang,
  profileDriver,
}

Future<void> showLacakTrackingInfoSheet(
  BuildContext context, {
  required LacakTrackingAudience audience,
}) async {
  AppAnalyticsService.logLacakHelpOpen(audience: audience.name);
  await showTrakaModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final (title, bullets) = _contentFor(audience);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 14),
              for (final b in bullets) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        b,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Mengerti'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

(String title, List<String> bullets) _contentFor(LacakTrackingAudience a) {
  switch (a) {
    case LacakTrackingAudience.lacakDriverMap:
      return (
        'Lacak driver di peta',
        [
          'Titik mobil diperbarui saat driver dalam status Siap Kerja (rute aktif) atau sedang navigasi penjemputan.',
          'Jika driver tidak aktif atau menyelesaikan kerja, pelacakan ke server dihentikan untuk menghemat baterai dan kuota — titik bisa berhenti bergerak; itu bukan error aplikasi.',
          'Di Android biasanya muncul notifikasi «Traka — navigasi aktif» saat GPS tetap jalan di belakang layar.',
          'Jadwal «Pesan nanti» mengikuti aturan tanggal dan driver yang sudah aktif di jadwal tersebut.',
        ],
      );
    case LacakTrackingAudience.lacakBarangMap:
      return (
        'Lacak kirim barang',
        [
          'Fase penjemputan: lolipop kuning (pengirim) diperbarui sampai barang dijemput atau konfirmasi. Lolipop hijau (penerima) menunjukkan tujuan.',
          'Setelah jemput: pengirim tidak lagi mengirim lokasi; yang diperbarui adalah titik penerima selama pengantaran.',
          'Selesai (pesanan selesai) atau setelah konfirmasi terima: tidak ada pembaruan lokasi otomatis, termasuk saat aplikasi di latar belakang.',
          'Jika titik tidak bergerak, pastikan pihak yang wajib membagikan lokasi mengizinkan GPS dan tidak membatasi baterai agresif.',
        ],
      );
    case LacakTrackingAudience.profilePenumpang:
      return (
        'Lokasi untuk pesanan & lacak',
        [
          'Lokasi Anda dapat dikirim ke pesanan saat sudah sepakat (agreed) dan belum konfirmasi jemput (scan atau otomatis). Setelah itu, pembaruan lokasi penjemputan dihentikan.',
          'Untuk kirim barang, setelah barang jemput, yang membagikan lokasi ke tujuan adalah penerima sampai pesanan selesai atau dikonfirmasi terima.',
          'Saat tidak ada pesanan yang memerlukan pembagian lokasi, aplikasi tidak melanjutkan stream GPS di latar belakang untuk itu (hemat baterai dan data).',
          'Izin lokasi «Selalu» atau saat dipakai membantu ketika Anda menutup atau mengunci layar.',
        ],
      );
    case LacakTrackingAudience.profileDriver:
      return (
        'Lokasi & pelacakan (driver)',
        [
          'Posisi Anda dikirim ke penumpang **hanya** saat **Siap Kerja** (rute aktif) atau navigasi penjemputan — agar lacak driver & kirim barang akurat.',
          'Jika Anda **tidak aktif** atau aplikasi di **latar belakang** (minimize / layar mati) dalam keadaan tidak kerja, polling GPS tambahan dihentikan untuk menghemat baterai dan kuota.',
          'Pastikan izin lokasi sesuai (idealnya «Selalu» saat kerja) dan hindari optimasi baterai yang membekukan Traka.',
          'Penumpang melihat pesan di lacak jika titik tertunda: sering karena driver belum Siap Kerja atau jaringan/GPS terbatas.',
        ],
      );
  }
}
