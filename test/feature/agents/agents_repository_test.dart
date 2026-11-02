import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_agent_binary.dart';

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

/// A probe that answers with [results] (by agent id) and records what it was asked.
class _ScriptedProbe implements IAgentProbe {
  final Map<String, AgentProbeResult> results = <String, AgentProbeResult>{};

  /// Agent id and the auth status wait of every probe.
  final List<(String, Duration?)> calls = <(String, Duration?)>[];

  @override
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait}) async {
    calls.add((agent.id, authStatusWait));
    return results[agent.id] ?? const AgentProbeResult();
  }

  @override
  Future<void> dispose() async {}
}

/// A probe whose answers wait for [gate].
final class _SlowProbe extends _ScriptedProbe {
  _SlowProbe(this.gate);

  final Future<void> gate;

  @override
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait}) async {
    final result = super.probe(agent, authStatusWait: authStatusWait);
    await gate;
    return result;
  }
}

/// Custom agents in memory: records the calls and sends [value] to its watchers.
final class _RecordingCustomAgents implements ICustomAgentsRepository {
  List<AgentDefinition> value = const <AgentDefinition>[];
  final List<String> calls = <String>[];
  final Set<StreamController<List<AgentDefinition>>> _watchers = {};

  void emit(List<AgentDefinition> agents) {
    value = agents;
    for (final watcher in _watchers.toList()) {
      watcher.add(agents);
    }
  }

  @override
  Stream<List<AgentDefinition>> watch() {
    final controller = StreamController<List<AgentDefinition>>();
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
  Future<String> add(CustomAgentDraft draft) async {
    calls.add('add:${draft.name}');
    return 'custom:1';
  }

  @override
  Future<void> update(String id, CustomAgentDraft draft) async =>
      calls.add('update:$id:${draft.name}');

  @override
  Future<void> remove(String id) async => calls.add('remove:$id');
}

typedef _Call = ({String executable, List<String> arguments, Duration? timeout});

/// Waits for [file] to hold a process id, written by a script before it goes on.
Future<int> _readPid(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final pid = file.existsSync() ? int.tryParse(file.readAsStringSync().trim()) : null;
    if (pid != null) return pid;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('${file.path} did not get a process id within 10 seconds');
}

/// Whether process [pid] is gone, polled until it is or ten seconds pass.
Future<bool> _isGone(int pid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    // SIGCONT is harmless to a running process; false means there is no such process.
    if (!Process.killPid(pid, ProcessSignal.sigcont)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

/// The methods of the requests the fake agent wrote to [file].
List<String> _requests(File file) => file.existsSync()
    ? <String>[
        for (final line in file.readAsLinesSync())
          if (line.isNotEmpty) (jsonDecode(line) as Map<String, Object?>)['method']! as String,
      ]
    : const <String>[];

/// The params of the first request [method] in [file].
Map<String, Object?> _paramsOf(File file, String method) =>
    <Map<String, Object?>>[
          for (final line in file.readAsLinesSync())
            if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
        ].firstWhere((request) => request['method'] == method)['params']!
        as Map<String, Object?>;

/// Polls until [condition] holds, for up to ten seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('the condition did not hold within 10 seconds');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const AgentProbeResult _geminiProbe = AgentProbeResult(
  version: '0.66.0',
  authMethods: <AcpAuthMethod>[
    AcpAuthMethod(id: 'oauth-personal', name: 'Log in with Google'),
    AcpAuthMethod(id: 'gemini-api-key', name: 'Use Gemini API key', apiKeyProvider: 'google'),
    AcpAuthMethod(id: 'vertex-ai', name: 'Vertex AI'),
    AcpAuthMethod(id: 'gateway', name: 'AI API Gateway'),
  ],
  mcpHttp: true,
  mcpSse: true,
);

const AgentProbeResult _codexProbe = AgentProbeResult(
  version: '2.5.0',
  authMethods: <AcpAuthMethod>[
    AcpAuthMethod(id: 'chat-gpt', name: 'Login with ChatGPT'),
    AcpAuthMethod(id: 'api-key', name: 'Use OPENAI_API_KEY', apiKeyProvider: 'openai'),
  ],
  canLogout: true,
);

void main() {
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  late AppDatabase database;
  late AgentHub hub;
  late List<_Call> calls;
  late String statusOutput;
  late Future<ProcessResult> Function(List<String> arguments, Duration? timeout) onStatus;
  late _ScriptedProbe probe;
  late _RecordingCustomAgents custom;
  late Directory home;
  final subscriptions = <StreamSubscription<Object?>>[];

  AgentHub newHub(List<AgentDefinition> agents) => AgentHub(
    database: database,
    environment: environment,
    agents: <String, AgentDefinition>{for (final agent in agents) agent.id: agent},
  );

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    hub = newHub(AgentDefinition.builtins);
    calls = [];
    statusOutput = '{"loggedIn":true,"email":"a@b.c"}';
    onStatus = (arguments, timeout) async => ProcessResult(1, 0, statusOutput, '');
    probe = _ScriptedProbe();
    custom = _RecordingCustomAgents();
    home = Directory.systemTemp.createTempSync('agents_repository_home');
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    await hub.dispose();
    await database.close();
    home.deleteSync(recursive: true);
  });

