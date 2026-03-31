import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traka/l10n/app_localizations.dart';
import 'package:traka/services/directions_service.dart';
import 'package:traka/widgets/traka_l10n_scope.dart';
import 'package:traka/widgets/turn_by_turn_banner.dart';

RouteStep _step(String instruction) {
  return RouteStep(
    instruction: instruction,
    distanceText: '100 m',
    distanceMeters: 100,
    startDistanceMeters: 0,
    endDistanceMeters: 100,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: TrakaL10n(
        data: AppLocalizations(locale: AppLocale.id),
        child: Stack(children: [child]),
      ),
    ),
  );
}

void main() {
  testWidgets('shows ETA line when etaArrival set', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TurnByTurnBanner(
          steps: [_step('Belok kanan')],
          currentStepIndex: 0,
          remainingMetersToManeuver: 80,
          etaArrival: DateTime(2026, 3, 30, 15, 9),
        ),
      ),
    );
    expect(find.textContaining('Tiba ~'), findsOneWidget);
  });

  testWidgets('shows reroute status in full card', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TurnByTurnBanner(
          steps: [_step('Belok kiri')],
          currentStepIndex: 0,
          remainingMetersToManeuver: 400,
          rerouteStatusText: 'Memuat ulang rute…',
        ),
      ),
    );
    expect(find.textContaining('Memuat ulang'), findsOneWidget);
  });

  testWidgets('stays expanded when reroute set after 6s timer', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TurnByTurnBanner(
          steps: [_step('Belok kanan')],
          currentStepIndex: 0,
          remainingMetersToManeuver: 400,
          rerouteStatusText: 'Menyesuaikan rute',
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.textContaining('Menyesuaikan'), findsOneWidget);
  });
}
