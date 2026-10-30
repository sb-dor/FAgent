import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/app_title_bar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_page_scaffold}
/// A full-window screen (Skills, Settings): the title bar with "← Back to chat" and [title], a
/// navigation of [sections] and the [child] of the [selected] section in a centered column.
///
/// The navigation is 220 px wide, or a 56 px icon rail when the window is narrower than
/// [kWideWindowWidth]. The column is at most 640 px wide with 32 px around it, and scrolls.
/// {@endtemplate}
class WorkspacePageScaffold extends StatelessWidget {
  /// {@macro workspace_page_scaffold}
  const WorkspacePageScaffold({
    required this.title,
    required this.sections,
    required this.selected,
    required this.onSelect,
    required this.child,
    super.key,
  });

  /// Name of the screen, shown in the title bar.
  final String title;

  /// Sections of the navigation: id, icon and label.
  final List<(String id, IconData icon, String label)> sections;

  /// Id of the open section.
  final String selected;

  /// Called with the id of the section the user picked.
  final ValueChanged<String> onSelect;

  /// Content of the open section.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    final rail = MediaQuery.sizeOf(context).width < kWideWindowWidth;
    final label = sections.where((section) => section.$1 == selected).firstOrNull?.$3 ?? title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTitleBar(
          leading: <Widget>[
            TextButton.icon(
              onPressed: scope.dataController.backToChat,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(Localization.of(context).backToChat),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.muted,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          title: Text(title),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Navigation(rail: rail, sections: sections, selected: selected, onSelect: onSelect),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      key: const ValueKey<String>('page-content'),
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            label,
                            style: Theme.of(context).textTheme.titleLarge!
                                .copyWith(color: context.colors.text),
                          ),
                          const SizedBox(height: 16),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.rail,
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final bool rail;
  final List<(String id, IconData icon, String label)> sections;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        key: const ValueKey<String>('page-navigation'),
        width: rail ? 56 : 220,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: rail ? 8 : 12, vertical: 12),
          children: <Widget>[
            for (final (id, icon, label) in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _NavItem(
                  icon: icon,
                  label: label,
                  rail: rail,
                  selected: id == selected,
                  onTap: () => onSelect(id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.rail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool rail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.accent : colors.text;
    final item = Material(
      color: selected ? colors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: rail ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: <Widget>[
              if (!rail) const SizedBox(width: 12),
              Icon(icon, size: 18, color: color),
              if (!rail) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return rail ? Tooltip(message: label, child: item) : item;
  }
}

/// Body of a section whose real content arrives in a later milestone.
class SectionPlaceholder extends StatelessWidget {
  /// Creates a placeholder for the section named [title].
  const SectionPlaceholder({
    required this.icon,
    required this.title,
    this.milestone,
    super.key,
  });

  /// Glyph of the section.
  final IconData icon;

  /// Name of the section.
  final String title;

  /// When the section is delivered, e.g. `M3`; `null` when there is no milestone yet.
  final String? milestone;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: icon,
    title: title,
    message: milestone == null
        ? Localization.of(context).comingSoon
        : Localization.of(context).comingInMilestone(milestone!),
    badge: const PreviewBadge(),
  );
}
