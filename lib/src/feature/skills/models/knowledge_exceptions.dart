/// A built-in skill or rule cannot be changed.
final class ReadOnlyKnowledgeException implements Exception {
  /// Creates the exception for the item [id].
  const ReadOnlyKnowledgeException(this.id);

  /// The `KnowledgeItem.id` that was written to.
  final String id;

  @override
  String toString() => 'ReadOnlyKnowledgeException: $id is read-only';
}

/// A name does not match `^[a-z0-9][a-z0-9-]{0,63}$`.
final class InvalidKnowledgeNameException implements Exception {
  /// Creates the exception for [name].
  const InvalidKnowledgeNameException(this.name);

  /// The rejected name.
  final String name;

  @override
  String toString() => 'InvalidKnowledgeNameException: "$name" is not a valid name';
}

/// A skill or rule with this name already exists.
final class KnowledgeExistsException implements Exception {
  /// Creates the exception for the item [id].
  const KnowledgeExistsException(this.id);

  /// The `KnowledgeItem.id` that is taken.
  final String id;

  @override
  String toString() => 'KnowledgeExistsException: $id already exists';
}

/// There is no skill or rule with this id (or no folder to look for it in).
final class KnowledgeNotFoundException implements Exception {
  /// Creates the exception for the item [id].
  const KnowledgeNotFoundException(this.id);

  /// The `KnowledgeItem.id` that was not found.
  final String id;

  @override
  String toString() => 'KnowledgeNotFoundException: $id not found';
}

/// A folder cannot be used as a skill, for example because it has no `SKILL.md`.
final class InvalidKnowledgeException implements Exception {
  /// Creates the exception.
  const InvalidKnowledgeException(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => 'InvalidKnowledgeException: $message';
}
