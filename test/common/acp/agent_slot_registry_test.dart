import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' as acp;
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_slot_registry.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;
  late List<AgentConnection> connections;
  late List<String> removed;
  late List<String> detached;
  late bool busy;
  final registries = <AgentSlotRegistry>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_slot_registry_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() {
    connections = <AgentConnection>[];
    removed = <String>[];
    detached = <String>[];
    busy = false;
  });

  tearDown(() async {
    for (final registry in registries) {
      await registry.dispose();
    }
    registries.clear();
  });

  AgentSlotRegistry newRegistry() {
    final registry = AgentSlotRegistry(
      agents: <String, AgentDefinition>{fakeAgent.id: fakeAgent},
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
      isAgentBusy: (_) => busy,
      onRemoved: removed.add,
      onDetached: (sessions, reason) async => detached.add(reason),
      onPermission: (slot, generation, context) async =>
          acp.RequestPermissionResponse(outcome: const acp.RequestPermissionOutcomeCancelled()),
      onFrame: (slot, message) {},
      onExit: (slot, generation, code) async {},
    );
    registries.add(registry);
    return registry;
  }

  AgentDefinition edited(AgentDefinition agent) => AgentDefinition(
    id: agent.id,
    displayName: agent.displayName,
    executable: agent.executable,
    loginArguments: agent.loginArguments,
    environment: const <String, String>{'EDITED': '1'},
  );

  test('a new id gets a slot', () {
    final registry = newRegistry();
    const other = AgentDefinition(id: 'other', displayName: 'Other', executable: 'other');

    registry.setAgents(<AgentDefinition>[fakeAgent, other]);

    expect(registry.contains('other'), isTrue);
    expect(registry.slotOf('other').definition, other);
    expect(registry.definitions, <AgentDefinition>[fakeAgent, other]);
  });

  test('connect is single-flight and bumps the generation', () async {
    final registry = newRegistry();
    final slot = registry.slotOf(fakeAgent.id);

    final results = await Future.wait(<Future<AgentConnection>>[
      registry.connect(slot),
      registry.connect(slot),
    ]);

    expect(connections, hasLength(1));
    expect(results, everyElement(same(connections.single)));
    expect(slot.generation, 1);
    expect(await registry.connect(slot), same(connections.single));
  });

  test('an equal definition changes nothing', () async {
    final registry = newRegistry();
    final slot = registry.slotOf(fakeAgent.id);
    await registry.connect(slot);

    registry.setAgents(<AgentDefinition>[
      AgentDefinition(
        id: fakeAgent.id,
        displayName: fakeAgent.displayName,
        executable: fakeAgent.executable,
        loginArguments: fakeAgent.loginArguments,
      ),
    ]);
    await pumpEventQueue();

    expect(slot.restartPending, isFalse);
    expect(slot.connection, same(connections.single));
    expect(detached, isEmpty);
  });

  test('a changed definition restarts an idle agent at once', () async {
    final registry = newRegistry();
    final slot = registry.slotOf(fakeAgent.id);
    await registry.connect(slot);
    final generation = slot.generation;

    final next = edited(fakeAgent);
    registry.setAgents(<AgentDefinition>[next]);

    expect(slot.definition, next);
    expect(slot.restartPending, isFalse);
    expect(slot.connection, isNull, reason: 'detached synchronously');
    expect(slot.generation, generation + 1);
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(detached, <String>['Agent settings changed']);
  });

  test('a changed definition waits while the agent is busy', () async {
    final registry = newRegistry();
    final slot = registry.slotOf(fakeAgent.id);
    await registry.connect(slot);
    busy = true;

    registry
      ..setAgents(<AgentDefinition>[edited(fakeAgent)])
      ..scheduleRestartCheck(fakeAgent.id);
    await pumpEventQueue();

    expect(slot.restartPending, isTrue);
    expect(slot.connection, same(connections.single));

    busy = false;
    registry.scheduleRestartCheck(fakeAgent.id);
    expect(slot.connection, isNotNull, reason: 'the check runs in a microtask');
    await pumpEventQueue();

    expect(slot.restartPending, isFalse);
    expect(slot.connection, isNull);
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(detached, <String>['Agent settings changed']);
  });

  test('a missing id is retired and closed', () async {
    final registry = newRegistry();
    final slot = registry.slotOf(fakeAgent.id);
    await registry.connect(slot);

    registry.setAgents(const <AgentDefinition>[]);

    expect(slot.retired, isTrue);
    expect(registry.contains(fakeAgent.id), isFalse);
    expect(() => registry.slotOf(fakeAgent.id), throwsStateError);
    expect(removed, <String>[fakeAgent.id]);
    expect(slot.connection, isNull);
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(detached, <String>['Agent removed']);
  });
}
