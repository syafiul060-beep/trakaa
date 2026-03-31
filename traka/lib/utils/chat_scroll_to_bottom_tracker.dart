import 'package:flutter/widgets.dart';

import '../models/chat_message_model.dart';

/// Scroll ke ujung bawah daftar chat hanya bila jumlah pesan naik atau pesan terakhir berganti.
/// Satu instance per layar chat ([State]); panggil [reset] saat pull-to-refresh.
class ChatScrollToBottomTracker {
  int _lastCount = 0;
  String? _lastBottomId;

  void onMessagesUpdated({
    required List<ChatMessageModel> messages,
    required ScrollController scrollController,
    required bool Function() isMounted,
  }) {
    if (messages.isEmpty) {
      _lastCount = 0;
      _lastBottomId = null;
      return;
    }
    final bottomId = messages.last.id;
    final shouldScroll =
        messages.length > _lastCount || bottomId != _lastBottomId;
    if (!shouldScroll) return;
    _lastCount = messages.length;
    _lastBottomId = bottomId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted() || !scrollController.hasClients) return;
      try {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      } catch (_) {}
    });
  }

  void reset() {
    _lastCount = 0;
    _lastBottomId = null;
  }
}
