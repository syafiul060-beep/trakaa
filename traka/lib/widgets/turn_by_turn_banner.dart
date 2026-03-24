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
    this.etaArrival,
    this.tollInfoText,
    this.routeWarnings = const [],
    this.accentColor = const Color(0xFF1A73E8),
    this.voiceMuted = false,
    this.onVoiceMuteToggle,
  });

  final List<RouteStep> steps;
  final int currentStepIndex;
  final DateTime? etaArrival;
  final String? tollInfoText;
  final List<String> routeWarnings;
  /// Warna aksen ikon (biru GM default; driver bisa hijau/oranye sesuai fase).
  final Color accentColor;
  final bool voiceMuted;
  final VoidCallback? onVoiceMuteToggle;

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
    final colorScheme = Theme.of(context).colorScheme;
    /// Sama dengan `_speakCurrentStep` di driver_screen — suara & teks satu sumber.
    final primaryCue = InstructionFormatter.formatStep(current);

    return Positioned(
      top: mq.padding.top + 6,
      left: 10,
      right: 10,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      InstructionFormatter.getIconForStep(current),
                      color: accentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryCue,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: colorScheme.onSurface,
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
                              color: colorScheme.onSurfaceVariant,
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
                            ? colorScheme.onSurfaceVariant
                            : accentColor,
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
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lalu: ${InstructionFormatter.formatStep(next)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
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
    );
  }
}
