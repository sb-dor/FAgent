import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/database/database.dart' show ProjectsTableCompanion;
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_server_row.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_mcp_probe.dart';
import '../../support/stub_app_mcp_server.dart';
import '../../support/test_app.dart';

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

McpServersConfigWidgetState _mcp(WidgetTester tester) =>
    McpServersConfigInhWidget.of(tester.element(find.byType(McpServerRow).first));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _pageContent() => find.byKey(const ValueKey<String>('page-content'));

Finder _row(String id) => find.byKey(ValueKey<String>('mcp-row-$id'));

Finder _field(String name) => find.byKey(ValueKey<String>('mcp-field-$name'));

/// Lets the snack bar finish showing, wait out its timer and leave.
Future<void> _expireSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

/// The real repository with the list of servers and the import replaced when a test needs it.
final class _StubServers implements IMcpServersRepository {
  _StubServers(this._inner, {this.servers, this.imported, this.importError});

  final IMcpServersRepository _inner;
  final List<McpServer>? servers;
  final ({List<String> added, List<(String, String)> skipped})? imported;
  final Exception? importError;
  final List<String> importedPaths = <String>[];

  @override
  Stream<List<McpServer>> watchServers() =>
      servers != null ? Stream<List<McpServer>>.value(servers!) : _inner.watchServers();

  @override
  Future<void> check({String? id}) => _inner.check(id: id);

  @override
  Future<McpServer> add(McpServerDraft draft) => _inner.add(draft);

  @override
  Future<void> remove(String id) => _inner.remove(id);

  @override
  Future<void> setEnabled(String id, {required bool enabled, int? projectId}) =>
      _inner.setEnabled(id, enabled: enabled, projectId: projectId);

