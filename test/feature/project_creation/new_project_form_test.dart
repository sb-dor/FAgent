import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_project_creation_repository.dart';
import '../../support/test_app.dart';

const _name = ValueKey<String>('new-project-name');
const _org = ValueKey<String>('new-project-org');

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// A repository whose target checks answer when the test says so.
final class _SlowTargets implements IProjectCreationRepository {
  final Map<String, Completer<TargetProblem?>> answers = <String, Completer<TargetProblem?>>{};

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) =>
      (answers[name] = Completer<TargetProblem?>()).future;

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) => const Stream.empty();
}

/// A repository whose default folder arrives when the test says so.
final class _SlowParent implements IProjectCreationRepository {
  final Completer<String> parent = Completer<String>();

  @override
  bool get isPreview => true;

  @override
  Future<String> defaultParent() => parent.future;

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Stream<List<CreationStep>> create(NewProjectRequest request) => const Stream.empty();
}

/// A repository whose folder questions fail like an unreadable (protected) parent does:
/// [checkTarget] throws for every name but `fine`.
final class _FailingFolders implements IProjectCreationRepository {
  _FailingFolders({this.failDefaultParent = false});

  final bool failDefaultParent;

  @override
  bool get isPreview => true;

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
  Stream<List<CreationStep>> create(NewProjectRequest request) => const Stream.empty();
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
      flutterSdkRepository: FakeFlutterSdkRepositoryImpl(
        which: (_) => sdkPath,
        step: Duration.zero,
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
    expect(tester.widget<TextField>(find.byKey(_org)).controller!.text, 'com.example');
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
    expect(find.text('Flutter 3.27.1'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    // Nothing is wrong on an empty form.
    expect(find.text('Choose at least one platform'), findsNothing);
    expect(find.textContaining('Lowercase'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('starts with the org of the settings', (tester) async {
    await openDialog(tester, org: 'dev.avaz');

    expect(tester.widget<TextField>(find.byKey(_org)).controller!.text, 'dev.avaz');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a bad org blocks creation and leaves the settings alone', (tester) async {
    await openDialog(tester);
    await typeName(tester, 'avera_booking');
    expect(canCreate(tester), isTrue);

    await tester.enterText(find.byKey(_org), 'Com.Example');
    await tester.pumpAndSettle();
    expect(find.text('For example, com.example'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await tester.enterText(find.byKey(_org), 'dev.avaz');
    await tester.pumpAndSettle();
    expect(find.text('For example, com.example'), findsNothing);
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

  testWidgets('git template is a preview', (tester) async {
    await openDialog(tester);

    expect(find.text('Coming in M4'), findsNothing);
    await tester.tap(find.text('From a git template…'));
    await tester.pump();

    // Shown inline: a SnackBar would sit under the dialog's barrier.
    expect(find.text('Coming in M4'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.text('My architecture'));
    await tester.pump();
    expect(find.text('Coming in M4'), findsNothing);

    await tester.tap(find.text('From a git template…'));
    await tester.pump();
    expect(find.text('Coming in M4'), findsOneWidget);
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
    await tester.tap(find.text('Plain flutter create'));
    await tester.tap(find.text('git init + first commit'));
    await tester.pump();

    await tester.tap(createButton());
    await tester.pumpAndSettle();

    final request = memory.requests.single;
    expect(request.name, 'avera_booking');
    expect(request.org, 'com.example');
    expect(request.parent, '/Users/test/StudioProjects');
    expect(request.platforms, <FlutterPlatform>{FlutterPlatform.ios, FlutterPlatform.android});
    expect(request.template, NewProjectTemplate.plain);
    expect(request.gitInit, isFalse);
    expect(request.openChat, isTrue);
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

  testWidgets('clone stays a preview', (tester) async {
    await openDialog(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clone from git…'));
    await tester.pumpAndSettle();

    expect(find.text('Coming in M4'), findsOneWidget);
    expect(find.byType(NewProjectDialog), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('speaks Russian', (tester) async {
    await openDialog(tester, locale: const Locale('ru'));
    await typeName(tester, 'My-App');

    expect(find.text('Новый Flutter-проект'), findsOneWidget);
    expect(find.text('Попробуйте "my_app"'), findsOneWidget);
    expect(find.text('Моя архитектура'), findsOneWidget);
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
