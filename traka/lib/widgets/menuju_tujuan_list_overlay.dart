import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../theme/app_interaction_styles.dart';
import '../theme/app_theme.dart';

/// Warna oranye untuk pengantaran (token Traka).
const Color _menujuTujuanColor = AppTheme.mapDropoffAccent;

/// Daftar penumpang/barang yang sudah dijemput dan menunggu diantar ke tujuan.
/// Tampil di Beranda driver. Tombol "Arahkan ke tujuan" → navigasi in-app ke destLat/destLng.
/// Urutan vertikal: paling bawah = terdekat ke tujuan.
class MenujuTujuanListOverlay extends StatelessWidget {
  const MenujuTujuanListOverlay({
    super.key,
    required this.orders,
    required this.driverPosition,
    required this.onSelectDestination,
    this.topOffset = 230,
  });

  final List<OrderModel> orders;
  final LatLng? driverPosition;
  final void Function(OrderModel order) onSelectDestination;
  /// Offset dari atas. Saat ada overlay Penjemputan di atas, gunakan 458.
  final double topOffset;

  static String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static (double?, double?) _getDestinationLatLng(OrderModel order) {
    if (order.isKirimBarang) {
      return (
        order.receiverLat ?? order.destLat,
        order.receiverLng ?? order.destLng,
      );
    }
    return (order.destLat, order.destLng);
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();

    // Filter: hanya order yang punya koordinat tujuan
    final withDest = orders.where((o) {
      final (lat, lng) = _getDestinationLatLng(o);
      return lat != null && lng != null;
    }).toList();
    if (withDest.isEmpty) return const SizedBox.shrink();

    // Urutan: paling bawah terdekat ke tujuan (sort by distance ascending)
    final withDistance = withDest.map((o) {
      final (lat, lng) = _getDestinationLatLng(o);
      final dist = driverPosition != null && lat != null && lng != null
          ? Geolocator.distanceBetween(
              driverPosition!.latitude,
              driverPosition!.longitude,
              lat,
              lng,
            )
          : double.infinity;
      return (order: o, distanceMeters: dist);
    }).toList();
    withDistance.sort(
        (a, b) => b.distanceMeters.compareTo(a.distanceMeters)); // Terdekat di bawah

    final colorScheme = Theme.of(context).colorScheme;
    const maxHeight = 200.0;
    return Positioned(
      top: topOffset,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _menujuTujuanColor.withValues(alpha: 0.5)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flag,
                          size: 16,
                          color: _menujuTujuanColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Menuju tujuan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _menujuTujuanColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...withDistance.asMap().entries.map((e) {
                      final i = e.key;
                      final item = e.value;
                      return Padding(
                        padding: EdgeInsets.only(top: i > 0 ? 6 : 0),
                        child: _DestinationCard(
                          order: item.order,
                          distanceText: item.distanceMeters < double.infinity
                              ? _formatDistance(item.distanceMeters)
                              : (driverPosition == null ? 'Memuat...' : '-'),
                          onArahkan: () => _showArahkanDialog(
                            context,
                            item.order,
                            onConfirm: () => onSelectDestination(item.order),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showArahkanDialog(
    BuildContext context,
    OrderModel order, {
    required VoidCallback onConfirm,
  }) {
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
              onConfirm();
            },
            style: AppInteractionStyles.elevatedPrimary(
              backgroundColor: _menujuTujuanColor,
              foregroundColor: Colors.white,
              shadowTint: _menujuTujuanColor,
            ),
            child: const Text('Ya, arahkan ke tujuan'),
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.order,
    required this.distanceText,
    required this.onArahkan,
  });

  final OrderModel order;
  final String distanceText;
  final VoidCallback onArahkan;

  static String _formatTujuanKecamatan(String destText) {
    if (destText.isEmpty) return '-';
    final parts = destText
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return destText;
    if (parts.length >= 2) {
      return '${parts[0]}, ${parts[1]}';
    }
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;
    final tujuanText = _formatTujuanKecamatan(order.destText);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onArahkan,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _menujuTujuanColor.withValues(alpha: 0.2),
                backgroundImage: (order.passengerPhotoUrl != null &&
                        order.passengerPhotoUrl!.trim().isNotEmpty)
                    ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                    : null,
                child: (order.passengerPhotoUrl == null ||
                        order.passengerPhotoUrl!.trim().isEmpty)
                    ? Icon(
                        order.isKirimBarang ? Icons.inventory_2 : Icons.person,
                        color: _menujuTujuanColor,
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tujuan: $tujuanText',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      distanceText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _menujuTujuanColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onArahkan,
                icon: const Icon(Icons.flag, size: 16),
                label: const Text('Arahkan'),
                style: AppInteractionStyles.elevatedPrimary(
                  backgroundColor: _menujuTujuanColor,
                  foregroundColor: Colors.white,
                  shadowTint: _menujuTujuanColor,
                ).copyWith(
                  elevation: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.pressed)) return 0.0;
                    return 2.0;
                  }),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  minimumSize: WidgetStateProperty.all(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
