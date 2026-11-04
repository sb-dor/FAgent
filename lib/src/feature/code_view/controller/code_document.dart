import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

/// How the Code view shows a file.
enum CodeDocumentKind {
  /// Text in the editor.
  text,

  /// A picture, read-only.
  image,

  /// Binary or not UTF-8.
  notText,

  /// Over [CodeFilesRepositoryImpl.maxBytes].
  tooLarge,

  /// It could not be read (no permission); [CodeDocument.error] says why.
  unreadable,
}

/// Extensions shown as pictures.
const Set<String> codeImageExtensions = <String>{'png', 'jpg', 'jpeg', 'gif', 'webp'};

/// {@template code_document}
/// One open file of the Code view: its text and undo history in [editing], what it was on disk,
/// and whether it has unsaved edits. The editor widget is only a view on it, so switching tabs keeps
/// the caret, the scroll and the undo history.
/// {@endtemplate}
final class CodeDocument extends ChangeNotifier {
  CodeDocument._({
    required this.path,
    required this.kind,
    required this._files,
    required this.editing,
    this.stamp,
    this._error,
  }) : _saved = editing.codeLines {
    editing.addListener(_onEdit);
  }

  /// Opens [path]: reads a text file, classifies the rest.
  ///
  /// Throws [io.PathNotFoundException] when the file does not exist.
  static Future<CodeDocument> open(String path, {required ICodeFilesRepository files}) async {
    CodeDocument other(CodeDocumentKind kind, [String? error]) => CodeDocument._(
      path: path,
      kind: kind,
      files: files,
      editing: CodeLineEditingController(),
      error: error,
    );

    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (codeImageExtensions.contains(extension)) return other(CodeDocumentKind.image);
    final FileContent content;
    try {
      content = await files.read(path);
    } on FileNotTextException {
      return other(CodeDocumentKind.notText);
    } on FileTooLargeException {
      return other(CodeDocumentKind.tooLarge);
    } on io.PathNotFoundException {
      rethrow;
    } on io.FileSystemException catch (error) {
      return other(CodeDocumentKind.unreadable, _describe(error));
    }
    late final CodeDocument document;
    return document = CodeDocument._(
      path: path,
      kind: CodeDocumentKind.text,
      files: files,
      editing: CodeLineEditingController(
        codeLines: CodeLines.fromText(content.text),
        options: CodeLineOptions(lineBreak: lineBreakOf(content.text)),
        // The controller takes its span builder once; the editor sets [decorator] later.
        spanBuilder:
            ({
              required context,
              required index,
              required codeLine,
              required textSpan,
              required style,
            }) =>
                document.decorator?.call(
                  context: context,
                  index: index,
                  codeLine: codeLine,
                  textSpan: textSpan,
                  style: style,
                ) ??
                textSpan,
      ),
      stamp: content.stamp,
    );
  }

  /// Draws something over the highlighted lines (the analysis's underlines); set by the editor.
  CodeLineSpanBuilder? decorator;

  /// The analysis's errors and warnings of this file.
  ValueListenable<List<DartDiagnostic>> get diagnostics => _diagnostics;
  final ValueNotifier<List<DartDiagnostic>> _diagnostics = ValueNotifier<List<DartDiagnostic>>(
    const <DartDiagnostic>[],
  );

  /// Errors among [diagnostics].
  int get errorCount => _diagnostics.value.where((d) => d.severity == DartSeverity.error).length;

  /// Warnings among [diagnostics].
  int get warningCount =>
      _diagnostics.value.where((d) => d.severity == DartSeverity.warning).length;

  /// Takes the analysis's [diagnostics] of this file and redraws the lines.
  void setDiagnostics(List<DartDiagnostic> diagnostics) {
    if (_disposed || listEquals(diagnostics, _diagnostics.value)) return;
    _diagnostics.value = List<DartDiagnostic>.unmodifiable(diagnostics);
    editing.forceRepaint();
    notifyListeners();
  }

  /// The line break the file mostly uses, so new lines match it.
  @visibleForTesting
  static TextLineBreak lineBreakOf(String text) {
    final crlf = '\r\n'.allMatches(text).length;
    final lf = '\n'.allMatches(text).length - crlf;
    final cr = '\r'.allMatches(text).length - crlf;
    if (crlf > lf && crlf >= cr) return TextLineBreak.crlf;
    if (cr > lf && cr > crlf) return TextLineBreak.cr;
    return TextLineBreak.lf;
  }

  static String _describe(io.FileSystemException error) => error.osError?.message ?? error.message;

  final ICodeFilesRepository _files;

  /// The file's absolute path.
  final String path;

  /// How the file is shown.
  final CodeDocumentKind kind;

  /// The editor's text, selection and undo history.
  final CodeLineEditingController editing;

  /// The file on disk when it was last read or written; a save expects it unchanged.
  FileStamp? stamp;

  /// The text at the last read or save.
  CodeLines _saved;

  /// Whether the text differs from the last read or save; undoing back to it clears this.
  bool get dirty => _dirty;
  bool _dirty = false;

  /// The file changed on disk while this document has unsaved edits.
  bool get changedOnDisk => _changedOnDisk;
  bool _changedOnDisk = false;

