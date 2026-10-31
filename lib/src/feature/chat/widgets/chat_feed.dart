import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/feed_grouping.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/read_group_row.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';

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
    this.projectRoot,
    this.onOpenChange,
    this.skills = ChatSkills.empty,
    this.onOpenSkill,
    this.keyboardRequestId,
    super.key,
  });

  /// Feed items, oldest first.
  final List<ChatItem> items;

  /// Answers a permission card.
  final void Function(String requestId, String optionId) onAnswerPermission;

  /// Declines a permission card and lets the user say why; `null` hides the button.
  final void Function(PermissionItem item)? onRejectAndSay;

  /// The chat's project folder; tool paths inside it are shown relative to it.
  final String? projectRoot;

  /// Called with the file's path when the user clicks an edit row; `null` keeps edit rows plain.
  final ValueChanged<String>? onOpenChange;

  /// The skills of the chat's project, for the line of a loaded skill.
  final ChatSkills skills;

  /// Called with the id of a skill when the user clicks the line of a loaded skill; `null` keeps
  /// the line plain.
  final ValueChanged<String>? onOpenSkill;

  /// `requestId` of the permission card that Enter and Esc answer (the latest waiting one); only
  /// that card shows the key hints.
  final String? keyboardRequestId;

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
        // The same outer padding as the composer, so both columns line up.
        return Padding(
          key: ValueKey<int>(entry.seq),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
              child: switch (entry) {
                SingleEntry(:final item) => ChatItemView(
                  item: item,
                  onAnswerPermission: onAnswerPermission,
                  onRejectAndSay: onRejectAndSay,
                  projectRoot: projectRoot,
                  onOpenChange: onOpenChange,
                  skills: skills,
                  onOpenSkill: onOpenSkill,
                  keyboardTarget: item is PermissionItem && item.requestId == keyboardRequestId,
                ),
                ReadGroupEntry(:final calls) => ReadGroupRow(
                  calls: calls,
                  projectRoot: projectRoot,
                ),
              },
            ),
          ),
        );
      },
    );
  }
}
