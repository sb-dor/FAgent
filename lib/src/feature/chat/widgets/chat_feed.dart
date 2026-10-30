import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';

/// {@template chat_feed}
/// The feed, newest at the bottom; it sticks to the bottom while new items
/// arrive (reversed list), and stays put when the user scrolled up.
/// {@endtemplate}
class ChatFeed extends StatelessWidget {
  /// {@macro chat_feed}
  const ChatFeed({required this.items, required this.onAnswerPermission, super.key});

  /// Feed items, oldest first.
  final List<ChatItem> items;

  /// Answers a permission card.
  final void Function(String requestId, String optionId) onAnswerPermission;

  @override
  Widget build(BuildContext context) => ListView.builder(
    reverse: true,
    padding: const EdgeInsets.symmetric(vertical: 16),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[items.length - 1 - index];
      return Center(
        key: ValueKey<int>(item.seq),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: ChatItemView(item: item, onAnswerPermission: onAnswerPermission),
          ),
        ),
      );
    },
  );
}
