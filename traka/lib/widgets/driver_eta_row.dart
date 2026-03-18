import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/directions_service.dart';
import 'traka_l10n_scope.dart';

/// Baris ETA driver ke lokasi penumpang (ala Gojek/Grab).
class DriverEtaRow extends StatelessWidget {
  const DriverEtaRow({
    super.key,
    required this.driverLat,
    required this.driverLng,
    this.passengerLat,
    this.passengerLng,
  });

  final double driverLat;
  final double driverLng;
  final double? passengerLat;
  final double? passengerLng;

  @override
  Widget build(BuildContext context) {
    if (passengerLat == null || passengerLng == null) return const SizedBox.shrink();
    return FutureBuilder<DirectionsResult?>(
      future: DirectionsService.getRoute(
        originLat: driverLat,
        originLng: driverLng,
        destLat: passengerLat!,
        destLng: passengerLng!,
      ),
      builder: (context, snap) {
        final eta = snap.data?.durationText;
        if (eta == null || eta.isEmpty) {
          return Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text(
                snap.connectionState == ConnectionState.waiting
                    ? (TrakaL10n.of(context).locale == AppLocale.id ? 'Memuat...' : 'Loading…')
                    : '-',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          );
        }
        return Row(
          children: [
            Icon(Icons.access_time, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              '${TrakaL10n.of(context).etaToYourLocation}: $eta',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        );
      },
    );
  }
}
