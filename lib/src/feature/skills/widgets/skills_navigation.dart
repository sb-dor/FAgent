import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';

/// {@template skills_navigation}
/// The "Sources" part of the Skills screen's navigation, under the Skills and Rules sections: one
/// item per source with the number of items in the open section, and "Add source…".
///
/// Choosing a source filters the list by it, and choosing it again shows every source. The
/// project source is there only while the screen has a project. In a window narrower than
/// [kWideWindowWidth] the navigation is an icon rail, and so are these items.
/// {@endtemplate}
class SkillsNavigation extends StatelessWidget {
  /// {@macro skills_navigation}
  const SkillsNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = SkillsConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final rail = MediaQuery.sizeOf(context).width < kWideWindowWidth;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.library, scope.view]),
      builder: (context, _) {
        final view = scope.view;
        final library = scope.library.library;
        final sources = <(SkillSource, IconData, String)>[
          (SkillSource.builtin, Icons.inventory_2_outlined, localization.skillsSourceBuiltin),
          (SkillSource.user, Icons.person_outline, localization.skillsSourceUser),
          if (view.projectId != null)
            (SkillSource.project, Icons.folder_outlined, localization.skillsSourceProject),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (rail)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider())
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                child: Text(
                  localization.skillsSources,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: context.colors.muted, fontWeight: FontWeight.w600),
                ),
              ),
            for (final (source, icon, label) in sources)
              _SourceItem(
                icon: icon,
                label: label,
                count: '${view.countOf(library, source)}',
                rail: rail,
                selected: view.source == source,
                onTap: () => view.setSource(view.source == source ? null : source),
              ),
            _SourceItem(
              icon: Icons.add,
              label: localization.skillsAddSource,
              rail: rail,
              accent: true,
              badge: const PreviewBadge(),
              onTap: () =>
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(SnackBar(content: Text(localization.comingInMilestone('M3')))),
            ),
          ],
        );
      },
    );
  }
}

class _SourceItem extends StatelessWidget {
  const _SourceItem({
    required this.icon,
    required this.label,
    required this.rail,
    required this.onTap,
    this.count,
    this.selected = false,
    this.accent = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool rail;
  final VoidCallback onTap;

  /// Number of items, shown at the right.
  final String? count;
  final bool selected;

  /// Draws the item in the accent color, like a call to action.
  final bool accent;

  /// Shown next to the label.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected || accent ? colors.accent : colors.text;
    final textStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400);
    final radius = BorderRadius.circular(AppRadius.small);
    final Widget content = rail
        ? SizedBox(
            height: 36,
            child: Center(child: Icon(icon, size: 18, color: color)),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(label, style: textStyle),
                        ?badge,
                      ],
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      count!,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
          );
    final item = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: radius,
        child: InkWell(borderRadius: radius, onTap: onTap, child: content),
      ),
    );
    return rail ? Tooltip(message: count == null ? label : '$label $count', child: item) : item;
  }
}
