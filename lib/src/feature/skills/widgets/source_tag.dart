import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';

/// {@template source_tag}
/// A small pill that says where a skill or rule comes from: built-in, mine or project.
/// {@endtemplate}
class SourceTag extends StatelessWidget {
  /// {@macro source_tag}
  const SourceTag({required this.source, super.key});

  /// Where the item comes from.
  final SkillSource source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final (label, background, foreground) = switch (source) {
      SkillSource.builtin => (localization.skillTagBuiltin, colors.surface, colors.muted),
      SkillSource.user => (localization.skillTagUser, colors.okSoft, colors.ok),
      SkillSource.project => (localization.skillTagProject, colors.accentSoft, colors.accent),
      // Git sources arrive with milestone M3; the name of the tool is not translated.
      SkillSource.git => ('git', colors.surface, colors.muted),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: foreground, fontSize: 10, height: 14 / 10),
        ),
      ),
    );
  }
}
