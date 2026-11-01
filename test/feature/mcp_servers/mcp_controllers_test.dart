import 'dart:async';

import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_server_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_servers_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every call and writes down the checks.
final class _Repository implements IMcpServersRepository {
  _Repository({this.checkError});

  final Exception? checkError;
  final List<String?> checks = <String?>[];
  final StreamController<List<McpServer>> servers = StreamController<List<McpServer>>.broadcast();

  Future<void> close() => servers.close();

  @override
  Stream<List<McpServer>> watchServers() => servers.stream;

  @override
  Future<void> check({String? id}) async {
    checks.add(id);
    if (checkError != null) throw checkError!;
  }

  @override
  Future<McpServer> add(McpServerDraft draft) async =>
      McpServer(id: 'user:7', name: draft.name, transport: draft.transport);

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> setEnabled(String id, {required bool enabled, int? projectId}) async {}

  @override
  Future<({List<String> added, List<(String name, String reason)> skipped})> importMcpJson(
    String path,
  ) async => (added: <String>[], skipped: <(String, String)>[]);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  const draft = McpServerDraft(name: 'figma', transport: McpTransport.stdio, command: 'npx');

  group('McpServersController', () {
    test('checks every server when it starts watching', () async {
      final repository = _Repository();
      addTearDown(repository.close);
      final controller = McpServersController(repository: repository)..watch();
      addTearDown(controller.dispose);
      await _settle();

      expect(repository.checks, [null]);
    });

    test('watching again does not check again', () async {
      final repository = _Repository();
      addTearDown(repository.close);
      final controller = McpServersController(repository: repository)
        ..watch()
        ..watch();
      addTearDown(controller.dispose);
      await _settle();

      expect(repository.checks, [null]);
    });

    test('a check that throws does not end the watch', () async {
      final repository = _Repository(checkError: Exception('disk'));
      addTearDown(repository.close);
      final controller = McpServersController(repository: repository)..watch();
      addTearDown(controller.dispose);
      await _settle();

      repository.servers.add(const <McpServer>[]);
      await _settle();

      expect(controller.state, isA<McpServers$CompletedState>());
    });
  });

  group('McpServerActionsController', () {
    late _Repository repository;
    late McpServerActionsController controller;

    setUp(() {
      repository = _Repository();
      controller = McpServerActionsController(repository: repository);
    });
    tearDown(() async {
      controller.dispose();
      await repository.close();
    });

    test('checks a server right after it was added', () async {
      controller.add(draft);
      await _settle();

      expect(repository.checks, ['user:7']);
      expect(controller.state, isA<McpServerActions$CompletedState>());
    });

    test('checks a server that was switched on everywhere', () async {
      controller.setEnabled('user:3', enabled: true);
      await _settle();

      expect(repository.checks, ['user:3']);
    });

    test('does not check a server that was switched off', () async {
      controller.setEnabled('user:3', enabled: false);
      await _settle();

      expect(repository.checks, isEmpty);
    });

    test('does not check when a project switch changes', () async {
      controller.setEnabled('user:3', enabled: true, projectId: 1);
      await _settle();

      expect(repository.checks, isEmpty);
    });

    test('a failing check does not turn the action into a failure', () async {
      controller.dispose();
      await repository.close();
      repository = _Repository(checkError: Exception('disk'));
      controller = McpServerActionsController(repository: repository)..add(draft);
      await _settle();

      expect(controller.state, isA<McpServerActions$CompletedState>());
    });
  });
}
