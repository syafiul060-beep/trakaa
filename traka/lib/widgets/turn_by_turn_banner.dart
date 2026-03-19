import 'package:flutter/material.dart';

import '../services/directions_service.dart';
import '../utils/instruction_formatter.dart';

/// Banner petunjuk belok turn-by-turn (instruksi saat ini + berikutnya).
/// Ditampilkan di bawah peta saat driver menuju penumpang.
class TurnByTurnBanner extends StatelessWidget {
  const TurnByTurnBanner({
    super.key,
    required this.steps,
    required this.currentStepIndex,
    this.etaArrival,
    this.tollInfoText,
    this.routeWarnings = const [],
  });

  final List<RouteStep> steps;
  final int currentStepIndex;
  /// Estimasi waktu tiba (untuk tampilan "Tiba ~14:35").
  final DateTime? etaArrival;
  /// Info tol jika rute melewati tol.
  final String? tollInfoText;
  /// Peringatan rute (penutupan jalan, dll).
  final List<String> routeWarnings;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty || currentStepIndex < 0 || currentStepIndex >= steps.length) {
      return const SizedBox.shrink();
    }
    final current = steps[currentStepIndex];
    final next = currentStepIndex + 1 < steps.length
        ? steps[currentStepIndex + 1]
        : null;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B14F).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      InstructionFormatter.getIconForStep(current),
                      color: const Color(0xFF00B14F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          InstructionFormatter.formatForBanner(current),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF008C3A),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          current.distanceText,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (etaArrival != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Tiba ~${etaArrival!.hour.toString().padLeft(2, '0')}:${etaArrival!.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (tollInfoText != null && tollInfoText!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.toll, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text(
                        tollInfoText!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (routeWarnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...routeWarnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
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
                )),
              ],
              if (next != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lalu: ${InstructionFormatter.formatForBanner(next)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        next.distanceText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
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
