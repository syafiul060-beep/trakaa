import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'traka_l10n_scope.dart';

/// Warna per rute: Rute 1=biru merek, 2=hijau, 3=oranye, 4=ungu.
const List<Color> _routeColors = [
  AppTheme.primary,
  AppTheme.mapDeliveryAccent,
  AppTheme.mapRouteOrange,
  AppTheme.mapRoutePurple,
  AppTheme.mapRouteTeal,
];

Color routeColorForIndex(int index) {
  return _routeColors[index % _routeColors.length];
}

/// Tombol pilih rute (Pilih Rute 1, 2, 3...) di bawah peta.
/// Auto-scroll ke rute yang dipilih + gradient edge jika banyak alternatif.
class DriverRouteSelectionButtons extends StatefulWidget {
  const DriverRouteSelectionButtons({
    super.key,
    required this.routeCount,
    required this.selectedIndex,
    required this.routeDistanceTexts,
    required this.onSelectRoute,
    required this.visible,
    this.routeSelected = false,
  });

  final int routeCount;
  final int selectedIndex;
  final List<String> routeDistanceTexts;
  final ValueChanged<int> onSelectRoute;
  final bool visible;
  /// Saat true, tombol "Mulai Rute" tampil di bawah → geser ke atas.
  final bool routeSelected;

  @override
  State<DriverRouteSelectionButtons> createState() =>
      _DriverRouteSelectionButtonsState();
}

class _DriverRouteSelectionButtonsState extends State<DriverRouteSelectionButtons> {
  late List<GlobalKey> _routeButtonKeys;

  @override
  void initState() {
    super.initState();
    _routeButtonKeys = List.generate(
      widget.routeCount > 0 ? widget.routeCount : 1,
      (_) => GlobalKey(),
    );
  }

