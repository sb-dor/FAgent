import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:path/path.dart' as p;

/// {@template picked_widget_card}
/// The result of picking a widget in the running app: its name, `file:line` and the chain of its
/// ancestors, with the actions to add it to the message and to open its file. While the app waits
/// for a tap ([picked] is `null`) it shows the hint instead.
/// {@endtemplate}
class PickedWidgetCard extends StatelessWidget {
  /// {@macro picked_widget_card}
  const PickedWidgetCard({
    required this.picked,
    required this.onAddToMessage,
    required this.onOpenFile,
    super.key,
  });

  /// The picked widget; `null` while the pick is in progress.
  final PickedWidget? picked;

  /// Called when the user adds the widget to the message.
  final VoidCallback onAddToMessage;

  /// Called with the file and the line of the widget when the user opens its file.
  final void Function(String file, int line) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final textTheme = Theme.of(context).textTheme;
    final picked = this.picked;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: picked == null
            ? Row(
                children: <Widget>[
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localization.pickWidgetHint,
                      style: textTheme.bodySmall!.copyWith(color: colors.muted),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        picked.name,
                        style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${p.basename(picked.file)}:${picked.line}',
                        style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
                      ),
                    ],
                  ),
                  if (picked.ancestors.isNotEmpty)
                    Text(
                      picked.ancestors.join(' › '),
                      style: textTheme.bodySmall!.copyWith(color: colors.muted),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      CompactButton(
                        primary: true,
                        icon: Icons.add,
                        label: localization.addToMessage,
                        onPressed: onAddToMessage,
                      ),
                      CompactButton(
                        label: localization.openFile,
                        onPressed: () => onOpenFile(picked.file, picked.line),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
