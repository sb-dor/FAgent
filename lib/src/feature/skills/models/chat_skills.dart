import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';

/// One skill as the chat sees it.
@immutable
final class ChatSkill {
  /// Creates a skill.
  const ChatSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.enabled,
    required this.invocable,
  });

  /// The id of the [KnowledgeItem] it comes from.
  final String id;

  /// The folder name; what `/name` and the agent's `Load skill: name` say.
  final String name;

  /// What the skill is for; empty when it says nothing.
  final String description;

  /// Where the skill comes from.
  final SkillSource source;

  /// Whether the skill is on for the chat's project.
  final bool enabled;

  /// Whether the user can run the skill as a `/name` command.
  final bool invocable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSkill &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.source == source &&
          other.enabled == enabled &&
          other.invocable == invocable;

  @override
  int get hashCode => Object.hash(id, name, description, source, enabled, invocable);
}

/// The skills of a chat's project: what the 🧩 chip, the `/` menu and the skill lines of the feed
/// show. Plain data, so the chat does not depend on the library. Equal skills are equal, so a
/// library that emits the same content again does not rebuild the composer.
@immutable
final class ChatSkills {
  /// Creates the skills of the project [projectName].
  const ChatSkills({required this.projectName, required this.skills});

  /// The skills of [library] for the project [projectName], project skills first (then mine, then
  /// the built-in ones; of one source by name). Rules are not skills.
  factory ChatSkills.of(SkillLibrary library, {required String projectName}) {
    // The sort is stable, so the library's order by name stays inside a source.
    final skills = <ChatSkill>[
      for (final item in library.skills)
        ChatSkill(
          id: item.id,
          name: item.name,
          description: item.description,
          source: item.source,
          enabled: item.enabled,
          invocable: item.invocable,
        ),
    ]..sort((a, b) => _rank(a.source).compareTo(_rank(b.source)));
    return ChatSkills(projectName: projectName, skills: List<ChatSkill>.unmodifiable(skills));
  }

  /// Nothing is known: the project or its library is not loaded. The chip is not shown.
  static const ChatSkills empty = ChatSkills(projectName: null, skills: <ChatSkill>[]);

  /// The name of the chat's project; `null` while it is not known.
  final String? projectName;

  /// Every skill found for the project, enabled or not, project skills first.
  final List<ChatSkill> skills;

  /// How many skills are on for the project.
  int get enabledCount => skills.where((skill) => skill.enabled).length;

  /// The skill called [name]: of several, the project's, else mine, else a built-in one. `null`
  /// when there is none.
  ChatSkill? byName(String name) {
    ChatSkill? best;
    for (final skill in skills) {
      if (skill.name != name) continue;
      if (best == null || _rank(skill.source) < _rank(best.source)) best = skill;
    }
    return best;
  }

  static int _rank(SkillSource source) => switch (source) {
    SkillSource.project => 0,
    SkillSource.user => 1,
    SkillSource.builtin => 2,
    SkillSource.git => 3,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSkills && other.projectName == projectName && listEquals(other.skills, skills);

  @override
  int get hashCode => Object.hash(projectName, Object.hashAll(skills));
}
