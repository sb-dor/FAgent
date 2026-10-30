import 'dart:async';

import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/data/knowledge_copy.dart';
import 'package:flutter_code_agent/src/feature/skills/data/knowledge_scanner.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skill_states.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';

final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// A built-in skill item for tests; [id] is `skill:builtin:<name>`.
KnowledgeItem memorySkill(
  String name, {
  SkillSource source = SkillSource.builtin,
  String description = '',
}) => _item(KnowledgeKind.skill, name, source, description);

/// A rule item for tests; [id] is `rule:<source>:<name>`.
KnowledgeItem memoryRule(
  String name, {
  SkillSource source = SkillSource.builtin,
  String description = '',
}) => _item(KnowledgeKind.rule, name, source, description);

KnowledgeItem _item(KnowledgeKind kind, String name, SkillSource source, String description) =>
    KnowledgeItem(
      id: '${kind.name}:${source.name}:$name',
      kind: kind,
      source: source,
      name: name,
      title: name,
      description: description,
      path: kind == KnowledgeKind.skill ? '/memory/$name' : '/memory/$name.md',
      files: kind == KnowledgeKind.skill ? const ['SKILL.md'] : const [],
      readOnly: source == SkillSource.builtin,
    );

/// [ISkillsRepository] that keeps everything in memory, for tests.
///
/// It follows the real repository: enablement is a global value plus per-project exceptions (a
/// project row equal to the global value is dropped, a `project` item refuses a global switch),
/// the same exceptions are thrown, and every change emits a new library to the watchers. It uses no
/// timers.
final class MemorySkillsRepository implements ISkillsRepository {
  /// Creates the repository.
  ///
  /// [items] are the built-in and user items, [projectItems] the items of a project folder by its
  /// root, [texts] the file text by item id and [importable] the texts of the folders
  /// [importFolder] accepts, by path.
  MemorySkillsRepository({
    List<KnowledgeItem> items = const [],
    Map<String, List<KnowledgeItem>> projectItems = const {},
    Map<String, String> texts = const {},
    Map<String, String> importable = const {},
  }) : _items = [...items],
       _projectItems = {
         for (final e in projectItems.entries) e.key: [...e.value],
       },
       _texts = {...texts},
       _importable = {...importable};

  final List<KnowledgeItem> _items;
  final Map<String, List<KnowledgeItem>> _projectItems;
  final Map<String, String> _texts;
  final Map<String, String> _importable;
  final Map<String, bool> _global = {};
  final Map<String, Map<int, bool>> _perProject = {};
  final Set<_Watcher> _watchers = {};

  /// The calls made so far, for example `setEnabled skill:builtin:a false project=1`.
  final List<String> calls = [];

  /// How many [watch] streams were cancelled.
  int cancels = 0;

  /// How many [watch] streams are listened to.
  int get activeWatchers => _watchers.length;

  /// Makes every active watcher fail with [error]; the next change emits a library again.
  void addWatchError(Object error) {
    for (final watcher in _watchers.toList()) {
      watcher.controller.addError(error);
    }
  }

  /// Adds [item] (with [text] as its file) among the built-in and user items and emits.
  void add(KnowledgeItem item, {String text = ''}) {
    _items.add(item);
    _texts[item.id] = text;
    _emit();
  }

  List<SkillStateRow> get _rows {
    var id = 0;
    return [
      for (final MapEntry(:key, :value) in _global.entries)
        SkillStateRow(id: id++, skillId: key, enabled: value),
      for (final MapEntry(:key, :value) in _perProject.entries)
        for (final MapEntry(key: project, value: enabled) in value.entries)
          SkillStateRow(id: id++, skillId: key, projectId: project, enabled: enabled),
    ];
  }

  SkillLibrary _libraryOf(_Watcher watcher) => applySkillStates(
    sortKnowledge([..._items, ...?_projectItems[watcher.projectRoot]]),
    _rows,
    watcher.projectId,
  );

  void _emit() {
    for (final watcher in _watchers.toList()) {
      watcher.controller.add(_libraryOf(watcher));
    }
  }

  @override
  Stream<SkillLibrary> watch({int? projectId, String? projectRoot}) {
    calls.add('watch project=$projectId root=$projectRoot');
    final watcher = _Watcher(projectId, projectRoot);
    watcher.controller
      ..onListen = () {
        _watchers.add(watcher);
        watcher.controller.add(_libraryOf(watcher));
      }
      ..onCancel = () {
        _watchers.remove(watcher);
        cancels++;
        return watcher.controller.close();
      };
    return watcher.controller.stream;
  }

