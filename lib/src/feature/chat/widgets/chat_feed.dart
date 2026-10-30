import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/feed_grouping.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/read_group_row.dart';

/// {@template chat_feed}
/// The feed, newest at the bottom; it sticks to the bottom while new items
/// arrive (reversed list), and stays put when the user scrolled up. Runs of
/// file reads fold into one row.
/// {@endtemplate}
class ChatFeed extends StatelessWidget {
  /// {@macro chat_feed}
  const ChatFeed({
    required this.items,
    required this.onAnswerPermission,
    this.onRejectAndSay,
    super.key,
  });

  /// Feed items, oldest first.
  final List<ChatItem> items;

  /// Answers a permission card.
  final void Function(String requestId, String optionId) onAnswerPermission;

  /// Declines a permission card and lets the user say why; `null` hides the button.
  final void Function(PermissionItem item)? onRejectAndSay;

  @override
  Widget build(BuildContext context) {
    final entries = groupFeed(items);
    final indexBySeq = <int, int>{
      for (var i = 0; i < entries.length; i++) entries[i].seq: entries.length - 1 - i,
    };
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: entries.length,
      // New items shift every index of the reversed list; map keys to their
      // new index so rows keep their state (an expanded group stays open).
      findChildIndexCallback: (key) => key is ValueKey<int> ? indexBySeq[key.value] : null,
      itemBuilder: (context, index) {
        final entry = entries[entries.length - 1 - index];
        return Center(
          key: ValueKey<int>(entry.seq),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: switch (entry) {
                SingleEntry(:final item) => ChatItemView(
                  item: item,
                  onAnswerPermission: onAnswerPermission,
                  onRejectAndSay: onRejectAndSay,
                ),
                ReadGroupEntry(:final calls) => ReadGroupRow(calls: calls),
              },
            ),
          ),
        );
      },
    );
  }
}
