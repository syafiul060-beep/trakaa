import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../theme/map_control_chrome.dart';

Widget _trakaMapFab(
  BuildContext context, {
  required VoidCallback onTap,
  required Icon icon,
  bool activeGlow = false,
  Color activeAccent = AppTheme.primary,
  double activeMix = 0.13,
}) {
  final deco = activeGlow
      ? TrakaMapControlChrome.fabDecorationActive(
          context,
          activeAccent,
          mix: activeMix,
        )
      : TrakaMapControlChrome.fabDecoration(context);
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: TrakaMapControlChrome.fabBorderRadius,
      splashColor: TrakaMapControlChrome.splashForPrimary(context),
      highlightColor: AppTheme.primary.withValues(alpha: 0.06),
      child: SizedBox(
        width: TrakaMapControlChrome.fabSize,
        height: TrakaMapControlChrome.fabSize,
        child: ClipRRect(
          borderRadius: TrakaMapControlChrome.fabBorderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: deco),
              TrakaMapControlChrome.fabTopGloss(context),
              TrakaMapControlChrome.fabSpecularRim(context),
              Center(child: icon),
            ],
          ),
        ),
      ),
    ),
  );
}

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
    this.onMapToolsTap,
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
  /// Driver: menu peta (precache, bantuan lacak, dll.).
  final VoidCallback? onMapToolsTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = ThemeService.current == ThemeMode.dark;
    const gap = 10.0;
    return Positioned(
      top: topOffset,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onThemeToggle != null) ...[
            Tooltip(
              message: isDark
                  ? 'Tema terang'
                  : 'Tema gelap',
              child: _trakaMapFab(
                context,
                onTap: onThemeToggle!,
                icon: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: TrakaMapControlChrome.iconSize,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: gap),
          ],
          Tooltip(
            message: mapType == MapType.normal
                ? 'Tampilan satelit'
                : 'Tampilan peta',
            child: _trakaMapFab(
              context,
              onTap: onToggleMapType,
              icon: Icon(
                mapType == MapType.normal
                    ? Icons.satellite_alt_rounded
                    : Icons.map_rounded,
                size: TrakaMapControlChrome.iconSize,
                color: AppTheme.primary,
              ),
            ),
          ),
          if (onToggleHeading != null) ...[
            const SizedBox(height: gap),
            Tooltip(
              message: headingTooltip ?? '',
              child: _trakaMapFab(
                context,
                onTap: onToggleHeading!,
                activeGlow: headingFollowEnabled,
                activeAccent: AppTheme.primary,
                activeMix: 0.11,
                icon: Icon(
                  headingFollowEnabled
                      ? Icons.navigation_rounded
                      : Icons.explore_outlined,
                  size: TrakaMapControlChrome.iconSize,
                  color: headingFollowEnabled
                      ? AppTheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
          if (onToggleTraffic != null) ...[
            const SizedBox(height: gap),
            Tooltip(
              message: 'Lalu lintas',
              child: _trakaMapFab(
                context,
                onTap: onToggleTraffic!,
                activeGlow: trafficEnabled,
                activeAccent: AppTheme.mapDropoffAccent,
                activeMix: 0.1,
                icon: Icon(
                  Icons.traffic_rounded,
                  size: TrakaMapControlChrome.iconSize,
                  color: trafficEnabled
                      ? AppTheme.mapDropoffAccent
                      : colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
          if (onMapToolsTap != null) ...[
            const SizedBox(height: gap),
            Tooltip(
              message: 'Alat peta',
              child: _trakaMapFab(
                context,
                onTap: onMapToolsTap!,
                icon: Icon(
                  Icons.tune_rounded,
                  size: TrakaMapControlChrome.iconSize,
                  color: colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
          const SizedBox(height: gap),
          SizedBox(
            width: TrakaMapControlChrome.fabSize,
            height: TrakaMapControlChrome.fabSize * 2,
            child: DecoratedBox(
              decoration: TrakaMapControlChrome.zoomStackDecoration(context),
              child: Column(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onZoomIn();
                        },
                        borderRadius: BorderRadius.only(
                          topLeft: TrakaMapControlChrome.fabBorderRadius.topLeft,
                          topRight: TrakaMapControlChrome.fabBorderRadius.topRight,
                        ),
                        splashColor: TrakaMapControlChrome.splashForPrimary(context),
                        child: Center(
                          child: Icon(
                            Icons.add_rounded,
                            size: 26,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: colorScheme.outline.withValues(alpha: 0.28),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onZoomOut();
                        },
                        borderRadius: BorderRadius.only(
                          bottomLeft:
                              TrakaMapControlChrome.fabBorderRadius.bottomLeft,
                          bottomRight:
                              TrakaMapControlChrome.fabBorderRadius.bottomRight,
                        ),
                        splashColor: TrakaMapControlChrome.splashForPrimary(context),
                        child: Center(
                          child: Icon(
                            Icons.remove_rounded,
                            size: 26,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showPickupDropoffShortcuts &&
              (onPickupShortcutTap != null || onDropoffShortcutTap != null)) ...[
            const SizedBox(height: gap),
            if (onPickupShortcutTap != null)
              _MapStopShortcutChip(
                tooltip: pickupShortcutTooltip ?? 'Penjemputan',
                icon: Icons.person_pin_circle_rounded,
                accentColor: AppTheme.mapPickupAccent,
                enabled: pickupShortcutEnabled,
                onTap: onPickupShortcutTap!,
              ),
            if (onPickupShortcutTap != null && onDropoffShortcutTap != null)
              const SizedBox(height: gap),
            if (onDropoffShortcutTap != null)
              _MapStopShortcutChip(
                tooltip: dropoffShortcutTooltip ?? 'Pengantaran',
                icon: Icons.flag_circle_rounded,
                accentColor: AppTheme.mapDeliveryAccent,
                enabled: dropoffShortcutEnabled,
                onTap: onDropoffShortcutTap!,
              ),
          ],
          if (showRouteInfoShortcut && onRouteInfoTap != null) ...[
            const SizedBox(height: gap),
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

/// Shortcut jemput/antar untuk kanan bawah peta driver — ikon lebih besar, di atas chip Nav premium.
class DriverMapStopShortcutsAbovePremium extends StatelessWidget {
  const DriverMapStopShortcutsAbovePremium({
    super.key,
    required this.show,
    this.onPickupTap,
    this.onDropoffTap,
    this.pickupEnabled = false,
    this.dropoffEnabled = false,
    this.pickupTooltip,
    this.dropoffTooltip,
  });

  final bool show;
  final VoidCallback? onPickupTap;
  final VoidCallback? onDropoffTap;
  final bool pickupEnabled;
  final bool dropoffEnabled;
  final String? pickupTooltip;
  final String? dropoffTooltip;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    if (!show || (onPickupTap == null && onDropoffTap == null)) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (onPickupTap != null)
          _MapStopShortcutChip(
            tooltip: pickupTooltip ?? 'Penjemputan',
            icon: Icons.person_pin_circle_rounded,
            accentColor: AppTheme.mapPickupAccent,
            enabled: pickupEnabled,
            onTap: onPickupTap!,
            dimension: TrakaMapControlChrome.fabSize,
            iconSize: TrakaMapControlChrome.stopShortcutIconSize,
          ),
        if (onDropoffTap != null && onPickupTap != null)
          const SizedBox(height: _gap),
        if (onDropoffTap != null)
          _MapStopShortcutChip(
            tooltip: dropoffTooltip ?? 'Pengantaran',
            icon: Icons.flag_circle_rounded,
            accentColor: AppTheme.mapDeliveryAccent,
            enabled: dropoffEnabled,
            onTap: onDropoffTap!,
            dimension: TrakaMapControlChrome.fabSize,
            iconSize: TrakaMapControlChrome.stopShortcutIconSize,
          ),
      ],
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
    final primary = AppTheme.primary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: TrakaMapControlChrome.fabBorderRadius,
          splashColor: TrakaMapControlChrome.splashForPrimary(context),
          highlightColor: primary.withValues(alpha: 0.06),
          child: SizedBox(
            width: TrakaMapControlChrome.fabSize,
            height: TrakaMapControlChrome.fabSize,
            child: ClipRRect(
              borderRadius: TrakaMapControlChrome.fabBorderRadius,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: TrakaMapControlChrome.fabFaceGradient(context),
                      borderRadius: TrakaMapControlChrome.fabBorderRadius,
                      border: Border.all(
                        color: operBadge
                            ? primary.withValues(alpha: 0.92)
                            : primary.withValues(alpha: 0.55),
                        width: operBadge ? 2 : 1.35,
                      ),
                      boxShadow: TrakaMapControlChrome.floatingShadows(context),
                    ),
                  ),
                  TrakaMapControlChrome.fabTopGloss(context),
                  TrakaMapControlChrome.fabSpecularRim(context),
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: TrakaMapControlChrome.iconSize,
                        color: primary,
                      ),
                      if (operBadge)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.55),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
    this.dimension = TrakaMapControlChrome.fabSize,
    this.iconSize = TrakaMapControlChrome.iconSize,
  });

  final String tooltip;
  final IconData icon;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;
  final double dimension;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final r = TrakaMapControlChrome.fabBorderRadius;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: r,
          splashColor: accentColor.withValues(alpha: enabled ? 0.22 : 0.08),
          highlightColor: accentColor.withValues(alpha: enabled ? 0.06 : 0.03),
          child: SizedBox(
            width: dimension,
            height: dimension,
            child: ClipRRect(
              borderRadius: r,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration:
                        TrakaMapControlChrome.stopShortcutBaseDecoration(
                      context,
                      accentColor,
                      enabled,
                    ),
                  ),
                  TrakaMapControlChrome.fabTopGloss(
                    context,
                    extent: dimension,
                  ),
                  TrakaMapControlChrome.fabSpecularRim(context),
                  Center(
                    child: dimension >= 44
                        ? Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: dimension * 0.58,
                                height: dimension * 0.58,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withValues(
                                        alpha:
                                            colorScheme.brightness ==
                                                    Brightness.dark
                                                ? 0.04
                                                : 0.14,
                                      ),
                                      accentColor.withValues(
                                        alpha: enabled ? 0.2 : 0.05,
                                      ),
                                      accentColor.withValues(
                                        alpha: enabled ? 0.05 : 0.02,
                                      ),
                                    ],
                                    stops: const [0.0, 0.45, 1.0],
                                  ),
                                  boxShadow: enabled
                                      ? [
                                          BoxShadow(
                                            color: accentColor.withValues(
                                              alpha: 0.15,
                                            ),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              Icon(
                                icon,
                                size: iconSize,
                                color: enabled
                                    ? accentColor
                                    : colorScheme.onSurface
                                        .withValues(alpha: 0.38),
                              ),
                            ],
                          )
                        : Icon(
                            icon,
                            size: iconSize,
                            color: enabled
                                ? accentColor
                                : colorScheme.onSurface
                                    .withValues(alpha: 0.38),
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
