import 'dart:async';
import 'dart:io' as io;
import 'dart:io' show FileSystemException;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_fields.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_project_creation_repository.dart';
import '../../support/test_app.dart';

const _name = ValueKey<String>('new-project-name');
const _org = ValueKey<String>('new-project-org');
const _applicationId = ValueKey<String>('new-project-application-id');

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// A repository whose target checks answer when the test says so.
final class _SlowTargets with CreateOnlyProjectCreation {
  final Map<String, Completer<TargetProblem?>> answers = <String, Completer<TargetProblem?>>{};

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) =>
      (answers[name] = Completer<TargetProblem?>()).future;

  @override
  Stream<CreationRun> create(NewProjectRequest request) => const Stream.empty();
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// A repository whose default folder arrives when the test says so.
final class _SlowParent with CreateOnlyProjectCreation {
  final Completer<String> parent = Completer<String>();

  @override
  Future<String> defaultParent() => parent.future;

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Stream<CreationRun> create(NewProjectRequest request) => const Stream.empty();
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// A repository whose folder questions fail like an unreadable (protected) parent does:
/// [checkTarget] throws for every name but `fine`.
final class _FailingFolders with CreateOnlyProjectCreation {
  _FailingFolders({this.failDefaultParent = false});

  final bool failDefaultParent;

  @override
  Future<String> defaultParent() async {
    if (failDefaultParent) throw const FileSystemException('Permission denied');
    return '/Users/test/StudioProjects';
  }

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async {
    if (name != 'fine') throw const FileSystemException('Permission denied');
    return null;
  }

  @override
  Stream<CreationRun> create(NewProjectRequest request) => const Stream.empty();
  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryProjectCreationRepository memory;

  /// Opens the "＋ Project" menu of the sidebar and picks "New Flutter project…".
  Future<void> openFromMenu(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    final ru = locale.languageCode == 'ru';
    await tester.tap(find.text(ru ? 'Проект' : 'Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ru ? 'Новый Flutter-проект…' : 'New Flutter project…'));
    await tester.pumpAndSettle();
  }

  /// Shows the window and opens the dialog through the sidebar menu.
  Future<void> openDialog(
    WidgetTester tester, {
    String? sdkPath = '/opt/flutter/bin/flutter',
    String dartVersion = '3.14.0',
    String? flutterVersion = '3.50.0',
    Future<void>? versionAnswered,
    String? org,
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
    Future<String?> Function(String)? pickFolder,
    IProjectCreationRepository? repository,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    memory = MemoryProjectCreationRepository(
      existing: const <String>{'/Users/test/StudioProjects/taken'},
    );
    dependencies = testDependencies(
      projectCreationRepository: repository ?? memory,
      flutterSdkRepository: FlutterSdkRepositoryImpl(
        which: (_) => sdkPath,
        runProcess: (executable, arguments, {environment}) async {
          await versionAnswered;
          return io.ProcessResult(
            1,
            0,
            '{${flutterVersion == null ? '' : '"frameworkVersion":"$flutterVersion",'}'
                '"channel":"stable","dartSdkVersion":"$dartVersion (build)"}',
            '',
          );
        },
      ),
    );
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
    if (org != null) {
      AppSettingsConfigInhWidget.of(tester.element(find.byType(WorkspaceConfigWidget))).controller
          .update((s) => s.copyWith(projectOrg: org));
      await _settle(tester);
    }
    if (pickFolder != null) _workspace(tester).pickFolder = pickFolder;
    await openFromMenu(tester, locale: locale);
  }

  Future<void> typeName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(_name), name);
    await tester.pumpAndSettle();
  }

  Finder createButton() => find.byKey(const ValueKey<String>('new-project-create'));

  bool canCreate(WidgetTester tester) =>
      tester.widget<FilledButton>(createButton()).onPressed != null;

  bool checked(WidgetTester tester, String key) => tester
      .widget<Checkbox>(
        find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(Checkbox)),
      )
      .value!;