  @override
  Future<({List<String> added, List<(String, String)> skipped})> importMcpJson(String path) async {
    importedPaths.add(path);
    if (importError != null) throw importError!;
    return imported ?? (added: <String>[], skipped: <(String, String)>[]);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late ScriptedMcpProbe probe;

  Future<List<McpServer>> servers(WidgetTester tester) => tester
      .runAsync(() => dependencies.mcpServersRepository.watchServers().first)
      .then((value) => value!);

  Future<int> addProject(WidgetTester tester, String name) => tester
      .runAsync(
        () => dependencies.database
            .into(dependencies.database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/work/$name', name: name)),
      )
      .then((value) => value!);

  Future<void> openSettings(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
    List<String> projects = const <String>[],
    List<McpServerDraft> own = const <McpServerDraft>[],
    IMcpServersRepository Function(IMcpServersRepository real)? wrap,
    IAppMcpServer? appServer,
    String? flutter = '/opt/flutter/bin/flutter',
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    probe = ScriptedMcpProbe();
    final base = testDependencies(
      appMcpServer: appServer,
      mcpProbe: probe,
      flutterSdkRepository: FakeFlutterSdkRepositoryImpl(
        which: (_) => flutter,
        step: Duration.zero,
      ),
    );
    dependencies = wrap == null
        ? base
        : testDependencies(
            appMcpServer: appServer,
            mcpProbe: probe,
            mcpServersRepository: wrap(base.mcpServersRepository),
          );
    for (final name in projects) {
      await addProject(tester, name);
    }
    for (final draft in own) {
      await tester.runAsync(() => dependencies.mcpServersRepository.add(draft));
    }
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
    _workspace(tester).dataController.openView(WorkspaceView.settings, section: 'mcp');
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  Future<void> fillDialog(
    WidgetTester tester, {
    required String name,
    String? command,
    String? args,
    String? url,
  }) async {
    await tester.enterText(_field('name'), name);
    if (command != null) await tester.enterText(_field('command'), command);
    if (args != null) await tester.enterText(_field('args'), args);
    if (url != null) await tester.enterText(_field('url'), url);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  const stdio = McpServerDraft(name: 'figma-local', transport: McpTransport.stdio, command: 'npx');

  group('the status of the servers', () {
    final running = StubAppMcpServer(url: Uri.parse('http://127.0.0.1:4321/mcp'));

    Finder inRow(String id, Finder matching) => find.descendant(of: _row(id), matching: matching);

    testWidgets('the app server row says where it runs and how many tools it has', (tester) async {
      await openSettings(tester, appServer: running);

      expect(find.text('flutter_code_agent'), findsOneWidget);
      expect(find.text('Dart MCP'), findsOneWidget);
      expect(find.text('built-in'), findsNWidgets(2));
      expect(
        inRow('builtin:app', find.text('Running on 127.0.0.1:4321 · 9 tools')),
        findsOneWidget,
      );
      expect(find.byType(PreviewBadge), findsNothing);
      expect(find.textContaining('Status and tools appear in M3'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the app server row says why the server did not start', (tester) async {
      await openSettings(
        tester,
        appServer: StubAppMcpServer(startError: StateError('Address already in use')),
      );

      expect(
        inRow(
          'builtin:app',
          find.textContaining('Could not start: Bad state: Address already in use'),
        ),
        findsOneWidget,
      );
      expect(inRow('builtin:app', find.textContaining('Running on')), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the Dart MCP row without an SDK says so', (tester) async {
      await openSettings(tester, appServer: running);

      expect(inRow('builtin:dart', find.text('Flutter SDK not found')), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the Dart MCP row shows the command and the tools the probe found', (tester) async {
      final sdk = Directory.systemTemp.createTempSync('mcp_row_sdk');
      addTearDown(() => sdk.deleteSync(recursive: true));
      File('${sdk.path}/bin/flutter').createSync(recursive: true);
      File('${sdk.path}/bin/dart').createSync(recursive: true);
      await openSettings(tester, appServer: running, flutter: '${sdk.path}/bin/flutter');
      probe.results['builtin:dart'] = const McpProbeConnected(18);

      await tester.runAsync(() => dependencies.mcpServersRepository.check());
      await _settle(tester);

      expect(inRow('builtin:dart', find.text('18 tools')), findsOneWidget);
      expect(
        inRow('builtin:dart', find.textContaining('/bin/dart mcp-server --flutter-sdk')),
        findsOneWidget,
      );
      expect(inRow('builtin:dart', find.text('Flutter SDK not found')), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the Dart MCP row without an SDK says so in Russian', (tester) async {
      await openSettings(tester, locale: const Locale('ru'), appServer: running);

      expect(inRow('builtin:dart', find.text('Flutter SDK не найден')), findsOneWidget);
      expect(
        inRow('builtin:app', find.text('Запущен на 127.0.0.1:4321 · 9 инструментов')),
        findsOneWidget,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a connected server shows its tool count and a failed one why', (tester) async {
      await openSettings(
        tester,
        appServer: running,
        own: const <McpServerDraft>[
          stdio,
          McpServerDraft(
            name: 'broken',
            transport: McpTransport.http,
            url: 'https://x.example/mcp',
          ),
        ],
      );
      probe.results['user:1'] = const McpProbeConnected(3);
      probe.results['user:2'] = const McpProbeFailed('Timed out');

      await tester.runAsync(() => dependencies.mcpServersRepository.check());
      await _settle(tester);

      expect(inRow('user:1', find.text('3 tools')), findsOneWidget);
      expect(inRow('user:2', find.text('Not connected: Timed out')), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the dot follows the status', (tester) async {
      McpServer server(int id, McpStatus status) => McpServer(
        id: 'user:$id',
        name: 'srv$id',
        transport: McpTransport.stdio,
        command: 'x',
        status: status,
      );
      await openSettings(
        tester,
        wrap: (real) => _StubServers(
          real,
          servers: <McpServer>[
            server(1, McpStatus.ready),
            server(2, McpStatus.needsAuth),
            server(3, McpStatus.failed),
            server(4, McpStatus.unknown),
          ],
        ),
      );
      final colors = tester.element(_row('user:1')).colors;
      Color dot(String id) {
        final box = tester.widget<DecoratedBox>(
          inRow(
            id,
            find.byWidgetPredicate(
              (w) => w is DecoratedBox && (w.decoration as BoxDecoration).shape == BoxShape.circle,
            ),
          ),
        );
        return (box.decoration as BoxDecoration).color!;
      }

      expect(dot('user:1'), colors.ok);
      expect(dot('user:2'), colors.warn);
      expect(dot('user:3'), colors.danger);
      expect(dot('user:4'), colors.muted);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('opening the section probes the enabled servers', (tester) async {
      await openSettings(tester, own: const <McpServerDraft>[stdio]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));

      // The SDK of Settings is no SDK here, so only the user's server is probed.
      expect(probe.probedIds, ['user:1']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('adding a server probes it', (tester) async {
      await openSettings(tester, appServer: running);
      expect(probe.probedIds, isEmpty);

      await tester.tap(find.text('＋ stdio (command)'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('name'), 'figma-local');
      await tester.enterText(_field('command'), 'npx');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(probe.probedIds, ['user:1']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('switching a server on probes it again, switching it off does not', (tester) async {
      await openSettings(tester, appServer: running, own: const <McpServerDraft>[stdio]);
      probe.probed.clear();
      final switchFinder = inRow('user:1', find.byType(Switch));

      await tester.tap(switchFinder);
      await tester.pump();
      await _settle(tester);
      expect(probe.probedIds, isEmpty);

      await tester.tap(switchFinder);
      await tester.pump();
      await _settle(tester);
      expect(probe.probedIds, ['user:1']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a note says when changes reach the chats', (tester) async {
      await openSettings(tester, appServer: running);

      expect(find.text('Changes apply to new and reopened chats'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the note is in Russian too', (tester) async {
      await openSettings(tester, locale: const Locale('ru'), appServer: running);

      expect(find.text('Изменения применятся к новым и заново открытым чатам'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('tool counts use the Russian plural forms', (tester) async {
    McpServer server(int id, int count) => McpServer(
      id: 'user:$id',
      name: 'srv$id',
      transport: McpTransport.stdio,
      command: 'x',
      toolCount: count,
    );
    await openSettings(
      tester,
      locale: const Locale('ru'),
      wrap: (real) => _StubServers(
        real,
        servers: <McpServer>[server(1, 1), server(2, 2), server(3, 5), server(4, 21)],
      ),
    );

    expect(find.text('1 инструмент'), findsOneWidget);
    expect(find.text('2 инструмента'), findsOneWidget);
    expect(find.text('5 инструментов'), findsOneWidget);
    expect(find.text('21 инструмент'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('adds a stdio server', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('＋ stdio (command)'));
    await tester.pumpAndSettle();
    expect(find.text('Add a stdio server'), findsOneWidget);
    await fillDialog(tester, name: 'figma-local', command: 'npx', args: '-y "@figma/mcp" --stdio');
    await tester.enterText(_field('env'), 'TOKEN=abc\nMODE=dev');
    await submit(tester);

    expect(find.text('Add a stdio server'), findsNothing);
    final saved = (await servers(tester)).singleWhere((s) => s.name == 'figma-local');
    expect(saved.command, 'npx');
    expect(saved.args, <String>['-y', '@figma/mcp', '--stdio']);
    expect(saved.env, <String, String>{'TOKEN': 'abc', 'MODE': 'dev'});
    expect(find.descendant(of: _pageContent(), matching: find.text('figma-local')), findsOneWidget);
    expect(find.textContaining('npx -y @figma/mcp --stdio'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('adds an HTTP server with headers', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('＋ HTTP (URL)'));
    await tester.pumpAndSettle();
    expect(find.text('Add an HTTP server'), findsOneWidget);
    await fillDialog(tester, name: 'remote', url: 'https://mcp.example.com/v1');
    await tester.enterText(_field('headers'), 'Authorization: Bearer xyz');
    await submit(tester);

    final saved = (await servers(tester)).singleWhere((s) => s.name == 'remote');
    expect(saved.transport, McpTransport.http);
    expect(saved.url, 'https://mcp.example.com/v1');
    expect(saved.headers, <String, String>{'Authorization': 'Bearer xyz'});
    expect(find.text('https://mcp.example.com/v1'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('duplicate name stays in the dialog', (tester) async {
    await openSettings(tester, own: const <McpServerDraft>[stdio]);

    await tester.tap(find.text('＋ stdio (command)'));
    await tester.pumpAndSettle();
    await fillDialog(tester, name: 'figma-local', command: 'npx');
    await submit(tester);

    expect(find.text('Add a stdio server'), findsOneWidget);
    expect(find.text('A server with this name already exists.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('A server with this name already exists.'),
      ),
      findsOneWidget,
    );
    expect((await servers(tester)).where((s) => s.name == 'figma-local'), hasLength(1));

    // Editing the name clears the error; another problem is explained under its own field.
    await tester.enterText(_field('name'), 'figma-two');
    await tester.enterText(_field('command'), '  ');
    // The error fades out of the field.
    await tester.pumpAndSettle();
    expect(find.text('A server with this name already exists.'), findsNothing);
    await submit(tester);
    expect(find.text('Enter the command to run.'), findsOneWidget);
    expect(find.text('Add a stdio server'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a bad name or URL is explained under its field', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('＋ HTTP (URL)'));
    await tester.pumpAndSettle();
    await fillDialog(tester, name: 'bad name', url: 'ftp://x');
    await submit(tester);
    expect(find.textContaining('Use 1 to 64 letters'), findsOneWidget);

    await tester.enterText(_field('name'), 'good');
    await tester.pump();
    await submit(tester);
    expect(find.text('Enter a full http:// or https:// address.'), findsOneWidget);
    expect(find.text('Add an HTTP server'), findsOneWidget);

    await tester.enterText(_field('headers'), 'no separator');
    await tester.pump();
    await submit(tester);
    expect(find.text('Each line must look like Name: value.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add an HTTP server'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a user server is switched off globally', (tester) async {
    await openSettings(tester, own: const <McpServerDraft>[stdio]);
    final id = (await servers(tester)).singleWhere((s) => s.name == 'figma-local').id;

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await _settle(tester);

    expect((await servers(tester)).singleWhere((s) => s.id == id).enabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('built-in switches off per project only', (tester) async {
    await openSettings(tester, projects: <String>['shop_app']);
    final shop = (await tester.runAsync(
      () => dependencies.database.select(dependencies.database.projectsTable).getSingle(),
    ))!.id;

    expect(find.descendant(of: _row('builtin:dart'), matching: find.byType(Switch)), findsNothing);
    expect(find.descendant(of: _row('builtin:app'), matching: find.byType(Switch)), findsNothing);
    final button = find.descendant(
      of: _row('builtin:dart'),
      matching: find.byIcon(Icons.folder_off_outlined),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('shop_app'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('shop_app'));
    await tester.pumpAndSettle();
    await _settle(tester);

    final dart = (await servers(tester)).singleWhere((s) => s.id == 'builtin:dart');
    expect(dart.disabledIn, <int>{shop});
    expect((await servers(tester)).singleWhere((s) => s.id == 'builtin:app').disabledIn, isEmpty);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('shop_app'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect((await servers(tester)).singleWhere((s) => s.id == 'builtin:dart').disabledIn, isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the projects menu says when there are no projects', (tester) async {
    await openSettings(tester);
    await tester.tap(
      find.descendant(of: _row('builtin:app'), matching: find.byIcon(Icons.folder_off_outlined)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No projects yet'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('remove asks first', (tester) async {
    await openSettings(tester, own: const <McpServerDraft>[stdio]);
    final remove = find.byIcon(Icons.delete_outline);
    expect(remove, findsOneWidget);
    // Built-in servers cannot be removed.
    expect(
      find.descendant(of: _row('builtin:dart'), matching: find.byIcon(Icons.delete_outline)),
      findsNothing,
    );

    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove the server figma-local?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(find.descendant(of: _pageContent(), matching: find.text('figma-local')), findsOneWidget);
    expect((await servers(tester)).any((s) => s.name == 'figma-local'), isTrue);

    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(find.descendant(of: _pageContent(), matching: find.text('figma-local')), findsNothing);
    expect((await servers(tester)).any((s) => s.name == 'figma-local'), isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a server that needs sign-in offers a button that says M3', (tester) async {
    await openSettings(
      tester,
      wrap: (real) => _StubServers(
        real,
        servers: const <McpServer>[
          McpServer(
            id: 'user:1',
            name: 'linear',
            transport: McpTransport.http,
            url: 'https://mcp.linear.app/mcp',
            status: McpStatus.needsAuth,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Coming in M3'), findsOneWidget);
    await _expireSnackBar(tester);
    await disposeTestApp(tester, dependencies);
  });

  group('import', () {
    testWidgets('tells what was added and what was skipped', (tester) async {
      late _StubServers stub;
      await openSettings(
        tester,
        wrap: (real) => stub = _StubServers(
          real,
          imported: (
            added: <String>['a', 'b'],
            skipped: <(String, String)>[
              ('c', 'name is taken'),
              ('d', 'sse is not supported'),
              ('e', 'invalidUrl'),
              ('f', 'something new'),
            ],
          ),
        ),
      );
      _mcp(tester).pickFile = () async => '/work/.mcp.json';

      await tester.tap(find.text('Import from .mcp.json'));
      await tester.pump();
      await tester.pump();

      expect(stub.importedPaths, <String>['/work/.mcp.json']);
      expect(
        find.text(
          'Added: 2. Skipped: 4 (c: name is taken; d: SSE is not supported; e: invalid URL; '
          'f: invalid entry).',
        ),
        findsOneWidget,
      );
      await _expireSnackBar(tester);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a cancelled picker does nothing', (tester) async {
      late _StubServers stub;
      await openSettings(tester, wrap: (real) => stub = _StubServers(real));
      _mcp(tester).pickFile = () async => null;

      await tester.tap(find.text('Import from .mcp.json'));
      await tester.pump();
      await tester.pump();

      expect(stub.importedPaths, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a file that is not a .mcp.json is explained', (tester) async {
      await openSettings(
        tester,
        wrap: (real) =>
            _StubServers(real, importError: const McpJsonException('no mcpServers object')),
      );
      _mcp(tester).pickFile = () async => '/work/x.json';

      await tester.tap(find.text('Import from .mcp.json'));
      await tester.pump();
      await tester.pump();

      expect(find.text('The file is not a valid .mcp.json'), findsOneWidget);
      expect(find.textContaining('no mcpServers object'), findsNothing);
      await _expireSnackBar(tester);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('another failure is reported with its text', (tester) async {
      await openSettings(
        tester,
        locale: const Locale('ru'),
        wrap: (real) => _StubServers(real, importError: Exception('boom')),
      );
      _mcp(tester).pickFile = () async => '/work/x.json';

      await tester.tap(find.text('Импорт из .mcp.json'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Действие с MCP-сервером не удалось'), findsOneWidget);
      await _expireSnackBar(tester);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('in a narrow page the controls move under the text', (tester) async {
    await openSettings(tester, size: const Size(600, 600), own: const <McpServerDraft>[stdio]);

    final row = _row('builtin:dart');
    expect(tester.getSize(row).width, lessThan(SettingsRow.wrapWidth));
    final name = find.descendant(of: row, matching: find.text('Dart MCP'));
    final button = find.descendant(of: row, matching: find.byIcon(Icons.folder_off_outlined));
    expect(tester.getTopLeft(button).dy, greaterThan(tester.getBottomLeft(name).dy));
    expect(tester.takeException(), isNull);
    await disposeTestApp(tester, dependencies);
  });

  group('layout', () {
    for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
      for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            'fits ${size.width.toInt()}×${size.height.toInt()} in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}',
            (tester) async {
              await openSettings(
                tester,
                locale: locale,
                dark: dark,
                size: size,
                own: <McpServerDraft>[
                  McpServerDraft(
                    name: 'a-remote-server-with-a-rather-long-name',
                    transport: McpTransport.http,
                    url:
                        'https://mcp.example-organization.com/very/long/path/to/the/endpoint/'
                        '${'segment/' * 12}?token=${'x' * 80}',
                  ),
                ],
              );
              expect(_pageContent(), findsOneWidget);
              expect(find.byType(McpServerRow), findsNWidgets(3));
              expect(tester.takeException(), isNull);

              await tester.ensureVisible(find.text('＋ HTTP (URL)'));
              await tester.tap(find.text('＋ HTTP (URL)'));
              await tester.pumpAndSettle();
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(tester.takeException(), isNull);
              await disposeTestApp(tester, dependencies);
            },
          );
        }
      }
    }
  });
}
