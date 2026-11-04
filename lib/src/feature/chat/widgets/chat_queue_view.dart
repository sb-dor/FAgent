import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/queued_prompt.dart';

/// {@template chat_queue_view}
/// The chat's queued messages above the composer, in the order they go: the first line of each
/// with its number of attachments, ✎ (back into the field) and ✕. While [paused] a line says so
/// with "Send next". Nothing while the queue is empty.
/// {@endtemplate}
class ChatQueueView extends StatelessWidget {
  /// {@macro chat_queue_view}
  const ChatQueueView({
    required this.items,
    required this.paused,
    required this.onEdit,
    required this.onRemove,
    required this.onSendNext,
    super.key,
  });

  /// The queued messages.
  final List<QueuedPrompt> items;

  /// The queue waits for the user after a failed or stopped turn.
  final bool paused;

  /// ✎ on the message at the index.
  final ValueChanged<int> onEdit;

  /// ✕ on the message at the index.
  final ValueChanged<int> onRemove;

  /// Sends the first message; `null` while the chat cannot take one.
  final VoidCallback? onSendNext;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kChatColumnWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (paused)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.pause_circle_outline_rounded, size: 16, color: colors.warn),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localization.queuePaused,
                              style: textTheme.bodySmall?.copyWith(color: colors.warn),
                            ),
                          ),
                          TextButton(
                            onPressed: onSendNext,
                            child: Text(localization.queueSendNext),
                          ),
                        ],
                      ),
                    ),
                  for (final (index, item) in items.indexed)
                    _QueueRow(
                      item: item,
                      onEdit: () => onEdit(index),
                      onRemove: () => onRemove(index),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item, required this.onEdit, required this.onRemove});

  final QueuedPrompt item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final attachments = item.attachmentCount;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.schedule_rounded, size: 14, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.typed.split('\n').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
          ),
          if (attachments > 0)
            Tooltip(
              message: localization.queueAttachments(attachments),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.attach_file_rounded, size: 14, color: colors.muted),
                    Text('$attachments', style: textTheme.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: localization.queueEdit,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: localization.queueRemove,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
