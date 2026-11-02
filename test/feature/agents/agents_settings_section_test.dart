import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_agents_repository.dart';
import '../../support/test_app.dart';

final List<ConfigOption> _catalog = ConfigOption.parseAll(<Map<String, Object?>>[
  <String, Object?>{
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': <Map<String, Object?>>[
      <String, Object?>{'value': 'default', 'name': 'Manual'},
      <String, Object?>{'value': 'acceptEdits', 'name': 'Accept edits'},
      <String, Object?>{'value': 'bypassPermissions', 'name': 'Bypass permissions'},
    ],
  },
  <String, Object?>{
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': 'opus',
    'options': <Map<String, Object?>>[
      <String, Object?>{'value': 'opus', 'name': 'Opus'},
      <String, Object?>{'value': 'sonnet', 'name': 'Sonnet'},
    ],
  },
  <String, Object?>{
    'id': 'effort',
    'name': 'Effort',
    'category': 'thought_level',
    'type': 'select',
    'currentValue': 'medium',
    'options': <Map<String, Object?>>[
      <String, Object?>{'value': 'low', 'name': 'Low'},
      <String, Object?>{'value': 'medium', 'name': 'Medium'},
    ],
  },
]);

AgentInfo _claude({
  AgentStatus status = AgentStatus.ready,
  String? account = 'a@b.c',
  List<ConfigOption>? options,
}) => memoryClaudeAgent.copyWith(status: status, account: account, options: options ?? _catalog);

MemoryAgentsRepository _repository({
  AgentInfo? claude,
  List<AgentInfo> more = const [],
  bool holdSignIns = false,
}) => MemoryAgentsRepository(
  agents: <AgentInfo>[claude ?? _claude(), memoryCodexAgent, memoryGeminiAgent, ...more],
  holdSignIns: holdSignIns,
);

const AgentInfo _custom = AgentInfo(
  id: 'custom:1',
  name: 'My agent',
  status: AgentStatus.ready,
  source: AgentSource.custom,
  custom: CustomAgentDraft(name: 'My agent', executable: '/opt/mine', arguments: <String>['--acp']),
);

/// A repository whose logins stay open: the test adds their output lines itself.
final class _OpenLoginAgents extends MemoryAgentsRepository {
  _OpenLoginAgents({super.agents});

  AgentLogin? lastLogin;

  @override
  Future<AgentLogin?> login(String agentId, String methodId) async =>
      lastLogin = AgentLogin.forTest(agentId, methodId);
}

/// A repository whose watch of the Settings section fails with an error before any agent arrives.
/// The workspace watches first (for the names in the sidebar), and that watch works.
final class _FailingWatchAgents extends MemoryAgentsRepository {
  _FailingWatchAgents({super.agents});

  int failures = 1;
  int watches = 0;

  @override
  Stream<List<AgentInfo>> watchAgents() {
    watches++;
    if (watches > 1 && failures > 0) {
      failures--;
      return Stream<List<AgentInfo>>.error(StateError('secret internal detail'));
    }
    return super.watchAgents();
  }
}

Finder _card(String agentId) => find.byKey(ValueKey<String>('agent-card-$agentId'));

Finder _inCard(String agentId, String text) =>
    find.descendant(of: _card(agentId), matching: find.textContaining(text));

Finder _chip(String agentId, String role) =>
    find.byKey(ValueKey<String>('agent-default-$agentId-$role'));

Finder _pageContent() => find.byKey(const ValueKey<String>('page-content'));

/// Lets the sign-in dialog open or close; its spinner never settles.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

