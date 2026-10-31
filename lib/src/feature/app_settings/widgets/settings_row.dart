import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template settings_card}
/// A bordered card (radius `AppRadius.medium`) that stacks [children], usually [SettingsRow]s,
/// with a divider between them.
/// {@endtemplate}
class SettingsCard extends StatelessWidget {
  /// {@macro settings_card}
  const SettingsCard({required this.children, super.key});

  /// Rows of the card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (index, child) in children.indexed) ...<Widget>[
              if (index > 0) Divider(height: 1, thickness: 1, color: colors.border),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// {@template settings_row}
/// A row of a settings section: the [label] (and a muted [hint] under it) on the left, the
/// [control] on the right. In a row narrower than [wrapWidth] the control moves under the label.
/// {@endtemplate}
class SettingsRow extends StatelessWidget {
  /// {@macro settings_row}
  const SettingsRow({required this.label, required this.control, this.hint, super.key});

  /// What the row sets.
  final String label;

  /// A muted line under the [label].
  final String? hint;

  /// The widget that changes the setting.
  final Widget control;

  /// Rows narrower than this put the [control] under the [label].
  static const double wrapWidth = 480;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final hint = this.hint;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: textTheme.bodyMedium!.copyWith(color: colors.text)),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < wrapWidth
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  text,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: control),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: text),
                  const SizedBox(width: 16),
                  control,
                ],
              ),
      ),
    );
  }
}
