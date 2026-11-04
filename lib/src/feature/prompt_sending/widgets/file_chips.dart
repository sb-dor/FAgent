import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_file.dart';

/// {@template file_chips}
/// The files and folders from outside the project that go with a message, as cards: the path
/// (`~` for the home folder, a long name cut in the middle) and a badge with the extension or
/// "Folder". With [onRemove] each card has a ✕.
/// {@endtemplate}
class FileChips extends StatelessWidget {
  /// {@macro file_chips}
  const FileChips({required this.files, this.onRemove, super.key});

  /// The cards in order.
  final List<ComposerFile> files;

  /// Removes a card; `null` for a sent message.
  final ValueChanged<ComposerFile>? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final file in files)
        FileCard(file: file, onRemove: onRemove == null ? null : () => onRemove!(file)),
    ],
  );
}

/// {@template file_card}
/// One card of [FileChips].
/// {@endtemplate}
class FileCard extends StatelessWidget {
  /// {@macro file_card}
  const FileCard({required this.file, this.onRemove, super.key});

  /// The file.
  final ComposerFile file;

  /// Removes it; `null` hides the ✕.
  final VoidCallback? onRemove;

  /// The card's width.
  static const double width = 200;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final textTheme = Theme.of(context).textTheme;
    final badge =
        file.badge ?? (file.folder ? localization.fileCardFolder : localization.fileCardFile);
    return Tooltip(
      message: file.path,
      waitDuration: const Duration(milliseconds: 500),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        composerFileLabel(
                          file.path,
                          home: Platform.environment['HOME'],
                          folder: file.folder,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: colors.text),
                      ),
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Text(
                            badge,
                            style: textTheme.labelSmall?.copyWith(color: colors.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: onRemove,
                      tooltip: localization.removeFile,
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: Icon(Icons.close, color: colors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
