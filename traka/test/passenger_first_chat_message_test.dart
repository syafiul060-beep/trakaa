import 'package:flutter_test/flutter_test.dart';
import 'package:traka/l10n/app_localizations.dart';
import 'package:traka/models/jarak_kontribusi_preview.dart';
import 'package:traka/services/passenger_first_chat_message.dart';

void main() {
  group('formatJarakKontribusiLines', () {
    test('formats distance, ferry, contribution in Indonesian', () {
      const p = JarakKontribusiPreview(
        kmStraight: 12.3,
        ferryKm: 2.5,
        contributionRp: 1234567,
      );
      final l10n = AppLocalizations(locale: AppLocale.id);
      final s = PassengerFirstChatMessage.formatJarakKontribusiLines(l10n, p);
      expect(s, contains('12.3'));
      expect(s, contains('2.5'));
      expect(s, contains('1.234.567'));
      expect(s, contains('kontribusi driver'));
    });

    test('omits ferry line when negligible', () {
      const p = JarakKontribusiPreview(
        kmStraight: 5.0,
        ferryKm: 0,
        contributionRp: 50000,
      );
      final l10n = AppLocalizations(locale: AppLocale.en);
      final s = PassengerFirstChatMessage.formatJarakKontribusiLines(l10n, p);
      expect(s, contains('Estimated origin'));
      expect(s, contains('50.000'));
      expect(s, isNot(contains('sea segment')));
    });
  });
}
