import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_hover.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_location.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:re_editor/re_editor.dart';

/// {@template code_hover_info}
/// What the hover card shows: the analysis's docs of the name, the errors and warnings under the
/// pointer, and where the pointer was (global).
/// {@endtemplate}
@immutable
final class CodeHoverInfo {
  /// {@macro code_hover_info}
  const CodeHoverInfo({required this.doc, required this.diagnostics, required this.anchor});

  /// The declaration and dartdoc; `null` when the analysis has none.
  final DartHover? doc;

  /// The errors and warnings whose range holds the position.
  final List<DartDiagnostic> diagnostics;

  /// The pointer when the card was asked for, global.
  final Offset anchor;
}

/// What go to definition or find references found: the [name] at the caret and its places.
typedef CodeJump = ({String name, List<LspLocation> locations});

/// One use (or declaration) of a name: the file, its short [label], the 0-based [line], the name's
/// column in the file ([column]), and the trimmed code [text] of that line with the name at
/// [start]–[end] in it.
typedef CodeReference = ({
  String path,
  String label,
  int line,
  int column,
  int start,
  int end,
  String text,
});

/// Whether [position] is within [range] (an empty range holds its own start).
bool lspRangeContains(LspRange range, LspPosition position) {
  int compare(LspPosition a, LspPosition b) =>
      a.line != b.line ? a.line.compareTo(b.line) : a.character.compareTo(b.character);
  if (compare(position, range.start) < 0) return false;
  final end = compare(position, range.end);
  return end < 0 || (end == 0 && range.start == range.end);
}

/// {@template code_navigation_controller}
/// Hover of one Dart tab: the pointer resting [hoverDelay] on a position asks the analysis for
/// its docs; the card closes when the pointer has left the name and the card for [hoverGrace],
/// on any edit or caret move, and on Esc. An answer that arrives after the text, the caret or the
/// pointer moved is dropped.
/// {@endtemplate}
final class CodeNavigationController extends ChangeNotifier {
  /// {@macro code_navigation_controller}
  CodeNavigationController({required this._document, required this._analysis}) {
    _document.editing.addListener(_onEditing);
  }

  final CodeDocument _document;
  final IDartAnalysisRepository _analysis;

  /// How long the pointer rests before the card is asked for.
  static const Duration hoverDelay = Duration(milliseconds: 500);

  /// How long the card stays after the pointer left, so it can move into the card.
  static const Duration hoverGrace = Duration(milliseconds: 150);

  CodeLineEditingController get _editing => _document.editing;

  /// The card's content; `null` while no card shows.
  CodeHoverInfo? get hover => _hover;
  CodeHoverInfo? _hover;

  /// The range of the name the card is about (or of its first diagnostic).
  LspRange? _hoverRange;

  /// Grows with every pointer move, edit and dismissal; an older answer is dropped.
  int _asks = 0;
  Timer? _delay;
  Timer? _grace;
  bool _disposed = false;

  /// The pointer is over [position] of the text (`null`: over no text), at [global].
  void pointerAt(LspPosition? position, Offset global) {
    if (_disposed) return;
    if (position == null) {
      pointerLeft();
      return;
    }
    final range = _hoverRange;
    if (_hover != null && range != null && lspRangeContains(range, position)) {
      _grace?.cancel();
      return;
    }
    _delay?.cancel();
    final ask = ++_asks;
    _delay = Timer(hoverDelay, () => _ask(ask, position, global).ignore());
    if (_hover != null) _startGrace();
  }

  /// The pointer left the text: the card closes unless it moves into it.
  void pointerLeft() {
    if (_disposed) return;
    _delay?.cancel();
    _asks++;
    if (_hover != null) _startGrace();
  }

  /// The pointer is in the card: it stays.
  void keepHover() => _grace?.cancel();

  /// Closes the card and forgets any answer on the way.
  void dismissHover() {
    _delay?.cancel();
    _grace?.cancel();
    _asks++;
    if (_hover == null) return;
    _hover = null;
    _hoverRange = null;
    if (!_disposed) notifyListeners();
  }

  void _startGrace() {
    _grace?.cancel();
    _grace = Timer(hoverGrace, dismissHover);
  }

  Future<void> _ask(int ask, LspPosition position, Offset global) async {
    final lines = _editing.codeLines;
    final selection = _editing.selection;
    final doc = await _analysis.hover(_document.path, _editing.text, position);
    if (_disposed ||
        ask != _asks ||
        !identical(lines, _editing.codeLines) ||
        selection != _editing.selection) {
      return;
    }
    final diagnostics = <DartDiagnostic>[
      for (final diagnostic in _document.diagnostics.value)
        if (lspRangeContains(diagnostic.range, position)) diagnostic,
    ];
    if (doc == null && diagnostics.isEmpty) return;
    _grace?.cancel();
    _hover = CodeHoverInfo(doc: doc, diagnostics: diagnostics, anchor: global);
    _hoverRange =
        doc?.range ??
        (diagnostics.isEmpty ? null : diagnostics.first.range) ??
        LspRange(start: position, end: position);
    notifyListeners();
  }

  /// Where the name at the caret is declared; `null` when the text or the caret changed before the
  /// answer came.
  Future<CodeJump?> definitionAtCaret() =>
      _jump((position) => _analysis.definition(_document.path, _editing.text, position));

  /// Every use of the name at the caret, its declaration included; `null` when the text or the
  /// caret changed before the answer came.
  Future<CodeJump?> referencesAtCaret() =>
      _jump((position) => _analysis.references(_document.path, _editing.text, position));

  static final RegExp _wordChar = RegExp(r'[A-Za-z0-9_$]');

  Future<CodeJump?> _jump(Future<List<LspLocation>> Function(LspPosition position) ask) async {
    dismissHover();
    final lines = _editing.codeLines;
    final selection = _editing.selection;
    final line = lines.index2lineIndex(selection.extentIndex);
    final position = LspPosition(
      line: line < 0 ? selection.extentIndex : line,
      character: selection.extentOffset,
    );
    final text = lines[selection.extentIndex].text;
    var start = selection.extentOffset.clamp(0, text.length);
    var end = start;
    while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
      start--;
    }
    while (end < text.length && _wordChar.hasMatch(text[end])) {
      end++;
    }
    final locations = await ask(position);
    if (_disposed || !identical(lines, _editing.codeLines) || selection != _editing.selection) {
      return null;
    }
    return (name: text.substring(start, end), locations: locations);
  }

  void _onEditing() {
    // Typing, a click or a caret move: the card and any answer on the way are stale.
    if (_hover != null || _delay?.isActive == true) dismissHover();
  }

  @override
  void dispose() {
    _disposed = true;
    _delay?.cancel();
    _grace?.cancel();
    _editing.removeListener(_onEditing);
    super.dispose();
  }
}
