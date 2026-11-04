import 'dart:io' as io;

import 'package:flutter/foundation.dart';
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
    return CodeDocument._(
      path: path,
      kind: CodeDocumentKind.text,
      files: files,
      editing: CodeLineEditingController.fromText(
        content.text,
        CodeLineOptions(lineBreak: lineBreakOf(content.text)),
      ),
      stamp: content.stamp,
    );
  }

  /// The line break the file mostly uses, so new lines match it.
  @visibleForTesting
  static TextLineBreak lineBreakOf(String text) {
    if (text.contains('\r\n')) return TextLineBreak.crlf;
    if (text.contains('\r')) return TextLineBreak.cr;
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

  /// The next save writes without checking the disk: the user chose to keep their edits.
  bool _overwriteNext = false;

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
  /// Throws [FileChangedOnDiskException] when the file changed since it was read, unless
  /// [overwrite] (or [keepMine] before). Other failures are kept in [error] and the document stays
  /// unsaved. A document without edits that is still on disk is not written.
  Future<void> save({bool overwrite = false}) async {
    if (kind != CodeDocumentKind.text || _saving) return;
    if (!_dirty && !_deleted && !overwrite && !_overwriteNext) return;
    _saving = true;
    final codeLines = editing.codeLines;
    try {
      final written = await _files.write(
        path,
        editing.text,
        expected: overwrite || _overwriteNext || _deleted ? null : stamp,
      );
      stamp = written;
      _saved = codeLines;
      _overwriteNext = false;
      _changedOnDisk = false;
      _deleted = false;
      _error = null;
      _dirty = !identical(editing.codeLines, _saved) && editing.codeLines != _saved;
    } on FileChangedOnDiskException {
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

  /// Replaces the text with the file on disk, keeping the caret where it still fits.
  Future<void> reloadFromDisk() async {
    if (kind != CodeDocumentKind.text) return;
    final FileContent content;
    try {
      content = await _files.read(path);
    } on Object catch (error) {
      _error = error is io.FileSystemException ? _describe(error) : '$error';
      notifyListeners();
      return;
    }
    if (_disposed) return;
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
    _overwriteNext = false;
    _error = null;
    notifyListeners();
  }

  /// Keeps the unsaved edits over the changed file: the next save overwrites it.
  void keepMine() {
    _changedOnDisk = false;
    _overwriteNext = true;
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
      _deleted = false;
      _changedOnDisk = true;
      notifyListeners();
      return;
    }
    await reloadFromDisk();
  }

  @override
  void dispose() {
    _disposed = true;
    editing
      ..removeListener(_onEdit)
      ..dispose();
    super.dispose();
  }
}