  /// Replaces the hub with one that runs [agents].
  Future<void> useAgents(List<AgentDefinition> agents) async {
    await hub.dispose();
    hub = newHub(agents);
  }

  AgentsRepositoryImpl newRepository({
    IAgentOptionsCatalog? catalog,
    Future<String> Function(AgentDefinition, ShellEnvironment)? preflight,
    Duration statusTimeout = const Duration(seconds: 30),
    String? homeDirectory,
    ShellEnvironment shell = environment,
  }) => AgentsRepositoryImpl(
    hub: hub,
    environment: shell,
    catalog: catalog ?? _MemoryCatalog(),
    customAgents: custom,
    probe: probe,
    preflight: preflight ?? (_, _) async => '/usr/bin/npx',
    statusTimeout: statusTimeout,
    homeDirectory: homeDirectory ?? home.path,
    runProcess: (executable, arguments, {environment, timeout}) async {
      calls.add((executable: executable, arguments: arguments, timeout: timeout));
      if (executable.endsWith('node')) return ProcessResult(1, 0, 'v22.11.0\n', '');
      if (executable == 'open') return ProcessResult(1, 0, '', '');
      return onStatus(arguments, timeout);
    },
  );

  /// Watches [repository] and checks Claude; the emissions until [count] arrived.
  Future<List<List<AgentInfo>>> emissions(IAgentsRepository repository, int count) {
    final done = Completer<List<List<AgentInfo>>>();
    final seen = <List<AgentInfo>>[];
    subscriptions.add(
      repository.watchAgents().listen((agents) {
        seen.add(agents);
        if (seen.length == count && !done.isCompleted) done.complete(seen);
      }),
    );
    unawaited(repository.refresh('claude'));
    return done.future.timeout(const Duration(seconds: 5));
  }

  AgentInfo agentOf(IAgentsRepository repository, String id) =>
      repository.agents.firstWhere((a) => a.id == id);

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
    expect(claude.methods, const <AgentLoginMethod>[
      AgentLoginMethod(
        id: 'claude-ai-login',
        name: 'claude-ai-login',
        kind: AgentLoginKind.terminal,
      ),
      AgentLoginMethod(id: 'console-login', name: 'console-login', kind: AgentLoginKind.terminal),
    ]);
    expect(claude.canStartChats, isTrue);
    expect(claude.canSignOut, isTrue);
    expect(claude.source, AgentSource.builtin);
    final status = calls.firstWhere((c) => c.arguments.contains('status'));
    expect(status.executable, '/usr/bin/npx');
    expect(status.arguments, [
      ...AgentDefinition.claude.arguments,
      '--cli',
      'auth',
      'status',
      '--json',
    ]);
    // Claude keeps its own check; it is never probed.
    expect(probe.calls, isEmpty);
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
    expect(claude.canStartChats, isFalse);
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
    await repository.refresh('claude');
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

  test('watching alone checks nothing', () async {
    final repository = newRepository();
    final seen = <List<AgentInfo>>[];
    subscriptions.add(repository.watchAgents().listen(seen.add));
    await pumpEventQueue();

    expect(seen.single.every((a) => a.status == AgentStatus.checking), isTrue);
    expect(calls, isEmpty);
    expect(probe.calls, isEmpty);
  });

