import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:path/path.dart' as p;

/// {@template picked_widget_card}
/// The widget picker of the Run tab: while the app waits for a tap, the hint and Cancel; then the
/// picked widget — its name, `file:line:column`, a thumbnail of it and the chain of the project's
/// widgets around it, with the current one highlighted — and the actions to add it to the message
/// and to open its file. When the pick or a switch gave nothing it says why.
/// {@endtemplate}
class PickedWidgetCard extends StatelessWidget {
  /// {@macro picked_widget_card}
  const PickedWidgetCard({
    required this.pick,
    required this.projectRoot,
    required this.onCancel,
    required this.onSelect,
    required this.onAddToMessage,
    required this.onOpenFile,
    super.key,
  });

  /// What the picker shows.
  final RunPickState pick;

  /// The folder of the project; the screenshot path is relative to it. `null` when it is not known.
  final String? projectRoot;

  /// Called when the user cancels a pick that waits.
  final VoidCallback onCancel;

  /// Called with the inspector id of the link of the chain the user switches to.
  final ValueChanged<String> onSelect;

  /// Called with the widget the card shows when the user adds it to the message.
  final ValueChanged<PickedWidget> onAddToMessage;

  /// Called with the file and the line of the widget when the user opens its file.
  final void Function(String file, int line) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final small = Theme.of(context).textTheme.bodySmall!;
    final widget = pick.widget;
    final problem = pick.problem;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: pick.picking
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
                      style: small.copyWith(color: colors.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CompactButton(label: localization.cancel, onPressed: onCancel),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget != null) ...<Widget>[
                    _Summary(widget: widget, projectRoot: projectRoot),
                    const SizedBox(height: 6),
                    _Chain(chain: pick.chain, current: pick.current, onSelect: onSelect),
                  ],
                  if (problem != null) ...<Widget>[
                    if (widget != null) const SizedBox(height: 6),
                    Text(
                      _problemText(localization, problem),
                      style: small.copyWith(
                        color: problem is PickFailed ? colors.danger : colors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      CompactButton(
                        primary: true,
                        icon: Icons.add,
                        label: localization.addToMessage,
                        onPressed: widget == null ? null : () => onAddToMessage(widget),
                      ),
                      if (widget != null)
                        CompactButton(
                          label: localization.openFile,
                          onPressed: () => onOpenFile(widget.file, widget.line),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  static String _problemText(GeneratedLocalization localization, PickResult problem) => switch (problem) {
    PickNoProjectWidget() => localization.pickNoProjectWidget,
    PickGone() => localization.pickGone,
    PickFailed(kind: PickFailure.inspectorUnavailable) => localization.pickInspectorUnavailable,
    PickFailed(kind: PickFailure.notDebug) => localization.pickNotDebug,
    PickFailed(kind: PickFailure.connectionLost) => localization.pickConnectionLost,
    PickFailed(kind: PickFailure.inspectorError, :final detail) => localization.pickInspectorError(
      detail ?? '',
    ),
    PickPicked() || PickCancelled() => '',
  };
}

/// The thumbnail, the name and the place of [widget]; a note instead of the thumbnail when there
/// is no screenshot.
class _Summary extends StatelessWidget {
  const _Summary({required this.widget, required this.projectRoot});

  final PickedWidget widget;
  final String? projectRoot;

  static const double _thumbnail = 64;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final textTheme = Theme.of(context).textTheme;
    final screenshot = widget.screenshot;
    final root = projectRoot;
    final note = Text(
      localization.pickNoScreenshot,
      style: textTheme.bodySmall!.copyWith(color: colors.muted, fontSize: 11),
    );
    final column = widget.column > 0 ? ':${widget.column}' : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (screenshot != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.surfaceAlt),
              child: Image.file(
                File(root == null ? screenshot : p.join(root, screenshot)),
                width: _thumbnail,
                height: _thumbnail,
                fit: BoxFit.contain,
                cacheWidth: (_thumbnail * 2).round(),
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.square(dimension: _thumbnail),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.name, style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
              Tooltip(
                message: widget.file,
                child: Text(
                  '${p.basename(widget.file)}:${widget.line}$column',
                  style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
                ),
              ),
              if (screenshot == null) ...<Widget>[const SizedBox(height: 2), note],
            ],
          ),
        ),
      ],
    );
  }
}

/// The links of [chain], from the picked widget outwards; the one at [current] is highlighted, a
/// tap on another one switches the card to it.
class _Chain extends StatelessWidget {
  const _Chain({required this.chain, required this.current, required this.onSelect});

  final List<PickedAncestor> chain;
  final int current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    final radius = BorderRadius.circular(AppRadius.small);
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final (index, link) in chain.indexed) ...<Widget>[
          if (index > 0) Text('›', style: style.copyWith(color: colors.muted)),
          DecoratedBox(
            decoration: BoxDecoration(
              color: index == current ? colors.accentSoft : null,
              borderRadius: radius,
            ),
            child: InkWell(
              key: ValueKey<String>('picked-link-$index'),
              borderRadius: radius,
              onTap: index == current || link.id.isEmpty ? null : () => onSelect(link.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  link.name,
                  style: style.copyWith(
                    color: index == current ? colors.accent : colors.text,
                    fontWeight: index == current ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
