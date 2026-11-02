import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_list_tile.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_scope.dart';
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

const KnowledgeItem _projectSkill = KnowledgeItem(
  id: 'skill:project:deploy',
  kind: KnowledgeKind.skill,
  source: SkillSource.project,
  name: 'deploy',
  title: 'deploy',
  description: 'Deploys the app',
  path: '/work/app/.claude/skills/deploy',
);

const String _claudeNote = 'Claude reads this rule from .claude/rules';

Widget _tile(KnowledgeItem item, {Locale locale = const Locale('en')}) =>
    _app(SkillListTile(item: item, selected: false, onTap: () {}, onToggle: (_) {}), locale);

Widget _app(Widget child, Locale locale) => MaterialApp(
  locale: locale,
  theme: AppTheme.light(),
  localizationsDelegates: const <LocalizationsDelegate<Object?>>[
    ...GlobalMaterialLocalizations.delegates,
    Localization.delegate,
  ],
  supportedLocales: Localization.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the AGENTS.md rule has the project tag and no switch', (tester) async {
    await tester.pumpWidget(_tile(_agents));

    expect(find.text('AGENTS'), findsOneWidget);
    expect(find.text('project'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('another project rule has no switch but says Claude reads it', (tester) async {
    await tester.pumpWidget(_tile(_plain));

    expect(find.byType(Switch), findsNothing);
    expect(find.text(_claudeNote), findsOneWidget);
  });

  testWidgets('the note is in Russian too', (tester) async {
    await tester.pumpWidget(_tile(_plain, locale: const Locale('ru')));
    await tester.pumpAndSettle();

    expect(find.text('Claude читает это правило из .claude/rules'), findsOneWidget);
  });

  testWidgets('a project skill keeps its switch and has no note', (tester) async {
    await tester.pumpWidget(_tile(_projectSkill));

    expect(find.byType(Switch), findsOneWidget);
    expect(find.text(_claudeNote), findsNothing);
  });

  testWidgets('the card scope of a project rule is the note, without a switch', (tester) async {
    await tester.pumpWidget(_app(const SkillScope(item: _plain), const Locale('en')));

    expect(find.byType(Switch), findsNothing);
    expect(find.text(_claudeNote), findsOneWidget);
  });
}
