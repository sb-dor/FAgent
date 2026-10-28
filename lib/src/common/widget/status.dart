import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// State shown by a [StatusDot] or a [StatusPill].
enum AppStatusTone {
  /// No state: transparent dot, muted pill.
  none,

  /// In progress / selected: the accent color.
  active,

  /// Needs attention.
  warn,

  /// Failed.
  danger,

  /// Healthy.
  ok,
}

/// {@template status_dot}
/// A 7 px dot colored by [tone].
/// {@endtemplate}
class StatusDot extends StatelessWidget {
  /// {@macro status_dot}
  const StatusDot({required this.tone, super.key});

  /// State the dot stands for.
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (tone) {
      AppStatusTone.none => Colors.transparent,
      AppStatusTone.active => colors.accent,
      AppStatusTone.warn => colors.warn,
      AppStatusTone.danger => colors.danger,
      AppStatusTone.ok => colors.ok,
    };
    return SizedBox.square(
      dimension: 7,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// {@template status_pill}
/// A small label on the soft background of [tone] with the strong tone color for the text.
/// {@endtemplate}
class StatusPill extends StatelessWidget {
  /// {@macro status_pill}
  const StatusPill({required this.label, required this.tone, super.key});

  /// Text of the pill.
  final String label;

  /// State the pill stands for.
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      AppStatusTone.none => (colors.surface, colors.muted),
      AppStatusTone.active => (colors.accentSoft, colors.accent),
      AppStatusTone.warn => (colors.warnSoft, colors.warn),
      AppStatusTone.danger => (colors.dangerSoft, colors.danger),
      AppStatusTone.ok => (colors.okSoft, colors.ok),
    };
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: foreground, fontWeight: FontWeight.w500);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
