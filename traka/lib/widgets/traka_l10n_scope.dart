import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';

/// InheritedWidget untuk menyediakan AppLocalizations ke seluruh pohon widget.
/// Gunakan: TrakaL10n.of(context).someString
class TrakaL10n extends InheritedWidget {
  final AppLocalizations data;

  const TrakaL10n({
    super.key,
    required this.data,
    required super.child,
  });

  static AppLocalizations of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<TrakaL10n>();
    return w?.data ?? AppLocalizations(locale: LocaleService.current);
  }

  @override
  bool updateShouldNotify(TrakaL10n old) => data.locale != old.data.locale;
}
