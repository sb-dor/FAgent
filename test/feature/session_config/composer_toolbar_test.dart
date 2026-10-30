import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_roles.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/composer_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

const _mode = SelectConfigOption(
  id: 'mode',
  name: 'Mode',
  category: 'mode',
  currentValue: 'default',
  choices: <ConfigChoice>[
    ConfigChoice(value: 'default', name: 'Manual', description: 'Ask before changes'),
    ConfigChoice(value: 'acceptEdits', name: 'Accept edits'),
    ConfigChoice(value: 'plan', name: 'Plan'),
    ConfigChoice(value: 'auto', name: 'Auto'),
    ConfigChoice(value: 'bypassPermissions', name: 'Bypass permissions'),
  ],
);

const _model = SelectConfigOption(
  id: 'model',
  name: 'Model',
  category: 'model',
  currentValue: 'opusplan',
  choices: <ConfigChoice>[
    ConfigChoice(value: 'opus', name: 'Opus 5.5'),
    ConfigChoice(value: 'sonnet', name: 'Sonnet 5.5'),
    ConfigChoice(value: 'haiku', name: 'Haiku 5.5'),
  ],
);

const _effort = SelectConfigOption(
  id: 'effort',
  name: 'Effort',
  category: 'thought_level',
  currentValue: 'medium',
  choices: <ConfigChoice>[
    ConfigChoice(value: 'low', name: 'Low'),
    ConfigChoice(value: 'medium', name: 'Medium'),
    ConfigChoice(value: 'high', name: 'High'),
  ],
);

SelectConfigOption _withMode(String value) => SelectConfigOption(
  id: _mode.id,
  name: _mode.name,
  category: _mode.category,
  currentValue: value,
  choices: _mode.choices,
);

