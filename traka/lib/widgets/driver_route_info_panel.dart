import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import 'traka_l10n_scope.dart';

/// Panel informasi rute driver: collapsible, atau tampilan "Menuju penumpang".
class DriverRouteInfoPanel extends StatelessWidget {
  const DriverRouteInfoPanel({
    super.key,
    required this.isNavigatingToPassenger,
    required this.routeToPassengerDistanceText,
    required this.routeToPassengerDurationText,
    required this.waitingPassengerCount,
    required this.routeInfoPanelExpanded,
    required this.onTogglePanel,
    required this.onExitNavigating,
    required this.onOperDriver,
    required this.displayDistance,
    required this.displayDuration,
    required this.originLocationText,
    this.currentPosition,
    required this.routeDestText,
    required this.jumlahPenumpang,
    required this.jumlahBarang,
    required this.jumlahPenumpangPickedUp,
  });

  final bool isNavigatingToPassenger;
  final String routeToPassengerDistanceText;
  final String routeToPassengerDurationText;
  final int waitingPassengerCount;
  final bool routeInfoPanelExpanded;
  final VoidCallback onTogglePanel;
  final VoidCallback onExitNavigating;
  final VoidCallback onOperDriver;
  final String displayDistance;
  final String displayDuration;
  final String originLocationText;
  final Position? currentPosition;
  final String routeDestText;
  final int jumlahPenumpang;
  final int jumlahBarang;
  final int jumlahPenumpangPickedUp;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!isNavigatingToPassenger) {
          onTogglePanel();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNavigatingToPassenger) ...[
              _buildNavigatingToPassengerHeader(context),
              const SizedBox(height: 8),
              _RouteInfoRow(
                icon: Icons.route,
                label: TrakaL10n.of(context).distanceToPassenger,
                value: (routeToPassengerDistanceText.isNotEmpty &&
                        routeToPassengerDurationText.isNotEmpty)
                    ? '$routeToPassengerDistanceText • Est. $routeToPassengerDurationText'
                    : (TrakaL10n.of(context).locale == AppLocale.id ? 'Memuat...' : 'Loading…'),
              ),
              const SizedBox(height: 6),
              Text(
                TrakaL10n.of(context).navigatingToPassengerHint,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (waitingPassengerCount > 1) ...[
                const SizedBox(height: 6),
                _RouteInfoRow(
                  icon: Icons.people_outline,
                  label: TrakaL10n.of(context).otherPassengers,
                  value: '$waitingPassengerCount menunggu',
                ),
              ],
            ] else ...[
              _buildRouteInfoHeader(context),
              const SizedBox(height: 10),
              Tooltip(
                message: jumlahPenumpangPickedUp > 0
                    ? TrakaL10n.of(context).operDriverTooltipEnabled
                    : TrakaL10n.of(context).operDriverTooltipDisabled,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: jumlahPenumpangPickedUp > 0 ? onOperDriver : null,
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car, size: 16),
                      const SizedBox(width: 2),
                      Stack(
                        children: [
                          const Icon(Icons.person, size: 14),
                          Positioned(left: 8, child: const Icon(Icons.person, size: 14)),
                          Positioned(left: 4, top: -2, child: const Icon(Icons.person, size: 12)),
                        ],
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.directions_car, size: 16),
                    ],
                  ),
                  label: Text(TrakaL10n.of(context).operDriver),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
              if (routeInfoPanelExpanded) ...[
                const SizedBox(height: 12),
                if (waitingPassengerCount > 0) ...[
                  _RouteInfoRow(
                    icon: Icons.person_pin_circle_outlined,
                    label: TrakaL10n.of(context).passengersWaiting,
                    value: '$waitingPassengerCount pemesan',
                  ),
                  const SizedBox(height: 6),
                ],
                _RouteInfoRow(
                  icon: Icons.location_on,
                  label: TrakaL10n.of(context).routeOrigin,
                  value: originLocationText.isNotEmpty
                      ? originLocationText
                      : (currentPosition != null
                            ? '${currentPosition!.latitude.toStringAsFixed(4)}, ${currentPosition!.longitude.toStringAsFixed(4)}'
                            : 'Lokasi driver'),
                ),
                const SizedBox(height: 6),
                _RouteInfoRow(
                  icon: Icons.place,
                  label: TrakaL10n.of(context).routeDestination,
                  value: routeDestText.isNotEmpty ? routeDestText : '-',
                ),
                const SizedBox(height: 6),
                _RouteInfoRow(
                  icon: Icons.route,
                  label: TrakaL10n.of(context).route,
                  value: (displayDistance.isNotEmpty && displayDuration.isNotEmpty)
                      ? '$displayDistance • Est. $displayDuration'
                      : '-',
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RouteInfoRow(
                            icon: Icons.people,
                            label: TrakaL10n.of(context).passengerCount,
                            value: '$jumlahPenumpang',
                          ),
                          const SizedBox(height: 6),
                          _RouteInfoRow(
                            icon: Icons.luggage,
                            label: TrakaL10n.of(context).goodsCount,
                            value: '$jumlahBarang',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavigatingToPassengerHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.person_pin_circle, size: 20, color: const Color(0xFF00B14F)),
            const SizedBox(width: 8),
            Text(
              TrakaL10n.of(context).headingToPassenger,
              style: const TextStyle(
                color: Color(0xFF00B14F),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: onExitNavigating,
          child: Text(TrakaL10n.of(context).backToRoute),
        ),
      ],
    );
  }

  Widget _buildRouteInfoHeader(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, size: 20, color: primary),
            const SizedBox(width: 8),
            Text(
              TrakaL10n.of(context).routeInfo,
              style: TextStyle(
                color: primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Icon(
          routeInfoPanelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 28,
          color: primary,
        ),
      ],
    );
  }
}

class _RouteInfoRow extends StatelessWidget {
  const _RouteInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 18, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(color: primary, fontSize: 13),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(fontWeight: FontWeight.w600, color: primary),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
