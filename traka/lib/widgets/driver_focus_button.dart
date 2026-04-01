import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tombol Fokus: recenter ke mobil saat driver geser/zoom manual.
/// Di tengah bawah agar tidak bertumpang dengan shortcut penjemputan/pengantaran (kanan).
class DriverFocusButton extends StatelessWidget {
  const DriverFocusButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 160;
    final radius = BorderRadius.circular(28);
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: Tooltip(
          message: 'Pusatkan ke lokasi',
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              borderRadius: radius,
              splashColor: Colors.white.withValues(alpha: 0.22),
              highlightColor: Colors.white.withValues(alpha: 0.12),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryLight,
                      AppTheme.primary,
                      AppTheme.primaryDark,
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.42),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.gps_fixed_rounded,
                    size: 26,
                    color: AppTheme.onPrimary,
                    shadows: const [
                      Shadow(
                        color: Color(0x40000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
