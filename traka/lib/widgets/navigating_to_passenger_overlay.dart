import 'package:flutter/material.dart';

import '../screens/chat_driver_screen.dart';

/// Overlay compact "Menuju penumpang" di kanan atas peta driver.
/// Menampilkan jarak, ETA, badge ~1 km lagi, tombol Chat, dan Kembali ke rute.
class NavigatingToPassengerOverlay extends StatelessWidget {
  const NavigatingToPassengerOverlay({
    super.key,
    required this.routeToPassengerDistanceText,
    required this.routeToPassengerDurationText,
    this.routeToPassengerDistanceMeters,
    required this.waitingPassengerCount,
    required this.navigatingToOrderId,
    required this.onExitNavigating,
    this.voiceMuted = false,
    this.onVoiceMuteToggle,
    this.onAlternativeRoutes,
  });

  final String routeToPassengerDistanceText;
  final String routeToPassengerDurationText;
  final double? routeToPassengerDistanceMeters;
  final int waitingPassengerCount;
  final String? navigatingToOrderId;
  final VoidCallback onExitNavigating;
  final bool voiceMuted;
  final VoidCallback? onVoiceMuteToggle;
  final VoidCallback? onAlternativeRoutes;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 185,
      right: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_pin_circle,
                            size: 20,
                            color: const Color(0xFF00B14F),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Menuju penumpang',
                              style: const TextStyle(
                                color: Color(0xFF00B14F),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onVoiceMuteToggle != null)
                      IconButton(
                        onPressed: onVoiceMuteToggle,
                        icon: Icon(
                          voiceMuted ? Icons.volume_off : Icons.volume_up,
                          size: 22,
                          color: voiceMuted
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : const Color(0xFF00B14F),
                        ),
                        tooltip: voiceMuted ? 'Nyalakan suara' : 'Matikan suara',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(36, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    TextButton(
                      onPressed: onExitNavigating,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Kembali ke rute'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (routeToPassengerDistanceMeters != null &&
                    routeToPassengerDistanceMeters! < 1000) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B14F).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '~1 km lagi',
                      style: const TextStyle(
                        color: Color(0xFF00B14F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                _RouteInfoRow(
                  icon: Icons.route,
                  label: 'Jarak ke penumpang',
                  value: (routeToPassengerDistanceText.isNotEmpty &&
                          routeToPassengerDurationText.isNotEmpty)
                      ? '$routeToPassengerDistanceText • Est. $routeToPassengerDurationText'
                      : 'Memuat...',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final id = navigatingToOrderId;
                          if (id != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChatDriverScreen(orderId: id),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Chat'),
                      ),
                    ),
                    if (onAlternativeRoutes != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: onAlternativeRoutes,
                        icon: const Icon(Icons.alt_route, size: 18),
                        label: const Text('Rute alternatif'),
                      ),
                    ],
                  ],
                ),
                if (waitingPassengerCount > 1) ...[
                  const SizedBox(height: 4),
                  _RouteInfoRow(
                    icon: Icons.people_outline,
                    label: 'Penumpang lainnya',
                    value: '$waitingPassengerCount menunggu',
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

class _RouteInfoRow extends StatelessWidget {
  const _RouteInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(color: primary, fontSize: 13),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
