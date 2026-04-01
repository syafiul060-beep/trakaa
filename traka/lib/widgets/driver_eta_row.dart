import 'package:flutter/material.dart';

import '../theme/app_interaction_styles.dart';
import '../services/app_analytics_service.dart';
import '../services/directions_service.dart';
import 'traka_l10n_scope.dart';

/// Baris ETA driver ke lokasi penumpang (ala Gojek/Grab).
class DriverEtaRow extends StatefulWidget {
  const DriverEtaRow({
    super.key,
    required this.driverLat,
    required this.driverLng,
    this.passengerLat,
    this.passengerLng,
    this.prominent = false,
  });

  final double driverLat;
  final double driverLng;
  final double? passengerLat;
  final double? passengerLng;

  /// Tampilan lebih menonjol (sheet detail driver / gaya Grab).
  final bool prominent;

  @override
  State<DriverEtaRow> createState() => _DriverEtaRowState();
}

class _DriverEtaRowState extends State<DriverEtaRow> {
  late Future<DirectionsEtaOutcome> _future;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _future = _makeFuture();
  }

  @override
  void didUpdateWidget(DriverEtaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverLat == widget.driverLat &&
        oldWidget.driverLng == widget.driverLng &&
        oldWidget.passengerLat == widget.passengerLat &&
        oldWidget.passengerLng == widget.passengerLng) {
      return;
    }
    if (widget.passengerLat != null && widget.passengerLng != null) {
      setState(() => _future = _makeFuture());
    }
  }

  Future<DirectionsEtaOutcome> _makeFuture() {
    if (widget.passengerLat == null || widget.passengerLng == null) {
      return Future.value(
        const DirectionsEtaOutcome(result: null, errorStatus: null),
      );
    }
    final id = ++_requestId;
    final started = DateTime.now();
    return DirectionsService.getRouteEta(
      originLat: widget.driverLat,
      originLng: widget.driverLng,
      destLat: widget.passengerLat!,
      destLng: widget.passengerLng!,
    ).then((outcome) {
      if (!mounted || id != _requestId) return outcome;
      final ms = DateTime.now().difference(started).inMilliseconds;
      AppAnalyticsService.logPassengerDriverEtaLoaded(
        durationMs: ms,
        success: outcome.hasRoute,
        staleCache: outcome.usedStaleCache,
      );
      return outcome;
    });
  }

  void _retry() {
    if (widget.passengerLat == null || widget.passengerLng == null) return;
    setState(() => _future = _makeFuture());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.passengerLat == null || widget.passengerLng == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DirectionsEtaOutcome>(
      future: _future,
      builder: (context, snap) {
        final cs = Theme.of(context).colorScheme;
        final l = TrakaL10n.of(context);
        final outcome = snap.data;
        final eta = outcome?.result?.durationText;
        final staleEta = outcome?.usedStaleCache ?? false;
        final failed = snap.connectionState == ConnectionState.done &&
            outcome != null &&
            !outcome.hasRoute &&
            outcome.errorStatus != null;

        Widget inner;
        if (eta != null && eta.isNotEmpty) {
          final row = Row(
            children: [
              Icon(
                Icons.access_time,
                size: widget.prominent ? 22 : 16,
                color: staleEta ? Colors.orange.shade800 : Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l.etaToYourLocation}: $eta',
                  style: TextStyle(
                    fontSize: widget.prominent ? 15 : 13,
                    fontWeight: widget.prominent ? FontWeight.w700 : FontWeight.w600,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          );
          inner = staleEta
              ? Tooltip(message: l.etaApproximateCachedHint, child: row)
              : row;
        } else if (snap.connectionState == ConnectionState.waiting) {
          inner = Row(
            children: [
              Icon(
                Icons.access_time,
                size: widget.prominent ? 20 : 16,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: widget.prominent ? 18 : 14,
                      height: widget.prominent ? 18 : 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.prominent ? l.etaCalculatingProminent : l.etaLoadingShort,
                        style: TextStyle(
                          fontSize: widget.prominent ? 14 : 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        } else if (failed) {
          inner = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.schedule,
                    size: widget.prominent ? 20 : 16,
                    color: cs.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.etaDirectionsUnavailable,
                      style: TextStyle(
                        fontSize: widget.prominent ? 14 : 13,
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.prominent) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l.retry),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: TextButton(
                    onPressed: _retry,
                    style: AppInteractionStyles.textFromTheme(
                      context,
                    ).copyWith(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                      minimumSize: WidgetStateProperty.all(Size.zero),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l.retry),
                  ),
                ),
            ],
          );
        } else {
          inner = Row(
            children: [
              Icon(
                Icons.access_time,
                size: widget.prominent ? 20 : 16,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '-',
                  style: TextStyle(
                    fontSize: widget.prominent ? 14 : 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        }

        if (!widget.prominent) return inner;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: inner,
        );
      },
    );
  }
}
