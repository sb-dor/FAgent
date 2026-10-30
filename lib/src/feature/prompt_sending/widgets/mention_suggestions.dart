import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:path/path.dart' as p;

/// The list of project files under a typed `@`; [highlighted] is the row Enter would insert.
class MentionSuggestions extends StatelessWidget {
  /// Creates the list.
  const MentionSuggestions({
    super.key,
    required this.files,
    required this.highlighted,
    required this.onSelected,
  });

  final List<String> files;
  final int highlighted;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, file) in files.indexed)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                selected: index == highlighted,
                selectedTileColor: context.colors.accentSoft,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
                leading: const Icon(Icons.description_outlined, size: 18),
                title: Text(p.basename(file)),
                subtitle: Text(
                  p.dirname(file) == '.' ? '' : p.dirname(file),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(file),
              ),
            ),
        ],
      ),
    );
  }
}
