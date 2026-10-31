import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/permission_rules/models/permission_rules_exceptions.dart';
import 'package:path/path.dart' as p;

/// The permission rules a project's agent was told to always allow.
///
/// They live in `<project>/.claude/settings.local.json` under `permissions.allow`, where the
/// Claude adapter writes them for "Always allow in this project". The shared
/// `.claude/settings.json` of the project is neither read nor changed.
abstract interface class IPermissionRulesRepository {
  /// The rules in `permissions.allow` of the project at [projectRoot], in file order.
  ///
  /// A missing file, `permissions` or `allow` gives an empty list; entries that are not strings
  /// are left out. Throws [PermissionRulesUnreadableException] when the file is not a JSON object.
  Future<List<String>> rules(String projectRoot);

  /// Removes every entry equal to [rule] from `permissions.allow` of the project at [projectRoot].
  ///
  /// The file is read again first and everything else in it (other keys, `deny`, `ask`, the order
  /// of keys) is kept. It is replaced in one step, so a reader never sees half of it. Does nothing
  /// when the file or the rule is not there. Throws [PermissionRulesUnreadableException] when the
  /// file is not a JSON object.
  Future<void> remove(String projectRoot, String rule);
}

/// [IPermissionRulesRepository] over the project's `.claude/settings.local.json`.
final class PermissionRulesRepositoryImpl implements IPermissionRulesRepository {
  /// Creates the repository.
  PermissionRulesRepositoryImpl();

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  String _fileOf(String projectRoot) => p.join(projectRoot, '.claude', 'settings.local.json');

  @override
  Future<List<String>> rules(String projectRoot) async {
    final path = _fileOf(projectRoot);
    final text = await _readOrNull(path);
    if (text == null) return const <String>[];
    final allow = _allowOf(_decode(path, text));
    return <String>[
      if (allow != null)
        for (final entry in allow)
          if (entry is String) entry,
    ];
  }

  @override
  Future<void> remove(String projectRoot, String rule) async {
    var path = _fileOf(projectRoot);
    try {
      // A link is followed, so the file it points to is the one that gets replaced.
      path = await File(path).resolveSymbolicLinks();
    } on PathNotFoundException {
      return;
    }
    final text = await _readOrNull(path);
    if (text == null) return;
    final root = _decode(path, text);
    final allow = _allowOf(root);
    if (allow == null || !allow.contains(rule)) return;
    allow.removeWhere((entry) => entry == rule);
    await _replaceFile(path, '${_encoder.convert(root)}\n');
  }

  /// The text of the file at [path]; `null` when there is no such file.
  Future<String?> _readOrNull(String path) async {
    try {
      return await File(path).readAsString();
    } on PathNotFoundException {
      return null;
    } on FileSystemException {
      // A folder or a file that cannot be opened is as unusable as a broken one.
      throw PermissionRulesUnreadableException(path);
    } on FormatException {
      // The file is not valid UTF-8.
      throw PermissionRulesUnreadableException(path);
    }
  }

  Map<String, Object?> _decode(String path, String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw PermissionRulesUnreadableException(path);
    }
    if (decoded is! Map<String, Object?>) throw PermissionRulesUnreadableException(path);
    return decoded;
  }

  /// The `permissions.allow` list of [root]; `null` when the file has none.
  List<Object?>? _allowOf(Map<String, Object?> root) {
    final permissions = root['permissions'];
    if (permissions is! Map<String, Object?>) return null;
    final allow = permissions['allow'];
    return allow is List<Object?> ? allow : null;
  }

  /// Writes [text] to a hidden temporary file next to [path] and renames it over [path].
  Future<void> _replaceFile(String path, String text) async {
    final temporary = File(
      p.join(p.dirname(path), '.${p.basename(path)}.${DateTime.now().microsecondsSinceEpoch}.tmp'),
    );
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } on Object {
      if (temporary.existsSync()) await temporary.delete();
      rethrow;
    }
  }
}
