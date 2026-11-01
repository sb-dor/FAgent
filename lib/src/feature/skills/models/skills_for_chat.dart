import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';

/// The skills a chat works with: the ones that are on for its project, minus the ones the chat
/// turned off ([chatStates], by [KnowledgeItem.id]; see `IChatSkillsRepository`).
///
/// A chat's `true` for a skill its project has off does not bring the skill in: the choice is
/// among the project's skills. Rules are not skills and never appear.
List<KnowledgeItem> skillsForChat(SkillLibrary library, Map<String, bool> chatStates) => [
  for (final skill in library.skills)
    if (skill.enabled && (chatStates[skill.id] ?? true)) skill,
];
