import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:path/path.dart' as p;

/// Rows quick open shows at most.
const int quickOpenLimit = 50;

/// The [files] (relative paths) whose path contains [query], case-insensitively: those whose
/// name contains it first, each group in the given order; at most [quickOpenLimit].
List<String> quickOpenMatches(List<String> files, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return files.take(quickOpenLimit).toList();
  final byName = <String>[];
  final byPath = <String>[];
  for (final file in files) {
    final lower = file.toLowerCase();
    if (!lower.contains(needle)) continue;
    (p.basename(lower).contains(needle) ? byName : byPath).add(file);
  }
  return <String>[...byName, ...byPath].take(quickOpenLimit).toList();
}

/// Asks for a file of the project by name; [files] lists them (relative paths). Returns the
/// chosen relative path.
Future<String?> showCodeQuickOpen(
  BuildContext context, {
  required Future<List<String>> Function() files,
}) => showDialog<String>(
  context: context,
  builder: (context) => _QuickOpenDialog(files: files),
);

class _QuickOpenDialog extends StatefulWidget {
  const _QuickOpenDialog({required this.files});

  final Future<List<String>> Function() files;

  @override
  State<_QuickOpenDialog> createState() => _QuickOpenDialogState();
}

class _QuickOpenDialogState extends State<_QuickOpenDialog> {
  final TextEditingController _query = TextEditingController();
  List<String> _files = const <String>[];
  List<String> _matches = const <String>[];
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    widget.files().then((files) {
      if (!mounted) return;
      setState(() {
        _files = files;
        _filter();
      });
    }).ignore();
    _query.addListener(() => setState(_filter));
  }

  void _filter() {
    _matches = quickOpenMatches(_files, _query.text);
    _highlighted = 0;
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
    return Dialog(
      alignment: const Alignment(0, -0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  onSubmitted: (_) => _pick(),
                  decoration: InputDecoration(
                    hintText: Localization.of(context).codeQuickOpenHint,
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
                itemBuilder: (context, index) => InkWell(
                  onTap: () => _pick(index),
                  child: ColoredBox(
                    color: index == _highlighted
                        ? colors.accentSoft
                        : colors.bg.withValues(alpha: 0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Text(
                        _matches[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