AppSettingsController _settings(WidgetTester tester) => _workspace(tester).settingsController;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;

  Future<void> openSettings(
    WidgetTester tester,
    String section,
    IAgentsRepository agents, {
    Locale locale = const Locale('ru'),
    bool dark = false,
    Size size = const Size(1280, 800),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dependencies = testDependencies(agentsRepository: agents);
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
    _workspace(tester).dataController.openView(WorkspaceView.settings, section: section);
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, Finder chip, String item) async {
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
    await _settle(tester);
  }

  testWidgets('shows three agents with their states', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Gemini CLI'), findsOneWidget);
    expect(find.textContaining('a@b.c'), findsOneWidget);
    expect(find.text('нужен вход'), findsNWidgets(2));
    expect(find.text('по умолчанию'), findsOneWidget);
    expect(find.byType(PreviewBadge), findsNothing);
    expect(find.text('0.96.0 · Node 22.11'), findsOneWidget);
    expect(find.text('2.5.0 · Node 22.11'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('opening the agents section checks every agent', (tester) async {
    final agents = _repository(more: const <AgentInfo>[_custom]);
    await openSettings(tester, 'agents', agents);

    expect(
      agents.calls.where((call) => call.startsWith('refresh:')),
      unorderedEquals(<String>['refresh:claude', 'refresh:codex', 'refresh:gemini', 'refresh:custom:1']),
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the general section checks nothing', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'general', agents);

    expect(agents.calls.where((call) => call.startsWith('refresh:')), isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a failed watch says so and can be retried', (tester) async {
    final agents = _FailingWatchAgents(agents: _repository().agents);
    await openSettings(tester, 'agents', agents);

    expect(agents.watches, 2);
    expect(find.text('Не удалось получить список агентов.'), findsOneWidget);
    expect(find.textContaining('secret internal detail'), findsNothing);
    expect(find.text('Claude Code'), findsNothing);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    await _settle(tester);

    expect(agents.watches, 3);
    expect(find.text('Не удалось получить список агентов.'), findsNothing);
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('Claude Code'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('shows the states in English', (tester) async {
    final agents = _repository(claude: _claude(account: null));
    await openSettings(tester, 'agents', agents, locale: const Locale('en'));

    expect(find.text('● signed in'), findsOneWidget);
    expect(find.text('login required'), findsNWidgets(2));
    expect(find.text('Sign out'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a checking agent shows a state and no action', (tester) async {
    final agents = _repository(claude: _claude(status: AgentStatus.checking));
    await openSettings(tester, 'agents', agents);

    expect(find.text('Проверяем…'), findsOneWidget);
    expect(find.text('Выйти'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('logout and login', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(agents.calls, contains('logout:claude'));
    expect(find.textContaining('a@b.c'), findsNothing);
    expect(find.text('Выйти'), findsNothing);

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic Console'), findsOneWidget);
    await tester.tap(find.text('Подписка Claude'));
    await tester.pumpAndSettle();
    await _settle(tester);

    expect(agents.calls, contains('login:claude:claude-ai-login'));
    expect(find.text('Opening the browser to sign in'), findsOneWidget);
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('Выйти'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('only the last eight login lines are shown', (tester) async {
    final agents = _OpenLoginAgents(
      agents: _repository(claude: _claude(status: AgentStatus.needsLogin)).agents,
    );
    await openSettings(tester, 'agents', agents);

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подписка Claude'));
    await tester.pumpAndSettle();
    await _settle(tester);
    final login = agents.lastLogin!;
    expect(login.methodId, 'claude-ai-login');
    for (var i = 0; i < 10; i++) {
      login.addLine('line $i');
    }
    await tester.pump();

    expect(find.text('line 1'), findsNothing);
    expect(find.text('line 2'), findsOneWidget);
    expect(find.text('line 9'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('default model is stored', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);
    expect(_settings(tester).settings.sessionDefaults, isEmpty);

    await pick(tester, _chip('claude', 'model'), 'Sonnet');
    expect(_settings(tester).settings.sessionDefaults['claude']!['model'], 'sonnet');
    expect(find.descendant(of: _chip('claude', 'model'), matching: find.text('Sonnet')), findsOne);

    await pick(tester, _chip('claude', 'effort'), 'Low');
    await pick(tester, _chip('claude', 'mode'), 'Accept edits');
    expect(_settings(tester).settings.sessionDefaults['claude'], <String, String>{
      'model': 'sonnet',
      'effort': 'low',
      'mode': 'acceptEdits',
    });
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('an unset default says the agent decides', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    expect(
      find.descendant(of: _chip('claude', 'model'), matching: find.text('Как у агента')),
      findsOneWidget,
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('mode menu has no bypass', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    await tester.ensureVisible(_chip('claude', 'mode'));
    await tester.tap(_chip('claude', 'mode'));
    await tester.pumpAndSettle();

    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Accept edits'), findsOneWidget);
    expect(find.text('Bypass permissions'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('empty catalog explains itself', (tester) async {
    final agents = _repository(claude: _claude(options: const <ConfigOption>[]));
    await openSettings(tester, 'agents', agents);
    _settings(tester).update(
      (s) => s.copyWith(
        sessionDefaults: <String, Map<String, String>>{
          'claude': <String, String>{'model': 'opus'},
        },
      ),
    );
    await _settle(tester);

    // The saved value stays readable even though the catalog cannot name it.
    expect(find.descendant(of: _chip('claude', 'model'), matching: find.text('opus')), findsOne);
    await tester.ensureVisible(_chip('claude', 'model'));
    await tester.tap(_chip('claude', 'model'));
    await tester.pumpAndSettle();
    expect(find.text('Откройте чат с агентом, чтобы выбрать'), findsOneWidget);
    expect(find.text('Сбросить'), findsOneWidget);

    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.sessionDefaults['claude'], isNot(contains('model')));

    // Nothing saved any more: the hint stays, there is nothing to reset.
    await tester.tap(_chip('claude', 'effort'));
    await tester.pumpAndSettle();
    expect(find.text('Откройте чат с агентом, чтобы выбрать'), findsOneWidget);
    expect(find.text('Сбросить'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('reset also works with a catalog', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);
    await pick(tester, _chip('claude', 'model'), 'Sonnet');

    await pick(tester, _chip('claude', 'model'), 'Сбросить');

    expect(_settings(tester).settings.sessionDefaults['claude'], isNot(contains('model')));
    await disposeTestApp(tester, dependencies);
  });

  group('sign-in methods', () {
    testWidgets('a browser method signs in with a dialog that can be cancelled', (tester) async {
      final agents = _repository(holdSignIns: true);
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(_inCard('codex', 'Login with ChatGPT'));
      await tester.tap(_inCard('codex', 'Login with ChatGPT'));
      await _pumpDialog(tester);

      expect(agents.calls, contains('login:codex:chat-gpt'));
      expect(find.text('Signing in to Codex'), findsOneWidget);
      expect(find.text('If the agent opened a browser window, finish signing in there.'), findsOne);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _pumpDialog(tester);
      await _settle(tester);

      expect(agents.calls, contains('cancelLogin:codex'));
      expect(find.text('Signing in to Codex'), findsNothing);
      // A cancelled sign-in is no error.
      expect(find.textContaining('failed'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a finished browser sign-in closes the dialog', (tester) async {
      final agents = _repository(holdSignIns: true);
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(_inCard('gemini', 'Log in with Google'));
      await tester.tap(_inCard('gemini', 'Log in with Google'));
      await _pumpDialog(tester);
      expect(find.text('Signing in to Gemini CLI'), findsOneWidget);

      agents.finishSignIn('gemini');
      await _pumpDialog(tester);
      await _settle(tester);

      expect(find.text('Signing in to Gemini CLI'), findsNothing);
      expect(_inCard('gemini', '● signed in'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a second tap while signing in starts nothing new', (tester) async {
      final agents = _repository(holdSignIns: true);
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));
      await tester.ensureVisible(_inCard('codex', 'Login with ChatGPT'));
      await tester.tap(_inCard('codex', 'Login with ChatGPT'));
      await _pumpDialog(tester);
      // The dialog covers the card; ask through the actions as a second caller would.
      final scope = AgentsConfigInhWidget.of(tester.element(_card('codex')));
      scope.actions.login('codex', memoryCodexAgent.methods.first);
      await _pumpDialog(tester);

      expect(agents.calls.where((call) => call == 'login:codex:chat-gpt'), hasLength(1));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _pumpDialog(tester);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an API key method without its variable names it', (tester) async {
      final agents = _repository();
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      expect(
        _inCard(
          'codex',
          'To sign in with a key, set CODEX_API_KEY or OPENAI_API_KEY in your shell profile, '
              'then restart the app to pick up the key.',
        ),
        findsOneWidget,
      );
      expect(_inCard('gemini', 'set GEMINI_API_KEY in your shell profile'), findsOneWidget);
      expect(find.text('Use API key'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an API key method with its variable offers Use API key', (tester) async {
      final gemini = memoryGeminiAgent.copyWith(
        methods: <AgentLoginMethod>[
          for (final method in memoryGeminiAgent.methods)
            if (method.kind == AgentLoginKind.apiKey)
              method.copyWith(keyPresent: true)
            else
              method,
        ],
      );
      final agents = MemoryAgentsRepository(
        agents: <AgentInfo>[_claude(), memoryCodexAgent, gemini],
        holdSignIns: true,
      );
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      expect(_inCard('gemini', 'GEMINI_API_KEY'), findsNothing);
      await tester.ensureVisible(_inCard('gemini', 'Use API key'));
      await tester.tap(_inCard('gemini', 'Use API key'));
      await _pumpDialog(tester);

      expect(agents.calls, contains('login:gemini:gemini-api-key'));
      expect(find.text('Signing in to Gemini CLI'), findsOneWidget);
      agents.finishSignIn('gemini');
      await _pumpDialog(tester);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an unsupported method says to set it up in the agent', (tester) async {
      final agents = _repository();
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      expect(
        _inCard('gemini', "Vertex AI: set this up in the agent's own settings."),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Vertex AI'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the method buttons are in Russian too', (tester) async {
      final agents = _repository();
      await openSettings(tester, 'agents', agents);

      expect(_inCard('gemini', 'Чтобы войти по ключу, задайте GEMINI_API_KEY'), findsOneWidget);
      expect(_inCard('gemini', 'Vertex AI: настройте в самом агенте.'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('a failed agent shows the reason and can be checked again', (tester) async {
    final agents = _repository(
      more: const <AgentInfo>[
        AgentInfo(
          id: 'custom:1',
          name: 'Broken',
          status: AgentStatus.failed,
          problem: 'no ACP answer to initialize',
          source: AgentSource.custom,
          custom: CustomAgentDraft(name: 'Broken', executable: 'broken'),
        ),
      ],
    );
    await openSettings(tester, 'agents', agents, locale: const Locale('en'));
    agents.calls.clear();

    expect(_inCard('custom:1', 'error'), findsOneWidget);
    expect(_inCard('custom:1', 'no ACP answer to initialize'), findsOneWidget);
    await tester.ensureVisible(_inCard('custom:1', 'Check again'));
    await tester.tap(_inCard('custom:1', 'Check again'));
    await tester.pumpAndSettle();

    expect(agents.calls, <String>['refresh:custom:1']);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a ready custom agent says sign-in is checked in the first chat', (tester) async {
    final agents = _repository(more: const <AgentInfo>[_custom]);
    await openSettings(tester, 'agents', agents, locale: const Locale('en'));

    expect(_inCard('custom:1', 'Sign-in is checked in the first chat.'), findsOneWidget);
    expect(_inCard('codex', 'Sign-in is checked in the first chat.'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  group('custom agents', () {
    testWidgets('Add ACP agent opens the dialog and adds the agent', (tester) async {
      final agents = _repository();
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(find.text('＋ Custom ACP agent'));
      await tester.tap(find.text('＋ Custom ACP agent'));
      await tester.pumpAndSettle();
      expect(find.text('Add ACP agent'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('custom-agent-name')), 'Mine');
      await tester.enterText(find.byKey(const ValueKey<String>('custom-agent-command')), 'mine');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(agents.calls, contains('addCustom:Mine'));
      expect(find.text('Add ACP agent'), findsNothing);
      expect(_card('custom:1'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Edit opens the dialog with the stored fields', (tester) async {
      final agents = _repository(more: const <AgentInfo>[_custom]);
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(_inCard('custom:1', 'Edit'));
      await tester.tap(_inCard('custom:1', 'Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit ACP agent'), findsOneWidget);
      expect(find.text('/opt/mine'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('custom-agent-name')), 'Renamed');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(agents.calls, contains('updateCustom:custom:1:Renamed'));
      expect(find.text('Renamed'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Remove of an idle custom agent removes it', (tester) async {
      final agents = _repository(more: const <AgentInfo>[_custom]);
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(_inCard('custom:1', 'Remove'));
      await tester.tap(_inCard('custom:1', 'Remove'));
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(agents.calls, contains('removeCustom:custom:1'));
      expect(_card('custom:1'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Remove asks when a chat of the agent is busy', (tester) async {
      final agents = _repository(more: const <AgentInfo>[_custom])..busyAgents.add('custom:1');
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      await tester.ensureVisible(_inCard('custom:1', 'Remove'));
      await tester.tap(_inCard('custom:1', 'Remove'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A chat of My agent is working.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(agents.calls, isNot(contains('removeCustom:custom:1')));

      await tester.tap(_inCard('custom:1', 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      await _settle(tester);

      expect(agents.calls, contains('removeCustom:custom:1'));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('built-in agents have no Edit or Remove', (tester) async {
      final agents = _repository();
      await openSettings(tester, 'agents', agents, locale: const Locale('en'));

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('sign out of an agent with a busy chat asks first', (tester) async {
    final agents = MemoryAgentsRepository(
      agents: <AgentInfo>[
        _claude(),
        memoryCodexAgent.copyWith(status: AgentStatus.ready, account: 'ChatGPT Plus'),
        memoryGeminiAgent,
      ],
    )..busyAgents.addAll(<String>['codex', 'claude']);
    await openSettings(tester, 'agents', agents, locale: const Locale('en'));

    await tester.ensureVisible(_inCard('codex', 'Sign out'));
    await tester.tap(_inCard('codex', 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('A chat of Codex is working. Signing out stops it.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(agents.calls, contains('logout:codex'));

    // Claude signs out through its CLI; a busy chat goes on, so nothing is asked.
    await tester.ensureVisible(_inCard('claude', 'Sign out'));
    await tester.tap(_inCard('claude', 'Sign out'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(find.textContaining('Signing out stops it'), findsNothing);
    expect(agents.calls, contains('logout:claude'));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('opening the Claude settings asks the repository', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    await tester.ensureVisible(find.text('открыть'));
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();

    expect(agents.calls, contains('openSettings:claude'));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('general offers every agent but not installed and failed ones', (tester) async {
    final agents = _repository(
      more: const <AgentInfo>[
        AgentInfo(id: 'missing', name: 'Missing Agent', status: AgentStatus.notInstalled),
        AgentInfo(
          id: 'custom:1',
          name: 'Broken Agent',
          status: AgentStatus.failed,
          source: AgentSource.custom,
        ),
        AgentInfo(id: 'custom:2', name: 'Other Agent', status: AgentStatus.ready),
      ],
    );
    await openSettings(tester, 'general', agents);
    expect(_settings(tester).settings.defaultAgentId, 'claude');

    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewBadge), findsNothing);

    // Agents that are missing or broken cannot be picked: the menu stays open.
    await tester.tap(find.text('Missing Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broken Agent'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.defaultAgentId, 'claude');

    // An agent that needs a sign-in can be the default.
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.defaultAgentId, 'codex');
    expect(find.text('Gemini CLI'), findsNothing);

    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Agent'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.defaultAgentId, 'custom:2');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a default that cannot start chats says new chats use Claude', (tester) async {
    const unavailable = 'Агент недоступен, поэтому новые чаты начинаются с Claude.';
    final agents = _repository(
      more: const <AgentInfo>[
        AgentInfo(
          id: 'missing',
          name: 'Missing Agent',
          status: AgentStatus.notInstalled,
          problem: 'Node.js 22 is required',
        ),
      ],
    );

    // The default was removed: Settings → General says so.
    await openSettings(tester, 'general', agents);
    expect(find.text(unavailable), findsNothing);
    _settings(tester).update((current) => current.copyWith(defaultAgentId: 'custom:9'));
    await tester.pumpAndSettle();
    expect(find.text(unavailable), findsOneWidget);

    // The default is an agent that is not installed: its card says so too.
    _settings(tester).update((current) => current.copyWith(defaultAgentId: 'missing'));
    await tester.pumpAndSettle();
    expect(find.text(unavailable), findsOneWidget);
    _workspace(tester).dataController.openView(WorkspaceView.settings, section: 'agents');
    await tester.pumpAndSettle();
    expect(_inCard('missing', unavailable), findsOneWidget);
    expect(_inCard('claude', unavailable), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  group('layout', () {
    for (final section in const <String>['general', 'agents']) {
      for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
        for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
          for (final dark in const <bool>[false, true]) {
            testWidgets(
              '$section fits ${size.width.toInt()}×${size.height.toInt()} in '
              '${locale.languageCode}, ${dark ? 'dark' : 'light'}',
              (tester) async {
                final agents = _repository(
                  claude: _claude(account: 'a.very.long.account.name@example-organization.com'),
                );
                await openSettings(
                  tester,
                  section,
                  agents,
                  locale: locale,
                  dark: dark,
                  size: size,
                );
                expect(_pageContent(), findsOneWidget);
                expect(tester.takeException(), isNull);
                await disposeTestApp(tester, dependencies);
              },
            );
          }
        }
      }
    }

    testWidgets('a login with long output fits 900×600', (tester) async {
      final agents = _OpenLoginAgents(
        agents: _repository(claude: _claude(status: AgentStatus.needsLogin)).agents,
      );
      await openSettings(tester, 'agents', agents, size: const Size(900, 600), dark: true);
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подписка Claude'));
      await tester.pumpAndSettle();
      final login = agents.lastLogin!;
      for (var i = 0; i < 12; i++) {
        login.addLine('https://claude.ai/oauth/authorize?code_challenge=${'x' * 120}&state=$i');
      }
      await tester.pumpAndSettle();

      expect(find.textContaining('state=11'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });
  });
}
