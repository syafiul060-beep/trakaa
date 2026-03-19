import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';

/// Warna hijau untuk penjemputan (beda dengan oranye pengantaran).
const Color _penjemputanColor = Color(0xFF00B14F); // Grab green

/// Daftar penumpang/barang yang sudah kesepakatan dan menunggu dijemput.
/// Tampil di bawah zoom in/out (kanan atas). Tombol "Arahkan ke penumpang" → navigasi ke lokasi jemput.
/// Urutan vertikal: paling bawah = terdekat.
class WaitingPassengersListOverlay extends StatelessWidget {
  const WaitingPassengersListOverlay({
    super.key,
    required this.orders,
    required this.driverPosition,
    required this.onSelectPassenger,
  });

  final List<OrderModel> orders;
  final LatLng? driverPosition;
  final void Function(OrderModel order) onSelectPassenger;

  static String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();

    // Urutan: paling bawah terdekat (sort by distance ascending, tampil dari atas)
    final withDistance = orders.map((o) {
      final dist = driverPosition != null && o.passengerLat != null && o.passengerLng != null
          ? Geolocator.distanceBetween(
              driverPosition!.latitude,
              driverPosition!.longitude,
              o.passengerLat!,
              o.passengerLng!,
            )
          : double.infinity;
      return (order: o, distanceMeters: dist);
    }).toList();
    withDistance.sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters)); // Terdekat di bawah = index terakhir

    final colorScheme = Theme.of(context).colorScheme;
    const maxHeight = 220.0;
    return Positioned(
      top: 230, // Di bawah zoom in/out (MapTypeZoomControls ~60+170)
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _penjemputanColor.withValues(alpha: 0.5),
            ),
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
                        Icons.person_pin_circle,
                        size: 16,
                        color: _penjemputanColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Penjemputan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _penjemputanColor,
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
                      child: _PassengerCard(
                        order: item.order,
                        distanceText: item.distanceMeters < double.infinity
                            ? _formatDistance(item.distanceMeters)
                            : (driverPosition == null ? 'Memuat...' : '-'),
                        onArahkan: () => _showArahkanDialog(
                          context,
                          item.order,
                          onConfirm: () => onSelectPassenger(item.order),
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
    final label = order.isKirimBarang
        ? 'barang kiriman'
        : 'penumpang';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Text(
          'Apakah anda akan mengambil $label ini? Jika ya, anda akan diarahkan ke lokasi pemesan.',
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
            child: const Text('Ya, arahkan'),
          ),
        ],
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.order,
    required this.distanceText,
    required this.onArahkan,
  });

  final OrderModel order;
  final String distanceText;
  final VoidCallback onArahkan;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = order.passengerName.trim().isEmpty
        ? (order.isKirimBarang ? 'Barang' : 'Penumpang')
        : order.passengerName;

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
                backgroundColor: _penjemputanColor.withValues(alpha: 0.2),
                backgroundImage: (order.passengerPhotoUrl != null &&
                        order.passengerPhotoUrl!.trim().isNotEmpty)
                    ? CachedNetworkImageProvider(order.passengerPhotoUrl!)
                    : null,
                child: (order.passengerPhotoUrl == null ||
                        order.passengerPhotoUrl!.trim().isEmpty)
                    ? Icon(
                        order.isKirimBarang ? Icons.inventory_2 : Icons.person,
                        color: _penjemputanColor,
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
                      distanceText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _penjemputanColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onArahkan,
                icon: const Icon(Icons.person_pin_circle, size: 16),
                label: const Text('Arahkan'),
                style: FilledButton.styleFrom(
                  foregroundColor: _penjemputanColor,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
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
