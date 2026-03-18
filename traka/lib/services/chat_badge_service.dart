import 'package:flutter/foundation.dart';

/// Service untuk optimistic update badge unread chat.
/// Saat user buka chat, orderId ditandai "sudah dibaca" agar badge hilang segera.
class ChatBadgeService extends ChangeNotifier {
  ChatBadgeService._();
  static final ChatBadgeService instance = ChatBadgeService._();

  final Set<String> _optimisticReadOrderIds = {};

  void markAsReadOptimistic(String orderId) {
    if (_optimisticReadOrderIds.add(orderId)) {
      notifyListeners();
    }
  }

  bool isOptimisticRead(String orderId) => _optimisticReadOrderIds.contains(orderId);
}
