import 'package:flutter/material.dart';

import '../services/directions_service.dart';

/// Overlay arah belok HUD (arrow besar + jarak + nama jalan) di atas peta.
class DriverTurnDirectionOverlay extends StatelessWidget {
  const DriverTurnDirectionOverlay({
    super.key,
    required this.step,
    required this.currentStreetName,
  });

  final RouteStep step;
  final String currentStreetName;

  @override
  Widget build(BuildContext context) {
    final instruction = step.instruction.toLowerCase();
    final isLeft = instruction.contains('kiri') || instruction.contains('left');
    final isRight =
        instruction.contains('kanan') || instruction.contains('right');
    final isUturn =
        instruction.contains('putar') ||
        instruction.contains('u-turn') ||
        instruction.contains('uturn') ||
        instruction.contains('balik');
    final isStraight =
        instruction.contains('lurus') ||
        instruction.contains('straight') ||
        instruction.contains('continue') ||
        instruction.contains('lanjut') ||
        instruction.contains('head ');
    if (!isLeft && !isRight && !isUturn && !isStraight) {
      return const SizedBox.shrink();
    }
    final showUturn = isUturn && !isLeft && !isRight;
    final showStraight = isStraight && !isLeft && !isRight && !isUturn;

    IconData turnIcon;
    if (showUturn) {
      turnIcon = Icons.u_turn_left;
    } else if (showStraight) {
      turnIcon = Icons.arrow_upward;
    } else {
      turnIcon = isLeft ? Icons.turn_left : Icons.turn_right;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 100,
      left: 24,
      right: 24,
      child: Center(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF2E7D32).withValues(alpha: 0.95),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(turnIcon, color: Colors.white, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.distanceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            step.instruction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (currentStreetName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    currentStreetName,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