  test('refreshAll checks every agent', () async {
    final repository = newRepository();

    await repository.refreshAll();

    expect(calls.where((c) => c.arguments.contains('status')), hasLength(1));
    expect(probe.calls.map((c) => c.$1), unorderedEquals(<String>['codex', 'gemini']));
  });

  test('refreshAll skips an agent whose check is still running', () async {
    final slow = Completer<void>();
    final slowProbe = _SlowProbe(slow.future);
    probe = slowProbe;
    final repository = newRepository();

    final startup = repository.refreshAll();
    await pumpEventQueue();
    // Settings → Agents opens while the startup check runs.
    final settings = repository.refreshAll();
    await pumpEventQueue();
    slow.complete();
    await Future.wait(<Future<void>>[startup, settings]);

    // Claude's quick check had finished, so only it ran again; the probes ran once each.
    expect(slowProbe.calls.map((c) => c.$1), unorderedEquals(<String>['codex', 'gemini']));
  });

  test('refresh of a running check still checks once more', () async {
    final slow = Completer<void>();
    final slowProbe = _SlowProbe(slow.future);
    probe = slowProbe;
    final repository = newRepository();

    final first = repository.refresh('codex');
    await pumpEventQueue();
    final second = repository.refresh('codex');
    slow.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(slowProbe.calls.map((c) => c.$1), <String>['codex', 'codex']);
  });

