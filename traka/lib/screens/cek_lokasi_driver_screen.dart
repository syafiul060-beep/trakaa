import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';
import '../services/order_service.dart';
import '../services/traka_pin_bitmap_service.dart';
import '../widgets/traka_l10n_scope.dart';
import '../services/sos_service.dart';
import '../widgets/lacak_tracking_info_sheet.dart';
import '../widgets/sos_emergency_confirm_dialog.dart';
import '../widgets/passenger_track_map_widget.dart';

/// Halaman Lacak Driver: full-screen map hybrid, posisi driver dengan marker mobil
/// (hijau/merah = bergerak/berhenti) + pin awal Traka untuk posisi penumpang.
/// Kamera membingkai penumpang dan driver.
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
            builder: (context, pinSnap) {
              final driverUid = order.driverUid;
              if (driverUid.isEmpty) {
                return _buildScaffold(
                  child: const Center(child: Text('Data driver tidak valid.')),
                );
              }

              final pickupPhase = order.status != OrderService.statusPickedUp;
              final passengerPair = order.coordsForDriverPickupProximity;
              final passengerLat = passengerPair?.$1 ??
                  order.originLat ??
                  order.passengerLat ??
                  0.0;
              final passengerLng = passengerPair?.$2 ??
                  order.originLng ??
                  order.passengerLng ??
                  0.0;
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

              final destForPair = pickupPhase
                  ? (passengerPair ?? (passengerLat, passengerLng))
                  : (destLat, destLng);
              final focalLat = pickupPhase ? passengerLat : destLat;
              final focalLng = pickupPhase ? passengerLng : destLng;

              final defaultBlue =
                  BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
              final penumpangIcon =
                  TrakaPinBitmapService.mapAwal ?? defaultBlue;

              final l10n = TrakaL10n.of(context);

              return _buildScaffold(
                child: PassengerTrackMapWidget(
                  order: order,
                  driverUid: driverUid,
                  originLat: passengerLat,
                  originLng: passengerLng,
                  destLat: destLat,
                  destLng: destLng,
                  destForDistanceLat: destForPair.$1,
                  destForDistanceLng: destForPair.$2,
                  useDualPartyBoundsCamera: true,
                  dualPartyFocalLat: focalLat,
                  dualPartyFocalLng: focalLng,
                  showSOS: true,
                  onSOS: () => _onSOS(context, order),
                  extraMarkers: (driverPos) {
                    return {
                      Marker(
                        markerId: const MarkerId('penumpang'),
                        position: LatLng(passengerLat, passengerLng),
                        icon: penumpangIcon,
                        anchor: const Offset(0.5, 1.0),
                        infoWindow: InfoWindow(
                          title: 'Penumpang',
                          snippet:
                              order.passengerLocationText ?? order.originText,
                        ),
                      ),
                    };
                  },
                  bottomBuilder:
                      (pos, isMoving, distanceMeters, distanceText, etaText, driverLocationText, ferryStatus) =>
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
                                  '${pickupPhase ? l10n.driverDistanceToYou : l10n.driverDistanceToTripDestination}: $distanceText',
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
                                  '${pickupPhase ? l10n.etaToYourLocation : l10n.etaToTripDestination}: $etaText',
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
            color: Theme.of(context).colorScheme.surface,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: TrakaL10n.of(context).back,
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surface,
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: TrakaL10n.of(context).mapToolsLacakHelpTitle,
              onPressed: () => unawaited(
                showLacakTrackingInfoSheet(
                  context,
                  audience: LacakTrackingAudience.lacakDriverMap,
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
