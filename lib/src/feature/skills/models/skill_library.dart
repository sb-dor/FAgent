import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'skill_library.freezed.dart';

/// Every skill and rule found for a project.
///
/// Each list is ordered by source (in the order of [SkillSource]), then by [KnowledgeItem.name].
@freezed
abstract class SkillLibrary with _$SkillLibrary {
  /// Creates a library.
  const factory SkillLibrary({
    @Default(<KnowledgeItem>[]) List<KnowledgeItem> skills,
    @Default(<KnowledgeItem>[]) List<KnowledgeItem> rules,
  }) = _SkillLibrary;

  const SkillLibrary._();

  /// A library without items.
  static const SkillLibrary empty = SkillLibrary();

  /// The item with this [KnowledgeItem.id]; `null` when there is none.
  KnowledgeItem? byId(String id) {
    for (final item in [...skills, ...rules]) {
      if (item.id == id) return item;
    }
    return null;
  }
}
