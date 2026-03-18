import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/active_drivers_service.dart';
import '../services/route_category_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'driver_eta_row.dart';

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
    required this.onPesanTravel,
    required this.onKirimBarang,
  });

  final ActiveDriverRoute driver;
  final bool isVerified;
  final double driverDisplayLat;
  final double driverDisplayLng;
  final double? passengerLat;
  final double? passengerLng;
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.all(context.responsive.horizontalPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.outline,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    FutureBuilder<
                        ({String category, String label, String estimatedDuration})>(
                      future: RouteCategoryService.getRouteCategory(
                        originLat: driver.routeOriginLat,
                        originLng: driver.routeOriginLng,
                        destLat: driver.routeDestLat,
                        destLng: driver.routeDestLng,
                      ),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    DriverEtaRow(
                      driverLat: driverDisplayLat,
                      driverLng: driverDisplayLng,
                      passengerLat: passengerLat,
                      passengerLng: passengerLng,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatDataMobilDriver(driver),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  onPressed: driver.hasPassengerCapacity ? onPesanTravel : null,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: Text(
                    driver.hasPassengerCapacity ? 'Pesan Travel' : 'Penuh',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onKirimBarang,
                  icon: const Icon(Icons.inventory_2, size: 20),
                  label: const Text('Kirim Barang'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
