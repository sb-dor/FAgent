import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_list_tile.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const KnowledgeItem _agents = KnowledgeItem(
  id: agentsRuleId,
  kind: KnowledgeKind.rule,
  source: SkillSource.project,
  name: 'AGENTS',
  title: 'AGENTS',
  description: '',
  path: '/work/app/AGENTS.md',
  readOnly: true,
);

const KnowledgeItem _plain = KnowledgeItem(
  id: 'rule:project:style',
  kind: KnowledgeKind.rule,
  source: SkillSource.project,
  name: 'style',
  title: 'style',
  description: 'Code style',
  path: '/work/app/.claude/rules/style.md',
);

Widget _tile(KnowledgeItem item) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: const <LocalizationsDelegate<Object?>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    Localization.delegate,
  ],
  supportedLocales: Localization.supportedLocales,
  home: Scaffold(
    body: SkillListTile(item: item, selected: false, onTap: () {}, onToggle: (_) {}),
  ),
);

void main() {
  testWidgets('the AGENTS.md rule has the project tag and no switch', (tester) async {
    await tester.pumpWidget(_tile(_agents));

    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('project'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('another project rule has a switch', (tester) async {
    await tester.pumpWidget(_tile(_plain));

    expect(find.byType(Switch), findsOneWidget);
  });
}
