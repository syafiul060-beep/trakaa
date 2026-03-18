import 'package:flutter/material.dart';

import '../screens/chat_driver_screen.dart';

/// Warna oranye untuk pengantaran (beda dengan hijau penjemputan).
const Color _menujuTujuanColor = Color(0xFFE65100); // Orange 900

/// Overlay compact "Menuju tujuan" di kanan atas peta driver.
/// Mirip NavigatingToPassengerOverlay tapi untuk fase pengantaran (oranye).
class NavigatingToDestinationOverlay extends StatelessWidget {
  const NavigatingToDestinationOverlay({
    super.key,
    required this.routeDistanceText,
    required this.routeDurationText,
    this.routeDistanceMeters,
    required this.navigatingToOrderId,
    required this.onExitNavigating,
    this.voiceMuted = false,
    this.onVoiceMuteToggle,
    this.onAlternativeRoutes,
  });

  final String routeDistanceText;
  final String routeDurationText;
  final double? routeDistanceMeters;
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
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _menujuTujuanColor.withValues(alpha: 0.5),
              ),
            ),
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
                              Icons.flag,
                              size: 20,
                              color: _menujuTujuanColor,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Menuju tujuan',
                                style: TextStyle(
                                  color: _menujuTujuanColor,
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
                                : _menujuTujuanColor,
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
                  if (routeDistanceMeters != null &&
                      routeDistanceMeters! < 1000) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _menujuTujuanColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '~1 km lagi',
                        style: TextStyle(
                          color: _menujuTujuanColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  _RouteInfoRow(
                    icon: Icons.route,
                    label: 'Jarak ke tujuan',
                    value: (routeDistanceText.isNotEmpty &&
                            routeDurationText.isNotEmpty)
                        ? '$routeDistanceText • Est. $routeDurationText'
                        : 'Memuat...',
                    color: _menujuTujuanColor,
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
                ],
              ),
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
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(color: color, fontSize: 13),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
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
