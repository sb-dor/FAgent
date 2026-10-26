import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

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
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
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
                        _label(localization, file.status),
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

  static String _label(GeneratedLocalization localization, String status) {
    if (status == 'clean') return localization.fileStatusReverted;
    if (status == '??' || status.contains('A')) return localization.fileStatusAdded;
    if (status.contains('D')) return localization.fileStatusDeleted;
    if (status.contains('R')) return localization.fileStatusRenamed;
    return localization.fileStatusModified;
  }
}
