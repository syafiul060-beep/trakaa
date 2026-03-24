import 'dart:async';

import 'package:flutter/material.dart';

import '../services/performance_trace_service.dart';
import '../widgets/traka_l10n_scope.dart';

/// Layar maintenance ketika admin mengaktifkan maintenance mode.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({
    super.key,
    this.message,
  });

  final String? message;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(PerformanceTraceService.stopStartupToInteractive());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                TrakaL10n.of(context).underMaintenance,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.message ?? TrakaL10n.of(context).maintenanceMessage,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
