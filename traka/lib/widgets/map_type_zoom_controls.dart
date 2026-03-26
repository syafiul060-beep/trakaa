import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/theme_service.dart';
import '../theme/app_theme.dart';

/// Kontrol map: toggle satelit/normal + zoom in/out + lalu lintas.
/// [onThemeToggle]: opsional, jika ada tampilkan tombol tema (mode malam/terang) untuk driver.
/// [trafficEnabled] + [onToggleTraffic]: layer kemacetan (seperti Grab).
/// [onToggleHeading] + [headingFollowEnabled] + [headingTooltip]: opsional — penumpang: north-up vs ikut bearing.
class MapTypeZoomControls extends StatelessWidget {
  const MapTypeZoomControls({
    super.key,
    required this.mapType,
    required this.onToggleMapType,
    required this.onZoomIn,
    required this.onZoomOut,
    this.topOffset = 60,
    this.onThemeToggle,
    this.trafficEnabled = false,
    this.onToggleTraffic,
    this.onToggleHeading,
    this.headingFollowEnabled = false,
    this.headingTooltip,
    this.showPickupDropoffShortcuts = false,
    this.onPickupShortcutTap,
    this.onDropoffShortcutTap,
    this.pickupShortcutEnabled = false,
    this.dropoffShortcutEnabled = false,
    this.pickupShortcutTooltip,
    this.dropoffShortcutTooltip,
    this.showRouteInfoShortcut = false,
    this.onRouteInfoTap,
    this.routeInfoOperBadge = false,
    this.routeInfoTooltip,
  });

  final MapType mapType;
  final VoidCallback onToggleMapType;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final double topOffset;
  final VoidCallback? onThemeToggle;
  final bool trafficEnabled;
  final VoidCallback? onToggleTraffic;
  final VoidCallback? onToggleHeading;
  final bool headingFollowEnabled;
  final String? headingTooltip;
  /// Saat driver aktif: tombol kuning (jemput) & hijau (antar) di bawah zoom ±.
  final bool showPickupDropoffShortcuts;
  final VoidCallback? onPickupShortcutTap;
  final VoidCallback? onDropoffShortcutTap;
  /// Hanya gaya visual (border/warna). Tap tetap diarahkan ke handler (SnackBar penjelasan jika belum ada data).
  final bool pickupShortcutEnabled;
  /// Hanya gaya visual. Tap tetap diarahkan ke handler.
  final bool dropoffShortcutEnabled;
  final String? pickupShortcutTooltip;
  final String? dropoffShortcutTooltip;
  /// Di bawah tombol pengantaran (atau di bawah zoom jika shortcut stop tidak tampil).
  final bool showRouteInfoShortcut;
  final VoidCallback? onRouteInfoTap;
  final bool routeInfoOperBadge;
  final String? routeInfoTooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = ThemeService.current == ThemeMode.dark;
    return Positioned(
      top: topOffset,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onThemeToggle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(4),
                color: colorScheme.surface,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onThemeToggle!();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: onToggleMapType,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                mapType == MapType.normal ? Icons.satellite : Icons.map,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
          ),
          if (onToggleHeading != null) ...[
            const SizedBox(height: 8),
            Tooltip(
              message: headingTooltip ?? '',
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(4),
                color: colorScheme.surface,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onToggleHeading!();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      headingFollowEnabled ? Icons.navigation : Icons.explore_outlined,
                      size: 20,
                      color: headingFollowEnabled ? AppTheme.primary : colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (onToggleTraffic != null) ...[
            const SizedBox(height: 8),
            Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              color: colorScheme.surface,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onToggleTraffic!();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.traffic,
                    size: 20,
                    color: trafficEnabled ? Colors.orange : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: onZoomIn,
                ),
              ),
              Container(width: 36, height: 1, color: colorScheme.outline),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.remove,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: onZoomOut,
                ),
              ),
            ],
          ),
          if (showPickupDropoffShortcuts &&
              (onPickupShortcutTap != null || onDropoffShortcutTap != null)) ...[
            const SizedBox(height: 8),
            if (onPickupShortcutTap != null)
              _MapStopShortcutChip(
                tooltip: pickupShortcutTooltip ?? 'Penjemputan',
                icon: Icons.person_pin_circle,
                accentColor: const Color(0xFFF9A825),
                enabled: pickupShortcutEnabled,
                onTap: onPickupShortcutTap!,
              ),
            if (onPickupShortcutTap != null && onDropoffShortcutTap != null)
              const SizedBox(height: 8),
            if (onDropoffShortcutTap != null)
              _MapStopShortcutChip(
                tooltip: dropoffShortcutTooltip ?? 'Pengantaran',
                icon: Icons.flag,
                accentColor: const Color(0xFF2E7D32),
                enabled: dropoffShortcutEnabled,
                onTap: onDropoffShortcutTap!,
              ),
          ],
          if (showRouteInfoShortcut && onRouteInfoTap != null) ...[
            const SizedBox(height: 8),
            _MapRouteInfoChip(
              tooltip: routeInfoTooltip ?? 'Informasi rute',
              onTap: onRouteInfoTap!,
              operBadge: routeInfoOperBadge,
            ),
          ],
        ],
      ),
    );
  }
}

class _MapRouteInfoChip extends StatelessWidget {
  const _MapRouteInfoChip({
    required this.tooltip,
    required this.onTap,
    this.operBadge = false,
  });

  final String tooltip;
  final VoidCallback onTap;
  final bool operBadge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = AppTheme.primary;
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        color: colorScheme.surface,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: operBadge
                    ? primary.withValues(alpha: 0.9)
                    : primary.withValues(alpha: 0.55),
                width: operBadge ? 2 : 1.5,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(Icons.info_outline, size: 20, color: primary),
                if (operBadge)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapStopShortcutChip extends StatelessWidget {
  const _MapStopShortcutChip({
    required this.tooltip,
    required this.icon,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        color: colorScheme.surface,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: enabled
                    ? accentColor.withValues(alpha: 0.85)
                    : colorScheme.outline.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? accentColor
                  : colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
