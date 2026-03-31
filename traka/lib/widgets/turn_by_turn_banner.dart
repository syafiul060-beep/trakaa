import 'package:flutter/material.dart';

import '../services/directions_service.dart';
import '../utils/instruction_formatter.dart';

/// Petunjuk belok turn-by-turn di **atas** peta (gaya Google Maps): satu kartu dengan ikon,
/// teks utama = [InstructionFormatter.formatStep] (sama dengan yang dibacakan TTS), mute di kanan atas kartu.
class TurnByTurnBanner extends StatelessWidget {
  const TurnByTurnBanner({
    super.key,
    required this.steps,
    required this.currentStepIndex,
    this.remainingMetersToManeuver,
    this.rerouteStatusText,
    this.etaArrival,
    this.tollInfoText,
    this.routeWarnings = const [],
    this.accentColor = const Color(0xFF1A73E8),
    this.voiceMuted = false,
    this.onVoiceMuteToggle,
    this.distanceToNextStepMeters,
    this.onResumeCameraTracking,
    this.resumeCameraTrackingLabel = 'Ikuti rute',
  });

  final List<RouteStep> steps;
  final int currentStepIndex;
  /// Jarak sepanjang polyline ke akhir langkah aktif (mirip angka besar di Google Maps).
  final double? remainingMetersToManeuver;
  /// Pesan singkat setelah re-route otomatis (bukan peringatan API).
  final String? rerouteStatusText;
  final DateTime? etaArrival;
  final String? tollInfoText;
  final List<String> routeWarnings;
  /// Warna aksen ikon (biru GM default; driver bisa hijau/oranye sesuai fase).
  final Color accentColor;
  final bool voiceMuted;
  final VoidCallback? onVoiceMuteToggle;
  /// Jarak perkiraan sepanjang polyline ke awal langkah berikutnya.
  final double? distanceToNextStepMeters;
  /// Setelah re-route: kembalikan kamera ke mode ikuti (opsional).
  final VoidCallback? onResumeCameraTracking;
  final String resumeCameraTrackingLabel;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty ||
        currentStepIndex < 0 ||
        currentStepIndex >= steps.length) {
      return const SizedBox.shrink();
    }
    final current = steps[currentStepIndex];
    final next = currentStepIndex + 1 < steps.length
        ? steps[currentStepIndex + 1]
        : null;
    final mq = MediaQuery.of(context);
    final rem = remainingMetersToManeuver;
    final useLiveRemaining = rem != null && rem > 2;
    /// Banner: jarak live + aksi (Maps); suara tetap pakai [InstructionFormatter.formatStep] / proximity.
    final primaryCue = InstructionFormatter.formatStep(current);
    final maneuverOnly = InstructionFormatter.maneuverPhraseOnly(current);

    // Di bawah pill Siap/Selesai kerja — offset selaras dengan [DriverWorkToggleButton].
    final safeTop = mq.padding.top;
    const double workPillTopInset = 4;
    const double workPillBlockHeight = 56;
    const double gapBelowWorkPill = 12;
    final double topBelowWorkPill =
        workPillTopInset + workPillBlockHeight + gapBelowWorkPill;
    const double rightReserveForMapControls = 88;
    const double bannerFillAlpha = 0.74;
    final Color cueColor = Colors.white;
    final Color cueMuted = Colors.white.withValues(alpha: 0.88);
    return Positioned(
      top: safeTop + topBelowWorkPill,
      left: 10,
      right: rightReserveForMapControls,
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: accentColor.withValues(alpha: bannerFillAlpha),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            if (rerouteStatusText != null && rerouteStatusText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.alt_route_rounded,
                              size: 18, color: accentColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rerouteStatusText!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onResumeCameraTracking != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onResumeCameraTracking,
                          icon: const Icon(Icons.navigation_rounded, size: 18),
                          label: Text(resumeCameraTrackingLabel),
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      InstructionFormatter.getIconForStep(current),
                      color: cueColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (useLiveRemaining) ...[
                          Text(
                            rem <= 22
                                ? 'Segera'
                                : InstructionFormatter.formatRemainingDistanceMeters(
                                    rem,
                                  ),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                              letterSpacing: -0.5,
                              color: cueColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            maneuverOnly,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: cueColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else
                          Text(
                            primaryCue,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: cueColor,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (etaArrival != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Tiba ~${etaArrival!.hour.toString().padLeft(2, '0')}:${etaArrival!.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cueMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onVoiceMuteToggle != null)
                    IconButton(
                      onPressed: onVoiceMuteToggle,
                      icon: Icon(
                        voiceMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 22,
                        color: voiceMuted
                            ? Colors.white.withValues(alpha: 0.55)
                            : cueColor,
                      ),
                      tooltip: voiceMuted
                          ? 'Nyalakan suara arahan'
                          : 'Matikan suara arahan',
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(40, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
            if (tollInfoText != null && tollInfoText!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.toll, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tollInfoText!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (routeWarnings.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: routeWarnings.map((w) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                w,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            if (next != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right_rounded,
                        size: 18,
                        color: cueMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (() {
                            final d = distanceToNextStepMeters;
                            final maneuver =
                                InstructionFormatter.maneuverPhraseOnly(next);
                            if (d != null && d > 35) {
                              final approx = InstructionFormatter
                                  .formatRemainingDistanceMeters(d);
                              return 'Lalu: ~$approx · $maneuver';
                            }
                            return 'Lalu: ${InstructionFormatter.formatStep(next)}';
                          })(),
                          style: TextStyle(
                            fontSize: 13,
                            color: cueMuted,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ],
          ),
        ),
      ),
    );
  }
}
