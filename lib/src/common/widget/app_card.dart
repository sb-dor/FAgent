import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template app_card}
/// A bordered card (radius `AppRadius.medium`, padding 14/16) with a header and an optional [body].
///
/// The header is a [Wrap]: [leading], [title] and [subtitle] sit on the first
/// line, [trailing] actions move below them when the card is too narrow.
/// {@endtemplate}
class AppCard extends StatelessWidget {
  /// {@macro app_card}
  const AppCard({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing = const <Widget>[],
    this.body,
    super.key,
  });

  /// Widget before the title, e.g. an icon or a [StatusDot].
  final Widget? leading;

  /// Main line of the header.
  final Widget title;

  /// Secondary line under the [title].
  final Widget? subtitle;

  /// Actions at the end of the header; they wrap below the title when there is no room.
  final List<Widget> trailing;

  /// Content under the header.
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    final body = this.body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)],
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DefaultTextStyle.merge(
                            style: textTheme.titleSmall!.copyWith(color: colors.text),
                            child: title,
                          ),
                          if (subtitle != null)
                            DefaultTextStyle.merge(
                              style: textTheme.bodySmall!.copyWith(color: colors.muted),
                              child: subtitle,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (trailing.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: trailing,
                  ),
              ],
            ),
            if (body != null) ...<Widget>[const SizedBox(height: 12), body],
          ],
        ),
      ),
    );
  }
}

/// {@template key_value_grid}
/// Rows of a muted label (120–170 px wide) and a value that takes the rest of the width and wraps.
/// {@endtemplate}
class KeyValueGrid extends StatelessWidget {
  /// {@macro key_value_grid}
  const KeyValueGrid({required this.rows, super.key});

  /// Label and value of every row.
  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.bodySmall!.copyWith(color: colors.muted);
    final valueStyle = textTheme.bodySmall!.copyWith(color: colors.text);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelWidth = math.min(170, math.max(120, constraints.maxWidth * 0.3)).toDouble();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final (index, (label, value)) in rows.indexed) ...<Widget>[
                  if (index > 0) const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: labelWidth,
                        child: Text(label, style: labelStyle),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DefaultTextStyle.merge(style: valueStyle, child: value),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
