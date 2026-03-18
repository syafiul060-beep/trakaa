import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../services/marker_icon_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/sos_service.dart';
import '../widgets/passenger_track_map_widget.dart';

/// Halaman Lacak Driver: full-screen map hybrid, posisi driver dengan icon mobil
/// (car_hijau = bergerak, car_merah = tidak bergerak). Pin penumpang + foto profil.
/// Pergerakan halus (semut) dan mengikuti alur jalan (snap-to-road).
class CekLokasiDriverScreen extends StatefulWidget {
  const CekLokasiDriverScreen({
    super.key,
    required this.orderId,
    this.order,
  });

  final String orderId;
  final OrderModel? order;

  @override
  State<CekLokasiDriverScreen> createState() => _CekLokasiDriverScreenState();
}

class _CekLokasiDriverScreenState extends State<CekLokasiDriverScreen> {
  Future<({OrderModel order, BitmapDescriptor? penumpangIcon})> _loadOrderAndMarkerIcon() async {
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    if (!snap.exists) throw Exception('Pesanan tidak ditemukan');
    final order = widget.order ?? OrderModel.fromFirestore(snap);
    BitmapDescriptor? penumpangIcon;
    try {
      penumpangIcon = await MarkerIconService.createProfilePhotoMarker(
        name: order.passengerName,
        photoUrl: order.passengerPhotoUrl,
        ribbonColor: Colors.blue,
        fallbackCircleColor: Colors.blue.shade300,
      );
    } catch (_) {}
    return (order: order, penumpangIcon: penumpangIcon);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<
          ({OrderModel order, BitmapDescriptor? penumpangIcon})>(
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

          final passengerLat = order.originLat ?? order.passengerLat ?? 0.0;
          final passengerLng = order.originLng ?? order.passengerLng ?? 0.0;
          final destLat = order.destLat ?? 0.0;
          final destLng = order.destLng ?? 0.0;

          if (passengerLat == 0 && passengerLng == 0) {
            return _buildScaffold(
              child: const Center(child: Text('Lokasi penumpang tidak valid.')),
            );
          }
          if (destLat == 0 && destLng == 0) {
            return _buildScaffold(
              child: const Center(child: Text('Lokasi tujuan tidak valid.')),
            );
          }

          final defaultBlue =
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
          return PassengerTrackMapWidget(
            order: order,
            driverUid: driverUid,
            originLat: passengerLat,
            originLng: passengerLng,
            destLat: destLat,
            destLng: destLng,
            destForDistanceLat: passengerLat,
            destForDistanceLng: passengerLng,
            showSOS: true,
            onSOS: () => _onSOS(context, order),
            extraMarkers: (driverPos) {
              return {
                Marker(
                  markerId: const MarkerId('penumpang'),
                  position: LatLng(passengerLat, passengerLng),
                  icon: data.penumpangIcon ?? defaultBlue,
                  anchor: const Offset(0.5, 1.0),
                  infoWindow: InfoWindow(
                    title: 'Penumpang',
                    snippet: order.passengerLocationText ?? order.originText,
                  ),
                ),
              };
            },
            bottomBuilder: (pos, isMoving, distanceMeters, distanceText, etaText, driverLocationText, ferryStatus) =>
                Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.straighten,
                            color: Theme.of(context).colorScheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${TrakaL10n.of(context).driverDistanceToYou}: $distanceText',
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
                            '${TrakaL10n.of(context).etaToYourLocation}: $etaText',
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
                ),
              ),
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
            color: Theme.of(context).colorScheme.surface,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: TrakaL10n.of(context).back,
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
