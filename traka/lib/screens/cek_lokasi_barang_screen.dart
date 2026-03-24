import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../services/ferry_distance_service.dart';
import '../services/lacak_barang_service.dart';
import '../services/marker_icon_service.dart';
import '../services/sos_service.dart';
import '../utils/time_formatter.dart';
import '../widgets/passenger_track_map_widget.dart';

/// Halaman Lacak Barang: full-screen map dengan driver (marker + overlay mobil) + penerima/pengirim.
/// Pengirim lihat: driver + pin penerima (foto profil). Penerima lihat: driver + pin pengirim (foto profil).
/// Kebijakan ikon: `docs/KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md`.
class CekLokasiBarangScreen extends StatefulWidget {
  const CekLokasiBarangScreen({
    super.key,
    required this.orderId,
    required this.isPengirim,
    this.order,
  });

  final String orderId;
  final bool isPengirim;
  final OrderModel? order;

  @override
  State<CekLokasiBarangScreen> createState() => _CekLokasiBarangScreenState();
}

class _CekLokasiBarangScreenState extends State<CekLokasiBarangScreen> {
  Future<({OrderModel order, BitmapDescriptor? markerIcon})> _loadOrderAndMarkerIcon() async {
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    if (!snap.exists) throw Exception('Pesanan tidak ditemukan');
    final order = widget.order ?? OrderModel.fromFirestore(snap);
    BitmapDescriptor? markerIcon;
    try {
      // Hanya load icon yang dipakai: pengirim lihat penerima, penerima lihat pengirim
      if (widget.isPengirim) {
        markerIcon = await MarkerIconService.createProfilePhotoMarker(
          name: order.receiverName ?? 'Penerima',
          photoUrl: order.receiverPhotoUrl,
          ribbonColor: Colors.orange,
        );
      } else {
        markerIcon = await MarkerIconService.createProfilePhotoMarker(
          name: order.passengerName,
          photoUrl: order.passengerPhotoUrl,
          ribbonColor: Colors.orange,
        );
      }
    } catch (_) {}
    return (order: order, markerIcon: markerIcon);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<
          ({OrderModel order, BitmapDescriptor? markerIcon})>(
        future: _loadOrderAndMarkerIcon(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return _buildScaffold(
              child: snap.hasError
                  ? Center(child: Text('${snap.error}'))
                  : const Center(child: CircularProgressIndicator()),
            );
          }
          final data = snap.data!;
          final order = data.order;
          final driverUid = order.driverUid;
          if (driverUid.isEmpty) {
            return _buildScaffold(
              child: const Center(child: Text('Data driver tidak valid.')),
            );
          }

          final receiverLat = order.receiverLat ?? order.destLat ?? 0.0;
          final receiverLng = order.receiverLng ?? order.destLng ?? 0.0;
          final passengerLat = order.passengerLat ?? order.originLat ?? 0.0;
          final passengerLng = order.passengerLng ?? order.originLng ?? 0.0;

          if (passengerLat == 0 && passengerLng == 0) {
            return _buildScaffold(
              child: const Center(child: Text('Lokasi pengirim tidak valid.')),
            );
          }
          if (receiverLat == 0 && receiverLng == 0) {
            return _buildScaffold(
              child: const Center(child: Text('Lokasi penerima tidak valid.')),
            );
          }

          final defaultOrange =
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
          return PassengerTrackMapWidget(
            order: order,
            driverUid: driverUid,
            originLat: passengerLat,
            originLng: passengerLng,
            destLat: receiverLat,
            destLng: receiverLng,
            destForDistanceLat: receiverLat,
            destForDistanceLng: receiverLng,
            showSOS: true,
            onSOS: () => _onSOS(context, order),
            enableFerryDetection: true,
            extraMarkers: (driverPos) {
              final markers = <Marker>{};
              if (widget.isPengirim) {
                markers.add(Marker(
                  markerId: const MarkerId('penerima'),
                  position: LatLng(receiverLat, receiverLng),
                  icon: data.markerIcon ?? defaultOrange,
                  anchor: const Offset(0.5, 1.0),
                  infoWindow: InfoWindow(
                    title: 'Penerima',
                    snippet: order.receiverLocationText ?? order.destText,
                  ),
                ));
              } else {
                markers.add(Marker(
                  markerId: const MarkerId('pengirim'),
                  position: LatLng(passengerLat, passengerLng),
                  icon: data.markerIcon ?? defaultOrange,
                  anchor: const Offset(0.5, 1.0),
                  infoWindow: InfoWindow(
                    title: 'Pengirim',
                    snippet: order.passengerLocationText ?? order.originText,
                  ),
                ));
              }
              return markers;
            },
            bottomBuilder: (pos, isMoving, distanceMeters, distanceText, etaText, driverLocationText, ferryStatus) =>
                _LacakBarangBottomPanel(
              order: order,
              distanceText: distanceText,
              etaText: etaText,
              driverLocationText: driverLocationText,
              ferryStatus: ferryStatus,
            ),
          );
        },
      ),
    );
  }

  Widget _buildScaffold({required Widget child}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Kembali',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSOS(BuildContext context, OrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SOS Darurat'),
        content: const Text(
          'Kirim lokasi dan info pesanan ke admin via WhatsApp? Pastikan Anda dalam keadaan darurat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Kirim SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SosService.triggerSOSWithLocation(order: order, isDriver: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS terkirim. WhatsApp akan terbuka ke admin.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Panel bawah Lacak Barang: info barang, biaya, lokasi driver, jarak, ETA.
class _LacakBarangBottomPanel extends StatelessWidget {
  const _LacakBarangBottomPanel({
    required this.order,
    required this.distanceText,
    required this.etaText,
    required this.driverLocationText,
    this.ferryStatus,
  });

  final OrderModel order;
  final String distanceText;
  final String etaText;
  final String? driverLocationText;
  final FerryStatus? ferryStatus;

  String _formatRupiah(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  @override
  Widget build(BuildContext context) {
    final originLat = order.pickupLat ?? order.passengerLat ?? order.originLat ?? 0.0;
    final originLng = order.pickupLng ?? order.passengerLng ?? order.originLng ?? 0.0;
    final destLat = order.receiverLat ?? order.destLat ?? 0.0;
    final destLng = order.receiverLng ?? order.destLng ?? 0.0;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<(int tier, int fee)>(
          future: LacakBarangService.getTierAndFee(
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng,
          ),
          builder: (context, feeSnap) {
            final feeRupiah = feeSnap.data?.$2 ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info barang
                Row(
                  children: [
                    Icon(
                      order.barangCategory == OrderModel.barangCategoryDokumen
                          ? Icons.mail_outline
                          : Icons.inventory_2_outlined,
                      size: 20,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jenis: ${order.barangCategoryDisplayLabel}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (order.barangDetailDisplay != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              order.barangDetailDisplay!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (order.barangFotoUrl != null &&
                              order.barangFotoUrl!.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: order.barangFotoUrl!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (_, url, error) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Biaya Lacak Barang
                if (feeRupiah > 0) ...[
                  Text(
                    'Biaya Lacak Barang',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _buildBayarRow(
                          context,
                          'Pengirim',
                          order.passengerLacakBarangPaidAt != null,
                          feeRupiah,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBayarRow(
                          context,
                          'Penerima',
                          order.receiverLacakBarangPaidAt != null,
                          feeRupiah,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (ferryStatus != null && ferryStatus!.isOnFerry) ...[
                  Row(
                    children: [
                      Icon(Icons.directions_boat,
                          color: Colors.blue.shade700, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Driver sedang di kapal laut',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            if (ferryStatus!.etaPortAt != null)
                              Text(
                                'Estimasi tiba di pelabuhan: ${TimeFormatter.format12h(ferryStatus!.etaPortAt!)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            if (ferryStatus!.routeLabel != null)
                              Text(
                                'Rute: ${ferryStatus!.routeLabel}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ] else
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          color: Theme.of(context).colorScheme.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Driver sedang di: ${driverLocationText ?? 'Memuat...'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.straighten,
                        color: Theme.of(context).colorScheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sisa jarak ke penerima: $distanceText',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.access_time,
                        color: Colors.green.shade700, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Estimasi sampai ke penerima: $etaText',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBayarRow(
    BuildContext context,
    String label,
    bool sudahBayar,
    int feeRupiah,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: sudahBayar
            ? Colors.green.shade50
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sudahBayar ? 'Rp ${_formatRupiah(feeRupiah)} ✓' : 'Rp ${_formatRupiah(feeRupiah)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sudahBayar ? Colors.green.shade800 : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
