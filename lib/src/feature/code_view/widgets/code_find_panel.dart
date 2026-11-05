import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:re_editor/re_editor.dart';

/// The height the find panel takes above the text: none while closed, one row, or two with
/// replace (never in a [readOnly] editor).
double codeFindPanelHeight(CodeFindValue? value, {bool readOnly = false}) => value == null
    ? 0
    : (value.replaceMode && !readOnly ? CodeFindPanel.rowHeight * 2 : CodeFindPanel.rowHeight) + 8;

/// {@template code_find_panel}
/// Find (⌘F) and replace in the open file, in the editor's top right corner.
/// {@endtemplate}
class CodeFindPanel extends StatelessWidget implements PreferredSizeWidget {
  /// {@macro code_find_panel}
  const CodeFindPanel({required this.controller, required this.readOnly, super.key});

  /// The editor's find state.
  final CodeFindController controller;

  /// A read-only editor offers no replace.
  final bool readOnly;

  /// Height of one row of the panel.
  static const double rowHeight = 36;

  @override
  Size get preferredSize =>
      Size(double.infinity, codeFindPanelHeight(controller.value, readOnly: readOnly));

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final colors = context.colors;
    final localization = Localization.of(context);
    final result = value.result;
    // Esc in a field of the panel closes it; the editor's own Esc only hears the editor.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): controller.close,
      },
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, right: 12),
          child: DecoratedBox(
            key: const ValueKey<String>('code-find-panel'),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: colors.border),
              boxShadow: <BoxShadow>[BoxShadow(color: colors.shadow, blurRadius: 8)],
            ),
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: <Widget>[
                        if (!readOnly)
                          _Button(
                            icon: value.replaceMode ? Icons.expand_more : Icons.chevron_right,
                            tooltip: localization.codeFindToggleReplace,
                            onPressed: controller.toggleMode,
                          ),
                        Expanded(
                          child: _Field(
                            controller: controller.findInputController,
                            focusNode: controller.findInputFocusNode,
                            hint: localization.codeFindHint,
                          ),
                        ),
                        _Toggle(
                          label: 'Aa',
                          tooltip: localization.codeMatchCase,
                          on: value.option.caseSensitive,
                          onPressed: controller.toggleCaseSensitive,
                        ),
                        _Toggle(
                          label: '.*',
                          tooltip: localization.codeRegex,
                          on: value.option.regex,
                          onPressed: controller.toggleRegex,
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            result == null || result.matches.isEmpty
                                ? localization.codeFindNoResults
                                : '${result.index + 1}/${result.matches.length}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.muted),
                          ),
                        ),
                        _Button(
                          icon: Icons.arrow_upward,
                          tooltip: localization.codeFindPrevious,
                          onPressed: result == null ? null : controller.previousMatch,
                        ),
                        _Button(
                          icon: Icons.arrow_downward,
                          tooltip: localization.codeFindNext,
                          onPressed: result == null ? null : controller.nextMatch,
                        ),
                        _Button(
                          icon: Icons.close,
                          tooltip: localization.close,
                          onPressed: controller.close,
                        ),
                      ],
                    ),
                  ),
                  if (value.replaceMode && !readOnly)
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 28),
                          Expanded(
                            child: _Field(
                              controller: controller.replaceInputController,
                              focusNode: controller.replaceInputFocusNode,
                              hint: localization.codeReplaceHint,
                            ),
                          ),
                          _Button(
                            icon: Icons.done,
                            tooltip: localization.codeReplaceOne,
                            onPressed: result == null ? null : controller.replaceMatch,
                          ),
                          _Button(
                            icon: Icons.done_all,
                            tooltip: localization.codeReplaceAll,
                            onPressed: result == null ? null : controller.replaceAllMatches,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.focusNode, required this.hint});

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 1,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: 16),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.tooltip,
    required this.on,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: SizedBox(
          width: 26,
          height: 26,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: on ? colors.accent : colors.muted,
                fontWeight: on ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
