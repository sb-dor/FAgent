import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';

/// {@template run_error_block}
/// An error of the running app in the logs: title, message and place, with the actions to send it
/// to the agent, open its file and expand the stack.
/// {@endtemplate}
class RunErrorBlock extends StatefulWidget {
  /// {@macro run_error_block}
  const RunErrorBlock({
    required this.error,
    required this.sent,
    required this.onSend,
    required this.onOpenFile,
    super.key,
  });

  /// The error to show.
  final RunError error;

  /// Whether the error was already sent to the agent.
  final bool sent;

  /// Called when the user sends the error to the agent.
  final VoidCallback onSend;

  /// Called with the file and the line of the error when the user opens its file.
  final void Function(String file, int? line) onOpenFile;

  @override
  State<RunErrorBlock> createState() => _RunErrorBlockState();
}

class _RunErrorBlockState extends State<RunErrorBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final error = widget.error;
    final file = error.file;
    final stack = error.stack;
    final mono = AppText.mono(context, size: 11);
    final place = error.location ?? (file == null ? null : '$file:${error.line ?? ''}');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              error.title,
              style: mono.copyWith(color: colors.danger, fontWeight: FontWeight.w600),
            ),
            Text(error.message, style: mono),
            if (place != null) Text(place, style: mono.copyWith(color: colors.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                CompactButton(
                  primary: true,
                  icon: widget.sent ? Icons.check : Icons.arrow_forward,
                  label: localization.sendToAgent,
                  onPressed: widget.onSend,
                ),
                if (file != null)
                  CompactButton(
                    label: localization.openFile,
                    onPressed: () => widget.onOpenFile(file, error.line),
                  ),
                if (stack != null && stack.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.muted,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 14),
                    iconAlignment: IconAlignment.end,
                    label: Text(localization.details),
                  ),
              ],
            ),
            if (_expanded && stack != null) ...<Widget>[
              const SizedBox(height: 6),
              SelectableText(stack, style: mono.copyWith(color: colors.muted, fontSize: 10.5)),
            ],
          ],
        ),
      ),
    );
  }
}
