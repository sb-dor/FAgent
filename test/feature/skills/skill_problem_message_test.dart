import 'dart:io';

import 'package:flutter_code_agent/src/common/localization/error_text.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization_en.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization_ru.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every problem has its own text in English and Russian', () {
    final english = GeneratedLocalizationEn();
    final russian = GeneratedLocalizationRu();

    final en = {for (final p in KnowledgeProblem.values) skillProblemMessage(english, p)};
    final ru = {for (final p in KnowledgeProblem.values) skillProblemMessage(russian, p)};

    expect(en, hasLength(KnowledgeProblem.values.length));
    expect(ru, hasLength(KnowledgeProblem.values.length));
    expect(en.intersection(ru), isEmpty);
  });

  test('an error that is not about the skill gets its own sentence, not the general one', () {
    final english = GeneratedLocalizationEn();
    const error = FileSystemException('Cannot write', '/p/SKILL.md', OSError('Disk full', 28));

    final text = skillErrorMessage(english, error);

    expect(text, isNot(english.somethingWentWrong));
    expect(text, errorText(english, error));
    expect(text, contains('/p/SKILL.md'));
  });
}