  /// The file is gone from disk; the text stays and a save creates it again.
  bool get deleted => _deleted;
  bool _deleted = false;

  /// Why the last save or read failed; `null` once it works.
  String? get error => _error;
  String? _error;

  /// The file on disk that [changedOnDisk] is about; [keepMine] makes the next save expect it, so
  /// a later change asks again.
  FileStamp? _diskStamp;

  bool _saving = false;

  /// A change on disk arrived during a save; it is checked once the save is done.
  FileChangeKind? _changeDuringSave;

  bool _disposed = false;

  void _onEdit() {
    final codeLines = editing.codeLines;
    final dirty = !identical(codeLines, _saved) && codeLines != _saved;
    if (dirty == _dirty) return;
    _dirty = dirty;
    notifyListeners();
  }

  /// Writes the text to disk.
  ///
  /// Throws [FileChangedOnDiskException] when the file changed since it was read (or came back
  /// after it was deleted), unless [overwrite]; the document is then [changedOnDisk]. Other
  /// failures are kept in [error] and the document stays unsaved. A document without edits that is
  /// still on disk is not written.
  Future<void> save({bool overwrite = false}) async {
    if (kind != CodeDocumentKind.text || _saving) return;
    if (!_dirty && !_deleted && !overwrite) return;
    _saving = true;
    final codeLines = editing.codeLines;
    try {
      var expected = stamp;
      if (overwrite) {
        expected = null;
      } else if (_deleted) {
        // A deleted file is written only while it is still gone: one that came back is someone
        // else's.
        final current = await _files.stamp(path);
        if (current != null) throw FileChangedOnDiskException(path, current);
        expected = null;
      }
      final written = await _files.write(path, editing.text, expected: expected);
      stamp = written;
      _saved = codeLines;
      _diskStamp = null;
      _changedOnDisk = false;
      _deleted = false;
      _error = null;
      _dirty = !identical(editing.codeLines, _saved) && editing.codeLines != _saved;
    } on FileChangedOnDiskException catch (error) {
      // The watch may not have told yet (or never will: a link's target outside the project).
      _changeDuringSave = null;
      _markChanged(error.actual);
      rethrow;
    } on io.FileSystemException catch (error) {
      _error = _describe(error);
    } finally {
      _saving = false;
    }
    if (_disposed) return;
    notifyListeners();
    if (_changeDuringSave case final change?) {
      _changeDuringSave = null;
      await onDiskChange(change);
    }
  }

  /// The file on disk is [actual] (gone when `null`) and not what the unsaved edits started from.
  void _markChanged(FileStamp? actual) {
    if (_disposed) return;
    if (actual == null) {
      _deleted = true;
      _changedOnDisk = false;
    } else {
      _deleted = false;
      _diskStamp = actual;
      _changedOnDisk = true;
    }
    notifyListeners();
  }

  /// Replaces the text with the file on disk, keeping the caret where it still fits.
  Future<void> reloadFromDisk() => _reload(followDisk: false);

  /// Reads the file and shows it. Following the disk on its own ([followDisk]), the reload gives
  /// way to edits typed while the file was read: they stay, and the document is [changedOnDisk].
  Future<void> _reload({required bool followDisk}) async {
    if (kind != CodeDocumentKind.text) return;
    final before = editing.codeLines;
    final FileContent content;
    try {
      content = await _files.read(path);
    } on Object catch (error) {
      _error = error is io.FileSystemException ? _describe(error) : '$error';
      notifyListeners();
      return;
    }
    if (_disposed) return;
    if (followDisk && !identical(editing.codeLines, before)) {
      _markChanged(content.stamp);
      return;
    }
    final selection = editing.selection;
    editing.text = content.text;
    final last = editing.lineCount - 1;
    if (selection.extentIndex <= last && selection.baseIndex <= last) {
      editing.selection = selection;
    }
    stamp = content.stamp;
    _saved = editing.codeLines;
    _dirty = false;
    _changedOnDisk = false;
    _deleted = false;
    _diskStamp = null;
    _error = null;
    notifyListeners();
  }

  /// Keeps the unsaved edits over the changed file: the next save overwrites that version of it,
  /// and a later change asks again.
  void keepMine() {
    stamp = _diskStamp ?? stamp;
    _diskStamp = null;
    _changedOnDisk = false;
    notifyListeners();
  }

  /// The file changed on disk: a document without edits follows it, one with edits is marked
  /// [changedOnDisk]; the app's own write (same stamp) changes nothing.
  Future<void> onDiskChange(FileChangeKind change) async {
    if (kind != CodeDocumentKind.text) return;
    if (_saving) {
      _changeDuringSave = change;
      return;
    }
    final current = await _files.stamp(path);
    if (_disposed) return;
    if (current == null) {
      if (_deleted) return;
      _deleted = true;
      notifyListeners();
      return;
    }
    if (current == stamp && !_deleted) return;
    if (_dirty) {
      _markChanged(current);
      return;
    }
    await _reload(followDisk: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _diagnostics.dispose();
    editing
      ..removeListener(_onEdit)
      ..dispose();
    super.dispose();
  }
}
