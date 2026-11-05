import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_controller.dart';

/// The [references] whose label or code contains [query], case-insensitively.
List<CodeReference> codeReferenceMatches(List<CodeReference> references, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return references;
  return <CodeReference>[
    for (final reference in references)
      if (reference.label.toLowerCase().contains(needle) ||
          reference.text.toLowerCase().contains(needle))
        reference,
  ];
}

/// Shows [references] under [title] like ⌘P: typing filters, ↑↓ and Enter pick one, Esc closes.
/// Returns the chosen one.
Future<CodeReference?> showCodeReferences(
  BuildContext context, {
  required String title,
  required List<CodeReference> references,
}) => showDialog<CodeReference>(
  context: context,
  builder: (context) => CodeReferencesDialog(title: title, references: references),
);

/// {@template code_references_dialog}
/// The list [showCodeReferences] shows.
/// {@endtemplate}
class CodeReferencesDialog extends StatefulWidget {
  /// {@macro code_references_dialog}
  const CodeReferencesDialog({required this.title, required this.references, super.key});

  /// "References to name (n)".
  final String title;

  /// The rows, in order.
  final List<CodeReference> references;

  @override
  State<CodeReferencesDialog> createState() => _CodeReferencesDialogState();
}

class _CodeReferencesDialogState extends State<CodeReferencesDialog> {
  final TextEditingController _query = TextEditingController();
  late List<CodeReference> _matches = widget.references;
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(
      () => setState(() {
        _matches = codeReferenceMatches(widget.references, _query.text);
        _highlighted = 0;
      }),
    );
  }

  void _pick([int? index]) {
    final at = index ?? _highlighted;
    if (at < _matches.length) Navigator.of(context).pop(_matches[at]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (step == 0 || _matches.isEmpty) return KeyEventResult.ignored;
    setState(() => _highlighted = (_highlighted + step).clamp(0, _matches.length - 1));
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final code = AppText.mono(context).copyWith(color: colors.text);
    return Dialog(
      alignment: const Alignment(0, -0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(color: colors.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  onSubmitted: (_) => _pick(),
                  decoration: InputDecoration(
                    hintText: Localization.of(context).codeReferencesFilter,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _matches.length,
                itemBuilder: (context, index) {
                  final reference = _matches[index];
                  final start = reference.start.clamp(0, reference.text.length);
                  final end = reference.end.clamp(start, reference.text.length);
                  return InkWell(
                    onTap: () => _pick(index),
                    child: ColoredBox(
                      color: index == _highlighted
                          ? colors.accentSoft
                          : colors.bg.withValues(alpha: 0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${reference.label}:${reference.line + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(color: colors.muted),
                            ),
                            Text.rich(
                              TextSpan(
                                style: code,
                                children: <InlineSpan>[
                                  TextSpan(text: reference.text.substring(0, start)),
                                  TextSpan(
                                    text: reference.text.substring(start, end),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(text: reference.text.substring(end)),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
