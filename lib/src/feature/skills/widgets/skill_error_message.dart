import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';

/// What to tell the user about [error] from an action on a skill or rule. Anything the user cannot
/// act on gets the general message.
String skillErrorMessage(GeneratedLocalization localization, Object error) => switch (error) {
  ReadOnlyKnowledgeException() => localization.skillErrorReadOnly,
  KnowledgeNotFoundException() => localization.skillErrorNotFound,
  InvalidKnowledgeException() => localization.skillErrorInvalidFolder,
  InvalidKnowledgeNameException() => localization.skillNameInvalid,
  KnowledgeExistsException() => localization.skillNameTaken,
  _ => localization.somethingWentWrong,
};

/// What to tell the user about the [problem] of a skill or rule.
String skillProblemMessage(GeneratedLocalization localization, KnowledgeProblem problem) =>
    switch (problem) {
      KnowledgeProblem.noFrontmatter => localization.skillProblemNoFrontmatter,
      KnowledgeProblem.noDescription => localization.skillProblemNoDescription,
      KnowledgeProblem.badYaml => localization.skillProblemBadYaml,
      KnowledgeProblem.unreadable => localization.skillProblemUnreadable,
      KnowledgeProblem.notUtf8 => localization.skillProblemNotUtf8,
    };
