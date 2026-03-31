import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../services/ferry_distance_service.dart';
import '../services/lacak_barang_service.dart';
import '../services/order_service.dart';
import '../services/traka_pin_bitmap_service.dart';
import '../services/sos_service.dart';
import '../widgets/lacak_tracking_info_sheet.dart';
import '../widgets/sos_emergency_confirm_dialog.dart';
import '../widgets/traka_l10n_scope.dart';
import '../utils/time_formatter.dart';

import '../widgets/passenger_track_map_widget.dart';

/// Halaman Lacak Barang: driver (mobil hijau/merah) + pin awal (pengirim) + pin akhir (penerima).
/// Kamera: fase jemput = pengirim + driver; setelah pickup = penerima + driver.
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<OrderModel?>(
        stream: OrderService.streamOrderById(widget.orderId),
        builder: (context, snap) {
          if (snap.hasError) {
            return _buildScaffold(
              child: Center(child: Text('${snap.error}')),
            );
          }
          final order = snap.data;
          if (order == null) {
            return _buildScaffold(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : const Center(child: Text('Pesanan tidak ditemukan.')),
            );
          }
          return FutureBuilder<void>(
            future: TrakaPinBitmapService.ensureLoaded(context),
            builder: (context, _) {
              final driverUid = order.driverUid;
              if (driverUid.isEmpty) {
                return _buildScaffold(
                  child: const Center(child: Text('Data driver tidak valid.')),
                );
              }

              final senderPair = order.coordsForDriverPickupProximity;
              final dropoffPair = order.coordsForDriverDropoffProximity;
              final passengerLat = senderPair?.$1 ??
                  order.passengerLat ??
                  order.originLat ??
                  0.0;
              final passengerLng = senderPair?.$2 ??
                  order.passengerLng ??
                  order.originLng ??
                  0.0;
              final receiverLat =
                  dropoffPair?.$1 ?? order.receiverLat ?? order.destLat ?? 0.0;
              final receiverLng =
                  dropoffPair?.$2 ?? order.receiverLng ?? order.destLng ?? 0.0;

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
              final iconAwal = TrakaPinBitmapService.mapAwal ?? defaultOrange;
              final iconAhir = TrakaPinBitmapService.mapAhir ?? defaultOrange;

              final pickupPhase = order.status != OrderService.statusPickedUp;
              final destForPair =
                  pickupPhase ? senderPair ?? (passengerLat, passengerLng) : dropoffPair ?? (receiverLat, receiverLng);
              final destForDistanceLat = destForPair.$1;
              final destForDistanceLng = destForPair.$2;
              final focalLat = pickupPhase ? passengerLat : receiverLat;
              final focalLng = pickupPhase ? passengerLng : receiverLng;

              return _buildScaffold(
                child: PassengerTrackMapWidget(
                  order: order,
                  driverUid: driverUid,
                  originLat: passengerLat,
                  originLng: passengerLng,
                  destLat: receiverLat,
                  destLng: receiverLng,
                  destForDistanceLat: destForDistanceLat,
                  destForDistanceLng: destForDistanceLng,
                  useDualPartyBoundsCamera: true,
                  dualPartyFocalLat: focalLat,
                  dualPartyFocalLng: focalLng,
                  showSOS: true,
                  onSOS: () => _onSOS(context, order),
                  enableFerryDetection: true,
                  extraMarkers: (driverPos) {
                    return {
                      Marker(
                        markerId: const MarkerId('pengirim'),
                        position: LatLng(passengerLat, passengerLng),
                        icon: iconAwal,
                        anchor: const Offset(0.5, 1.0),
                        infoWindow: InfoWindow(
                          title: 'Pengirim',
                          snippet: order.passengerLocationText ?? order.originText,
                        ),
                      ),
                      Marker(
                        markerId: const MarkerId('penerima'),
                        position: LatLng(receiverLat, receiverLng),
                        icon: iconAhir,
                        anchor: const Offset(0.5, 1.0),
                        infoWindow: InfoWindow(
                          title: 'Penerima',
                          snippet: order.receiverLocationText ?? order.destText,
                        ),
                      ),
                    };
                  },
                  bottomBuilder: (pos, isMoving, distanceMeters, distanceText, etaText, driverLocationText, ferryStatus) =>
                      _LacakBarangBottomPanel(
                    order: order,
                    pickupPhase: pickupPhase,
                    distanceText: distanceText,
                    etaText: etaText,
                    driverLocationText: driverLocationText,
                    ferryStatus: ferryStatus,
                  ),
                ),
              );
            },
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
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: TrakaL10n.of(context).mapToolsLacakHelpTitle,
              onPressed: () => unawaited(
                showLacakTrackingInfoSheet(
                  context,
                  audience: LacakTrackingAudience.lacakBarangMap,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSOS(BuildContext context, OrderModel order) async {
    final confirmed = await showSosEmergencyConfirmDialog(context);
    if (confirmed != true || !context.mounted) return;
    await SosService.triggerSOSWithLocation(order: order, isDriver: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TrakaL10n.of(context).sosSent),
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
    required this.pickupPhase,
    required this.distanceText,
    required this.etaText,
    required this.driverLocationText,
    this.ferryStatus,
  });

  final OrderModel order;
  /// True = driver menuju pengirim (belum picked_up).
  final bool pickupPhase;
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (_, url, error) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Icon(Icons.broken_image,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
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
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant,
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
                        'Sisa jarak ke ${pickupPhase ? 'pengirim' : 'penerima'}: $distanceText',
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
                        'Estimasi sampai ke ${pickupPhase ? 'pengirim' : 'penerima'}: $etaText',
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
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
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
            sudahBayar
                ? 'Rp ${_formatRupiah(feeRupiah)} ✓'
                : 'Rp ${_formatRupiah(feeRupiah)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sudahBayar
                  ? Colors.green.shade800
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
