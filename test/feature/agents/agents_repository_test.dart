import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_test/flutter_test.dart';

/// A catalog that holds [value] and sends it, and every change, to its watchers.
final class _MemoryCatalog implements IAgentOptionsCatalog {
  _MemoryCatalog([this.value = const {}]);

  Map<String, List<Map<String, Object?>>> value;
  final Set<StreamController<Map<String, List<Map<String, Object?>>>>> _watchers = {};

  @override
  Stream<Map<String, List<Map<String, Object?>>>> watch() {
    final controller = StreamController<Map<String, List<Map<String, Object?>>>>();
    controller
      ..onListen = () {
        _watchers.add(controller);
        controller.add(value);
      }
      ..onCancel = () {
        _watchers.remove(controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> save(String agentId, List<Map<String, Object?>> options) async {
    value = {...value, agentId: options};
    for (final watcher in _watchers.toList()) {
      watcher.add(value);
    }
  }
}

typedef _Call = ({String executable, List<String> arguments, Duration? timeout});

void main() {
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  late AppDatabase database;
  late AgentHub hub;
  late List<_Call> calls;
  late String statusOutput;
  late Future<ProcessResult> Function(List<String> arguments, Duration? timeout) onStatus;
  final subscriptions = <StreamSubscription<Object?>>[];

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    hub = AgentHub(database: database, environment: environment);
    calls = [];
    statusOutput = '{"loggedIn":true,"email":"a@b.c"}';
    onStatus = (arguments, timeout) async => ProcessResult(1, 0, statusOutput, '');
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    await hub.dispose();
    await database.close();
  });

  AgentsRepositoryImpl newRepository({
    IAgentOptionsCatalog? catalog,
    Future<String> Function(AgentDefinition, ShellEnvironment)? preflight,
    Duration statusTimeout = const Duration(seconds: 30),
    String? homeDirectory,
  }) => AgentsRepositoryImpl(
    hub: hub,
    environment: environment,
    catalog: catalog ?? _MemoryCatalog(),
    preflight: preflight ?? (_, _) async => '/usr/bin/npx',
    statusTimeout: statusTimeout,
    homeDirectory: homeDirectory,
    runProcess: (executable, arguments, {environment, timeout}) async {
      calls.add((executable: executable, arguments: arguments, timeout: timeout));
      if (executable.endsWith('node')) return ProcessResult(1, 0, 'v22.11.0\n', '');
      if (executable == 'open') return ProcessResult(1, 0, '', '');
      return onStatus(arguments, timeout);
    },
  );

  /// The first [count] emissions of [repository].
  Future<List<List<AgentInfo>>> emissions(IAgentsRepository repository, int count) {
    final done = Completer<List<List<AgentInfo>>>();
    final seen = <List<AgentInfo>>[];
    subscriptions.add(
      repository.watchAgents().listen((agents) {
        seen.add(agents);
        if (seen.length == count && !done.isCompleted) done.complete(seen);
      }),
    );
    return done.future.timeout(const Duration(seconds: 5));
  }

  AgentInfo claudeOf(List<AgentInfo> agents) => agents.firstWhere((a) => a.id == 'claude');

  test('claude is ready with the account', () async {
    final seen = await emissions(newRepository(), 2);

    expect(seen.first.map((a) => a.id), ['claude', 'codex', 'gemini']);
    expect(claudeOf(seen.first).status, AgentStatus.checking);
    final claude = claudeOf(seen[1]);
    expect(claude.status, AgentStatus.ready);
    expect(claude.account, 'a@b.c');
    expect(claude.runtime, 'Node 22.11');
    expect(claude.version, AgentDefinition.claudeAdapterVersion);
    expect(claude.loginMethods, ['claude-ai-login', 'console-login']);
    expect(claude.canStartChats, isTrue);
    expect(claude.isPreview, isFalse);
    final status = calls.firstWhere((c) => c.arguments.contains('status'));
    expect(status.executable, '/usr/bin/npx');
    expect(status.arguments, [
      ...AgentDefinition.claude.arguments,
      '--cli',
      'auth',
      'status',
      '--json',
    ]);
  });

  test('missing node is not installed with a hint', () async {
    final repository = newRepository(
      preflight: (_, _) async => throw const AgentPreflightException(
        'Node.js 22+ is required for Claude Code but was not found.',
        hint: 'Install Node.js 22 or newer (https://nodejs.org)',
      ),
    );

    final claude = claudeOf((await emissions(repository, 2))[1]);

    expect(claude.status, AgentStatus.notInstalled);
    expect(claude.problem, contains('Node.js 22+'));
    expect(claude.hint, contains('Install Node.js 22'));
    expect(calls, isEmpty);
  });

  test('hanging status ends as ready without account', () async {
    onStatus = (arguments, timeout) async {
      // The real runner kills the process and throws once the timeout is over.
      await Future<void>.delayed(timeout!);
      throw TimeoutException('npx did not finish', timeout);
    };

    final claude = claudeOf(
      (await emissions(newRepository(statusTimeout: const Duration(milliseconds: 50)), 2))[1],
    );

    expect(claude.status, AgentStatus.ready);
    expect(claude.account, isNull);
    expect(
      calls.where((c) => c.arguments.contains('status')).single.timeout,
      const Duration(milliseconds: 50),
    );
  });

  test('logged out claude needs login', () async {
    statusOutput = '{"loggedIn":false}';

    final claude = claudeOf((await emissions(newRepository(), 2))[1]);

    expect(claude.status, AgentStatus.needsLogin);
    expect(claude.account, isNull);
  });

  test('logout runs auth logout then checks again', () async {
    final repository = newRepository();
    final seen = <List<AgentInfo>>[];
    subscriptions.add(repository.watchAgents().listen(seen.add));
    await pumpEventQueue();
    expect(claudeOf(seen.last).status, AgentStatus.ready);

    statusOutput = '{"loggedIn":false}';
    await repository.logout('claude');
    await pumpEventQueue();

    final npxCalls = calls.where((c) => c.executable == '/usr/bin/npx').toList();
    expect(npxCalls, hasLength(3));
    List<String> tail(_Call call, int count) =>
        call.arguments.sublist(call.arguments.length - count);
    expect(tail(npxCalls[0], 3), ['auth', 'status', '--json']);
    expect(tail(npxCalls[1], 3), ['--cli', 'auth', 'logout']);
    expect(tail(npxCalls[2], 3), ['auth', 'status', '--json']);
    expect(claudeOf(seen.last).status, AgentStatus.needsLogin);
  });

  test('fake agents refuse actions', () async {
    final repository = newRepository();

    await expectLater(
      repository.login('codex', 'x'),
      throwsA(isA<AgentPreviewException>().having((e) => e.milestone, 'milestone', 'M5')),
    );
    await expectLater(
      repository.install('gemini'),
      throwsA(isA<AgentPreviewException>().having((e) => e.milestone, 'milestone', 'M5')),
    );
    await expectLater(repository.logout('gemini'), throwsA(isA<AgentPreviewException>()));
    await expectLater(repository.openSettings('codex'), throwsA(isA<AgentPreviewException>()));
    await repository.refresh('codex');
    expect(calls, isEmpty);
  });

  test('the preview agents match their descriptions', () async {
    final agents = (await emissions(newRepository(), 1)).single;

    final codex = agents[1];
    expect(codex.status, AgentStatus.notInstalled);
    expect(codex.problem, 'codex-acp · Node 22+');
    expect([codex.isPreview, codex.canStartChats], [true, false]);
    final gemini = agents[2];
    expect(gemini.status, AgentStatus.needsLogin);
    expect(gemini.version, '0.9.2');
    expect(gemini.loginMethods, ['google']);
    expect([gemini.isPreview, gemini.canStartChats], [true, false]);
  });

  test('catalog options reach the agent', () async {
    final catalog = _MemoryCatalog({
      'claude': [
        {
          'id': 'model',
          'type': 'select',
          'currentValue': 'opus',
          'options': [
            {'value': 'opus', 'name': 'Opus'},
          ],
        },
      ],
    });
    final repository = newRepository(catalog: catalog);
    final latest = <List<AgentInfo>>[];
    subscriptions.add(repository.watchAgents().listen(latest.add));
    await pumpEventQueue();

    final options = claudeOf(latest.last).options;
    expect(options.single, isA<SelectConfigOption>().having((o) => o.id, 'id', 'model'));
    expect(claudeOf(latest.last).status, AgentStatus.ready);
  });

  test('a changed catalog emits the agents again', () async {
    final catalog = _MemoryCatalog();
    final repository = newRepository(catalog: catalog);
    final latest = <List<AgentInfo>>[];
    subscriptions.add(repository.watchAgents().listen(latest.add));
    await pumpEventQueue();
    expect(claudeOf(latest.last).options, isEmpty);

    await catalog.save('claude', [
      {'id': 'mode', 'type': 'select', 'currentValue': 'default', 'options': <Object?>[]},
    ]);
    await pumpEventQueue();

    expect(claudeOf(latest.last).options.single.id, 'mode');
  });

  group('openSettings', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('agents_repository_test'));
    tearDown(() => home.deleteSync(recursive: true));

    test('opens the settings file in the editor', () async {
      Directory('${home.path}/.claude').createSync();
      File('${home.path}/.claude/settings.json').writeAsStringSync('{}');

      await newRepository(homeDirectory: home.path).openSettings('claude');

      expect(calls.single.executable, 'open');
      expect(calls.single.arguments, ['-t', '${home.path}/.claude/settings.json']);
    });

    test('opens the folder when there is no file', () async {
      Directory('${home.path}/.claude').createSync();

      await newRepository(homeDirectory: home.path).openSettings('claude');

      expect(calls.single.arguments, ['${home.path}/.claude']);
    });

    test('reports a missing folder', () async {
      await expectLater(
        newRepository(homeDirectory: home.path).openSettings('claude'),
        throwsA(isA<AgentSettingsMissingException>()),
      );
      expect(calls, isEmpty);
    });
  });

  group('runProcessKillingOnTimeout', () {
    test('returns the output of a finished process', () async {
      final result = await runProcessKillingOnTimeout('/bin/echo', ['hi']);

      expect([result.exitCode, '${result.stdout}'.trim()], [0, 'hi']);
    });

    test('kills a process that outlives the timeout', () async {
      final stopwatch = Stopwatch()..start();

      await expectLater(
        runProcessKillingOnTimeout('/bin/sleep', [
          '30',
        ], timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
