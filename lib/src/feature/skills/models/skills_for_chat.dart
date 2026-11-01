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

/// Whether the app serves [skill] to the agent (`list_skills`, `load_skill`): the built-in and the
/// user's skills. The project's own skills (`.claude/skills`) are the agent's to read.
bool servedByApp(KnowledgeItem skill) =>
    skill.source == SkillSource.builtin || skill.source == SkillSource.user;

/// The skills of [skillsForChat] that the app serves ([servedByApp]): what `list_skills` lists and
/// the rules prompt names.
List<KnowledgeItem> appSkillsForChat(SkillLibrary library, Map<String, bool> chatStates) =>
    skillsForChat(library, chatStates).where(servedByApp).toList();
