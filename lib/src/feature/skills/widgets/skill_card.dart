import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_editor.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_scope.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/source_tag.dart';

/// Width of the labels of the fields.
const double _kLabelWidth = 120;

/// Below this width the buttons go under the title.
const double _kWideHeader = 640;

/// {@template skill_card}
/// The open skill or rule: its title, where it comes from, what it does, where it is on and its
/// text. Without an open item it asks to pick one.
///
/// The card scrolls vertically and is meant to be at least 400 px wide.
/// {@endtemplate}
class SkillCard extends StatelessWidget {
  /// {@macro skill_card}
  const SkillCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.view, scope.library]),
      builder: (context, _) {
        final id = scope.view.selectedId;
        final item = id == null ? null : scope.library.library.byId(id);
        if (item == null) {
          return EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: Localization.of(context).skillsPickOne,
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(item: item),
              if (item.problem case final problem?) ...<Widget>[
                const SizedBox(height: 12),
                _Problem(text: problem),
              ],
              const SizedBox(height: 16),
              _Field(
                label: Localization.of(context).skillDescription,
                child: Text(item.description.isEmpty ? '—' : item.description),
              ),
              if (item.whenToUse case final whenToUse? when whenToUse.isNotEmpty)
                _Field(label: Localization.of(context).skillWhenToUse, child: Text(whenToUse)),
              _Field(
                label: Localization.of(context).skillEnabled,
                child: SkillScope(item: item),
              ),
              if (item.files.isNotEmpty)
                _Field(
                  label: Localization.of(context).skillFiles,
                  child: Text(
                    item.files.join(' · '),
                    style: AppText.mono(context, size: 11).copyWith(color: context.colors.muted),
                  ),
                ),
              const SizedBox(height: 16),
              // The editor belongs to one item, so another item starts a new one.
              SkillEditor(key: ValueKey<String>(item.id), item: item),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final colors = context.colors;
    final version = item.version;
    final title = Row(
      children: <Widget>[
        Flexible(
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(context, size: 15).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        SourceTag(source: item.source),
        if (version != null && version.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            '· v$version',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (item.readOnly)
          CompactButton(
            label: localization.skillDuplicate,
            icon: Icons.copy_outlined,
            onPressed: () => scope.duplicate(item),
          ),
        // Running a skill from a chat is for project skills for now; the rest arrives with M3.
        _Tooltip(
          message: item.invocable ? null : localization.comingInMilestone('M3'),
          child: CompactButton(
            label: localization.skillTryInChat,
            icon: Icons.chat_bubble_outline,
            onPressed: item.invocable ? () => scope.tryInChat(item) : null,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= _kWideHeader
              ? Row(
                  children: <Widget>[
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[title, const SizedBox(height: 8), actions],
                ),
        ),
        if (item.readOnly) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            localization.skillReadOnlyNote,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
          ),
        ],
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, size: 16, color: colors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A label and its value on one row.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _kLabelWidth,
            child: Text(label, style: theme.bodySmall!.copyWith(color: context.colors.muted)),
          ),
          Expanded(
            child: DefaultTextStyle.merge(style: theme.bodyMedium, child: child),
          ),
        ],
      ),
    );
  }
}

/// A [Tooltip] when there is a [message], else just the [child].
class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message == null ? child : Tooltip(message: message, child: child);
}
