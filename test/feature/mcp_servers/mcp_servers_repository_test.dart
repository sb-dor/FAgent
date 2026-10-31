import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';

McpServerDraft stdio(String name) =>
    McpServerDraft(name: name, transport: McpTransport.stdio, command: 'npx', args: ['-y', name]);

Matcher problem(McpServerProblem expected) =>
    isA<InvalidMcpServerException>().having((e) => e.problem, 'problem', expected);

void main() {
  late AppDatabase database;
  late McpServersRepositoryImpl repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = McpServersRepositoryImpl(database: database);
  });
  tearDown(() => database.close());

  Future<int> insertProject([String path = '/work/app']) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: path, name: 'app'));

  Future<List<McpServer>> servers() => repository.watchServers().first;

  test('built-ins come first', () async {
    final list = await servers();
    expect(list.map((s) => s.id), ['builtin:app', 'builtin:dart']);
    expect(list.every((s) => s.builtin && s.enabled && s.isPreview), isTrue);
    expect(list.first.name, 'flutter_code_agent');
    expect(list.first.toolCount, 9);
    expect(list.last.name, 'Dart MCP');
    expect(list.last.command, 'dart');
    expect(list.last.args, ['mcp-server']);
    expect(list.last.toolCount, 18);
    expect(list.every((s) => s.status == McpStatus.ready), isTrue);
  });

  test('add, disable in a project, remove', () async {
    final project = await insertProject();
    final added = await repository.add(stdio('figma-local'));
    expect(added.id, 'user:1');
    expect(added.status, McpStatus.unknown);
    expect(added.toolCount, isNull);
    expect((await servers()).map((s) => s.id), ['builtin:app', 'builtin:dart', 'user:1']);

    await repository.setEnabled('user:1', enabled: false, projectId: project);
    expect((await servers()).last.disabledIn, {project});
    await repository.setEnabled('user:1', enabled: true, projectId: project);
    expect((await servers()).last.disabledIn, isEmpty);

    await repository.setEnabled('user:1', enabled: false, projectId: project);
    await repository.setEnabled('user:1', enabled: false);
    expect((await servers()).last.enabled, isFalse);

    await repository.remove('user:1');
    expect((await servers()).map((s) => s.id), ['builtin:app', 'builtin:dart']);
    expect(await database.select(database.mcpServerStatesTable).get(), isEmpty);
  });

  test('built-ins only switch per project', () async {
    final project = await insertProject();
    expect(
      () => repository.setEnabled('builtin:dart', enabled: false),
      throwsA(isA<ArgumentError>()),
    );
    await repository.setEnabled('builtin:dart', enabled: false, projectId: project);
    expect((await servers()).last.disabledIn, {project});
    expect(() => repository.remove('builtin:app'), throwsA(isA<ArgumentError>()));
  });

  test('names are checked', () async {
    await repository.add(stdio('figma'));
    expect(() => repository.add(stdio('Figma')), throwsA(problem(McpServerProblem.duplicateName)));
    expect(() => repository.add(stdio('dart')), throwsA(problem(McpServerProblem.invalidName)));
    expect(
      () => repository.add(stdio('flutter_code_agent')),
      throwsA(problem(McpServerProblem.invalidName)),
    );
    expect(() => repository.add(stdio('a b')), throwsA(problem(McpServerProblem.invalidName)));
    expect(
      () => repository.add(
        const McpServerDraft(name: 'x', transport: McpTransport.http, url: 'ftp://x'),
      ),
      throwsA(problem(McpServerProblem.invalidUrl)),
    );
    expect(
      () => repository.add(const McpServerDraft(name: 'y', transport: McpTransport.stdio)),
      throwsA(problem(McpServerProblem.missingCommand)),
    );
  });

  test('import skips taken names and keeps existing ones', () async {
    await repository.add(stdio('figma'));
    final dir = Directory.systemTemp.createTempSync('mcp_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/.mcp.json')
      ..writeAsStringSync(
        '{"mcpServers": {"figma": {"command": "other"}, "linear": {"url": "https://mcp.linear.app/mcp"}}}',
      );

    final result = await repository.importMcpJson(file.path);
    expect(result.added, ['linear']);
    expect(result.skipped, contains(('figma', 'name is taken')));
    final list = await servers();
    expect(list.where((s) => !s.builtin).map((s) => s.name), ['figma', 'linear']);
    expect(list.firstWhere((s) => s.name == 'figma').command, 'npx');
    expect(list.firstWhere((s) => s.name == 'linear').transport, McpTransport.http);
  });

  test('deleting a project drops its states', () async {
    final project = await insertProject();
    await repository.setEnabled('builtin:app', enabled: false, projectId: project);
    expect((await servers()).first.disabledIn, {project});
    await (database.delete(database.projectsTable)..where((p) => p.id.equals(project))).go();
    expect((await servers()).first.disabledIn, isEmpty);
  });

  test('the stream follows changes and a cancelled listener leaves nothing behind', () async {
    final stream = repository.watchServers();
    final seen = <int>[];
    final subscription = stream.listen((list) => seen.add(list.length));
    await pumpEventQueue();
    await repository.add(stdio('a'));
    await pumpEventQueue();
    expect(seen.last, 3);
    await subscription.cancel();
  });
}
