import 'package:flutter/material.dart';

import '../services/app_config_service.dart';
import 'traka_l10n_scope.dart';

/// Dialog yang menampilkan jenis tarif kontribusi dan contoh perhitungan.
/// Penjelasan tier selaras dengan [LacakBarangService] & rumus di OrderService.
Future<void> showContributionTariffDialog(BuildContext context) async {
  final min = await AppConfigService.getMinKontribusiTravelRupiah();
  final t1 = await AppConfigService.getTarifKontribusiTravelPerKm(1);
  final t2 = await AppConfigService.getTarifKontribusiTravelPerKm(2);
  final t3 = await AppConfigService.getTarifKontribusiTravelPerKm(3);
  final maxRute = await AppConfigService.getMaxKontribusiTravelPerRuteRupiah();
  final b1 = await AppConfigService.getTarifBarangPerKmWithCategory(1, null);
  final b2 = await AppConfigService.getTarifBarangPerKmWithCategory(2, null);
  final b3 = await AppConfigService.getTarifBarangPerKmWithCategory(3, null);
  final d1 = await AppConfigService.getTarifBarangPerKmWithCategory(1, 'dokumen');
  final d2 = await AppConfigService.getTarifBarangPerKmWithCategory(2, 'dokumen');
  final d3 = await AppConfigService.getTarifBarangPerKmWithCategory(3, 'dokumen');

  String fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

  // Contoh travel (tier 1)
  const contohTravelKm = 52;
  final byDistance = (contohTravelKm * t1).round();
  final baseTravel = byDistance > min ? byDistance : min;

  // Contoh barang
  const contohBarangKm = 30;
  final contribB1 = contohBarangKm * b1;
  final contribD1 = contohBarangKm * d1;

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
              l10n.contributionTariffDialogIntro,
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.contributionTariffTierTableTitle,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text('• ${l10n.contributionTariffTier1Desc}', style: _bodyStyle(ctx)),
            Text('• ${l10n.contributionTariffTier2Desc}', style: _bodyStyle(ctx)),
            Text('• ${l10n.contributionTariffTier3Desc}', style: _bodyStyle(ctx)),
            const SizedBox(height: 6),
            Text(
              l10n.contributionTariffSameProvinceNote,
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _sectionHeader(ctx, l10n.contributionTariffTravelSectionTitle, Icons.directions_car),
            const SizedBox(height: 6),
            Text(
              l10n.contributionTariffTravelRates(fmt(t1), fmt(t2), fmt(t3), fmt(min)),
              style: _bodyStyle(ctx),
            ),
            const SizedBox(height: 4),
            Text(l10n.contributionTariffTravelFormula, style: _bodyStyle(ctx)),
            const SizedBox(height: 4),
            if (maxRute != null)
              Text(
                l10n.contributionTariffTravelCapPerRoute(fmt(maxRute)),
                style: _bodyStyle(ctx),
              ),
            const SizedBox(height: 8),
            _exampleBox(ctx, l10n.contributionTariffTravelExampleTitle(contohTravelKm, fmt(t1)), [
              l10n.contributionTariffExTravelBase(
                '$contohTravelKm',
                fmt(t1),
                fmt(byDistance),
                fmt(min),
                fmt(baseTravel),
              ),
              l10n.contributionTariffExTravelOnePax(fmt(baseTravel)),
              l10n.contributionTariffExTravelFourPax(fmt(4 * baseTravel)),
            ]),
            const SizedBox(height: 16),
            _sectionHeader(ctx, l10n.contributionTariffBarangSectionTitle, Icons.inventory_2_outlined),
            const SizedBox(height: 6),
            Text(l10n.contributionTariffBarangRates(fmt(b1), fmt(b2), fmt(b3)), style: _bodyStyle(ctx)),
            const SizedBox(height: 4),
            Text(l10n.contributionTariffBarangDokumenRates(fmt(d1), fmt(d2), fmt(d3)), style: _bodyStyle(ctx)),
            const SizedBox(height: 4),
            Text(l10n.contributionTariffBarangFormula, style: _bodyStyle(ctx)),
            const SizedBox(height: 8),
            _exampleBox(ctx, l10n.contributionTariffExampleBarang(contohBarangKm), [
              l10n.contributionTariffExBarangTier(
                l10n.contributionTariffExBarangTier1,
                '$contohBarangKm',
                fmt(b1),
                fmt(contribB1),
              ),
              l10n.contributionTariffExBarangTier(
                l10n.contributionTariffExBarangTier1Doc,
                '$contohBarangKm',
                fmt(d1),
                fmt(contribD1),
              ),
            ]),
            const SizedBox(height: 12),
            Text(l10n.contributionTariffViolationNote, style: _bodyStyle(ctx)),
            const SizedBox(height: 8),
            Text(
              l10n.contributionTariffGeocodingNote,
              style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Text(l10n.contributionTariffGooglePlayNominals, style: _bodyStyle(ctx)),
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
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Theme.of(ctx).colorScheme.onSurface,
          ),
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
