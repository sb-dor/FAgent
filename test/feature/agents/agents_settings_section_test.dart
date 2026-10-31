import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agent_card.dart';
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
}) => AgentInfo(
  id: 'claude',
  name: 'Claude Code',
  version: '0.96.0',
  runtime: 'Node 22.11',
  status: status,
  account: account,
  loginMethods: const <String>['claude-ai-login', 'console-login'],
  options: options ?? _catalog,
  canStartChats: true,
);

MemoryAgentsRepository _repository({AgentInfo? claude, List<AgentInfo> more = const []}) =>
    MemoryAgentsRepository(
      agents: <AgentInfo>[claude ?? _claude(), previewCodexAgent, previewGeminiAgent, ...more],
    );

/// A repository whose logins stay open: the test adds their output lines itself.
final class _OpenLoginAgents implements IAgentsRepository {
  _OpenLoginAgents(this.inner);

  final MemoryAgentsRepository inner;
  AgentLogin? lastLogin;

  @override
  Stream<List<AgentInfo>> watchAgents() => inner.watchAgents();

  @override
  Future<void> refresh(String agentId) => inner.refresh(agentId);

  @override
  Future<AgentLogin> login(String agentId, String methodId) async =>
      lastLogin = AgentLogin.forTest(agentId, methodId);

  @override
  Future<void> logout(String agentId) => inner.logout(agentId);

  @override
  Future<void> install(String agentId) => inner.install(agentId);

  @override
  Future<void> openSettings(String agentId) => inner.openSettings(agentId);
}

/// A repository whose first watch fails with an error before any agent arrives.
final class _FailingWatchAgents implements IAgentsRepository {
  _FailingWatchAgents(this.inner);

  final MemoryAgentsRepository inner;
  int failures = 1;
  int watches = 0;

  @override
  Stream<List<AgentInfo>> watchAgents() {
    watches++;
    if (failures > 0) {
      failures--;
      return Stream<List<AgentInfo>>.error(StateError('secret internal detail'));
    }
    return inner.watchAgents();
  }

  @override
  Future<void> refresh(String agentId) => inner.refresh(agentId);

  @override
  Future<AgentLogin> login(String agentId, String methodId) => inner.login(agentId, methodId);

  @override
  Future<void> logout(String agentId) => inner.logout(agentId);

  @override
  Future<void> install(String agentId) => inner.install(agentId);

  @override
  Future<void> openSettings(String agentId) => inner.openSettings(agentId);
}

Finder _chip(String agentId, String role) =>
    find.byKey(ValueKey<String>('agent-default-$agentId-$role'));

Finder _pageContent() => find.byKey(const ValueKey<String>('page-content'));

/// Lets the snack bar finish showing, wait out its timer and leave.
Future<void> _expireSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
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
    expect(find.text('не установлен'), findsOneWidget);
    expect(find.text('нужен вход'), findsOneWidget);
    expect(find.text('по умолчанию'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AgentCard), matching: find.byType(PreviewBadge)),
      findsNWidgets(2),
    );
    expect(find.text('0.96.0 · Node 22.11'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a failed watch says so and can be retried', (tester) async {
    final agents = _FailingWatchAgents(_repository());
    await openSettings(tester, 'agents', agents);

    expect(agents.watches, 1);
    expect(find.text('Не удалось получить список агентов.'), findsOneWidget);
    expect(find.textContaining('secret internal detail'), findsNothing);
    expect(find.text('Claude Code'), findsNothing);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    await _settle(tester);

    expect(agents.watches, 2);
    expect(find.text('Не удалось получить список агентов.'), findsNothing);
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('Claude Code'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('shows the states in English', (tester) async {
    final agents = _repository(claude: _claude(account: null));
    await openSettings(tester, 'agents', agents, locale: const Locale('en'));

    expect(find.text('● signed in'), findsOneWidget);
    expect(find.text('not installed'), findsOneWidget);
    expect(find.text('login required'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('checking and installing agents show a state and no action', (tester) async {
    final agents = _repository(
      claude: _claude(status: AgentStatus.checking),
      more: const <AgentInfo>[
        AgentInfo(id: 'x', name: 'Installing One', status: AgentStatus.installing),
      ],
    );
    await openSettings(tester, 'agents', agents);

    expect(find.text('Проверяем…'), findsOneWidget);
    expect(find.text('Устанавливаем…'), findsOneWidget);
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
      _repository(claude: _claude(status: AgentStatus.needsLogin)),
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

  testWidgets('preview actions say the milestone', (tester) async {
    final agents = _repository();
    await openSettings(tester, 'agents', agents);

    await tester.ensureVisible(find.text('Установить'));
    await tester.tap(find.text('Установить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(agents.calls, contains('install:codex'));
    expect(find.text('Появится в M5'), findsOneWidget);
    await _expireSnackBar(tester);
    expect(find.text('Появится в M5'), findsNothing);

    await tester.ensureVisible(find.text('＋ Свой ACP-агент'));
    await tester.tap(find.text('＋ Свой ACP-агент'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Появится в M5'), findsOneWidget);

    await _expireSnackBar(tester);
    await tester.ensureVisible(find.text('Войти с Google'));
    await tester.tap(find.text('Войти с Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(agents.calls, contains('login:gemini:google'));
    expect(find.text('Появится в M5'), findsOneWidget);
    await _expireSnackBar(tester);
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

  testWidgets('general offers only agents that can start chats', (tester) async {
    final agents = _repository(
      more: const <AgentInfo>[
        AgentInfo(id: 'other', name: 'Other Agent', canStartChats: true, status: AgentStatus.ready),
      ],
    );
    await openSettings(tester, 'general', agents);
    expect(_settings(tester).settings.defaultAgentId, 'claude');

    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();
    expect(find.byType(PreviewBadge), findsNWidgets(2));

    // Codex and Gemini cannot be picked: the menu stays open.
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini CLI'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.defaultAgentId, 'claude');
    expect(find.text('Other Agent'), findsOneWidget);

    await tester.tap(find.text('Other Agent'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(_settings(tester).settings.defaultAgentId, 'other');
    expect(find.text('Other Agent'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
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
        _repository(claude: _claude(status: AgentStatus.needsLogin)),
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
