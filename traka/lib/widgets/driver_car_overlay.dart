import 'package:flutter/material.dart';

import '../theme/responsive.dart';
import 'driver_map_overlays.dart';

/// Overlay lokasi driver: icon mobil + label "Anda".
class DriverCarOverlay extends StatelessWidget {
  const DriverCarOverlay({
    super.key,
    required this.bearing,
    required this.isMoving,
  });

  final double bearing;
  final bool isMoving;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 100,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CarOverlayWidget(
              bearing: bearing,
              isMoving: isMoving,
              size: context.responsive.iconSize(28).clamp(24.0, 36.0),
            ),
            const SizedBox(height: 4),
            Text(
              'Anda',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                shadows: [
                  Shadow(
                    color: Theme.of(context).colorScheme.surface,
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
