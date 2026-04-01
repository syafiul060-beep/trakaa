import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/active_drivers_service.dart';
import '../services/route_category_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_interaction_styles.dart';
import '../theme/responsive.dart';
import 'driver_eta_row.dart';
import 'traka_l10n_scope.dart';

/// Konten bottom sheet detail driver (nama, rating, foto, tujuan, ETA, data mobil, tombol Pesan Travel / Kirim Barang).
class PenumpangDriverDetailSheet extends StatelessWidget {
  const PenumpangDriverDetailSheet({
    super.key,
    required this.driver,
    required this.isVerified,
    required this.driverDisplayLat,
    required this.driverDisplayLng,
    this.passengerLat,
    this.passengerLng,
    this.isRecommended = false,
    required this.onPesanTravel,
    required this.onKirimBarang,
  });

  final ActiveDriverRoute driver;
  final bool isVerified;
  final double driverDisplayLat;
  final double driverDisplayLng;
  final double? passengerLat;
  final double? passengerLng;
  /// Driver terdekat di peta (ikon biru / rekomendasi).
  final bool isRecommended;
  final VoidCallback onPesanTravel;
  final VoidCallback onKirimBarang;

  static String _formatTujuanKecamatanKabupaten(String? fullAddress) {
    if (fullAddress == null || fullAddress.trim().isEmpty) return '-';
    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}, ${parts[parts.length - 1]}';
    }
    return fullAddress;
  }

  static Color _categoryColor(String category) {
    switch (category) {
      case RouteCategoryService.categoryDalamKota:
        return Colors.green.shade700;
      case RouteCategoryService.categoryAntarKabupaten:
        return Colors.teal.shade700;
      case RouteCategoryService.categoryAntarProvinsi:
        return Colors.blue.shade700;
      case RouteCategoryService.categoryNasional:
        return Colors.orange.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  static String _formatDataMobilDriver(ActiveDriverRoute d) {
    final merek = (d.vehicleMerek ?? '').trim();
    final type = (d.vehicleType ?? '').trim();
    if (merek.isEmpty && type.isEmpty) return '-';
    if (merek.isEmpty) return type;
    if (type.isEmpty) return merek;
    return '$merek $type';
  }

  @override
  Widget build(BuildContext context) {
    final l = TrakaL10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    tooltip: l.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.responsive.horizontalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          driver.driverName ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (driver.isVerified) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.verified,
                          size: 24,
                          color: cs.primary,
                        ),
                      ],
                    ],
                  ),
                  if (isRecommended) ...[
                    const SizedBox(height: 10),
                    Align(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              l.driverDetailRecommended,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (driver.averageRating != null && driver.reviewCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '${driver.averageRating!.toStringAsFixed(1)} (${driver.reviewCount} ulasan)',
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  DriverEtaRow(
                    key: ValueKey(driver.driverUid),
                    driverLat: driverDisplayLat,
                    driverLng: driverDisplayLng,
                    passengerLat: passengerLat,
                    passengerLng: passengerLng,
                    prominent: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: cs.outline,
                        backgroundImage:
                            (driver.driverPhotoUrl != null &&
                                    driver.driverPhotoUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(driver.driverPhotoUrl!)
                                : null,
                        child:
                            (driver.driverPhotoUrl == null ||
                                    driver.driverPhotoUrl!.isEmpty)
                                ? Icon(
                                    Icons.person,
                                    color: cs.onSurfaceVariant,
                                    size: 28,
                                  )
                                : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tujuan: ${_formatTujuanKecamatanKabupaten(driver.routeDestText)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            FutureBuilder<
                                ({
                                  String category,
                                  String label,
                                  String estimatedDuration
                                })>(
                              future: RouteCategoryService.getRouteCategory(
                                originLat: driver.routeOriginLat,
                                originLng: driver.routeOriginLng,
                                destLat: driver.routeDestLat,
                                destLng: driver.routeDestLng,
                              ),
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cs.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          l.loadingRouteCategory,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                if (!snap.hasData) {
                                  return const SizedBox.shrink();
                                }
                                final data = snap.data!;
                                return Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _categoryColor(data.category)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        data.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _categoryColor(data.category),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      data.estimatedDuration,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _formatDataMobilDriver(driver),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.people, size: 18, color: AppTheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  driver.remainingPassengerCapacity != null
                                      ? (driver.hasPassengerCapacity
                                          ? 'Sisa ${driver.remainingPassengerCapacity} kursi'
                                          : 'Penuh')
                                      : (driver.maxPassengers != null
                                          ? '${driver.maxPassengers} kursi'
                                          : '-'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: driver.hasPassengerCapacity
                                        ? AppTheme.primary
                                        : Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              driver.hasPassengerCapacity ? onPesanTravel : null,
                          icon: const Icon(Icons.chat_bubble_outline, size: 20),
                          label: Text(
                            driver.hasPassengerCapacity ? 'Pesan Travel' : 'Penuh',
                          ),
                          style: AppInteractionStyles.filledFromTheme(
                            context,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onKirimBarang,
                          icon: const Icon(Icons.inventory_2, size: 20),
                          label: const Text('Kirim Barang'),
                          style: AppInteractionStyles.filledFromTheme(
                            context,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!driver.hasPassengerCapacity) ...[
                    const SizedBox(height: 10),
                    Text(
                      l.travelFullTryOtherDriver,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
