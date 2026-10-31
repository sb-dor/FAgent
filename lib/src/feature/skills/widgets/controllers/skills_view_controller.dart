import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';

/// What the Skills screen shows: the section, the source filter, the search, the open item and the
/// project the screen is about.
class SkillsViewController with ChangeNotifier {
  /// Creates the view on the [kind] section, for [projectId] (`null` for no project).
  SkillsViewController({this._kind = KnowledgeKind.skill, this._projectId});

  KnowledgeKind _kind;
  SkillSource? _source;
  String _query = '';
  String? _selectedId;
  int? _projectId;

  /// The open section.
  KnowledgeKind get kind => _kind;

  /// Shows only the items of this source; `null` shows every source.
  SkillSource? get source => _source;

  /// Text the list is searched for.
  String get query => _query;

  /// The id of the open item; `null` when none is open.
  String? get selectedId => _selectedId;

  /// The project whose enablement the screen shows and changes; `null` is the global one.
  int? get projectId => _projectId;

  /// The section of the item with [id].
  static KnowledgeKind kindOf(String id) =>
      id.startsWith('${KnowledgeKind.rule.name}:') ? KnowledgeKind.rule : KnowledgeKind.skill;

  /// The items of the open section, from every source.
  List<KnowledgeItem> sectionItems(SkillLibrary library) =>
      _kind == KnowledgeKind.skill ? library.skills : library.rules;

  /// How many items of the open section come from [source].
  int countOf(SkillLibrary library, SkillSource source) =>
      sectionItems(library).where((item) => item.source == source).length;

  /// The items of the open section that pass the source filter and the search.
  List<KnowledgeItem> visibleItems(SkillLibrary library) {
    final query = _query.trim().toLowerCase();
    bool matches(KnowledgeItem item) =>
        query.isEmpty ||
        item.title.toLowerCase().contains(query) ||
        item.name.toLowerCase().contains(query) ||
        item.description.toLowerCase().contains(query);
    return [
      for (final item in sectionItems(library))
        if ((_source == null || item.source == _source) && matches(item)) item,
    ];
  }

  /// Opens the item [id]; `null` closes it.
  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Shows the item [id] whatever the filter and the search say: its section, every source, no
  /// search.
  void reveal(String id) {
    _kind = kindOf(id);
    _source = null;
    _query = '';
    _selectedId = id;
    notifyListeners();
  }

  /// Opens a section; the source filter is cleared, and so is the open item if it belongs to the
  /// other section.
  void setKind(KnowledgeKind kind) {
    if (_kind == kind && _source == null) return;
    if (_kind != kind) _selectedId = null;
    _kind = kind;
    _source = null;
    notifyListeners();
  }

  /// Filters the list by [source]; `null` shows every source.
  void setSource(SkillSource? source) {
    if (_source == source) return;
    _source = source;
    notifyListeners();
  }

  /// Searches the list for [query].
  void setQuery(String query) {
    if (_query == query) return;
    _query = query;
    notifyListeners();
  }

  /// Makes [projectId] the project of the screen (`null` for none). The project source filter and
  /// the open project item belong to the old project, so they are dropped.
  void setProject(int? projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    if (_source == SkillSource.project) _source = null;
    if (_selectedId?.contains(':${SkillSource.project.name}:') ?? false) _selectedId = null;
    notifyListeners();
  }
}
