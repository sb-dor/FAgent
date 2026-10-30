import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';

/// One selectable row of an [AppMenuSection].
@immutable
final class AppMenuItem<T> {
  /// Creates a menu row.
  const AppMenuItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.shortcut,
    this.tone = AppTone.neutral,
  });

  /// Result of the menu when this row is picked.
  final T value;

  /// Main line.
  final String title;

  /// Secondary, muted line.
  final String? subtitle;

  /// Optional leading icon.
  final IconData? icon;

  /// Draws a checkmark: the current choice.
  final bool selected;

  /// Disabled rows are dimmed and skipped by keyboard navigation.
  final bool enabled;

  /// Hint shown at the trailing edge, e.g. `⌘K`.
  final String? shortcut;

  /// [AppTone.warn] / [AppTone.danger] mark rows that need caution.
  final AppTone tone;
}

/// A titled group of [AppMenuItem]s.
@immutable
final class AppMenuSection<T> {
  /// Creates a group. Without [title] no header is drawn.
  const AppMenuSection({required this.items, this.title});

  /// Small header above the rows.
  final String? title;

  /// Rows of the group.
  final List<AppMenuItem<T>> items;
}

/// Builds the area under the rows of a menu. Calling `close(value)` closes the
/// menu and makes [showAppMenu] return `value`.
typedef AppMenuFooterBuilder<T> = Widget Function(
  BuildContext context,
  void Function(T? value) close,
);

/// Shows a popover menu next to [anchor] (a rect in global coordinates) and
/// returns the picked value, or `null` when it is dismissed.
///
/// The menu opens below [anchor], or above it when it does not fit. Arrow keys
/// move the highlight over enabled rows, Enter picks, Escape and a click
/// outside close it. Escape is consumed by the menu and does not reach
/// shortcuts of the page below. The row of the selected item is scrolled into
/// view when the menu opens.
///
/// With [searchable] a focused search field is shown above the rows; it filters
/// rows by title and subtitle, ignoring case, and hides sections left without
/// rows. The arrows and Enter keep working from the field. [searchHint] is the
/// placeholder of the field ("Search" when `null`).
///
/// [footerBuilder] adds interactive content under the rows, e.g. an option
/// toggle; it can close the menu with a value through its `close` callback.
Future<T?> showAppMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<AppMenuSection<T>> sections,
  double width = 320,
  bool searchable = false,
  String? searchHint,
  AppMenuFooterBuilder<T>? footerBuilder,
}) {
  final navigator = Navigator.of(context);
  final navigatorBox = navigator.context.findRenderObject()! as RenderBox;
  final localAnchor = Rect.fromPoints(
    navigatorBox.globalToLocal(anchor.topLeft),
    navigatorBox.globalToLocal(anchor.bottomRight),
  );
  return navigator.push<T>(
    _AppMenuRoute<T>(
      anchor: localAnchor,
      sections: sections,
      width: width,
      searchable: searchable,
      searchHint: searchHint,
      footerBuilder: footerBuilder,
    ),
  );
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.anchor,
    required this.sections,
    required this.width,
    required this.searchable,
    required this.searchHint,
    required this.footerBuilder,
  });

  final Rect anchor;
  final List<AppMenuSection<T>> sections;
  final double width;
  final bool searchable;
  final String? searchHint;
  final AppMenuFooterBuilder<T>? footerBuilder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
  ) => CustomSingleChildLayout(
    delegate: _MenuLayout(anchor: anchor, width: width),
    child: FadeTransition(
      opacity: animation,
      child: _AppMenu<T>(
        sections: sections,
        searchable: searchable,
        searchHint: searchHint,
        footerBuilder: footerBuilder,
      ),
    ),
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.anchor, required this.width});

  static const double _margin = 8;
  static const double _gap = 4;

  final Rect anchor;
  final double width;

  double _spaceBelow(double height) => height - _margin - (anchor.bottom + _gap);

  double get _spaceAbove => anchor.top - _gap - _margin;

  /// The menu may use the larger of the two sides of the anchor, so it never
  /// covers the anchor: it is then placed on the side where it fits.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: math.max(0, math.max(_spaceBelow(constraints.maxHeight), _spaceAbove)),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(_margin, size.width - childSize.width - _margin);
    final x = anchor.left.clamp(_margin, maxX);
    final double y;
    if (childSize.height <= _spaceBelow(size.height)) {
      y = anchor.bottom + _gap;
    } else {
      // The height is capped by the larger side, so it fits above here.
      y = anchor.top - _gap - childSize.height;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || width != oldDelegate.width;
}

class _AppMenu<T> extends StatefulWidget {
  const _AppMenu({
    required this.sections,
    required this.searchable,
    required this.searchHint,
    required this.footerBuilder,
  });

  final List<AppMenuSection<T>> sections;
  final bool searchable;
  final String? searchHint;
  final AppMenuFooterBuilder<T>? footerBuilder;

  @override
  State<_AppMenu<T>> createState() => _AppMenuState<T>();
}

