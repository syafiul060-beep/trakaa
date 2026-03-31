import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traka/l10n/app_localizations.dart';
import 'package:traka/widgets/driver_nav_premium_map_chip.dart';
import 'package:traka/widgets/traka_l10n_scope.dart';

void main() {
  testWidgets('DriverNavPremiumMapChip shows Premium label and is tappable', (tester) async {
    const tooltip = 'Navigasi premium aktif';
    await tester.pumpWidget(
      MaterialApp(
        home: TrakaL10n(
          data: AppLocalizations(),
          child: Scaffold(
            body: Center(
              child: DriverNavPremiumMapChip(
                enabled: true,
                debtBlocked: false,
                tooltip: tooltip,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nav premium'), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    await tester.pump();
  });
}