  group('status', () {
    test('codex signed in from the auth status push', () async {
      probe.results['codex'] = _codexProbe.copyWith(
        authStatus: const AcpAuthStatus(kind: 'account', label: 'ChatGPT Plus'),
      );
      final repository = newRepository();

      await repository.refresh('codex');

      final codex = agentOf(repository, 'codex');
      expect(codex.status, AgentStatus.ready);
      expect(codex.account, 'ChatGPT Plus');
      expect(codex.version, '2.5.0');
      expect(codex.runtime, 'Node 22.11');
      expect(codex.canSignOut, isTrue);
      expect(codex.canStartChats, isTrue);
      // Codex gets the probe's default wait for the push; nothing else waits.
      expect(probe.calls.single, ('codex', null));
    });

    test('codex with the push saying none needs sign-in', () async {
      probe.results['codex'] = _codexProbe.copyWith(
        authStatus: const AcpAuthStatus(kind: 'none', label: 'Not logged in'),
      );
      // The push wins over the files.
      Directory(p.join(home.path, '.codex')).createSync();
      File(p.join(home.path, '.codex', 'auth.json')).writeAsStringSync('{}');
      final repository = newRepository();

      await repository.refresh('codex');

      expect(agentOf(repository, 'codex').status, AgentStatus.needsLogin);
      expect(agentOf(repository, 'codex').account, isNull);
    });

    test('codex falls back to auth.json', () async {
      probe.results['codex'] = _codexProbe;
      Directory(p.join(home.path, '.codex')).createSync();
      File(p.join(home.path, '.codex', 'auth.json')).writeAsStringSync('{}');
      final repository = newRepository();

      await repository.refresh('codex');

      expect(agentOf(repository, 'codex').status, AgentStatus.ready);
    });

    test('codex falls back to a key variable', () async {
      probe.results['codex'] = _codexProbe;
      final repository = newRepository(
        shell: const ShellEnvironment(<String, String>{'PATH': '/bin', 'OPENAI_API_KEY': 'k'}),
      );

      await repository.refresh('codex');

      final codex = agentOf(repository, 'codex');
      expect(codex.status, AgentStatus.ready);
      expect(codex.account, 'OPENAI_API_KEY');
      final key = codex.methods.firstWhere((m) => m.id == 'api-key');
      expect(key.kind, AgentLoginKind.apiKey);
      expect(key.keyVariables, <String>['CODEX_API_KEY', 'OPENAI_API_KEY']);
      expect(key.keyPresent, isTrue);
    });

    test('codex without push, files or key needs sign-in', () async {
      probe.results['codex'] = _codexProbe;
      final repository = newRepository();

      await repository.refresh('codex');

      final codex = agentOf(repository, 'codex');
      expect(codex.status, AgentStatus.needsLogin);
      expect(codex.methods, const <AgentLoginMethod>[
        AgentLoginMethod(id: 'chat-gpt', name: 'Login with ChatGPT', kind: AgentLoginKind.browser),
        AgentLoginMethod(
          id: 'api-key',
          name: 'Use OPENAI_API_KEY',
          kind: AgentLoginKind.apiKey,
          keyVariables: <String>['CODEX_API_KEY', 'OPENAI_API_KEY'],
        ),
      ]);
    });

    test('gemini needs sign-in without creds or key', () async {
      probe.results['gemini'] = _geminiProbe;
      final repository = newRepository();

      await repository.refresh('gemini');

      final gemini = agentOf(repository, 'gemini');
      expect(gemini.status, AgentStatus.needsLogin);
      expect(gemini.canSignOut, isFalse);
      expect(gemini.methods.map((m) => (m.id, m.kind)), <(String, AgentLoginKind)>[
        ('oauth-personal', AgentLoginKind.browser),
        ('gemini-api-key', AgentLoginKind.apiKey),
        ('vertex-ai', AgentLoginKind.unsupported),
        ('gateway', AgentLoginKind.unsupported),
      ]);
      final key = gemini.methods[1];
      expect(key.keyVariables, <String>['GEMINI_API_KEY']);
      expect(key.keyPresent, isFalse);
      expect(probe.calls.single, ('gemini', Duration.zero));
    });

    test('vertex-ai is unsupported', () async {
      probe.results['gemini'] = _geminiProbe;
      final repository = newRepository();

      await repository.refresh('gemini');

      final vertex = agentOf(repository, 'gemini').methods.firstWhere((m) => m.id == 'vertex-ai');
      expect(vertex.kind, AgentLoginKind.unsupported);
      expect(vertex.name, 'Vertex AI');
    });

    test('gemini signed in with oauth_creds.json', () async {
      probe.results['gemini'] = _geminiProbe;
      Directory(p.join(home.path, '.gemini')).createSync();
      File(p.join(home.path, '.gemini', 'oauth_creds.json')).writeAsStringSync('{}');
      final repository = newRepository();

      await repository.refresh('gemini');

      expect(agentOf(repository, 'gemini').status, AgentStatus.ready);
    });

    test('gemini signed in with GEMINI_API_KEY', () async {
      probe.results['gemini'] = _geminiProbe;
      final repository = newRepository(
        shell: const ShellEnvironment(<String, String>{'PATH': '/bin', 'GEMINI_API_KEY': 'k'}),
      );

      await repository.refresh('gemini');

      final gemini = agentOf(repository, 'gemini');
      expect(gemini.status, AgentStatus.ready);
      expect(gemini.account, 'GEMINI_API_KEY');
      expect(gemini.methods.firstWhere((m) => m.id == 'gemini-api-key').keyPresent, isTrue);
    });

    test('custom agent is ready with the first-chat hint', () async {
      const mine = AgentDefinition(
        id: 'custom:1',
        displayName: 'Mine',
        executable: '/opt/mine',
        source: AgentSource.custom,
      );
      await useAgents(<AgentDefinition>[...AgentDefinition.builtins, mine]);
      probe.results['custom:1'] = const AgentProbeResult(
        version: '0.1.0',
        authMethods: <AcpAuthMethod>[AcpAuthMethod(id: 'login', name: 'Log in')],
      );
      final repository = newRepository();

      await repository.refresh('custom:1');

      final info = agentOf(repository, 'custom:1');
      expect(info.name, 'Mine');
      expect(info.source, AgentSource.custom);
      expect(info.status, AgentStatus.ready);
      expect(info.signInCheckedInChat, isTrue);
      expect(info.custom, const CustomAgentDraft(name: 'Mine', executable: '/opt/mine'));
      expect(info.methods.single.kind, AgentLoginKind.browser);
      expect(info.runtime, isNull);
      expect(agentOf(repository, 'codex').signInCheckedInChat, isFalse);
    });

    test('a failed probe is failed with its reason', () async {
      probe.results['codex'] = const AgentProbeResult(failure: 'no ACP answer to initialize');
      final repository = newRepository();

      await repository.refresh('codex');

      final codex = agentOf(repository, 'codex');
      expect(codex.status, AgentStatus.failed);
      expect(codex.problem, 'no ACP answer to initialize');
      expect(codex.canStartChats, isFalse);
    });

    test('a missing agent is not installed with the reason and the hint', () async {
      probe.results['gemini'] = const AgentProbeResult(
        notInstalled: true,
        notInstalledReason: 'Node.js 22+ is required for Gemini CLI but was not found.',
        notInstalledHint: 'Install Node.js 22 or newer (https://nodejs.org)',
      );
      final repository = newRepository();

      await repository.refresh('gemini');

      final gemini = agentOf(repository, 'gemini');
      expect(gemini.status, AgentStatus.notInstalled);
      expect(gemini.problem, contains('Gemini CLI'));
      expect(gemini.hint, contains('Install Node.js'));
    });

    test('a custom agent added while watched shows up and is probed', () async {
      final repository = newRepository();
      final seen = <List<AgentInfo>>[];
      subscriptions.add(repository.watchAgents().listen(seen.add));
      await pumpEventQueue();

      custom.emit(const <AgentDefinition>[
        AgentDefinition(
          id: 'custom:2',
          displayName: 'New one',
          executable: '/opt/new',
          source: AgentSource.custom,
        ),
      ]);
      await pumpEventQueue();

      expect(seen.last.map((a) => a.id), ['claude', 'codex', 'gemini', 'custom:2']);
      expect(seen.last.last.status, AgentStatus.ready);
      expect(probe.calls.map((c) => c.$1), contains('custom:2'));

      custom.emit(const <AgentDefinition>[]);
      await pumpEventQueue();
      expect(seen.last.map((a) => a.id), ['claude', 'codex', 'gemini']);
    });
  });

