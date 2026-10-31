import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_code_agent/src/feature/skills/data/knowledge_copy.dart';
import 'package:flutter_code_agent/src/feature/skills/data/knowledge_scanner.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skill_states.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:path/path.dart' as p;

/// Skills and rules: the built-in ones, the user's and the project's, and where they are on.
abstract interface class ISkillsRepository {
  /// The library for a project: the current one at once, then again whenever files, enablement
  /// or the repository's own changes make it differ.
  ///
  /// [projectRoot] is the project folder whose `.claude/` is scanned (nothing when `null` or when
  /// the folders do not exist yet); [projectId] picks the enablement exceptions. Cancel the
  /// subscription to stop watching.
  Stream<SkillLibrary> watch({int? projectId, String? projectRoot});

  /// The text of the `SKILL.md` or rule file of [id].
  ///
  /// A `*:project:*` id needs the [projectRoot] of its project and throws
  /// [KnowledgeNotFoundException] without it; other ids ignore it. The same goes for [write] and
  /// [duplicate].
  Future<String> read(String id, {String? projectRoot});

  /// Replaces the text of [id]; throws [ReadOnlyKnowledgeException] for a built-in item.
  ///
  /// The file is replaced in one step, so a reader never sees half of the text. When [expected] is
  /// given (the text the caller last read) and the file holds something else now, nothing is
  /// written and [KnowledgeConflictException] is thrown.
  Future<void> write(String id, String text, {String? projectRoot, String? expected});

  /// Turns [id] on or off for everything (`projectId == null`) or as an exception for one project.
  Future<void> setEnabled(String id, {required bool enabled, int? projectId});

  /// Removes the exception of [projectId] for [id], so the project follows the global value.
  Future<void> clearException(String id, int projectId);

  /// Creates a skill or rule named [name] among the user's items and returns its id.
  Future<String> create(KnowledgeKind kind, String name);

  /// Copies [id] to the user's items under a free name and returns the new id.
  Future<String> duplicate(String id, {String? projectRoot});

  /// Copies the skill folder at [path] to the user's items and returns the new id.
  Future<String> importFolder(String path);
}

/// The description a new skill or rule starts with, so it does not open with a problem banner.
const String _skillPlaceholder = 'Describe when to use this skill.';
const String _rulePlaceholder = 'Describe the rule.';

final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// [ISkillsRepository] over folders on disk, the built-in assets and the `skill_states` table.
final class SkillsRepositoryImpl implements ISkillsRepository {
  /// Creates the repository; [userRoot] holds the user's `skills/` and `rules/` folders.
  SkillsRepositoryImpl({
    required this._database,
    required this._builtin,
    required this._userRoot,
    this._pollInterval = const Duration(seconds: 2),
  });

  final AppDatabase _database;
  final IBuiltinKnowledge _builtin;
  final String _userRoot;
  final Duration _pollInterval;

  final Set<Future<void> Function({bool force})> _watchers = {};

  /// How many [watch] streams are listened to.
  @visibleForTesting
  int get activeWatchers => _watchers.length;

