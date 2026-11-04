import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/completion_edit.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/snippet_session.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:re_editor/re_editor.dart';

/// {@template dart_completion_controller}
/// The completion list of one Dart tab: it asks the analysis after a letter or `.` (or on
/// ⌃Space), keeps the newest answer only, narrows it by the word before the caret, and inserts
/// the chosen entry, snippets and imports included.
/// {@endtemplate}
final class DartCompletionController extends ChangeNotifier {
  /// {@macro dart_completion_controller}
  DartCompletionController({required this._document, required this._analysis}) {
    _lines = _document.editing.codeLines;
    _document.editing.addListener(_onEditing);
  }

  final CodeDocument _document;
  final IDartAnalysisRepository _analysis;

  /// How long typing must pause before the analysis is asked.
  static const Duration requestDelay = Duration(milliseconds: 50);

  CodeLineEditingController get _editing => _document.editing;

  /// The answer of the analysis for the current word, all of it.
  List<DartCompletion> _answer = const <DartCompletion>[];

  /// What the list shows: [_answer] narrowed by the word before the caret.
  List<DartCompletion> get items => _items;
  List<DartCompletion> _items = const <DartCompletion>[];

  /// The highlighted row.
  int get highlighted => _highlighted;
  int _highlighted = 0;

  /// The list is shown.
  bool get open => _items.isNotEmpty;

  /// The snippet being filled in, if any.
  SnippetSession? get snippet => _snippet;
  SnippetSession? _snippet;

  /// The text the last edit left; a selection change leaves it as it is.
  late CodeLines _lines;

  /// Grows with every edit; an answer to an older one is dropped.
  int _edits = 0;
  Timer? _timer;
  bool _applying = false;
  bool _disposed = false;

  static final RegExp _wordChar = RegExp(r'[A-Za-z0-9_$]');

  void _onEditing() {
    if (_applying || _disposed) return;
    if (_snippet case final snippet?) {
      // A fold hides lines the snippet's offsets count: the session cannot follow it.
      if (_editing.codeLines.length != _editing.lineCount) snippet.end();
      snippet.onEdit();
      if (!snippet.active) _snippet = null;
    }
    final lines = _editing.codeLines;
    if (identical(lines, _lines)) {
      // The caret moved without an edit: nothing asked for it, and no answer still on the way.
      _timer?.cancel();
      _edits++;
      if (open) dismiss();
      return;
    }
    _lines = lines;
    _edits++;
    final before = _charBeforeCaret();
    if (before != null && (_wordChar.hasMatch(before) || before == '.')) {
      if (open) _narrow();
      _timer?.cancel();
      _timer = Timer(requestDelay, _request);
    } else {
      _timer?.cancel();
      dismiss();
    }
  }

  String? _charBeforeCaret() {
    final selection = _editing.selection;
    if (!selection.isCollapsed) return null;
    final line = _editing.codeLines[selection.extentIndex].text;
    final offset = selection.extentOffset;
    return offset == 0 || offset > line.length ? null : line[offset - 1];
  }

  /// The identifier before the caret.
  String _word() {
    final selection = _editing.selection;
    final line = _editing.codeLines[selection.extentIndex].text;
    var start = selection.extentOffset.clamp(0, line.length);
    final end = start;
    while (start > 0 && _wordChar.hasMatch(line[start - 1])) {
      start--;
    }
    return line.substring(start, end);
  }

  /// Opens the list for the caret now (⌃Space), whatever is before it.
  void trigger() {
    _timer?.cancel();
    _request();
  }

  Future<void> _request() async {
    final edits = _edits;
    final selection = _editing.selection;
    final items = await _analysis.complete(
      _document.path,
      _editing.text,
      LspPosition(line: _documentLine(selection.extentIndex), character: selection.extentOffset),
    );
    // Typed on since it was asked: a newer request answers instead.
    if (_disposed || edits != _edits) return;
    _answer = List<DartCompletion>.of(items)
      ..sort((a, b) => (a.sortText ?? a.label).compareTo(b.sortText ?? b.label));
    _narrow();
  }

