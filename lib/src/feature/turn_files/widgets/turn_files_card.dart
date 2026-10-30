import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:flutter_code_agent/src/feature/turn_files/widgets/file_change_label.dart';

/// {@template turn_files_card}
/// Files the turn changed (from `git status` before and after it), collapsed
/// to a count.
/// {@endtemplate}
class TurnFilesCard extends StatelessWidget {
  /// {@macro turn_files_card}
  const TurnFilesCard({required this.files, super.key});

  /// Changed files.
  final List<TurnFile> files;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localization = Localization.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.border),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.difference_outlined, size: 18),
          title: Text(localization.filesChanged(files.length), style: theme.textTheme.bodyMedium),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: <Widget>[
            for (final file in files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 110,
                      child: Text(
                        fileChangeLabel(localization, fileChangeKind(file.status)),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        file.path,
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
