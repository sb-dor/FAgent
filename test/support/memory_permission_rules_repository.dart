import 'package:flutter_code_agent/src/feature/permission_rules/data/permission_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/models/permission_rules_exceptions.dart';
import 'package:path/path.dart' as p;

/// [IPermissionRulesRepository] that keeps the rules in memory, for tests; it never touches the
/// file system.
///
/// [rules] are the saved rules by project root path. A root in [unreadable] fails like a broken
/// `settings.local.json`; a root in neither has no file.
final class MemoryPermissionRulesRepository implements IPermissionRulesRepository {
  /// Creates the repository.
  MemoryPermissionRulesRepository({
    Map<String, List<String>> rules = const <String, List<String>>{},
    Set<String> unreadable = const <String>{},
  }) : _rules = <String, List<String>>{
         for (final entry in rules.entries) entry.key: <String>[...entry.value],
       },
       _unreadable = <String>{...unreadable};

  final Map<String, List<String>> _rules;
  final Set<String> _unreadable;

  /// The removals made so far, as `<projectRoot>|<rule>`.
  final List<String> removed = <String>[];

  @override
  Future<List<String>> rules(String projectRoot) async {
    if (_unreadable.contains(projectRoot)) {
      throw PermissionRulesUnreadableException(
        p.join(projectRoot, '.claude', 'settings.local.json'),
      );
    }
    return <String>[...?_rules[projectRoot]];
  }

  @override
  Future<void> remove(String projectRoot, String rule) async {
    removed.add('$projectRoot|$rule');
    if (_unreadable.contains(projectRoot)) {
      throw PermissionRulesUnreadableException(
        p.join(projectRoot, '.claude', 'settings.local.json'),
      );
    }
    _rules[projectRoot]?.removeWhere((entry) => entry == rule);
  }
}
