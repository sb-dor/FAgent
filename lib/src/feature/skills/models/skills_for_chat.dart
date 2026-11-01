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

/// The skills of [skillsForChat] that the app serves ([servedByApp]), a name possibly twice.
List<KnowledgeItem> appSkillsForChat(SkillLibrary library, Map<String, bool> chatStates) =>
    skillsForChat(library, chatStates).where(servedByApp).toList();

/// The skills of [appSkillsForChat], one per name: what `list_skills` lists, `load_skill` and
/// `read_skill_file` serve and the rules prompt names.
///
/// "Duplicate" on a built-in skill makes a user skill of the same name; of the two, the user's
/// wins (as in `ChatSkills.byName`), and the built-in one is there only while the user's is off.
/// Each name keeps the place where it first appears.
List<KnowledgeItem> appSkillsByName(SkillLibrary library, Map<String, bool> chatStates) {
  final byName = <String, KnowledgeItem>{};
  for (final skill in appSkillsForChat(library, chatStates)) {
    // Replacing the value of a key keeps its place in the map.
    if (!byName.containsKey(skill.name) || skill.source == SkillSource.user) {
      byName[skill.name] = skill;
    }
  }
  return byName.values.toList();
}
