import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// One tab of [PaneTabs].
final class PaneTab<T> {
  /// Creates a tab.
  const PaneTab({required this.id, required this.label, this.count, this.errors});

  /// Value reported through `PaneTabs.onSelected`.
  final T id;

  /// Text of the tab.
  final String label;

  /// Number of items behind the tab, shown muted next to the label.
  final int? count;

  /// Number of errors; a positive value shows a red badge.
  final int? errors;
}

/// {@template pane_tabs}
/// The tab strip of the right pane. The [selected] tab is highlighted.
/// {@endtemplate}
class PaneTabs<T> extends StatelessWidget {
  /// {@macro pane_tabs}
  const PaneTabs({required this.tabs, required this.selected, required this.onSelected, super.key});

  /// Tabs in display order.
  final List<PaneTab<T>> tabs;

  /// Id of the highlighted tab.
  final T selected;

  /// Called with the id of the tab the user tapped.
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final tab in tabs) ...<Widget>[
                _Tab(tab: tab, selected: tab.id == selected, onTap: () => onSelected(tab.id)),
                if (tab != tabs.last) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab<T> extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final PaneTab<T> tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    final radius = BorderRadius.circular(AppRadius.small);
    final count = tab.count;
    final errors = tab.errors;
    return Semantics(
      button: true,
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.bg : Colors.transparent,
          borderRadius: radius,
          border: selected ? Border.all(color: colors.border) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    tab.label,
                    style: style.copyWith(
                      color: selected ? colors.text : colors.muted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Text('$count', style: style.copyWith(color: colors.muted)),
                  ],
                  if (errors != null && errors > 0) ...<Widget>[
                    const SizedBox(width: 4),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '$errors',
                          style: style.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
