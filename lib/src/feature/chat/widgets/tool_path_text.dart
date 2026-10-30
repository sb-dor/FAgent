import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/feature/chat/models/tool_row_label.dart';

/// {@template tool_path_text}
/// The text of a tool row on one line: the agent's wording, the file name (mono, prominent) and
/// its folder (mono, muted). It is one paragraph that ends in an ellipsis, so the folder at the
/// end gives way first and the file name stays readable.
/// {@endtemplate}
class ToolPathText extends StatelessWidget {
  /// {@macro tool_path_text}
  const ToolPathText({required this.label, super.key});

  /// What to show.
  final ToolRowLabel label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = AppText.mono(context);
    final title = label.title;
    final name = label.name;
    final folder = label.folder;
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.text),
        children: <InlineSpan>[
          if (title != null) TextSpan(text: name == null ? title : '$title '),
          if (name != null)
            TextSpan(
              text: name,
              style: mono.copyWith(color: colors.text),
            ),
          if (folder != null)
            TextSpan(
              text: ' $folder',
              style: mono.copyWith(color: colors.muted),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
