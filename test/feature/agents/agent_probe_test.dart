import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_agent_binary.dart';

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_probe_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  /// Every connection the probe opened, so tests can check the process is gone.
  late List<AgentConnection> opened;
  late Completer<void> firstOpened;

  setUp(() {
    opened = <AgentConnection>[];
    firstOpened = Completer<void>();
  });

  AgentProbeImpl createProbe({
    Duration timeout = const Duration(seconds: 20),
    Duration authStatusWait = Duration.zero,
  }) => AgentProbeImpl(
    environment: environment,
    timeout: timeout,
    authStatusWait: authStatusWait,
    connect:
        ({
          required definition,
          required environment,
          required onPermissionRequest,
          workingDirectory,
          initializeTimeout = const Duration(seconds: 120),
          abort,
        }) async {
          final connection = await AgentConnection.start(
            definition: definition,
            environment: environment,
            onPermissionRequest: onPermissionRequest,
            workingDirectory: workingDirectory,
            initializeTimeout: initializeTimeout,
            abort: abort,
          );
          opened.add(connection);
          if (!firstOpened.isCompleted) firstOpened.complete();
          return connection;
        },
  );

  /// Reports that the process of [connection] exited.
  Future<void> exited(AgentConnection connection) =>
      connection.exitCode.timeout(const Duration(seconds: 10)).then((_) {});

  AgentDefinition withEnvironment(Map<String, String> variables) => AgentDefinition(
    id: fakeAgent.id,
    displayName: fakeAgent.displayName,
    executable: fakeAgent.executable,
    environment: variables,
  );

  /// An agent that reads stdin and never answers; its pid goes to [pidFile].
  AgentDefinition silentAgent({String pidFile = '/dev/null'}) {
    final script = File(p.join(temp.path, 'silent_agent.sh'))
      ..writeAsStringSync('#!/bin/sh\necho \$\$ > "$pidFile"\ncat >/dev/null\n');
    Process.runSync('chmod', <String>['+x', script.path]);
    return AgentDefinition(id: 'silent', displayName: 'Silent', executable: script.path);
  }

  /// Waits until the process [pid] no longer exists.
  Future<void> expectGone(int pid) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (Process.killPid(pid, ProcessSignal.sigcont)) {
      if (DateTime.now().isAfter(deadline)) fail('process $pid survived');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('ready agent reports version, methods and capabilities', () async {
    final probe = createProbe();
    addTearDown(probe.dispose);

    final result = await probe.probe(fakeAgent);

    expect(result.failure, isNull);
    expect(result.notInstalled, isFalse);
    expect(result.version, '1.0.0');
    expect(result.authMethods.map((method) => method.id), <String>['browser-login', 'api-key']);
    expect(result.authMethods.first.name, 'Browser login');
    expect(result.authMethods.first.apiKeyProvider, isNull);
    expect(result.authMethods.last.apiKeyProvider, 'fake');
    expect(result.loadSession, isTrue);
    expect(result.mcpHttp, isFalse);
    expect(result.mcpSse, isFalse);
    expect(result.systemPrompt, isFalse);
    expect(result.canLogout, isTrue);
    expect(result.authStatus, isNull);
    expect(result.image, isFalse);
  });

  test('promptCapabilities.image is read', () async {
    final probe = createProbe();
    addTearDown(probe.dispose);

    final result = await probe.probe(withEnvironment(<String, String>{'FAKE_AGENT_IMAGE': '1'}));

    expect(result.failure, isNull);
    expect(result.image, isTrue);
  });

  test('auth status notification is read, without the account', () async {
    final probe = createProbe(authStatusWait: const Duration(seconds: 10));
    addTearDown(probe.dispose);

    final result = await probe.probe(
      withEnvironment(<String, String>{'FAKE_AGENT_AUTH_STATUS': 'account:ChatGPT Plus'}),
    );

    expect(result.authStatus, const AcpAuthStatus(kind: 'account', label: 'ChatGPT Plus'));
    expect(result.authStatus.toString(), isNot(contains('example.com')));
  });

  test('a per-call auth status wait replaces the default', () async {
    // Without a push, the default wait would hold the probe for 30 seconds.
    final probe = createProbe(authStatusWait: const Duration(seconds: 30));
    addTearDown(probe.dispose);
    final stopwatch = Stopwatch()..start();

    final result = await probe.probe(fakeAgent, authStatusWait: Duration.zero);

    expect(result.failure, isNull);
    expect(result.authStatus, isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('missing executable is not installed with its reason', () async {
    final probe = createProbe();
    addTearDown(probe.dispose);

    final result = await probe.probe(
      const AgentDefinition(id: 'x', displayName: 'X', executable: 'no-such-agent-binary'),
    );

    expect(result.notInstalled, isTrue);
    expect(result.notInstalledReason, contains('no-such-agent-binary'));
    expect(result.failure, isNull);
  });

  test('old Node is not installed with the hint', () async {
    final probe = createProbe();
    addTearDown(probe.dispose);

    final result = await probe.probe(
      const AgentDefinition(id: 'x', displayName: 'X', executable: 'npx', minimumNodeMajor: 999),
    );

    expect(result.notInstalled, isTrue);
    expect(result.notInstalledReason, contains('Node.js 999'));
    expect(result.notInstalledHint, contains('Node.js 999'));
    expect(result.failure, isNull);
  });

  test('silent agent times out as "no ACP answer to initialize"', () async {
    final probe = createProbe(timeout: const Duration(milliseconds: 700));
    addTearDown(probe.dispose);

    final pidFile = File(p.join(temp.path, 'timeout.pid'));
    final result = await probe.probe(silentAgent(pidFile: pidFile.path));

    expect(result.failure, 'no ACP answer to initialize');
    expect(result.notInstalled, isFalse);
    await expectGone(int.parse(pidFile.readAsStringSync().trim()));
  });

  test('the probe process is gone afterwards', () async {
    final probe = createProbe();
    addTearDown(probe.dispose);

    await probe.probe(fakeAgent);

    expect(opened, hasLength(1));
    expect(opened.single.isAlive, isFalse);
    await exited(opened.single);
  });

  test('dispose closes a probe in flight', () async {
    final probe = createProbe(authStatusWait: const Duration(seconds: 30));

    final running = probe.probe(fakeAgent);
    await firstOpened.future;
    await probe.dispose();
    await running.timeout(const Duration(seconds: 10));

    await exited(opened.single);
  });

  test('dispose stops an agent that is still starting', () async {
    final probe = createProbe(timeout: const Duration(seconds: 30));

    final pidFile = File(p.join(temp.path, 'silent.pid'));
    final running = probe.probe(silentAgent(pidFile: pidFile.path));
    final started = DateTime.now().add(const Duration(seconds: 10));
    while (!pidFile.existsSync() || pidFile.readAsStringSync().trim().isEmpty) {
      if (DateTime.now().isAfter(started)) fail('the silent agent did not start');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final pid = int.parse(pidFile.readAsStringSync().trim());
    await probe.dispose();
    final result = await running.timeout(const Duration(seconds: 10));

    expect(result.failure, isNotNull);
    expect(opened, isEmpty);
    await expectGone(pid);
  });

  test('probe after dispose fails without starting anything', () async {
    final probe = createProbe();
    await probe.dispose();

    final result = await probe.probe(fakeAgent);

    expect(result.failure, 'probe disposed');
    expect(opened, isEmpty);
  });
}
