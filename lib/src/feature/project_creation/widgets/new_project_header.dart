import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template new_project_header}
/// The title row of the New project dialog: [title] and a ✕ that closes the dialog.
/// {@endtemplate}
class NewProjectHeader extends StatelessWidget {
  /// {@macro new_project_header}
  const NewProjectHeader({required this.title, super.key});

  /// What the dialog is about now.
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium!
                  .copyWith(color: colors.text, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: Localization.of(context).close,
            icon: Icon(Icons.close, size: 18, color: colors.muted),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
