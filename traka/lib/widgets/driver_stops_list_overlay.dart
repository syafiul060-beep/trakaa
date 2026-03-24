import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';

/// Warna untuk penjemputan dan pengantaran.
const Color _penjemputanColor = Color(0xFF00B14F); // Grab green
const Color _menujuTujuanColor = Color(0xFFE65100); // Orange 900

/// Panel list penumpang/barang di beranda driver (#6 + #7).
/// Urutan: greedy optimal (#7) jika [optimizedStops] disediakan, else pickup→dropoff.
/// Tap item → fokus map + navigasi ke lokasi.
class DriverStopsListOverlay extends StatelessWidget {
  const DriverStopsListOverlay({
    super.key,
    required this.pickupOrders,
    required this.dropoffOrders,
    required this.driverPosition,
    required this.onSelectPickup,
    required this.onSelectDropoff,
    this.optimizedStops = const [],
    this.stackTop = 230,
  });

  final List<OrderModel> pickupOrders;
  final List<OrderModel> dropoffOrders;
  final LatLng? driverPosition;
  final void Function(OrderModel order) onSelectPickup;
  final void Function(OrderModel order) onSelectDropoff;
  /// Urutan greedy optimal dari RouteOptimizationService (#7).
  final List<({OrderModel order, bool isPickup})> optimizedStops;
  /// Jarak dari atas Stack (portrait ~230; landscape lebih rendah agar tidak tabrak status bar).
  final double stackTop;

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  List<OrderModel> _sortedByDistance(List<OrderModel> orders, bool isPickup) {
    if (driverPosition == null) return orders;
    final withDist = orders.map((o) {
      double dist = double.infinity;
      if (isPickup) {
        final lat = o.passengerLat ?? o.originLat;
        final lng = o.passengerLng ?? o.originLng;
        if (lat != null && lng != null) {
          dist = Geolocator.distanceBetween(
            driverPosition!.latitude, driverPosition!.longitude, lat, lng,
          );
        }
      } else {
        final (lat, lng) = _getDestinationLatLng(o);
        if (lat != null && lng != null) {
          dist = Geolocator.distanceBetween(
            driverPosition!.latitude, driverPosition!.longitude, lat, lng,
          );
        }
      }
      return (order: o, dist: dist);
    }).toList();
    withDist.sort((a, b) => a.dist.compareTo(b.dist));
    return withDist.map((e) => e.order).toList();
  }

  static (double?, double?) _getDestinationLatLng(OrderModel order) {
    if (order.isKirimBarang) {
      return (order.receiverLat ?? order.destLat, order.receiverLng ?? order.destLng);
    }
    return (order.destLat, order.destLng);
  }