  group('custom agents', () {
    test('add/update/remove custom delegate', () async {
      final repository = newRepository();
      const draft = CustomAgentDraft(name: 'Mine', executable: '/opt/mine');

      await repository.addCustom(draft);
      await repository.updateCustom('custom:1', draft.copyWith(name: 'Renamed'));
      await repository.removeCustom('custom:1');

      expect(custom.calls, ['add:Mine', 'update:custom:1:Renamed', 'remove:custom:1']);
    });
  });

  test('nothing is busy without chats', () async {
    expect(await newRepository().hasBusyChats('codex'), isFalse);
  });

  test('openSettings is only for Claude', () async {
    await expectLater(newRepository().openSettings('codex'), throwsArgumentError);
  });

  test('logout of an agent that cannot sign out is refused', () async {
    probe.results['gemini'] = _geminiProbe;
    final repository = newRepository();
    await repository.refresh('gemini');

    await expectLater(repository.logout('gemini'), throwsA(isA<UnsupportedError>()));
  });

  group('sign-in with a real agent', () {
    late Directory temp;
    late AgentDefinition fake;

    setUpAll(() async {
      temp = Directory.systemTemp.createTempSync('agents_repository_agent');
      fake = await compileFakeAgent(temp);
    });

    tearDownAll(() => temp.deleteSync(recursive: true));

    late File requests;

    setUp(() => requests = File(p.join(home.path, 'requests.jsonl')));

    AgentDefinition fakeAs(String id, {Map<String, String> environment = const {}}) =>
        AgentDefinition(
          id: id,
          displayName: id,
          executable: fake.executable,
          loginArguments: id == 'claude' ? fake.loginArguments : const <String, List<String>>{},
          environment: <String, String>{'FAKE_AGENT_REQUESTS_FILE': requests.path, ...environment},
        );

    test('browser login goes to authenticate', () async {
      await useAgents(<AgentDefinition>[fakeAs('codex')]);
      final repository = newRepository();

      final login = await repository.login('codex', 'browser-login');

      expect(login, isNull);
      expect(_requests(requests), contains('authenticate'));
      expect(_paramsOf(requests, 'authenticate')['methodId'], 'browser-login');
      // Checked again after the sign-in.
      await _until(() => probe.calls.isNotEmpty);
      expect(probe.calls.single.$1, 'codex');
    });

    test('terminal login goes to hub.login', () async {
      await useAgents(<AgentDefinition>[fakeAs('claude')]);
      final repository = newRepository();

      final login = await repository.login('claude', 'claude-ai-login');

      expect(login, isNotNull);
      expect(await login!.succeeded, isTrue);
      expect(login.output.value.join('\n'), contains('Logged in (--claudeai)'));
      expect(_requests(requests), isNot(contains('authenticate')));
    });

    test('logout of codex calls hub.logout', () async {
      await useAgents(<AgentDefinition>[fakeAs('codex')]);
      probe.results['codex'] = _codexProbe;
      final repository = newRepository();
      await repository.refresh('codex');

      await repository.logout('codex');

      expect(_requests(requests), contains('logout'));
      // Checked once before and once after the sign-out.
      expect(probe.calls.map((c) => c.$1), ['codex', 'codex']);
    });

    test('a second sign-in while one runs joins it; cancel ends both', () async {
      await useAgents(<AgentDefinition>[
        fakeAs('codex', environment: const <String, String>{'FAKE_AGENT_AUTH_HANG': '1'}),
      ]);
      final repository = newRepository();

      final first = repository.login('codex', 'browser-login');
      final second = repository.login('codex', 'api-key');
      final firstFailed = expectLater(first, throwsA(isA<CancellationException>()));
      final secondFailed = expectLater(second, throwsA(isA<CancellationException>()));
      await _until(() => _requests(requests).contains('authenticate'));

      await repository.cancelLogin('codex');

      await firstFailed;
      await secondFailed;
      expect(_requests(requests).where((m) => m == 'authenticate'), hasLength(1));
      // Nothing is checked after a cancelled sign-in, and a new one can start.
      expect(probe.calls, isEmpty);
      final third = repository.login('codex', 'browser-login');
      final thirdFailed = expectLater(third, throwsA(isA<CancellationException>()));
      await _until(() => _requests(requests).where((m) => m == 'authenticate').length == 2);
      await repository.cancelLogin('codex');
      await thirdFailed;
    });

    test('cancelLogin without a sign-in changes nothing', () async {
      await newRepository().cancelLogin('codex');
    });
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
    await repository.refresh('claude');
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
    test('opens the settings file in the editor', () async {
      Directory('${home.path}/.claude').createSync();
      File('${home.path}/.claude/settings.json').writeAsStringSync('{}');

      await newRepository().openSettings('claude');

      expect(calls.single.executable, 'open');
      expect(calls.single.arguments, ['-t', '${home.path}/.claude/settings.json']);
    });

    test('opens the folder when there is no file', () async {
      Directory('${home.path}/.claude').createSync();

      await newRepository().openSettings('claude');

      expect(calls.single.arguments, ['${home.path}/.claude']);
    });

    test('reports a missing folder', () async {
      await expectLater(
        newRepository().openSettings('claude'),
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

    test('kills the whole group of a process that outlives the timeout', () async {
      final dir = Directory.systemTemp.createTempSync('runner_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pidFile = File('${dir.path}/pid');
      // A child and a grandchild, like `npx` and `node`; both outlive the timeout.
      final script = 'sleep 30 & echo \$! > "${pidFile.path}"; sleep 30';

      final run = runProcessKillingOnTimeout('/bin/sh', [
        '-c',
        script,
      ], timeout: const Duration(seconds: 2));
      final expectation = expectLater(run, throwsA(isA<TimeoutException>()));
      final pid = await _readPid(pidFile);
      addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));

      await expectation;

      expect(await _isGone(pid), isTrue);
    });

    test('kills what a finished process left running', () async {
      final dir = Directory.systemTemp.createTempSync('runner_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pidFile = File('${dir.path}/pid');

      final result = await runProcessKillingOnTimeout('/bin/sh', [
        '-c',
        'sleep 30 >/dev/null 2>&1 & echo \$! > "${pidFile.path}"',
      ], timeout: const Duration(seconds: 5));
      final pid = await _readPid(pidFile);
      addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));

      expect(result.exitCode, 0);
      expect(await _isGone(pid), isTrue);
    });
  });
}
