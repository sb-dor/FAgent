import 'dart:io' as io;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/add_member_dialog.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_fields.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_project_creation_repository.dart';
import '../../support/test_app.dart';

const _folder = ValueKey<String>('add-member-folder');
const _package = ValueKey<String>('add-member-package');
const _org = ValueKey<String>('add-member-org');
const _create = ValueKey<String>('add-member-create');

const _project = Project(id: 3, path: '/work/shop', name: 'shop', isFlutter: true);

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryProjectCreationRepository memory;

  /// Shows the window and opens the Add to project dialog of [_project].
  Future<void> openDialog(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool ui = true,
    bool git = true,
    String? flutterVersion = '3.50.0',
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    memory = MemoryProjectCreationRepository(existing: const <String>{'/work/shop/apps/taken'})
      ..takenPackages = <String>{'shop_taken_name'}
      ..uiPackage = ui
      ..gitRepo = git;
    dependencies = testDependencies(
      projectCreationRepository: memory,
      flutterSdkRepository: FlutterSdkRepositoryImpl(
        which: (_) => '/opt/flutter/bin/flutter',
        runProcess: (executable, arguments, {environment}) async => io.ProcessResult(
          1,
          0,
          '{${flutterVersion == null ? '' : '"frameworkVersion":"$flutterVersion",'}'
              '"channel":"stable","dartSdkVersion":"3.14.0 (build)"}',
          '',
        ),
      ),
    );
    addTearDown(() => disposeTestApp(tester, dependencies));
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
    _workspace(tester).openAddMember(_project).ignore();
    await tester.pumpAndSettle();
  }

  Finder createButton() => find.byKey(_create);

  bool canCreate(WidgetTester tester) =>
      tester.widget<FilledButton>(createButton()).onPressed != null;

  Future<void> type(WidgetTester tester, Key field, String text) async {
    await tester.enterText(find.byKey(field), text);
    await tester.pumpAndSettle();
  }

  Future<void> pickKind(WidgetTester tester, MemberKind kind) async {
    await tester.tap(find.byKey(ValueKey<String>('kind-${kind.name}')));
    await tester.pumpAndSettle();
  }

  bool shown(String key) => find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty;

  testWidgets('opens with the four kinds and a Flutter app selected', (tester) async {
    await openDialog(tester);

    expect(find.byType(AddMemberDialog), findsOneWidget);
    expect(find.text('New project member'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('add-member-kind')), findsOneWidget);
    for (final kind in MemberKind.values) {
      expect(find.byKey(ValueKey<String>('kind-${kind.name}')), findsOneWidget);
    }
    expect(find.text('apps/ — flutter create and the skeleton'), findsOneWidget);
    expect(canCreate(tester), isFalse);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('fields per kind', (tester) async {
    await openDialog(tester);

    // A Flutter app: organization, platforms and template.
    expect(find.byKey(_folder), findsOneWidget);
    expect(find.byKey(_package), findsOneWidget);
    expect(find.byKey(_org), findsOneWidget);
    expect(shown('platform-ios'), isTrue);
    expect(shown('template-architecture'), isTrue);
    expect(shown('template-plain'), isTrue);

    for (final kind in <MemberKind>[
      MemberKind.dartApp,
      MemberKind.flutterPackage,
      MemberKind.dartPackage,
    ]) {
      await pickKind(tester, kind);
      expect(find.byKey(_folder), findsOneWidget, reason: '$kind');
      expect(find.byKey(_package), findsOneWidget, reason: '$kind');
      expect(find.byKey(_org), findsNothing, reason: '$kind');
      expect(shown('platform-ios'), isFalse, reason: '$kind');
      expect(shown('template-plain'), isFalse, reason: '$kind');
    }
    await pickKind(tester, MemberKind.dartPackage);
    expect(find.text('packages/ — without Flutter'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('no packages/ui offers only Empty', (tester) async {
    await openDialog(tester, ui: false);

    expect(shown('template-architecture'), isFalse);
    expect(shown('template-plain'), isTrue);
    expect(find.text('No packages/ui: only the empty template is available'), findsOneWidget);

    await type(tester, _folder, 'admin');
    await tester.tap(createButton());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(memory.memberRequests.single.template, NewProjectTemplate.plain);
  });

  testWidgets('with packages/ui both templates are offered', (tester) async {
    await openDialog(tester);

    expect(find.text('No packages/ui: only the empty template is available'), findsNothing);
    expect(shown('template-architecture'), isTrue);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  CreationTemplateCard card(WidgetTester tester, String key) =>
      tester.widget<CreationTemplateCard>(find.byKey(ValueKey<String>(key)));

  testWidgets('My architecture is on with Flutter 3.50', (tester) async {
    await openDialog(tester);

    expect(card(tester, 'template-architecture').enabled, isTrue);
    expect(card(tester, 'template-architecture').selected, isTrue);
    expect(find.text('Needs Flutter 3.50 or newer'), findsNothing);
    await type(tester, _folder, 'admin');
    await tester.tap(createButton());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(memory.memberRequests.single.template, NewProjectTemplate.architecture);
  });

  for (final version in const <String?>['3.47.2', null]) {
    testWidgets(
      'My architecture is off with Flutter ${version ?? 'unknown'}: the empty one is added',
      (tester) async {
        await openDialog(tester, flutterVersion: version);

        expect(card(tester, 'template-architecture').enabled, isFalse);
        expect(card(tester, 'template-architecture').selected, isFalse);
        expect(card(tester, 'template-plain').selected, isTrue);
        expect(find.text('Needs Flutter 3.50 or newer'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey<String>('template-architecture')));
        await tester.pumpAndSettle();
        expect(card(tester, 'template-architecture').selected, isFalse);
        await type(tester, _folder, 'admin');
        await tester.tap(createButton());
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(memory.memberRequests.single.template, NewProjectTemplate.plain);
      },
    );
  }

  testWidgets('the Flutter hint of My architecture is in Russian too', (tester) async {
    await openDialog(tester, flutterVersion: '3.47.2', locale: const Locale('ru'));

    expect(find.text('Нужен Flutter 3.50 или новее'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
  });

  testWidgets('folder exists and package taken show errors and disable create', (tester) async {
    await openDialog(tester);

    await type(tester, _folder, 'admin');
    expect(canCreate(tester), isTrue);

    await type(tester, _folder, 'taken');
    expect(find.text('The folder already exists'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await type(tester, _folder, 'admin');
    expect(find.text('The folder already exists'), findsNothing);
    expect(canCreate(tester), isTrue);

    await type(tester, _package, 'shop_taken_name');
    expect(find.text('The project already has this package'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await type(tester, _package, 'Bad Name');
    expect(find.text('The project already has this package'), findsNothing);
    expect(find.textContaining('Lowercase'), findsOneWidget);
    expect(canCreate(tester), isFalse);

    await type(tester, _folder, 'Bad-Folder');
    expect(find.textContaining('Lowercase'), findsNWidgets(2));
    expect(canCreate(tester), isFalse);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('package follows the folder until it is typed', (tester) async {
    await openDialog(tester);

    String package() => tester.widget<TextField>(find.byKey(_package)).controller!.text;

    await type(tester, _folder, 'admin');
    expect(package(), 'shop_admin');
    await type(tester, _folder, 'desktop');
    expect(package(), 'shop_desktop');

    await type(tester, _package, 'my_pkg');
    await type(tester, _folder, 'server');
    expect(package(), 'my_pkg');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('create sends the request', (tester) async {
    await openDialog(tester, git: false);

    await pickKind(tester, MemberKind.dartPackage);
    await type(tester, _folder, 'core');
    await type(tester, _package, 'shop_core');
    await tester.tap(createButton());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final request = memory.memberRequests.single;
    expect(request.projectId, 3);
    expect(request.projectPath, '/work/shop');
    expect(request.kind, MemberKind.dartPackage);
    expect(request.folder, 'core');
    expect(request.packageName, 'shop_core');
    expect(request.gitRepo, isFalse);
    expect(request.platforms, isEmpty);
  });

  testWidgets('a Flutter app request carries org, platforms and template', (tester) async {
    await openDialog(tester);

    await type(tester, _folder, 'admin');
    await type(tester, _org, 'dev.shop');
    await tester.tap(find.byKey(const ValueKey<String>('platform-ios')));
    await tester.tap(find.byKey(const ValueKey<String>('template-plain')));
    await tester.pumpAndSettle();
    await tester.tap(createButton());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final request = memory.memberRequests.single;
    expect(request.kind, MemberKind.flutterApp);
    expect(request.org, 'dev.shop');
    expect(request.platforms, <FlutterPlatform>{FlutterPlatform.android, FlutterPlatform.macos});
    expect(request.template, NewProjectTemplate.plain);
    expect(request.gitRepo, isTrue);
  });

  for (final (locale, text) in <(Locale, String)>[
    (const Locale('en'), 'scripts/test.bash lists members by name: add apps/admin to it'),
    (
      const Locale('ru'),
      'scripts/test.bash перечисляет участников по именам: добавьте в него apps/admin',
    ),
  ]) {
    testWidgets('scripts note after success (${locale.languageCode})', (tester) async {
      await openDialog(tester, locale: locale);
      memory.listingScripts = const <String>['scripts/test.bash'];

      await type(tester, _folder, 'admin');
      await tester.tap(createButton());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text(text), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('creation-close')), findsOneWidget);
      // A member is not a project: nothing to open.
      expect(find.byKey(const ValueKey<String>('creation-open-project')), findsNothing);
    });
  }

  testWidgets('no note when no script lists members', (tester) async {
    await openDialog(tester);

    await type(tester, _folder, 'admin');
    await tester.tap(createButton());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('lists members by name'), findsNothing);
    expect(find.byKey(const ValueKey<String>('creation-close')), findsOneWidget);
  });
}