  /// The document line of the visible line [index]: a folded block above counts its hidden lines.
  int _documentLine(int index) {
    final line = _editing.codeLines.index2lineIndex(index);
    return line < 0 ? index : line;
  }

  /// Opens every folded block, so visible lines are document lines again (LSP edits count the
  /// latter).
  void _unfoldAll() {
    var folded = true;
    while (folded) {
      folded = false;
      for (var i = _editing.codeLines.length - 1; i >= 0; i--) {
        if (_editing.codeLines[i].chunkParent) {
          _editing.expandChunk(i);
          folded = true;
        }
      }
    }
  }

  void _narrow() {
    final word = _word().toLowerCase();
    final byStart = <DartCompletion>[];
    final byPart = <DartCompletion>[];
    for (final item in _answer) {
      final filter = item.filterText.toLowerCase();
      if (filter.startsWith(word)) {
        byStart.add(item);
      } else if (word.isNotEmpty && filter.contains(word)) {
        byPart.add(item);
      }
    }
    _items = <DartCompletion>[...byStart, ...byPart];
    _highlighted = 0;
    notifyListeners();
  }

  /// Moves the highlight by [step] rows, round the ends.
  void move(int step) {
    if (!open) return;
    _highlighted = (_highlighted + step) % _items.length;
    notifyListeners();
  }

  /// Closes the list.
  void dismiss() {
    if (_items.isEmpty && _answer.isEmpty) return;
    _answer = const <DartCompletion>[];
    _items = const <DartCompletion>[];
    _highlighted = 0;
    notifyListeners();
  }

  /// Inserts the highlighted row.
  Future<void> accept() => open ? select(_items[_highlighted]) : Future<void>.value();

  /// Inserts [item] at the caret: its edit (stretched to the caret if typing went on), its
  /// snippet, and the imports the analysis adds when resolving it.
  Future<void> select(DartCompletion item) async {
    _timer?.cancel();
    // An answer still on the way is about the text before this insert.
    _edits++;
    dismiss();
    final resolved = item.data == null ? item : await _analysis.resolve(item);
    if (_disposed) return;
    _applying = true;
    try {
      _unfoldAll();
    } finally {
      _applying = false;
    }
    final selection = _editing.selection;
    final caret = LspPosition(line: selection.extentIndex, character: selection.extentOffset);
    final edit = resolved.edit;
    final completion =
        edit != null &&
            edit.range.end.line == caret.line &&
            edit.range.start.line == caret.line &&
            edit.range.start.character <= caret.character
        ? DartCompletion(
            label: resolved.label,
            kind: resolved.kind,
            insertText: resolved.insertText,
            isSnippet: resolved.isSnippet,
            edit: LspTextEdit(
              range: LspRange(start: edit.range.start, end: caret),
              newText: edit.newText,
            ),
            additionalEdits: resolved.additionalEdits,
          )
        : resolved;
    _applying = true;
    try {
      _snippet = applyCompletion(_editing, completion, caret: caret);
    } finally {
      _applying = false;
    }
    _lines = _editing.codeLines;
    notifyListeners();
  }

  /// Tab in a snippet: the next stop; `false` when there is no snippet.
  bool nextStop() {
    final snippet = _snippet;
    if (snippet == null) return false;
    _applying = true;
    try {
      snippet.next();
    } finally {
      _applying = false;
    }
    if (!snippet.active) _snippet = null;
    return true;
  }

  /// ⇧Tab in a snippet: the previous stop; `false` when there is no snippet.
  bool previousStop() {
    final snippet = _snippet;
    if (snippet == null) return false;
    _applying = true;
    try {
      snippet.previous();
    } finally {
      _applying = false;
    }
    return true;
  }

  /// Esc in a snippet ends it.
  void endSnippet() {
    _snippet?.end();
    _snippet = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _document.editing.removeListener(_onEditing);
    super.dispose();
  }
}
