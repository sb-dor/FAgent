import 'package:freezed_annotation/freezed_annotation.dart';

part 'knowledge_item.freezed.dart';

/// What a [KnowledgeItem] is.
enum KnowledgeKind {
  /// A folder with a `SKILL.md` the agent loads on demand.
  skill,

  /// A single Markdown file the agent always follows.
  rule,
}

/// Where a [KnowledgeItem] comes from.
enum SkillSource {
  /// Ships with the app; read-only.
  builtin,

  /// The user's own folder, shared by every project.
  user,

  /// The project's own folder, for example `.claude/skills`.
  project,

  /// Installed from a git repository.
  git,
}

/// A skill or a rule shown on the Skills and rules screen.
@freezed
abstract class KnowledgeItem with _$KnowledgeItem {
  /// Creates an item.
  const factory KnowledgeItem({
    /// `<kind>:<source>:<name>`, for example `skill:builtin:feature-architecture`.
    required String id,
    required KnowledgeKind kind,
    required SkillSource source,

    /// The folder name of a skill or the file name of a rule without `.md`.
    required String name,

    /// The frontmatter `name`, or [name] when there is none.
    required String title,
    required String description,

    /// The frontmatter `when_to_use`; `null` when there is none.
    String? whenToUse,

    /// The frontmatter `version`; `null` when there is none.
    String? version,

    /// The absolute path of the skill folder or the rule file; the asset key for built-in items.
    required String path,

    /// Paths of the skill's files relative to [path], `SKILL.md` first; empty for rules.
    @Default(<String>[]) List<String> files,

    /// Whether the item cannot be edited or deleted.
    @Default(false) bool readOnly,

    /// What is wrong with the item (for example a broken frontmatter); `null` when it is fine.
    String? problem,

    /// Whether the item is on for the project being watched.
    @Default(true) bool enabled,

    /// Whether the item is on by default, for projects without an exception.
    @Default(true) bool enabledGlobally,

    /// Ids of the projects where [enabled] differs from [enabledGlobally].
    @Default(<int>{}) Set<int> exceptions,
  }) = _KnowledgeItem;

  const KnowledgeItem._();

  /// Whether the user can run the item as a `/<name>` command in a chat.
  bool get invocable => kind == KnowledgeKind.skill && source == SkillSource.project;
}