  @override
  void didUpdateWidget(DriverRouteSelectionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routeCount > _routeButtonKeys.length) {
      _routeButtonKeys = List.generate(
        widget.routeCount,
        (_) => GlobalKey(),
      );
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToSelectedRoute();
    }
  }

  void _scrollToSelectedRoute() {
    _scrollToIndex(widget.selectedIndex);
  }

  void _scrollToIndex(int index) {
    if (index < 0 || index >= _routeButtonKeys.length) return;
    final ctx = _routeButtonKeys[index].currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  void _onTapRoute(int i) {
    widget.onSelectRoute(i);
    if (i != widget.selectedIndex) {
      _scrollToIndex(i); // Scroll ke rute yang baru dipilih (parent belum rebuild)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || widget.routeCount == 0) return const SizedBox.shrink();
    return Positioned(
      bottom: widget.routeSelected ? 140 : 80,
      left: 16,
      right: 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.routeCount, (i) {
                if (i >= _routeButtonKeys.length) return const SizedBox.shrink();
                final color = routeColorForIndex(i);
                final isSelected = i == widget.selectedIndex;
                final distanceText = i < widget.routeDistanceTexts.length
                    ? widget.routeDistanceTexts[i]
                    : '';
                return Padding(
                  key: _routeButtonKeys[i],
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onTapRoute(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isSelected ? 1 : 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: isSelected ? 8 : 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rute ${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            if (distanceText.isNotEmpty)
                              Text(
                                distanceText,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 10,
                                ),
                              ),
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Dipilih',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
            ),
          ),
          if (widget.routeCount >= 3)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                        Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Petunjuk tap untuk pilih rute alternatif (driver belum mulai bekerja).
class DriverRouteTapHint extends StatelessWidget {
  const DriverRouteTapHint({
    super.key,
    required this.routeSelected,
    required this.visible,
  });

  final bool routeSelected;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            routeSelected
                ? 'Tap Rute 1/2/3 di atas untuk ganti rute, lalu tap Mulai Rute ini.'
                : 'Pilih rute dengan tombol di atas atau tap garis di peta.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Pengingat: ada penumpang terjadwal hari ini tapi driver belum mulai rute dari jadwal.
class DriverScheduledReminder extends StatelessWidget {
  const DriverScheduledReminder({
    super.key,
    required this.scheduledCount,
    required this.onOpenJadwal,
    required this.visible,
  });

  final int scheduledCount;
  final VoidCallback onOpenJadwal;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      top: 108,
      left: 16,
      right: 16,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Colors.amber.shade100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.amber.shade800, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Anda punya $scheduledCount penumpang terjadwal hari ini. Pilih rute di Jadwal, lalu Mulai Rute.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenJadwal,
                  child: const Text('Buka Jadwal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol Siap Kerja / Selesai Bekerja — pill Material 3 + bayangan tema merek.
class DriverWorkToggleButton extends StatelessWidget {
  const DriverWorkToggleButton({
    super.key,
    required this.isDriverWorking,
    required this.routeSelected,
    required this.hasActiveOrder,
    required this.onTap,
  });

  final bool isDriverWorking;
  final bool routeSelected;
  final bool hasActiveOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + 4;

    final blockedFinish = isDriverWorking && hasActiveOrder;
    final showFinish = isDriverWorking && !hasActiveOrder;
    final showRouteSelected = !isDriverWorking && routeSelected;
    final showReady = !isDriverWorking && !routeSelected;

    late final List<Color> gradientColors;
    late final Color fg;
    late final Color shadowTint;
    late final double shadowOpacity;
    late final double blur;
    late final Color borderColor;

    if (blockedFinish) {
      gradientColors = [cs.surfaceContainerHighest, cs.surfaceContainerHigh];
      fg = cs.onSurfaceVariant;
      shadowTint = cs.shadow;
      shadowOpacity = 0.12;
      blur = 10;
      borderColor = cs.outline.withValues(alpha: 0.5);
    } else if (showFinish) {
      final hi = Color.lerp(cs.error, Colors.white, 0.12) ?? cs.error;
      gradientColors = [cs.error, hi];
      fg = cs.onError;
      shadowTint = cs.error;
      shadowOpacity = 0.38;
      blur = 20;
      borderColor = Colors.white.withValues(alpha: 0.28);
    } else if (showRouteSelected) {
      gradientColors = [cs.surfaceContainerHigh, cs.surfaceContainer];
      fg = cs.onSurface;
      shadowTint = cs.primary;
      shadowOpacity = 0.14;
      blur = 14;
      borderColor = cs.outline.withValues(alpha: 0.45);
    } else {
      gradientColors = [AppTheme.primary, AppTheme.primaryLight];
      fg = AppTheme.onPrimary;
      shadowTint = AppTheme.primaryDark;
      shadowOpacity = 0.42;
      blur = 22;
      borderColor = Colors.white.withValues(alpha: 0.32);
    }

    return Positioned(
      top: topInset,
      left: 16,
      child: Tooltip(
        message: blockedFinish
            ? TrakaL10n.of(context).driverFinishWorkBlockedTooltip
            : '',
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            splashColor: fg.withValues(alpha: 0.14),
            highlightColor: fg.withValues(alpha: 0.08),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowTint.withValues(alpha: shadowOpacity),
                    blurRadius: blur,
                    offset: const Offset(0, 8),
                    spreadRadius: -3,
                  ),
                ],
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDriverWorking
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_rounded,
                      color: fg,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isDriverWorking
                          ? TrakaL10n.of(context).finishWork
                          : (routeSelected
                              ? TrakaL10n.of(context).routeSelected
                              : TrakaL10n.of(context).readyToWork),
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        letterSpacing: 0.25,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon informasi rute - di bawah tombol Selesai bekerja, buka bottom sheet.
class DriverRouteInfoIconButton extends StatelessWidget {
  const DriverRouteInfoIconButton({
    super.key,
    required this.visible,
    required this.onTap,
    this.hasOperDriverAvailable = false,
  });

  final bool visible;
  final VoidCallback onTap;
  final bool hasOperDriverAvailable;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      top: 118,
      left: 16,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: hasOperDriverAvailable
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      TrakaL10n.of(context).routeInfo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (hasOperDriverAvailable)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 10,
                      height: 10,
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

/// Tombol "Mulai Rute ini" - pill gradient, muncul setelah rute dipilih.
class DriverStartRouteButton extends StatelessWidget {
  const DriverStartRouteButton({
    super.key,
    required this.visible,
    required this.onTap,
    this.isLoading = false,
  });

  final bool visible;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLoading
                      ? [Colors.grey.shade600, Colors.grey.shade700]
                      : [
                          AppTheme.mapDeliveryAccent,
                          Color.lerp(
                                AppTheme.mapDeliveryAccent,
                                Colors.white,
                                0.22,
                              ) ??
                              AppTheme.mapDeliveryAccent,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    const Icon(Icons.navigation, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    isLoading ? 'Memuat...' : 'Mulai Rute ini',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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

/// Overlay icon mobil tetap di bawah tengah (head unit style).
/// Dipakai di driver screen dan Lacak Driver/Barang.
///
/// **Bukan** marker peta penumpang: hijau/merah di sini = bergerak vs berhenti
/// (lihat `docs/KEBIJAKAN_ICON_MOBIL_DAN_OVERLAY.md`). Aset diselaraskan dengan
/// folder premium saja.
class CarOverlayWidget extends StatelessWidget {
  const CarOverlayWidget({
    super.key,
    required this.bearing,
    required this.isMoving,
    this.size = 42,
  });

  /// Bearing dalam derajat (0 = utara, 90 = timur).
  final double bearing;
  /// Hijau = bergerak, merah = berhenti (bukan "kursi penuh").
  final bool isMoving;
  /// Ukuran px. Driver: 56, Lacak: 62.
  final double size;

  static const String _premiumMoving = 'assets/images/traka_car_icons_premium/car_green.png';
  static const String _premiumIdle = 'assets/images/traka_car_icons_premium/car_red.png';

  @override
  Widget build(BuildContext context) {
    final primary = isMoving ? _premiumMoving : _premiumIdle;
    final b = ((bearing % 360) + 360) % 360;
    // Premium PNG: depan mobil = bawah gambar → +180°.
    final rotationRad = ((b + 180) % 360) * math.pi / 180;
    return Image.asset(
      primary,
      width: size,
      height: size,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) return child;
        return Transform.rotate(angle: rotationRad, child: child);
      },
      errorBuilder: (context, error, stackTrace) {
        final color =
            isMoving ? AppTheme.mapDeliveryAccent : AppTheme.mapStopRed;
        return Transform.rotate(
          angle: rotationRad,
          child: Icon(Icons.directions_car, size: size * 0.85, color: color),
        );
      },
    );
  }
}