void main() {
  group('config roles', () {
    test('the model and effort are found by id or category', () {
      const byCategory = SelectConfigOption(
        id: 'm1',
        name: 'Brain',
        category: 'model',
        currentValue: 'a',
        choices: <ConfigChoice>[],
      );
      const byId = SelectConfigOption(
        id: 'effort',
        name: 'Effort',
        currentValue: 'a',
        choices: <ConfigChoice>[],
      );
      const byThoughtLevel = SelectConfigOption(
        id: 'think',
        name: 'Think',
        category: 'thought_level',
        currentValue: 'a',
        choices: <ConfigChoice>[],
      );

      expect(modelOption(const <ConfigOption>[_mode, byCategory]), byCategory);
      expect(modelOption(const <ConfigOption>[_model]), _model);
      expect(modelOption(const <ConfigOption>[_mode]), isNull);
      expect(effortOption(const <ConfigOption>[byId]), byId);
      expect(effortOption(const <ConfigOption>[byThoughtLevel]), byThoughtLevel);
      expect(effortOption(const <ConfigOption>[_model]), isNull);
    });

    test('the mode cycle skips bypass and wraps around', () {
      expect(cycleModes(_mode), <String>['default', 'acceptEdits', 'plan', 'auto']);
      expect(nextCycleMode(_withMode('default')), 'acceptEdits');
      expect(nextCycleMode(_withMode('auto')), 'default');
      // Leaving bypass goes to the start of the cycle.
      expect(nextCycleMode(_withMode('bypassPermissions')), 'default');
    });

    test('chat defaults hold model, effort and mode but never bypass', () {
      expect(defaultsOf(<ConfigOption>[_withMode('plan'), _model, _effort]), <String, String>{
        'mode': 'plan',
        'model': 'opusplan',
        'effort': 'medium',
      });
      expect(defaultsOf(<ConfigOption>[_withMode('bypassPermissions'), _model]), <String, String>{
        'model': 'opusplan',
      });
      expect(defaultsOf(const <ConfigOption>[]), isEmpty);
    });
  });

  group('ComposerToolbar', () {
    final changes = <(String, Object)>[];
    var attached = 0;
    var madeDefault = 0;
    late Dependencies dependencies;

    setUp(() {
      dependencies = testDependencies();
      addTearDown(dependencies.database.close);
      changes.clear();
      attached = 0;
      madeDefault = 0;
    });

    Widget toolbar({
      List<ConfigOption> options = const <ConfigOption>[_mode, _model, _effort],
      bool agentLocked = false,
      bool enabled = true,
    }) => testApp(
      dependencies: dependencies,
      ComposerToolbar(
        agentName: 'Claude Code',
        agentLocked: agentLocked,
        options: options,
        enabled: enabled,
        onChanged: (id, value) => changes.add((id, value)),
        onAttach: () => attached++,
        onMakeDefault: () => madeDefault++,
      ),
    );

    Color? chipBackground(WidgetTester tester, String label) {
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('the plus button attaches a file', (tester) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.byTooltip('Attach a file'));
      expect(attached, 1);
    });

    testWidgets('the agent menu marks the chat agent and lists the others as coming later', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.text('Claude Code'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Gemini CLI'), findsOneWidget);
      expect(find.text('Coming in M5'), findsNWidgets(2));

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();
      // Disabled rows do not close the menu or change anything.
      expect(find.text('Gemini CLI'), findsOneWidget);
      expect(changes, isEmpty);
    });

    testWidgets('after the first message the agent cannot be changed', (tester) async {
      await tester.pumpWidget(toolbar(agentLocked: true));
      await tester.tap(find.text('Claude Code'));
      await tester.pumpAndSettle();

      final claude = find.ancestor(
        of: find.text('Claude Code').last,
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(claude.first).opacity, lessThan(1));
    });

    testWidgets('the model chip shows a value the agent does not list', (tester) async {
      await tester.pumpWidget(toolbar());
      expect(find.text('opusplan'), findsOneWidget);

      await tester.tap(find.text('opusplan'));
      await tester.pumpAndSettle();
      expect(find.text('Sonnet 5.5'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);

      await tester.tap(find.text('Sonnet 5.5'));
      await tester.pumpAndSettle();
      expect(changes, <(String, Object)>[('model', 'sonnet')]);
    });

    testWidgets('picking the current model changes nothing', (tester) async {
      final sonnet = SelectConfigOption(
        id: _model.id,
        name: _model.name,
        category: _model.category,
        currentValue: 'sonnet',
        choices: _model.choices,
      );
      await tester.pumpWidget(toolbar(options: <ConfigOption>[_mode, sonnet]));
      await tester.tap(find.text('Sonnet 5.5'));
      await tester.pumpAndSettle();
      expect(find.text('Haiku 5.5'), findsOneWidget);

      await tester.tap(find.text('Sonnet 5.5').last);
      await tester.pumpAndSettle();
      expect(find.text('Haiku 5.5'), findsNothing);
      expect(changes, isEmpty);
    });

    testWidgets('the model list is searchable', (tester) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.text('opusplan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hai');
      await tester.pumpAndSettle();

      expect(find.text('Haiku 5.5'), findsOneWidget);
      expect(find.text('Opus 5.5'), findsNothing);
    });

    testWidgets('effort is picked in the model menu footer', (tester) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.text('opusplan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();

      expect(changes, <(String, Object)>[('effort', 'high')]);
      // The menu is closed.
      expect(find.text('Sonnet 5.5'), findsNothing);
    });

    testWidgets('make default asks to save the current settings and closes the menu', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.text('opusplan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make default for new chats'));
      await tester.pumpAndSettle();

      expect(madeDefault, 1);
      expect(changes, isEmpty);
      expect(find.text('Sonnet 5.5'), findsNothing);
    });

    testWidgets('without a model option there is no model chip and effort stays a plain chip', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar(options: <ConfigOption>[_mode, _effort]));
      expect(find.text('opusplan'), findsNothing);
      expect(find.text('Effort: Medium'), findsOneWidget);
    });

    testWidgets('the mode chip is coloured by risk', (tester) async {
      await tester.pumpWidget(toolbar(options: <ConfigOption>[_withMode('default')]));
      final colors = tester.element(find.text('Manual')).colors;
      expect(chipBackground(tester, 'Manual'), colors.surface);

      await tester.pumpWidget(toolbar(options: <ConfigOption>[_withMode('acceptEdits')]));
      expect(chipBackground(tester, 'Accept edits'), colors.warnSoft);

      await tester.pumpWidget(toolbar(options: <ConfigOption>[_withMode('auto')]));
      expect(chipBackground(tester, 'Auto'), colors.warnSoft);

      await tester.pumpWidget(toolbar(options: <ConfigOption>[_withMode('bypassPermissions')]));
      expect(chipBackground(tester, 'Bypass permissions'), colors.dangerSoft);
    });

    testWidgets('the mode menu shows the agent descriptions and changes without a dialog', (
      tester,
    ) async {
      await tester.pumpWidget(toolbar());
      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      expect(find.text('Ask before changes'), findsOneWidget);

      await tester.tap(find.text('Accept edits'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(changes, <(String, Object)>[('mode', 'acceptEdits')]);
    });

    testWidgets('choosing bypass still asks first', (tester) async {
      await tester.pumpWidget(toolbar());

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bypass permissions'));
      await tester.pumpAndSettle();
      expect(find.text('Allow bypassing permissions?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);

      await tester.tap(find.text('Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bypass permissions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow for this chat'));
      await tester.pumpAndSettle();
      expect(changes, <(String, Object)>[('mode', bypassPermissionMode)]);
    });

    testWidgets('other options keep their own chips', (tester) async {
      const boolean = BooleanConfigOption(id: 'thinking', name: 'Thinking', currentValue: false);
      const other = SelectConfigOption(
        id: 'agent',
        name: 'Agent',
        currentValue: 'default',
        choices: <ConfigChoice>[
          ConfigChoice(value: 'default', name: 'Default'),
          ConfigChoice(value: 'guide', name: 'Guide'),
        ],
      );
      const unknown = UnknownConfigOption(id: 'budget', name: 'Budget', type: 'number');
      await tester.pumpWidget(toolbar(options: <ConfigOption>[_mode, boolean, other, unknown]));

      await tester.tap(find.text('Thinking'));
      await tester.tap(find.text('Agent: Default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Budget'));
      await tester.pumpAndSettle();

      expect(changes, <(String, Object)>[('thinking', true), ('agent', 'guide')]);
    });

    testWidgets('without options the model and mode chips are disabled', (tester) async {
      await tester.pumpWidget(toolbar(options: const <ConfigOption>[]));

      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Mode'), findsOneWidget);
      await tester.tap(find.text('Model'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Available after the agent starts'), findsNWidgets(2));
      expect(find.byTooltip('Attach a file'), findsOneWidget);
    });

    testWidgets('inside the composer the chips wrap on a narrow window', (tester) async {
      tester.view
        ..physicalSize = const Size(420, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final text = TextEditingController();
      final focus = FocusNode();
      addTearDown(text.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        testApp(
          dependencies: dependencies,
          PromptComposer(
            controller: text,
            focusNode: focus,
            canSend: true,
            canStop: false,
            onSend: () {},
            onStop: () {},
            toolbar: <Widget>[
              ComposerToolbar(
                agentName: 'Claude Code',
                agentLocked: false,
                options: const <ConfigOption>[_mode, _model, _effort],
                enabled: true,
                onChanged: (_, _) {},
                onAttach: () {},
                onMakeDefault: () {},
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('opusplan'), findsOneWidget);
    });

    testWidgets('while the chat cannot change settings the menus stay closed', (tester) async {
      await tester.pumpWidget(toolbar(enabled: false));
      await tester.tap(find.text('opusplan'));
      await tester.pumpAndSettle();
      expect(find.text('Sonnet 5.5'), findsNothing);
    });
  });
}
