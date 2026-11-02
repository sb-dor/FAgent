import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_mcp_probe.dart';
import '../../support/stub_app_mcp_server.dart';

McpServerDraft stdio(String name) =>
    McpServerDraft(name: name, transport: McpTransport.stdio, command: 'npx', args: ['-y', name]);

Matcher problem(McpServerProblem expected) =>
    isA<InvalidMcpServerException>().having((e) => e.problem, 'problem', expected);

void main() {
  late AppDatabase database;
  late McpServersRepositoryImpl repository;
  late StubAppMcpServer appServer;
  late ScriptedMcpProbe probe;
  late Directory sdk;
  String? flutter;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    appServer = StubAppMcpServer(url: Uri.parse('http://127.0.0.1:4321/mcp'));
    probe = ScriptedMcpProbe();
    sdk = Directory.systemTemp.createTempSync('mcp_servers_sdk');
    File(p.join(sdk.path, 'bin', 'flutter')).createSync(recursive: true);
    File(p.join(sdk.path, 'bin', 'dart')).createSync(recursive: true);
    flutter = p.join(sdk.path, 'bin', 'flutter');
    repository = McpServersRepositoryImpl(
      database: database,
      appServer: appServer,
      probe: probe,
      flutterSdk: FakeFlutterSdkRepositoryImpl(which: (_) => flutter, step: Duration.zero),
    );
  });
  tearDown(() async {
    await database.close();
    sdk.deleteSync(recursive: true);
  });

  Future<int> insertProject([String path = '/work/app']) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: path, name: 'app'));

  Future<List<McpServer>> servers() => repository.watchServers().first;

  test('built-ins come first and are real, not previews', () async {
    final list = await servers();
    expect(list.map((s) => s.id), ['builtin:app', 'builtin:dart']);
    expect(list.every((s) => s.builtin && s.enabled && !s.isPreview), isTrue);
    expect(list.first.name, 'flutter_code_agent');
    expect(list.last.name, 'Dart MCP');
  });

  group('the app server entry', () {
    test('is an http server on the address the app server listens on', () async {
      final app = (await servers()).first;

      expect(app.transport, McpTransport.http);
      expect(app.url, 'http://127.0.0.1:4321/mcp');
      expect(app.status, McpStatus.ready);
      expect(app.toolCount, 9);
      expect(app.error, isNull);
    });

    test('carries the start error of a server that did not start', () async {
      appServer
        ..url = null
        ..startError = const SocketException('Address already in use');

      final app = (await servers()).first;

      expect(app.status, McpStatus.failed);
      expect(app.error, contains('Address already in use'));
      expect(app.url, isNull);
      expect(app.toolCount, isNull);
    });

    test('is not known before the server was started', () async {
      appServer.url = null;

      final app = (await servers()).first;

      expect(app.status, McpStatus.unknown);
      expect(app.toolCount, isNull);
    });

    test('is never probed: the app knows its own server', () async {
      await repository.check();

      expect(probe.probedIds, isNot(contains('builtin:app')));
    });
  });

  group('the Dart MCP entry', () {
    test('is unknown until the first check looks for the SDK', () async {
      final dart = (await servers()).last;

      expect(dart.status, McpStatus.unknown);
      expect(dart.toolCount, isNull);
    });

    test('is probed with the command a session starts on the SDK of Settings', () async {
      probe.results['builtin:dart'] = const McpProbeConnected(18);

      await repository.check();

      final dart = (await servers()).last;
      expect(probe.probedIds, ['builtin:dart']);
      // The SDK is found through symlinks, like a session does.
      final root = sdk.resolveSymbolicLinksSync();
      expect(dart.command, p.join(root, 'bin', 'dart'));
      expect(dart.args, ['mcp-server', '--flutter-sdk', root, '--disable', 'launch_app,stop_app']);
      expect(dart.status, McpStatus.ready);
      expect(dart.toolCount, 18);
    });

    test('fails with "SDK not found" when Settings has no Flutter SDK', () async {
      flutter = null;

      await repository.check();

      final dart = (await servers()).last;
      expect(probe.probed, isEmpty);
      expect(dart.status, McpStatus.failed);
      expect(dart.error, mcpSdkNotFoundError);
      expect(dart.command, isNull);
    });

    test('fails with "SDK not found" for a flutter that is not an SDK', () async {
      File(p.join(sdk.path, 'bin', 'dart')).deleteSync();

      await repository.check();

      expect((await servers()).last.error, mcpSdkNotFoundError);
    });
  });

  group('checking user servers', () {
    Future<void> add(String name, {bool http = false}) async {
      await repository.add(
        http
            ? McpServerDraft(
                name: name,
                transport: McpTransport.http,
                url: 'https://mcp.example/$name',
              )
            : stdio(name),
      );
    }

    test('shows what the probe found', () async {
      await add('ready');
      await add('broken');
      await add('linear', http: true);
      probe.results.addAll({
        'user:1': const McpProbeConnected(4),
        'user:2': const McpProbeFailed('Timed out'),
        'user:3': const McpProbeNeedsAuth(),
      });

      await repository.check();

      final list = (await servers()).where((s) => !s.builtin).toList();
      expect(list[0].status, McpStatus.ready);
      expect(list[0].toolCount, 4);
      expect(list[1].status, McpStatus.failed);
      expect(list[1].error, 'Timed out');
      expect(list[1].toolCount, isNull);
      expect(list[2].status, McpStatus.needsAuth);
    });

    test('a server is unknown until it is checked', () async {
      await add('fresh');

      expect((await servers()).last.status, McpStatus.unknown);
    });

    test('check(id) probes only that server', () async {
      await add('a');
      await add('b');

      await repository.check(id: 'user:2');

      expect(probe.probedIds, ['user:2']);
    });

    test('a server that is switched off everywhere is not probed and shows no status', () async {
      await add('on');
      await add('off');
      probe.fallback = const McpProbeConnected(2);
      await repository.check();
      await repository.setEnabled('user:2', enabled: false);
      probe.probed.clear();

      await repository.check();

      expect(probe.probedIds, ['builtin:dart', 'user:1']);
      expect((await servers()).last.status, McpStatus.unknown);
    });

    test('a server switched off in a project is still probed', () async {
      final project = await insertProject();
      await add('on');
      await repository.setEnabled('user:1', enabled: false, projectId: project);

      await repository.check(id: 'user:1');

      expect(probe.probedIds, ['user:1']);
    });

    test('an unknown id is ignored', () async {
      await repository.check(id: 'user:99');
      await repository.check(id: 'builtin:app');

      expect(probe.probed, isEmpty);
    });

    test('a check that is running is not started twice', () async {
      await add('slow');
      probe.held.add('user:1');

      final first = repository.check(id: 'user:1');
      final second = repository.check(id: 'user:1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      probe.release('user:1');
      await Future.wait([first, second]);

      expect(probe.probedIds, ['user:1']);
    });

    test('the watched list updates when a probe finishes', () async {
      await add('slow');
      probe.held.add('user:1');
      probe.results['user:1'] = const McpProbeConnected(7);
      final seen = <McpStatus>[];
      final subscription = repository.watchServers().listen((list) => seen.add(list.last.status));
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final check = repository.check(id: 'user:1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.last, McpStatus.unknown);
      probe.release('user:1');
      await check;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen.last, McpStatus.ready);
    });

    test('removing a server forgets its result', () async {
      await add('gone');
      probe.fallback = const McpProbeConnected(1);
      await repository.check();

      await repository.remove('user:1');
      await add('again');

      expect((await servers()).last.status, McpStatus.unknown);
    });
  });

  test('add, disable in a project, remove', () async {
    final project = await insertProject();
    final added = await repository.add(stdio('figma-local'));
    expect(added.id, 'user:1');
    expect(added.status, McpStatus.unknown);
    expect(added.isPreview, isFalse);
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
    // A refusal is a failed Future, not a synchronous throw.
    await expectLater(
      repository.add(stdio('Figma')),
      throwsA(problem(McpServerProblem.duplicateName)),
    );
    await expectLater(
      repository.setEnabled('builtin:dart', enabled: false),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(repository.remove('builtin:app'), throwsA(isA<ArgumentError>()));
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

  test('import reports a file it cannot read as a McpJsonException', () async {
    final dir = Directory.systemTemp.createTempSync('mcp_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final binary = File('${dir.path}/binary.json')..writeAsBytesSync([0xff, 0xfe, 0xfd]);

    await expectLater(
      repository.importMcpJson('${dir.path}/missing.json'),
      throwsA(isA<McpJsonException>()),
    );
    await expectLater(repository.importMcpJson(binary.path), throwsA(isA<McpJsonException>()));
  });

  test('deleting a project drops its states', () async {
    final project = await insertProject();
    await repository.setEnabled('builtin:app', enabled: false, projectId: project);
    expect((await servers()).first.disabledIn, {project});
    await (database.delete(database.projectsTable)..where((p) => p.id.equals(project))).go();
    expect((await servers()).first.disabledIn, isEmpty);
  });

  test('the stream follows changes and stops after cancel', () async {
    final stream = repository.watchServers();
    final seen = <int>[];
    final subscription = stream.listen((list) => seen.add(list.length));
    await pumpEventQueue();
    await repository.add(stdio('a'));
    await pumpEventQueue();
    expect(seen.last, 3);
    await subscription.cancel();
    final count = seen.length;
    await repository.add(stdio('b'));
    await pumpEventQueue();
    expect(seen.length, count);
  });
}
