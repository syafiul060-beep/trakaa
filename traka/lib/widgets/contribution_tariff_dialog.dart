import 'package:flutter/material.dart';

import '../services/app_config_service.dart';
import 'traka_l10n_scope.dart';

/// Dialog yang menampilkan jenis tarif kontribusi dan contoh perhitungan.
Future<void> showContributionTariffDialog(BuildContext context) async {
  final min = await AppConfigService.getMinKontribusiTravelRupiah();
  final t1 = await AppConfigService.getTarifKontribusiTravelPerKm(1);
  final t2 = await AppConfigService.getTarifKontribusiTravelPerKm(2);
  final t3 = await AppConfigService.getTarifKontribusiTravelPerKm(3);
  final maxRute = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah();
  final b1 = await AppConfigService.getTarifBarangPerKm(1);
  final b2 = await AppConfigService.getTarifBarangPerKm(2);
  final b3 = await AppConfigService.getTarifBarangPerKm(3);

  final fmt = (int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  // Contoh travel
  const contohTravelKm = 52;
  final byDistance = (contohTravelKm * t1).round();
  final baseTravel = byDistance > min ? byDistance : min;
  // Contoh barang
  const contohBarangKm = 30;
  final contribB1 = contohBarangKm * b1;
  final contribB2 = contohBarangKm * b2;
  final contribB3 = contohBarangKm * b3;

  if (!context.mounted) return;
  final l10n = TrakaL10n.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.receipt_long, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.contributionTariffDialogTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kontribusi dibayar per rute. Tarif tergantung jarak dan kategori rute.',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _sectionHeader(ctx, '1. Travel (antar kota)', Icons.directions_car),
            const SizedBox(height: 6),
            Text(
              'Kategori jarak:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text('• Dalam provinsi = 1 provinsi (mis. Bandung–Cirebon)', style: _bodyStyle(ctx)),
            Text('• Antar provinsi = 2 provinsi (mis. Bandung–Jakarta)', style: _bodyStyle(ctx)),
            Text('• Lintas pulau = 3+ provinsi (mis. Jawa–Sumatera)', style: _bodyStyle(ctx)),
            const SizedBox(height: 6),
            Text(
              'Rumus: (Jarak km × tarif/km) × jumlah penumpang. Min Rp ${fmt(min)}, max Rp ${maxRute != null ? fmt(maxRute) : "—"} per rute.',
              style: _bodyStyle(ctx),
            ),
            const SizedBox(height: 4),
            Text(
              'Tarif per km: dalam provinsi Rp ${fmt(t1)}, antar provinsi Rp ${fmt(t2)}, lintas pulau Rp ${fmt(t3)}.',
              style: _bodyStyle(ctx),
            ),
            const SizedBox(height: 10),
            _exampleBox(ctx, 'Contoh A: $contohTravelKm km dalam provinsi (Rp ${fmt(t1)}/km)', [
              'Dasar: $contohTravelKm × ${fmt(t1)} = Rp ${fmt(byDistance)} → min Rp ${fmt(min)} = Rp ${fmt(baseTravel)}',
              '1 penumpang: 1 × Rp ${fmt(baseTravel)} = Rp ${fmt(baseTravel)}',
              '4 penumpang (1 + 3 kerabat): 4 × Rp ${fmt(baseTravel)} = Rp ${fmt(4 * baseTravel)}',
            ]),
            const SizedBox(height: 16),
            _sectionHeader(ctx, l10n.contributionTariffBarangLabel, Icons.inventory_2_outlined),
            const SizedBox(height: 6),
            Text(
              l10n.contributionTariffBarangRates(fmt(b1), fmt(b2), fmt(b3)),
              style: _bodyStyle(ctx),
            ),
            const SizedBox(height: 10),
            _exampleBox(ctx, 'Contoh: $contohBarangKm km kirim barang', [
              'Dalam provinsi: $contohBarangKm × Rp ${fmt(b1)}/km = Rp ${fmt(contribB1)}',
              'Antar provinsi: $contohBarangKm × Rp ${fmt(b2)}/km = Rp ${fmt(contribB2)}',
              'Lintas pulau: $contohBarangKm × Rp ${fmt(b3)}/km = Rp ${fmt(contribB3)}',
            ]),
            const SizedBox(height: 16),
            _sectionHeader(ctx, '3. Pembayaran via Google Play', Icons.payment),
            const SizedBox(height: 6),
            Text(
              'Pilih nominal terdekat: Rp 5.000, Rp 7.500, Rp 10.000, Rp 12.500, Rp 15.000, Rp 20.000, Rp 25.000, Rp 30.000, Rp 40.000, Rp 50.000.',
              style: _bodyStyle(ctx),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.contributionTariffAdminNote,
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(TrakaL10n.of(ctx).close),
        ),
      ],
    ),
  );
}

TextStyle _bodyStyle(BuildContext ctx) =>
    TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant);

Widget _sectionHeader(BuildContext ctx, String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 18, color: Theme.of(ctx).colorScheme.primary),
      const SizedBox(width: 6),
      Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(ctx).colorScheme.onSurface,
        ),
      ),
    ],
  );
}

Widget _exampleBox(BuildContext ctx, String title, List<String> lines) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        ...lines.map((line) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $line', style: _bodyStyle(ctx)),
            )),
      ],
    ),
  );
}
