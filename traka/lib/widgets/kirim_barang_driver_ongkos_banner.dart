import 'package:flutter/material.dart';

import '../models/order_model.dart';

/// Info untuk driver: siapa yang menanggung ongkos travel (kirim barang + hybrid).
class KirimBarangDriverOngkosBanner extends StatelessWidget {
  const KirimBarangDriverOngkosBanner({
    super.key,
    required this.order,
    this.dense = false,
  });

  final OrderModel order;

  /// Satu baris tipis (chat / dialog); false = kartu penjelasan (Data Order).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (!order.isKirimBarang) return const SizedBox.shrink();
    final receiverPays =
        order.effectiveTravelFarePaidBy == OrderModel.travelFarePaidByReceiver;
    final scheme = Theme.of(context).colorScheme;
    final title = receiverPays
        ? 'Ongkos travel ditanggung penerima'
        : 'Ongkos travel ditanggung pengirim';
    final subtitle = receiverPays
        ? 'Penerima konfirmasi bayar di app sebelum scan terima barang.'
        : 'Pengirim konfirmasi bayar di app sebelum scan jemput barang.';

    if (dense) {
      return Material(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  receiverPays
                      ? 'Ongkos ke driver: penerima barang'
                      : 'Ongkos ke driver: pengirim barang',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.payments_outlined, size: 22, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