  @override
  Stream<SkillLibrary> watch({int? projectId, String? projectRoot}) {
    final root = projectRoot == null ? null : p.join(projectRoot, '.claude');
    final controller = StreamController<SkillLibrary>();
    StreamSubscription<List<SkillStateRow>>? statesSubscription;
    Timer? timer;
    var closed = false;
    var running = false;
    var rescan = false;
    var rescanForced = false;
    var statesChanged = false;
    var states = const <SkillStateRow>[];
    Snapshot? lastSnapshot;
    var items = const <KnowledgeItem>[];
    SkillLibrary? emitted;

    Future<void> refresh({bool force = false}) async {
      if (closed) return;
      rescanForced |= force;
      if (running) {
        rescan = true;
        return;
      }
      running = true;
      try {
        do {
          rescan = false;
          final forced = rescanForced;
          rescanForced = false;
          final user = await snapshotRoot(_userRoot);
          final project = root == null ? <String, String>{} : await snapshotRoot(root);
          if (closed) return;
          final snapshot = {...user, ...project};
          if (forced || !mapEquals(lastSnapshot, snapshot)) {
            lastSnapshot = snapshot;
            items = [
              ...builtinItems(await _builtin.load()),
              ...await itemsFromSnapshot(root: _userRoot, source: SkillSource.user, snapshot: user),
              if (root != null)
                ...await itemsFromSnapshot(
                  root: root,
                  source: SkillSource.project,
                  snapshot: project,
                ),
            ];
            statesChanged = true;
          }
          if (closed || !statesChanged) continue;
          statesChanged = false;
          final library = applySkillStates(sortKnowledge(items), states, projectId);
          if (library != emitted) controller.add(emitted = library);
        } while (rescan && !closed);
      } on Object catch (error, stackTrace) {
        // The next poll tries again; a broken folder must not end the stream.
        if (!closed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller
      ..onListen = () {
        _watchers.add(refresh);
        unawaited(
          () async {
            states = await _database.select(_database.skillStatesTable).get();
            if (closed) return;
            await refresh(force: true);
            if (closed) return;
            statesSubscription = _database.select(_database.skillStatesTable).watch().listen((
              rows,
            ) {
              if (listEquals(rows, states)) return;
              states = rows;
              statesChanged = true;
              unawaited(refresh());
            });
            timer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
          }().onError<Object>((error, stackTrace) {
            if (!closed) controller.addError(error, stackTrace);
          }),
        );
      }
      ..onCancel = () async {
        closed = true;
        _watchers.remove(refresh);
        timer?.cancel();
        await statesSubscription?.cancel();
        await controller.close();
      };
    return controller.stream;
  }

  void _filesChanged() {
    for (final refresh in _watchers.toList()) {
      unawaited(refresh(force: true));
    }
  }

  // --- Reading and writing ---

  ({KnowledgeKind kind, SkillSource source, String name}) _parse(String id) {
    final parts = id.split(':');
    final kind = KnowledgeKind.values.asNameMap()[parts.first];
    final source = parts.length > 2 ? SkillSource.values.asNameMap()[parts[1]] : null;
    final name = parts.skip(2).join(':');
    if (kind == null ||
        source == null ||
        name.isEmpty ||
        p.basename(name) != name ||
        name.startsWith('.')) {
      throw KnowledgeNotFoundException(id);
    }
    return (kind: kind, source: source, name: name);
  }

  String _rootOf(SkillSource source, String id, String? projectRoot) => switch (source) {
    SkillSource.user => _userRoot,
    SkillSource.project when projectRoot != null => p.join(projectRoot, '.claude'),
    _ => throw KnowledgeNotFoundException(id),
  };

  /// The skill folder or the rule file of an item that lives on disk; a project item needs the
  /// [projectRoot] of its project.
  String _pathOf(String id, {String? projectRoot}) {
    final (:kind, :source, :name) = _parse(id);
    final root = _rootOf(source, id, projectRoot);
    return kind == KnowledgeKind.skill
        ? p.join(root, 'skills', name)
        : p.join(root, 'rules', '$name.md');
  }

  String _mainFile(KnowledgeKind kind, String path) =>
      kind == KnowledgeKind.skill ? p.join(path, skillFileName) : path;

  @override
  Future<String> read(String id, {String? projectRoot}) async {
    final (:kind, :source, :name) = _parse(id);
    if (source == SkillSource.builtin) {
      final key = kind == KnowledgeKind.skill ? 'skills/$name/$skillFileName' : 'rules/$name.md';
      return (await _builtin.load())[key] ?? (throw KnowledgeNotFoundException(id));
    }
    try {
      return await File(_mainFile(kind, _pathOf(id, projectRoot: projectRoot))).readAsString();
    } on PathNotFoundException {
      throw KnowledgeNotFoundException(id);
    }
  }

  @override
  Future<void> write(String id, String text, {String? projectRoot, String? expected}) async {
    final (:kind, :source, name: _) = _parse(id);
    if (source == SkillSource.builtin) throw ReadOnlyKnowledgeException(id);
    final path = _mainFile(kind, _pathOf(id, projectRoot: projectRoot));
    // A link is followed, so the file it points to is the one that gets replaced.
    final String target;
    try {
      target = await File(path).resolveSymbolicLinks();
    } on PathNotFoundException {
      throw KnowledgeNotFoundException(id);
    }
    if (expected != null) {
      final String current;
      try {
        current = await File(target).readAsString();
      } on PathNotFoundException {
        throw KnowledgeNotFoundException(id);
      }
      if (current != expected) throw KnowledgeConflictException(id);
    }
    await _replaceFile(target, text);
    _filesChanged();
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

  // --- Enablement ---

  @override
  Future<void> setEnabled(String id, {required bool enabled, int? projectId}) {
    // Ids carry no project, so a global row would apply to every project that has the same name.
    if (projectId == null && _parse(id).source == SkillSource.project) {
      throw ArgumentError.value(
        id,
        'id',
        'A project item can only be turned on or off per project',
      );
    }
    return setSkillEnabled(_database, id, enabled: enabled, projectId: projectId);
  }

  @override
  Future<void> clearException(String id, int projectId) =>
      clearSkillException(_database, id, projectId);

  // --- Creating ---

  Future<bool> _taken(KnowledgeKind kind, String name) async {
    final path = kind == KnowledgeKind.skill
        ? p.join(_userRoot, 'skills', name)
        : p.join(_userRoot, 'rules', '$name.md');
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  @override
  Future<String> create(KnowledgeKind kind, String name) async {
    if (!_validName.hasMatch(name)) throw InvalidKnowledgeNameException(name);
    final id = '${kind.name}:${SkillSource.user.name}:$name';
    if (await _taken(kind, name)) throw KnowledgeExistsException(id);
    final file = File(_mainFile(kind, _pathOf(id)));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      writeFrontmatter({
        'name': name,
        'description': kind == KnowledgeKind.skill ? _skillPlaceholder : _rulePlaceholder,
      }, '# $name\n'),
    );
    _filesChanged();
    return id;
  }

  @override
  Future<String> duplicate(String id, {String? projectRoot}) async {
    final (:kind, :source, :name) = _parse(id);
    final copyName = await freeName(name, (candidate) => _taken(kind, candidate));
    final copyId = '${kind.name}:${SkillSource.user.name}:$copyName';
    final target = _pathOf(copyId);

    try {
      if (source == SkillSource.builtin) {
        final prefix = kind == KnowledgeKind.skill ? 'skills/$name/' : 'rules/$name.md';
        final files = {...await _builtin.load()}..removeWhere((key, _) => !key.startsWith(prefix));
        if (files.isEmpty) throw KnowledgeNotFoundException(id);
        for (final MapEntry(:key, :value) in files.entries) {
          final file = File(
            kind == KnowledgeKind.skill
                ? p.joinAll([target, ...p.posix.split(key.substring(prefix.length))])
                : target,
          );
          await file.parent.create(recursive: true);
          await file.writeAsString(value);
        }
      } else {
        final from = _pathOf(id, projectRoot: projectRoot);
        if (kind == KnowledgeKind.skill) {
          if (!Directory(from).existsSync()) throw KnowledgeNotFoundException(id);
          await copyDirectory(Directory(from), Directory(target));
        } else {
          if (!File(from).existsSync()) throw KnowledgeNotFoundException(id);
          await Directory(p.dirname(target)).create(recursive: true);
          await File(from).copy(target);
        }
      }
      await _renameCopy(kind, target, from: name, to: copyName);
    } on Object {
      await _removeCopy(kind, target);
      rethrow;
    }
    _filesChanged();
    return copyId;
  }

  @override
  Future<String> importFolder(String path) async {
    final folder = Directory(path);
    final name = p.basename(folder.path);
    if (name.startsWith('.')) throw InvalidKnowledgeNameException(name);
    // The scanner wants exactly `SKILL.md`, which a case-insensitive `existsSync` would not check.
    final hasSkillFile = await _hasEntry(folder, skillFileName);
    if (!hasSkillFile) throw InvalidKnowledgeException('$path has no $skillFileName');
    final copyName = await freeName(name, (candidate) => _taken(KnowledgeKind.skill, candidate));
    final copyId = 'skill:${SkillSource.user.name}:$copyName';
    final target = _pathOf(copyId);
    try {
      await copyDirectory(folder, Directory(target));
      await _renameCopy(KnowledgeKind.skill, target, from: name, to: copyName);
    } on Object {
      await _removeCopy(KnowledgeKind.skill, target);
      rethrow;
    }
    _filesChanged();
    return copyId;
  }

  /// Whether [folder] lists an entry that is named exactly [name].
  Future<bool> _hasEntry(Directory folder, String name) async {
    try {
      return await folder.list().any((entity) => p.basename(entity.path) == name);
    } on FileSystemException {
      return false;
    }
  }

  /// Deletes what a failed copy left at [path]; the failure being handled is the one that counts.
  Future<void> _removeCopy(KnowledgeKind kind, String path) async {
    try {
      if (kind == KnowledgeKind.skill) {
        final directory = Directory(path);
        if (directory.existsSync()) await directory.delete(recursive: true);
      } else {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      }
    } on FileSystemException {
      // Nothing more can be done; the original error is rethrown by the caller.
    }
  }

  /// Gives a copy that got another name the same `name` in its frontmatter.
  Future<void> _renameCopy(
    KnowledgeKind kind,
    String path, {
    required String from,
    required String to,
  }) async {
    if (from == to) return;
    final file = File(_mainFile(kind, path));
    await file.writeAsString(renameFrontmatterName(await file.readAsString(), to));
  }
}
