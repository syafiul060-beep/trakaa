import 'package:flutter/material.dart';

/// Tombol Fokus: recenter ke mobil saat driver geser/zoom manual.
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
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).colorScheme.surface,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.my_location,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Fokus ke mobil',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
