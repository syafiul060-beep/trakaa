import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tombol Fokus: recenter ke mobil saat driver geser/zoom manual. Gaya Grab/Google Maps.
class DriverFocusButton extends StatelessWidget {
  const DriverFocusButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 160,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(24),
          child: Tooltip(
            message: 'Pusatkan ke lokasi',
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.my_location,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
