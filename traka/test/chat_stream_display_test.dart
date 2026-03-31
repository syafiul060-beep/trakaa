import 'package:flutter_test/flutter_test.dart';
import 'package:traka/models/chat_message_model.dart';
import 'package:traka/utils/chat_stream_display.dart';

void main() {
  group('ChatStreamDisplay.shouldApplyTransientHold', () {
    final hold = [
      const ChatMessageModel(
        id: 'a',
        senderUid: 'u1',
        text: 'hi',
        createdAt: null,
      ),
    ];
    final t0 = DateTime(2026, 3, 29, 12);

    test('false when stream has messages', () {
      expect(
        ChatStreamDisplay.shouldApplyTransientHold(
          streamMsgs: hold,
          hasError: false,
          waitingFirst: false,
          hold: hold,
          holdAt: t0,
          now: t0.add(const Duration(seconds: 1)),
        ),
        false,
      );
    });

    test('false when waiting for first event without prior hold', () {
      expect(
        ChatStreamDisplay.shouldApplyTransientHold(
          streamMsgs: const [],
          hasError: false,
          waitingFirst: true,
          hold: null,
          holdAt: null,
          now: t0.add(const Duration(seconds: 1)),
        ),
        false,
      );
    });

    test('true when waiting but hold exists (reconnect / burst)', () {
      expect(
        ChatStreamDisplay.shouldApplyTransientHold(
          streamMsgs: const [],
          hasError: false,
          waitingFirst: true,
          hold: hold,
          holdAt: t0,
          now: t0.add(const Duration(seconds: 2)),
        ),
        true,
      );
    });

    test('true when empty active snapshot within TTL', () {
      expect(
        ChatStreamDisplay.shouldApplyTransientHold(
          streamMsgs: const [],
          hasError: false,
          waitingFirst: false,
          hold: hold,
          holdAt: t0,
          now: t0.add(const Duration(seconds: 2)),
        ),
        true,
      );
    });

    test('false after TTL', () {
      expect(
        ChatStreamDisplay.shouldApplyTransientHold(
          streamMsgs: const [],
          hasError: false,
          waitingFirst: false,
          hold: hold,
          holdAt: t0,
          now: t0.add(const Duration(seconds: 13)),
        ),
        false,
      );
    });
  });
}