  ({KnowledgeKind kind, SkillSource source, String name}) _parse(String id) {
    final parts = id.split(':');
    final kind = KnowledgeKind.values.asNameMap()[parts.first];
    final source = parts.length > 2 ? SkillSource.values.asNameMap()[parts[1]] : null;
    final name = parts.skip(2).join(':');
    if (kind == null || source == null || name.isEmpty) throw KnowledgeNotFoundException(id);
    return (kind: kind, source: source, name: name);
  }

  KnowledgeItem _find(String id, String? projectRoot) {
    final source = _parse(id).source;
    final pool = source == SkillSource.project
        ? _projectItems[projectRoot] ?? const <KnowledgeItem>[]
        : _items;
    return pool.firstWhere(
      (item) => item.id == id,
      orElse: () => throw KnowledgeNotFoundException(id),
    );
  }

  @override
  Future<String> read(String id, {String? projectRoot}) async {
    calls.add('read $id');
    _find(id, projectRoot);
    return _texts[id] ?? (throw KnowledgeNotFoundException(id));
  }

  @override
  Future<void> write(String id, String text, {String? projectRoot}) async {
    calls.add('write $id');
    if (_parse(id).source == SkillSource.builtin) throw ReadOnlyKnowledgeException(id);
    _find(id, projectRoot);
    _texts[id] = text;
    _emit();
  }

  @override
  Future<void> setEnabled(String id, {required bool enabled, int? projectId}) async {
    calls.add('setEnabled $id $enabled project=$projectId');
    if (projectId == null && _parse(id).source == SkillSource.project) {
      throw ArgumentError.value(
        id,
        'id',
        'A project item can only be turned on or off per project',
      );
    }
    if (projectId == null) {
      _global[id] = enabled;
      _perProject[id]?.removeWhere((_, value) => value == enabled);
    } else if (enabled == (_global[id] ?? true)) {
      _perProject[id]?.remove(projectId);
    } else {
      (_perProject[id] ??= {})[projectId] = enabled;
    }
    _emit();
  }

  @override
  Future<void> clearException(String id, int projectId) async {
    calls.add('clearException $id project=$projectId');
    _perProject[id]?.remove(projectId);
    _emit();
  }

  bool _taken(KnowledgeKind kind, String name) =>
      _items.any((item) => item.id == '${kind.name}:${SkillSource.user.name}:$name');

  String _addUser(KnowledgeKind kind, String name, String text) {
    final item = _item(kind, name, SkillSource.user, '');
    _items.add(item);
    _texts[item.id] = text;
    _emit();
    return item.id;
  }

  @override
  Future<String> create(KnowledgeKind kind, String name) async {
    calls.add('create ${kind.name} $name');
    if (!_validName.hasMatch(name)) throw InvalidKnowledgeNameException(name);
    final id = '${kind.name}:${SkillSource.user.name}:$name';
    if (_taken(kind, name)) throw KnowledgeExistsException(id);
    return _addUser(kind, name, '---\nname: $name\ndescription: \n---\n# $name\n');
  }

  @override
  Future<String> duplicate(String id, {String? projectRoot}) async {
    calls.add('duplicate $id');
    final (:kind, source: _, :name) = _parse(id);
    final original = _find(id, projectRoot);
    final text = _texts[id] ?? '';
    final copyName = await freeName(name, (candidate) async => _taken(kind, candidate));
    final copy = _addUser(kind, copyName, renameFrontmatterName(text, copyName));
    final index = _items.indexWhere((item) => item.id == copy);
    _items[index] = _items[index].copyWith(description: original.description);
    _emit();
    return copy;
  }

  @override
  Future<String> importFolder(String path) async {
    calls.add('importFolder $path');
    final name = path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
    if (name.startsWith('.')) throw InvalidKnowledgeNameException(name);
    final text = _importable[path];
    if (text == null) throw InvalidKnowledgeException('$path has no SKILL.md');
    final copyName = await freeName(
      name,
      (candidate) async => _taken(KnowledgeKind.skill, candidate),
    );
    return _addUser(KnowledgeKind.skill, copyName, renameFrontmatterName(text, copyName));
  }
}

final class _Watcher {
  _Watcher(this.projectId, this.projectRoot);

  final int? projectId;
  final String? projectRoot;
  // Closed by the `onCancel` that `watch` sets.
  // ignore: close_sinks
  final StreamController<SkillLibrary> controller = StreamController<SkillLibrary>();
}
