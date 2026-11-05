import 'package:meta/meta.dart';

/// {@template project_rule}
/// A built-in rule the app can write into a project's `docs/rules`: its library [id], file [name],
/// one-line [description], and whether it is on ([enabled]: written into new projects and checked
/// in the offer by default).
/// {@endtemplate}
@immutable
final class ProjectRule {
  /// {@macro project_rule}
  const ProjectRule({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
  });

  /// `KnowledgeItem.id`, for reading its text.
  final String id;

  /// File name without `.md`.
  final String name;

  /// What the rule is about, one line.
  final String description;

  /// Whether the rule is on.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is ProjectRule &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, name, description, enabled);

  @override
  String toString() => 'ProjectRule($name)';
}
