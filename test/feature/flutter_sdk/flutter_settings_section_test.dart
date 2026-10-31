import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart' show ProjectsTableCompanion;
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// The fake repository with a project that pins an fvm version; it reads no file.
final class _FvmRepository implements IFlutterSdkRepository {
  _FvmRepository(this._fake);

  final FakeFlutterSdkRepositoryImpl _fake;

  @override
  Future<FlutterSdk> sdkFor(String? projectPath) async =>
      (await _fake.sdkFor(null)).copyWith(fvmVersion: '3.24.0');

  @override
  Future<List<DoctorCheck>> doctor() => _fake.doctor();
}

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

AppSettings _settings(WidgetTester tester) =>
    AppSettingsConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget))).controller.settings;

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

String _composerText(WidgetTester tester) =>
    tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)).textController.text;

FakeFlutterSdkRepositoryImpl _fake({String? path = '/opt/flutter/bin/flutter'}) =>
    FakeFlutterSdkRepositoryImpl(which: (_) => path, step: Duration.zero);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late int projectId;

  /// Opens the Flutter section with a project selected (unless [withProject] is `false`).
  Future<void> openSettings(
    WidgetTester tester, {
    IFlutterSdkRepository? repository,
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
    bool withProject = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dependencies = testDependencies(flutterSdkRepository: repository ?? _fake());
    await tester.runAsync(() async {
      projectId = await dependencies.database
          .into(dependencies.database.projectsTable)
          // The folder does not exist: the fake finds no fvm file in it.
          .insert(ProjectsTableCompanion.insert(path: '/work/none/alpha', name: 'alpha'));
    });
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
    final data = _workspace(tester).dataController;
    if (withProject) data.selectProject(projectId);
    data.openView(WorkspaceView.settings, section: 'flutter');
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the sdk and the project fvm', (tester) async {
    await openSettings(tester, repository: _FvmRepository(_fake()));

    expect(find.text('Flutter SDK'), findsOneWidget);
    expect(find.text('/opt/flutter/bin/flutter'), findsOneWidget);
    expect(find.text('3.27.1 · stable'), findsOneWidget);
    expect(find.text('fvm: 3.24.0'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a project without fvm uses the system sdk', (tester) async {
    await openSettings(tester);

    expect(find.text('System SDK'), findsOneWidget);
    expect(find.textContaining('fvm:'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('missing sdk explains itself', (tester) async {
    await openSettings(tester, repository: _fake(path: null));

    expect(find.text('Flutter SDK not found'), findsOneWidget);
    expect(find.text('Install Flutter or add it to PATH'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('doctor lists the checks', (tester) async {
    await openSettings(tester);
    expect(find.text('Android toolchain'), findsNothing);

    await tester.tap(find.text('Run flutter doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Android toolchain'), findsOneWidget);
    expect(find.text('cmdline-tools component is missing'), findsOneWidget);
    expect(find.text('Channel stable, 3.27.1'), findsOneWidget);
    // Only the check that is not fine can be fixed.
    expect(find.text('Fix with agent'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('doctor fix starts a chat with a draft', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text('Run flutter doctor'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fix with agent'));
    for (var i = 0; i < 5; i++) {
      await _settle(tester);
    }

    final data = _workspace(tester).dataController;
    expect(data.view, WorkspaceView.chat);
    expect(data.projectId, projectId);
    expect(data.sessionId, isNotNull);
    expect(
      _composerText(tester),
      'flutter doctor reports: Android toolchain — cmdline-tools component is missing. '
      'Help me fix it.',
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('without a project the fix button is off', (tester) async {
    await openSettings(tester, withProject: false);
    await tester.tap(find.text('Run flutter doctor'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Fix with agent'), matching: find.byType(OutlinedButton)),
    );
    expect(button.onPressed, isNull);
    expect(find.byTooltip('Open a project to start a chat'), findsOneWidget);
    expect(find.text('Project'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('org is validated', (tester) async {
    await openSettings(tester);
    final field = find.byKey(const ValueKey<String>('flutter-org'));
    expect(find.text('For example, com.example'), findsNothing);

    await tester.enterText(field, 'Com.Example');
    await tester.pump();
    await _settle(tester);
    expect(find.text('For example, com.example'), findsOneWidget);
    expect(_settings(tester).projectOrg, 'com.example');

    await tester.enterText(field, 'dev.avaz');
    await tester.pump();
    await _settle(tester);
    expect(find.text('For example, com.example'), findsNothing);
    expect(_settings(tester).projectOrg, 'dev.avaz');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the template is chosen', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('flutter create'));
    await tester.pump();
    await _settle(tester);

    expect(_settings(tester).projectTemplate, NewProjectTemplate.plain);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('git template and in-app DevTools are previews', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('From git'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Coming in M4'), findsOneWidget);
    expect(_settings(tester).projectTemplate, NewProjectTemplate.architecture);

    ScaffoldMessenger.of(tester.element(find.text('DevTools'))).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('In the app'));
    await tester.pump();
    await _settle(tester);
    expect(find.text('Coming in M2'), findsOneWidget);
    expect(_settings(tester).devToolsTarget, DevToolsTarget.browser);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('DevTools opens in the browser by choice', (tester) async {
    await openSettings(tester);

    await tester.tap(find.text('In the browser'));
    await tester.pump();
    await _settle(tester);

    expect(_settings(tester).devToolsTarget, DevToolsTarget.browser);
    expect(find.textContaining('Coming in'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
    for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('fits ${size.width.toInt()}×${size.height.toInt()} in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}', (tester) async {
          await openSettings(
            tester,
            repository: _FvmRepository(_fake()),
            locale: locale,
            dark: dark,
            size: size,
          );
          await tester.tap(find.byKey(const ValueKey<String>('flutter-doctor-run')));
          await tester.pump();
          await tester.pump();

          expect(find.byKey(const ValueKey<String>('page-content')), findsOneWidget);
          expect(find.byType(OutlinedButton), findsWidgets);
          expect(tester.takeException(), isNull);
          await disposeTestApp(tester, dependencies);
        });
      }
    }
  }
}
