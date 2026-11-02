import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' as acp;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_sign_in.dart';
import 'package:flutter_code_agent/src/common/acp/agent_slot_registry.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

void main() {
  late Directory temp;
  late AgentDefinition compiled;
  late ShellEnvironment environment;
  late List<AgentConnection> connections;
  late List<String> detached;
  late List<String> continued;
  final cleanups = <Future<void> Function()>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_sign_in_test');
    compiled = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() {
    connections = <AgentConnection>[];
    detached = <String>[];
    continued = <String>[];
  });

  tearDown(() async {
    for (final cleanup in cleanups) {
      await cleanup();
    }
    cleanups.clear();
  });

  (AgentSignIn, AgentSlotRegistry) newSignIn({
    Map<String, String> agentEnvironment = const <String, String>{},
  }) {
    final agent = AgentDefinition(
      id: compiled.id,
      displayName: compiled.displayName,
      executable: compiled.executable,
      loginArguments: compiled.loginArguments,
      environment: agentEnvironment,
    );
    final registry = AgentSlotRegistry(
      agents: <String, AgentDefinition>{agent.id: agent},
      connector: (definition, onPermission) async {
        final connection = await AgentConnection.start(
          definition: definition,
          environment: environment,
          onPermissionRequest: onPermission,
          initializeTimeout: const Duration(seconds: 20),
        );
        connections.add(connection);
        return connection;
      },
      isDisposing: () => false,
      isAgentBusy: (_) => false,
      onRemoved: (_) {},
      onDetached: (sessions, reason) async => detached.add(reason),
      onPermission: (slot, generation, context) async =>
          acp.RequestPermissionResponse(outcome: const acp.RequestPermissionOutcomeCancelled()),
      onFrame: (slot, message) {},
      onExit: (slot, generation, code) async {},
    );
    final auth = AgentAuth(environment: environment);
    cleanups.add(() async {
      await registry.dispose();
      await auth.dispose();
    });
    final signIn = AgentSignIn(
      registry: registry,
      auth: auth,
      isDisposing: () => false,
      continueAfterSignIn: (agentId) async => continued.add(agentId),
    );
    return (signIn, registry);
  }

  test('repeated logins share one login and restart the agent once', () async {
    final (signIn, registry) = newSignIn();
    final slot = registry.slotOf(compiled.id);
    await registry.connect(slot);

    final first = await signIn.login(compiled.id, 'claude-ai-login');
    final second = await signIn.login(compiled.id, 'claude-ai-login');

    expect(second, same(first));
    expect(await first.succeeded, isTrue);
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    await pumpEventQueue();
    expect(detached, <String>['Agent restarted after login']);
    expect(continued, <String>[compiled.id]);
  });

  test('authenticate continues the waiting chats on the same connection', () async {
    final (signIn, registry) = newSignIn();
    final slot = registry.slotOf(compiled.id);

    await signIn.authenticate(compiled.id, 'browser-login');

    expect(slot.signIns, 0);
    expect(slot.connection, same(connections.single));
    expect(continued, <String>[compiled.id]);
    expect(detached, isEmpty);
  });

  test('cancelled authenticate closes the connection and continues nothing', () async {
    final (signIn, registry) = newSignIn(
      agentEnvironment: const <String, String>{'FAKE_AGENT_AUTH_HANG': '1'},
    );
    final slot = registry.slotOf(compiled.id);
    final source = acp.CancellationSource();

    final signingIn = signIn.authenticate(compiled.id, 'browser-login', cancel: source.token);
    while (slot.connection == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(slot.signIns, 1, reason: 'the call in flight holds off a restart');
    source.cancel();

    await expectLater(signingIn, throwsA(isA<acp.CancellationException>()));
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(slot.signIns, 0);
    expect(detached, <String>['Sign-in cancelled']);
    expect(continued, isEmpty);
  });

  test('logout signs out and closes the connection', () async {
    final (signIn, registry) = newSignIn();
    final slot = registry.slotOf(compiled.id);

    await signIn.logout(compiled.id);

    expect(slot.signIns, 0);
    expect(slot.connection, isNull);
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(detached, <String>['Signed out']);
    expect(continued, isEmpty);
  });

  test('an unknown agent throws', () async {
    final (signIn, _) = newSignIn();

    await expectLater(signIn.login('nobody', 'claude-ai-login'), throwsStateError);
    await expectLater(signIn.authenticate('nobody', 'browser-login'), throwsStateError);
    await expectLater(signIn.logout('nobody'), throwsStateError);
  });
}