class _AppMenuState<T> extends State<_AppMenu<T>> {
  late final List<AppMenuItem<T>> _items = <AppMenuItem<T>>[
    for (final section in widget.sections) ...section.items,
  ];
  late final List<GlobalKey> _keys = List<GlobalKey>.generate(_items.length, (_) => GlobalKey());
  late final TextEditingController _query = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onKey);

  /// Indices into [_items] of the rows that match the query, in order.
  late List<int> _visible = List<int>.generate(_items.length, (i) => i);

  String _appliedQuery = '';

  /// Index into [_items] of the highlighted row.
  int? _highlighted;

  @override
  void initState() {
    super.initState();
    final selected = _items.indexWhere((item) => item.selected && item.enabled);
    _highlighted = selected >= 0 ? selected : _step(-1, 1);
    _query.addListener(_onQueryChanged);
    _scrollToHighlighted(const Duration(milliseconds: 1));
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _matches(AppMenuItem<T> item, String query) =>
      item.title.toLowerCase().contains(query) ||
      (item.subtitle?.toLowerCase().contains(query) ?? false);

  void _onQueryChanged() {
    final query = _query.text.trim().toLowerCase();
    // The controller also notifies about caret moves; those keep the highlight.
    if (query == _appliedQuery) return;
    _appliedQuery = query;
    setState(() {
      _visible = <int>[
        for (var i = 0; i < _items.length; i++)
          if (query.isEmpty || _matches(_items[i], query)) i,
      ];
      _highlighted = _step(-1, 1);
    });
    _scrollToHighlighted(const Duration(milliseconds: 1));
  }

  /// Index into [_items] of the next enabled visible row after [from] (an index
  /// into [_items], or `-1` / `_items.length` for the ends) in [direction].
  int? _step(int from, int direction) {
    for (final index in direction > 0 ? _visible : _visible.reversed) {
      if (direction > 0 ? index > from : index < from) {
        if (_items[index].enabled) return index;
      }
    }
    return null;
  }

  void _scrollToHighlighted(Duration duration) {
    final target = _highlighted;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemContext = _keys[target].currentContext;
      if (itemContext != null && itemContext.mounted) {
        Scrollable.ensureVisible(itemContext, duration: duration);
      }
    });
  }

  void _move(int direction) {
    final next = _step(_highlighted ?? (direction > 0 ? -1 : _items.length), direction);
    if (next == null) return;
    setState(() => _highlighted = next);
    _scrollToHighlighted(const Duration(milliseconds: 80));
  }

  void _pick(int index) {
    final item = _items[index];
    if (item.enabled) Navigator.of(context).pop(item.value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final index = _highlighted;
      if (index != null && event is KeyDownEvent) _pick(index);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtering = _visible.length != _items.length;
    final visible = _visible.toSet();
    var index = 0;
    final rows = <Widget>[];
    for (final section in widget.sections) {
      final first = index;
      final sectionRows = <Widget>[];
      for (final item in section.items) {
        final i = index++;
        if (!visible.contains(i)) continue;
        sectionRows.add(
          _MenuRow<T>(
            key: _keys[i],
            item: item,
            highlighted: _highlighted == i,
            onHover: () {
              if (_highlighted != i) setState(() => _highlighted = i);
            },
            onTap: () => _pick(i),
          ),
        );
      }
      if (filtering && sectionRows.isEmpty && index > first) continue;
      if (section.title != null) rows.add(_SectionHeader(title: section.title!));
      rows.addAll(sectionRows);
    }
    final footerBuilder = widget.footerBuilder;
    return Focus(
      autofocus: !widget.searchable,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: colors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.shadow,
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.searchable) ...<Widget>[
                  _SearchField(
                    controller: _query,
                    focusNode: _searchFocus,
                    hint: widget.searchHint ?? Localization.of(context).search,
                  ),
                  Divider(color: colors.border),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
                  ),
                ),
                if (footerBuilder != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Divider(color: colors.border),
                  footerBuilder(context, (value) => Navigator.of(context).pop(value)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.hint});

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 16, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: style,
              cursorColor: colors.accent,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: style.copyWith(color: colors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(color: context.colors.muted, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
    super.key,
  });

  final AppMenuItem<T> item;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context).textTheme;
    final toneColor = switch (item.tone) {
      AppTone.neutral => null,
      AppTone.warn => colors.warn,
      AppTone.danger => colors.danger,
    };
    final subtitle = item.subtitle;
    final shortcut = item.shortcut;
    return Semantics(
      button: true,
      enabled: item.enabled,
      selected: item.selected,
      child: MouseRegion(
        cursor: item.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: item.enabled ? (_) => onHover() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.enabled ? onTap : null,
          child: Opacity(
            opacity: item.enabled ? 1 : 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highlighted ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: <Widget>[
                    if (item.icon != null) ...<Widget>[
                      Icon(item.icon, size: 16, color: toneColor ?? colors.muted),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            item.title,
                            style: theme.bodyMedium!.copyWith(color: toneColor ?? colors.text),
                          ),
                          if (subtitle != null)
                            Text(subtitle, style: theme.bodySmall!.copyWith(color: colors.muted)),
                        ],
                      ),
                    ),
                    if (toneColor != null) ...<Widget>[
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(color: toneColor, shape: BoxShape.circle),
                        child: const SizedBox.square(dimension: 8),
                      ),
                    ],
                    if (shortcut != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(shortcut, style: theme.bodySmall!.copyWith(color: colors.muted)),
                    ],
                    if (item.selected) ...<Widget>[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 16, color: colors.accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