  @override
  Widget build(BuildContext context) {
    final useOptimized = optimizedStops.isNotEmpty;
    final hasPickups = pickupOrders.isNotEmpty;
    final hasDropoffs = dropoffOrders.isNotEmpty;
    if (!hasPickups && !hasDropoffs) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    const maxHeight = 380.0;

    return Positioned(
      top: stackTop,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Stop perjalanan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (useOptimized) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.route, size: 14, color: _penjemputanColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (useOptimized) ...[
                      ...optimizedStops.map((item) {
                        final lat = item.isPickup
                            ? (item.order.passengerLat ?? item.order.originLat)
                            : _getDestinationLatLng(item.order).$1;
                        final lng = item.isPickup
                            ? (item.order.passengerLng ?? item.order.originLng)
                            : _getDestinationLatLng(item.order).$2;
                        final dist = driverPosition != null && lat != null && lng != null
                            ? Geolocator.distanceBetween(
                                driverPosition!.latitude,
                                driverPosition!.longitude,
                                lat,
                                lng,
                              )
                            : double.infinity;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StopCard(
                            order: item.order,
                            isPickup: item.isPickup,
                            distanceText: dist < double.infinity
                                ? _formatDistance(dist)
                                : (driverPosition == null ? 'Memuat...' : '-'),
                            subtitle: item.isPickup ? null : _formatTujuanKecamatan(item.order.destText),
                            onTap: item.isPickup
                                ? () => _showPickupDialog(context, item.order)
                                : () => _showDropoffDialog(context, item.order),
                          ),
                        );
                      }),
                    ] else ...[
                      if (hasPickups) ...[
                        _SectionHeader(
                          icon: Icons.person_pin_circle,
                          label: 'Penjemputan',
                          color: _penjemputanColor,
                        ),
                        const SizedBox(height: 8),
                        ..._sortedByDistance(pickupOrders, true).map((o) {
                          final lat = o.passengerLat ?? o.originLat;
                          final lng = o.passengerLng ?? o.originLng;
                          final dist = driverPosition != null && lat != null && lng != null
                              ? Geolocator.distanceBetween(
                                  driverPosition!.latitude,
                                  driverPosition!.longitude,
                                  lat,
                                  lng,
                                )
                              : double.infinity;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StopCard(
                              order: o,
                              isPickup: true,
                              distanceText: dist < double.infinity
                                  ? _formatDistance(dist)
                                  : (driverPosition == null ? 'Memuat...' : '-'),
                              onTap: () => _showPickupDialog(context, o),
                            ),
                          );
                        }),
                        if (hasDropoffs) const SizedBox(height: 16),
                      ],
                      if (hasDropoffs) ...[
                        _SectionHeader(
                          icon: Icons.flag,
                          label: 'Pengantaran',
                          color: _menujuTujuanColor,
                        ),
                        const SizedBox(height: 8),
                        ..._sortedByDistance(dropoffOrders, false).map((o) {
                          final (lat, lng) = _getDestinationLatLng(o);
                          final dist = driverPosition != null && lat != null && lng != null
                              ? Geolocator.distanceBetween(
                                  driverPosition!.latitude,
                                  driverPosition!.longitude,
                                  lat,
                                  lng,
                                )
                              : double.infinity;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _StopCard(
                              order: o,
                              isPickup: false,
                              distanceText: dist < double.infinity
                                  ? _formatDistance(dist)
                                  : (driverPosition == null ? 'Memuat...' : '-'),
                              subtitle: _formatTujuanKecamatan(o.destText),
                              onTap: () => _showDropoffDialog(context, o),
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPickupDialog(BuildContext context, OrderModel order) {
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;
    final label = order.isKirimBarang ? 'barang kiriman' : 'penumpang';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Text(
          'Ambil $label ini? Anda akan diarahkan ke lokasi pemesan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSelectPickup(order);
            },
            child: const Text('Ya, arahkan'),
          ),
        ],
      ),
    );
  }

  void _showDropoffDialog(BuildContext context, OrderModel order) {
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;
    final tujuan = order.destText.isNotEmpty
        ? order.destText
        : (order.isKirimBarang ? 'lokasi penerima' : 'tujuan');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Text(
          'Arahkan ke $tujuan? Anda akan diarahkan ke lokasi tujuan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSelectDropoff(order);
            },
            style: FilledButton.styleFrom(backgroundColor: _menujuTujuanColor),
            child: const Text('Ya, arahkan ke tujuan'),
          ),
        ],
      ),
    );
  }

  static String _formatTujuanKecamatan(String destText) {
    if (destText.isEmpty) return '-';
    final parts = destText
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return destText;
    if (parts.length >= 2) return '${parts[0]}, ${parts[1]}';
    return parts.first;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.order,
    required this.isPickup,
    required this.distanceText,
    this.subtitle,
    required this.onTap,
  });

  final OrderModel order;
  final bool isPickup;
  final String distanceText;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isPickup ? _penjemputanColor : _menujuTujuanColor;
    final colorScheme = Theme.of(context).colorScheme;
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.2),
                backgroundImage: (order.passengerPhotoUrl != null &&
                        order.passengerPhotoUrl!.trim().isNotEmpty)
                    ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                    : null,
                child: (order.passengerPhotoUrl == null ||
                        order.passengerPhotoUrl!.trim().isEmpty)
                    ? Icon(
                        order.isKirimBarang ? Icons.inventory_2 : Icons.person,
                        color: color,
                        size: 22,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Tujuan: $subtitle',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      distanceText,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isPickup ? Icons.person_pin_circle : Icons.flag,
                color: color,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