  bool platformOn(WidgetTester tester, FlutterPlatform platform) => find
      .descendant(
        of: find.byKey(ValueKey<String>('platform-${platform.name}')),
        matching: find.byIcon(Icons.check),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('opens from the sidebar with defaults', (tester) async {
    await openDialog(tester);

    expect(find.byType(NewProjectDialog), findsOneWidget);
    expect(find.text('New Flutter project'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_applicationId)).controller!.text, 'com.example.');
    expect(find.byKey(_org), findsNothing);
    expect(find.text('/Users/test/StudioProjects/'), findsOneWidget);
    expect(platformOn(tester, FlutterPlatform.ios), isTrue);
    expect(platformOn(tester, FlutterPlatform.android), isTrue);
    expect(platformOn(tester, FlutterPlatform.macos), isTrue);
    expect(platformOn(tester, FlutterPlatform.web), isFalse);
    expect(platformOn(tester, FlutterPlatform.windows), isFalse);
    expect(platformOn(tester, FlutterPlatform.linux), isFalse);
    expect(find.text('My architecture'), findsOneWidget);
    expect(find.text('Plain flutter create'), findsOneWidget);
    expect(find.text('From a git template…'), findsOneWidget);
    expect(checked(tester, 'new-project-git'), isTrue);
    expect(checked(tester, 'new-project-chat'), isTrue);
    expect(find.text('Flutter 3.50.0'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    // Nothing is wrong on an empty form.
    expect(find.text('Choose at least one platform'), findsNothing);
    expect(find.textContaining('Lowercase'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  String applicationIdOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_applicationId)).controller!.text;

  testWidgets('the application ID starts as the org of the settings and follows the name', (
    tester,
  ) async {
    await openDialog(tester, org: 'dev.avaz');
    expect(applicationIdOf(tester), 'dev.avaz.');
    // Nothing is wrong before a name.
    expect(find.text('For example, com.example.my_app'), findsNothing);

    await typeName(tester, 'avera_booking');
    expect(applicationIdOf(tester), 'dev.avaz.avera_booking');
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a typed application ID no longer follows the name and goes whole', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    await tester.enterText(find.byKey(_applicationId), 'tj.avera.booking');
    await tester.pumpAndSettle();

    await typeName(tester, 'avera_shop');
    expect(applicationIdOf(tester), 'tj.avera.booking');
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    final request = memory.requests.single;
    expect(request.name, 'avera_shop');
    expect(request.org, 'tj.avera');
    expect(request.applicationId, 'tj.avera.booking');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a bad application ID blocks creation and leaves the settings alone', (
    tester,
  ) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    expect(canCreate(tester), isTrue);

    for (final bad in const <String>['Com.Example.App', 'booking', 'com.example.', 'com.1x.app']) {
      await tester.enterText(find.byKey(_applicationId), bad);
      await tester.pumpAndSettle();
      expect(find.text('For example, com.example.my_app'), findsOneWidget, reason: bad);
      expect(canCreate(tester), isFalse, reason: bad);
    }

    await tester.enterText(find.byKey(_applicationId), 'dev.avaz.booking');
    await tester.pumpAndSettle();
    expect(find.text('For example, com.example.my_app'), findsNothing);
    expect(canCreate(tester), isTrue);
    expect(
      AppSettingsConfigInhWidget.of(tester.element(find.byType(NewProjectDialog)))
          .controller
          .settings
          .projectOrg,
      'com.example',
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a package asks for the org, not an application ID', (tester) async {
    await openDialog(tester, org: 'dev.avaz');
    await typeName(tester, 'avera_kit');
    await tester.tap(find.text('Package'));
    await tester.pumpAndSettle();

    expect(find.byKey(_applicationId), findsNothing);
    expect(tester.widget<TextField>(find.byKey(_org)).controller!.text, 'dev.avaz');
    await tester.enterText(find.byKey(_org), 'Com.Example');
    await tester.pumpAndSettle();
    expect(find.text('For example, com.example'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    await tester.enterText(find.byKey(_org), 'dev.avaz');
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(memory.requests.single.org, 'dev.avaz');
    expect(memory.requests.single.applicationId, isNull);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('name errors like flutter create', (tester) async {
    await openDialog(tester);

    await typeName(tester, 'My-App');
    expect(
      find.text('Lowercase Latin letters, digits and _ only, not starting with a digit'),
      findsOneWidget,
    );
    expect(find.text('Try "my_app"'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await typeName(tester, 'class');
    expect(find.textContaining('reserved'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await typeName(tester, 'flutter');
    expect(find.textContaining('Flutter dependency'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await typeName(tester, 'avera_booking');
    expect(find.textContaining('reserved'), findsNothing);
    expect(find.textContaining('Flutter dependency'), findsNothing);
    expect(find.textContaining('Lowercase'), findsNothing);
    expect(canCreate(tester), isTrue);

    // Emptied again: no error text, but nothing to create.
    await typeName(tester, '');
    expect(find.textContaining('Lowercase'), findsNothing);
    expect(canCreate(tester), isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('existing folder blocks creation', (tester) async {
    await openDialog(tester);

    await typeName(tester, 'taken');

    expect(find.text('The folder already exists'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('picked folder becomes the parent', (tester) async {
    String? asked;
    await openDialog(
      tester,
      pickFolder: (confirm) async {
        asked = confirm;
        return '/tmp/elsewhere';
      },
    );
    await typeName(tester, 'avera_booking');
    expect(find.text('/Users/test/StudioProjects/avera_booking'), findsOneWidget);

    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();

    expect(asked, 'Choose');
    expect(find.text('/tmp/elsewhere/avera_booking'), findsOneWidget);
    expect(find.text('/Users/test/StudioProjects/avera_booking'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a folder that was picked is checked again', (tester) async {
    await openDialog(tester, pickFolder: (_) async => '/Users/test/StudioProjects');
    await typeName(tester, 'taken');
    expect(canCreate(tester), isFalse);

    // The name moves away from the taken one: the check follows the change.
    await typeName(tester, 'free');
    expect(find.text('The folder already exists'), findsNothing);
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the latest answer of the target check wins', (tester) async {
    final slow = _SlowTargets();
    await openDialog(tester, repository: slow);

    await typeName(tester, 'first');
    await typeName(tester, 'second');
    // Not known yet: nothing can be created.
    expect(canCreate(tester), isFalse);

    slow.answers['second']!.complete(null);
    await tester.pumpAndSettle();
    expect(canCreate(tester), isTrue);

    // The old answer arrives late and is dropped.
    slow.answers['first']!.complete(TargetProblem.exists);
    await tester.pumpAndSettle();
    expect(find.text('The folder already exists'), findsNothing);
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a folder that cannot be checked blocks creation with a message', (tester) async {
    await openDialog(tester, repository: _FailingFolders());

    await typeName(tester, 'avera_booking');
    expect(find.text('Cannot check this folder'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    expect(tester.takeException(), isNull);

    // A later successful check clears it.
    await typeName(tester, 'fine');
    expect(find.text('Cannot check this folder'), findsNothing);
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a stale failure of the folder check is dropped', (tester) async {
    final slow = _SlowTargets();
    await openDialog(tester, repository: slow);

    await typeName(tester, 'first');
    await typeName(tester, 'second');
    slow.answers['second']!.complete(null);
    await tester.pumpAndSettle();
    slow.answers['first']!.completeError(const FileSystemException('Permission denied'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot check this folder'), findsNothing);
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('without a default folder: a placeholder, then the folder error', (tester) async {
    await openDialog(tester, repository: _FailingFolders(failDefaultParent: true));

    expect(find.text('…'), findsOneWidget);
    expect(find.text('/'), findsNothing);
    expect(find.text('Cannot check this folder'), findsOneWidget);
    await typeName(tester, 'fine');
    expect(canCreate(tester), isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the folder shows a placeholder until the default folder arrives', (tester) async {
    final slow = _SlowParent();
    await openDialog(tester, repository: slow);

    expect(find.text('…'), findsOneWidget);
    expect(find.text('/'), findsNothing);

    slow.parent.complete('/Users/test/StudioProjects');
    await tester.pumpAndSettle();
    expect(find.text('…'), findsNothing);
    expect(find.text('/Users/test/StudioProjects/'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('no platform blocks creation', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    expect(canCreate(tester), isTrue);

    for (final platform in <String>['ios', 'android', 'macos']) {
      await tester.tap(find.byKey(ValueKey<String>('platform-$platform')));
      await tester.pump();
    }

    expect(find.text('Choose at least one platform'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey<String>('platform-web')));
    await tester.pump();
    expect(find.text('Choose at least one platform'), findsNothing);
    expect(canCreate(tester), isTrue);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('missing sdk links to settings', (tester) async {
    await openDialog(tester, sdkPath: null);
    await typeName(tester, 'avera_booking');

    expect(find.text('Flutter SDK not found'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await tester.tap(find.text('Settings → Flutter'));
    await tester.pumpAndSettle();

    expect(find.byType(NewProjectDialog), findsNothing);
    final data = _workspace(tester).dataController;
    expect(data.view, WorkspaceView.settings);
    expect(data.section, 'flutter');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('git template says coming later', (tester) async {
    await openDialog(tester);

    expect(find.text('Coming later'), findsNothing);
    await tester.ensureVisible(find.text('From a git template…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From a git template…'));
    await tester.pump();

    // Shown inline: a SnackBar would sit under the dialog's barrier.
    expect(find.text('Coming later'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.ensureVisible(find.text('My architecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My architecture'));
    await tester.pump();
    expect(find.text('Coming later'), findsNothing);

    await tester.ensureVisible(find.text('From a git template…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From a git template…'));
    await tester.pump();
    expect(find.text('Coming later'), findsOneWidget);
    await typeName(tester, 'avera_booking');
    await tester.tap(createButton());
    await tester.pumpAndSettle();
    expect(memory.requests.single.template, NewProjectTemplate.architecture);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('create starts with the request', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    await tester.tap(find.byKey(const ValueKey<String>('platform-macos')));
    await tester.ensureVisible(find.text('Plain flutter create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain flutter create'));
    // The project type sits above the fields: the switches start below the fold.
    await tester.ensureVisible(find.text('git init + first commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('git init + first commit'));
    await tester.pump();

    await tester.tap(createButton());
    await tester.pumpAndSettle();

    final request = memory.requests.single;
    expect(request.name, 'avera_booking');
    expect(request.org, 'com.example');
    expect(request.applicationId, 'com.example.avera_booking');
    expect(request.parent, '/Users/test/StudioProjects');
    expect(request.platforms, <FlutterPlatform>{FlutterPlatform.ios, FlutterPlatform.android});
    expect(request.template, NewProjectTemplate.plain);
    expect(request.gitInit, isFalse);
    expect(request.openChat, isTrue);
    await disposeTestApp(tester, dependencies);
  });

  CreationTemplateCard card(WidgetTester tester, String key) =>
      tester.widget<CreationTemplateCard>(find.byKey(ValueKey<String>(key)));

  testWidgets('My architecture is on with Flutter 3.50', (tester) async {
    await openDialog(tester);

    expect(card(tester, 'template-architecture').enabled, isTrue);
    expect(card(tester, 'template-architecture').selected, isTrue);
    expect(find.text('Needs Flutter 3.50 or newer'), findsNothing);
    await typeName(tester, 'avera_booking');
    await tester.tap(createButton());
    await tester.pumpAndSettle();
    expect(memory.requests.single.template, NewProjectTemplate.architecture);
    await disposeTestApp(tester, dependencies);
  });

  for (final version in const <String?>['3.47.2', null]) {
    testWidgets(
      'My architecture is off with Flutter ${version ?? 'unknown'}: the empty one is made',
      (tester) async {
        await openDialog(tester, flutterVersion: version);

        expect(card(tester, 'template-architecture').enabled, isFalse);
        expect(card(tester, 'template-architecture').selected, isFalse);
        expect(card(tester, 'template-plain').selected, isTrue);
        expect(find.text('Needs Flutter 3.50 or newer'), findsOneWidget);
        await tester.ensureVisible(find.text('My architecture'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('My architecture'));
        await tester.pump();
        expect(card(tester, 'template-architecture').selected, isFalse);
        await typeName(tester, 'avera_booking');
        await tester.tap(createButton());
        await tester.pumpAndSettle();
        expect(memory.requests.single.template, NewProjectTemplate.plain);
        await disposeTestApp(tester, dependencies);
      },
    );
  }

  testWidgets('while the Flutter version is looked up the chosen template stays', (tester) async {
    final answer = Completer<void>();
    await openDialog(tester, flutterVersion: '3.47.2', versionAnswered: answer.future);

    expect(card(tester, 'template-architecture').selected, isTrue);
    expect(card(tester, 'template-architecture').enabled, isTrue);
    expect(find.text('Needs Flutter 3.50 or newer'), findsNothing);
    await typeName(tester, 'avera_booking');
    expect(canCreate(tester), isFalse);

    answer.complete();
    await tester.pumpAndSettle();
    expect(card(tester, 'template-architecture').enabled, isFalse);
    expect(card(tester, 'template-plain').selected, isTrue);
    expect(find.text('Needs Flutter 3.50 or newer'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the Flutter hint of My architecture is in Russian too', (tester) async {
    await openDialog(tester, flutterVersion: '3.47.2', locale: const Locale('ru'));

    expect(find.text('Нужен Flutter 3.50 или новее'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  const structureKey = ValueKey<String>('new-project-structure');
  const folderKey = ValueKey<String>('new-project-app-folder');
  const packageKey = ValueKey<String>('new-project-app-package');
  String textOf(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller!.text;

  testWidgets('structure row only for an app', (tester) async {
    await openDialog(tester);
    expect(find.byKey(structureKey), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('structure-single')), findsOneWidget);

    await tester.tap(find.text('Package'));
    await tester.pump();

    expect(find.byKey(structureKey), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  const reporterKey = ValueKey<String>('new-project-crash-reporter');
  Finder reporterOption(String label) =>
      find.descendant(of: find.byKey(reporterKey), matching: find.text(label));

  testWidgets('crash reports: three options for My architecture, Sentry first', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');

    expect(find.byKey(reporterKey), findsOneWidget);
    expect(find.text('Crash reports'), findsOneWidget);
    for (final label in const <String>['Sentry', 'Firebase Crashlytics', 'Log only']) {
      expect(reporterOption(label), findsOneWidget, reason: label);
    }
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(memory.requests.single.crashReporter, CrashReporter.sentry);
    await disposeTestApp(tester, dependencies);
  });

  for (final (label, reporter) in const <(String, CrashReporter)>[
    ('Firebase Crashlytics', CrashReporter.crashlytics),
    ('Log only', CrashReporter.logOnly),
  ]) {
    testWidgets('crash reports: the request carries $label', (tester) async {
      await openDialog(tester);
      await typeName(tester, 'avera_booking');

      await tester.ensureVisible(reporterOption(label));
      await tester.tap(reporterOption(label));
      await tester.pumpAndSettle();
      await tester.tap(createButton());
      await tester.pumpAndSettle();

      expect(memory.requests.single.crashReporter, reporter);
      await disposeTestApp(tester, dependencies);
    });
  }

  testWidgets('crash reports: also in a monorepo', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'shop');
    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(reporterOption('Log only'));
    await tester.tap(reporterOption('Log only'));
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(memory.requests.single.crashReporter, CrashReporter.logOnly);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('crash reports: hidden for Empty and for another type', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byKey(const ValueKey<String>('template-plain')));
    await tester.pumpAndSettle();
    expect(find.byKey(reporterKey), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('template-architecture')));
    await tester.pumpAndSettle();
    expect(find.byKey(reporterKey), findsOneWidget);

    await tester.tap(find.text('Package'));
    await tester.pumpAndSettle();
    expect(find.byKey(reporterKey), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('crash reports: hidden when My architecture is off on an old Flutter', (
    tester,
  ) async {
    await openDialog(tester, flutterVersion: '3.47.2');
    expect(find.byKey(reporterKey), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('crash reports: Russian', (tester) async {
    await openDialog(tester, locale: const Locale('ru'));

    expect(find.text('Отчёты о сбоях'), findsOneWidget);
    for (final label in const <String>['Sentry', 'Firebase Crashlytics', 'Только журнал']) {
      expect(reporterOption(label), findsOneWidget, reason: label);
    }
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('monorepo shows the first app fields', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'shop');
    expect(find.byKey(folderKey), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    expect(textOf(tester, folderKey), 'app');
    expect(textOf(tester, packageKey), 'shop_app');
    await typeName(tester, 'store');
    expect(textOf(tester, packageKey), 'store_app');
    await tester.enterText(find.byKey(packageKey), 'my_app');
    await typeName(tester, 'shop');
    expect(textOf(tester, packageKey), 'my_app');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('monorepo request', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'shop');
    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    await tester.tap(createButton());
    await tester.pumpAndSettle();

    final request = memory.requests.single;
    expect(request.structure, ProjectStructure.monorepo);
    expect(request.appFolder, 'app');
    expect(request.appPackage, 'shop_app');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('monorepo disabled on an old SDK', (tester) async {
    await openDialog(tester, dartVersion: '3.13.0');
    await typeName(tester, 'shop');

    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    expect(find.byKey(folderKey), findsNothing);
    expect(find.textContaining('3.14'), findsOneWidget);
    await tester.tap(createButton());
    await tester.pumpAndSettle();
    expect(memory.requests.single.structure, ProjectStructure.single);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('invalid app package disables create', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'shop');
    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();
    expect(canCreate(tester), isTrue);

    await tester.enterText(find.byKey(packageKey), 'Bad-Name');
    await tester.pumpAndSettle();

    expect(canCreate(tester), isFalse);
    await tester.enterText(find.byKey(packageKey), 'class');
    await tester.pumpAndSettle();
    expect(canCreate(tester), isFalse);
    await tester.enterText(find.byKey(folderKey), '');
    await tester.enterText(find.byKey(packageKey), 'good');
    await tester.pumpAndSettle();
    expect(canCreate(tester), isFalse);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the app package cannot take the name of packages/ui or of the root', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'shop');
    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    for (final taken in const <String>['ui', 'shop_workspace']) {
      await tester.enterText(find.byKey(packageKey), taken);
      await tester.pumpAndSettle();
      expect(canCreate(tester), isFalse, reason: '$taken breaks pub get');
      expect(find.text('The project already uses this name'), findsOneWidget);
    }
    await tester.enterText(find.byKey(packageKey), 'shop_desktop');
    await tester.pumpAndSettle();
    expect(canCreate(tester), isTrue);
    expect(find.text('The project already uses this name'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a taken app package is worded in Russian too', (tester) async {
    await openDialog(tester, locale: const Locale('ru'));
    await typeName(tester, 'shop');
    await tester.tap(find.byKey(const ValueKey<String>('structure-monorepo')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(packageKey), 'ui');
    await tester.pumpAndSettle();

    expect(find.text('Это имя уже занято в проекте'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the type starts as an app with the platforms and the templates', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');

    expect(find.text('Project type'), findsOneWidget);
    expect(find.text('An application. Its code goes straight into lib/.'), findsOneWidget);
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(memory.requests.single.type, FlutterProjectType.app);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a package needs no platform and has no template', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    for (final platform in <String>['ios', 'android', 'macos']) {
      await tester.tap(find.byKey(ValueKey<String>('platform-$platform')));
      await tester.pump();
    }
    expect(canCreate(tester), isFalse);

    await tester.tap(find.text('Package'));
    await tester.pump();

    expect(find.text('Dart code to share: lib/<name>.dart and lib/src/.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('platform-ios')), findsNothing);
    expect(find.text('Choose at least one platform'), findsNothing);
    expect(find.text('My architecture'), findsNothing);
    expect(canCreate(tester), isTrue);
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    expect(memory.requests.single.type, FlutterProjectType.package);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a plugin keeps the platforms but has no template', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');

    await tester.tap(find.text('Plugin'));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('platform-ios')), findsOneWidget);
    expect(find.text('My architecture'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('platform-web')));
    await tester.tap(createButton());
    await tester.pumpAndSettle();

    final request = memory.requests.single;
    expect(request.type, FlutterProjectType.plugin);
    expect(request.platforms, contains(FlutterPlatform.web));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('enter in the name field creates', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byKey(_name), 'avera_booking');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(memory.requests.single.name, 'avera_booking');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('enter does nothing while creation is off', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byKey(_name), 'class');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(memory.requests, isEmpty);
    expect(find.byType(NewProjectDialog), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the cross, Cancel and Esc close the dialog', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(NewProjectDialog), findsNothing);

    await openFromMenu(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(NewProjectDialog), findsNothing);

    await openFromMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NewProjectDialog), findsNothing);

    // Esc works with the focus off the text field too.
    _workspace(tester).openNewProject();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('platform-web')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NewProjectDialog), findsNothing);
    expect(memory.requests, isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a second call does not open a second dialog', (tester) async {
    await openDialog(tester);

    _workspace(tester).openNewProject();
    await tester.pumpAndSettle();

    expect(find.byType(NewProjectDialog), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('clone says coming later', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from git…'));
    await tester.pumpAndSettle();

    expect(find.text('Coming later'), findsOneWidget);
    expect(find.byType(NewProjectDialog), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('speaks Russian', (tester) async {
    await openDialog(tester, locale: const Locale('ru'));
    await typeName(tester, 'My-App');

    expect(find.text('Новый Flutter-проект'), findsOneWidget);
    expect(find.text('Попробуйте "my_app"'), findsOneWidget);
    expect(find.text('Моя архитектура'), findsOneWidget);
    expect(find.text('Тип проекта'), findsOneWidget);
    expect(find.text('Структура'), findsOneWidget);
    expect(find.text('Одно приложение'), findsOneWidget);
    expect(find.text('Монорепозиторий'), findsOneWidget);
    expect(find.text('Пакет'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
    for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('fits ${size.width.toInt()}×${size.height.toInt()} in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}', (tester) async {
          await openDialog(
            tester,
            locale: locale,
            dark: dark,
            size: size,
            pickFolder: (_) async => '/Users/test/StudioProjects/a/very/long/path/of/nested/folders/that/keeps/going/on/and/on',
          );
          await typeName(tester, 'My-App');
          await tester.tap(find.text(locale.languageCode == 'ru' ? 'Выбрать…' : 'Choose…'));
          await tester.pumpAndSettle();

          expect(find.byType(NewProjectDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await disposeTestApp(tester, dependencies);
        });
      }
    }
  }
}
