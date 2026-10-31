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
}
