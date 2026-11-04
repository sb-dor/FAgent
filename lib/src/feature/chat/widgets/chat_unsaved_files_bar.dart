import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template chat_unsaved_files_bar}
/// Above the composer while a message waits because the project has unsaved files: save them
/// all and send, or send as it is.
/// {@endtemplate}
class ChatUnsavedFilesBar extends StatelessWidget {
  /// {@macro chat_unsaved_files_bar}
  const ChatUnsavedFilesBar({
    required this.count,
    required this.onSaveAll,
    required this.onSendAnyway,
    super.key,
  });

  /// Unsaved files of the project.
  final int count;

  /// Saves them, then sends.
  final VoidCallback onSaveAll;

  /// Sends without saving.
  final VoidCallback onSendAnyway;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warnSoft,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: <Widget>[
              Icon(Icons.save_outlined, size: 16, color: colors.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localization.chatUnsavedFiles(count),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.text),
                ),
              ),
              TextButton(onPressed: onSendAnyway, child: Text(localization.chatSendAnyway)),
              FilledButton(onPressed: onSaveAll, child: Text(localization.saveAll)),
            ],
          ),
        ),
      ),
    );
  }
}
