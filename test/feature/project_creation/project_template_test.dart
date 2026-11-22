import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The packages a template file may import: the project itself, the SDK's, and what the one
  /// `pub add` installs.
  final allowedPackages = <String>[
    'my_app',
    'flutter',
    'flutter_test',
    for (final argument in skeletonPubAddArguments)
      RegExp('^(?:dev:)?([a-z_0-9]+)').firstMatch(argument)!.group(1)!,
  ];

  test('every template file is an asset', () async {
    expect(projectTemplateFiles, hasLength(projectTemplateFiles.toSet().length));
    for (final path in projectTemplateFiles) {
      final text = await rootBundle.loadString('$projectTemplateRoot$path');
      expect(text, isNotEmpty, reason: path);
    }
  });

  test('fill leaves no placeholder', () async {
    final packageImport = RegExp('package:([a-z_0-9]+)/');
    for (final path in projectTemplateFiles) {
      final text = await rootBundle.loadString('$projectTemplateRoot$path');
      final filled = fillProjectTemplate(text, package: 'my_app', date: DateTime(2026, 11, 6));
      expect(filled, isNot(contains('{{')), reason: path);
      if (!path.endsWith('.dart')) continue;
      for (final match in packageImport.allMatches(filled)) {
        expect(allowedPackages, contains(match.group(1)), reason: '$path: ${match.group(0)}');
      }
    }
  });

  test('fill replaces every occurrence of the package', () {
    expect(
      fillProjectTemplate('{{package}} and {{package}}', package: 'my_app', date: DateTime(2026)),
      'my_app and my_app',
    );
  });

  test('fill writes the date as YYYY-MM-DD', () {
    expect(
      fillProjectTemplate('## [1.0.0] - {{date}}', package: 'my_app', date: DateTime(2026, 3, 7)),
      '## [1.0.0] - 2026-03-07',
    );
  });

  test('an app keeps its code directly in lib: _core and one folder per feature, no src', () {
    final libFiles = projectTemplateFiles.where((path) => path.startsWith('lib/')).toList();
    for (final path in libFiles) {
      expect(path, isNot(startsWith('lib/src/')), reason: path);
      expect(path, isNot(startsWith('lib/feature/')), reason: path);
      expect(path, isNot(contains('/common/')), reason: path);
    }
    expect(
      libFiles,
      containsAll(<String>[
        'lib/main.dart',
        'lib/_core/api_client/api_client.dart',
        'lib/initialization/widget/app.dart',
        'lib/home/widgets/home_screen.dart',
      ]),
    );
    // The shared UI is a package: it keeps the package layout, `lib/ui.dart` and `lib/src/`.
    expect(projectTemplateFiles, containsAll(<String>['packages/ui/lib/ui.dart']));
    expect(projectTemplateFiles, containsAll(<String>['Makefile', 'CHANGELOG.md']));
  });

  test('no app file imports or names a path under lib/src', () async {
    for (final path in projectTemplateFiles.where((path) => !path.startsWith('packages/'))) {
      final text = await rootBundle.loadString('$projectTemplateRoot$path');
      expect(text, isNot(contains('{{package}}/src/')), reason: path);
      expect(text, isNot(contains('lib/src/')), reason: path);
    }
  });

  test('the Makefile is indented with tabs', () async {
    final makefile = await rootBundle.loadString('${projectTemplateRoot}Makefile');
    final recipes = makefile.split('\n').where((line) => line.startsWith('\t@'));
    expect(recipes, isNotEmpty);
    expect(makefile, isNot(contains('\n    @')));
  });

  test("control pin matches the app's pubspec", () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('url: $controlGitUrl'));
    expect(pubspec, contains('ref: $controlGitRef'));
  });

  test('pub add takes the newest versions and skips what the rules advise against', () {
    final names = [
      for (final argument in skeletonPubAddArguments)
        RegExp('^(?:dev:)?([a-z_0-9]+)').firstMatch(argument)!.group(1)!,
    ];
    // No version constraint: every creation resolves the newest release.
    for (final argument in skeletonPubAddArguments) {
      final spec = argument.replaceFirst('dev:', '');
      expect(spec, isNot(matches(RegExp('^[a-z_0-9]+:'))), reason: argument);
    }
    expect(
      names,
      containsAll(<String>['control', 'drift', 'drift_flutter', 'http', 'ui', 'window_manager']),
    );
    expect(
      skeletonPubAddArguments,
      containsAll(<String>[
        'control@{git: {url: https://github.com/PlugFox/control.git, ref: 685a9bc6ef60c987b99b5526e125813adba54e2a}}',
        'ui@{path: packages/ui}',
        'dev:build_runner',
        'dev:drift_dev',
      ]),
    );
    // Routing is the app's own navigator; models are parsed by hand; `test` next to build_runner
    // breaks `pub get`; sqlite3_flutter_libs is end-of-life (drift bundles SQLite itself).
    for (final name in const <String>[
      'octopus',
      'json_annotation',
      'json_serializable',
      'flutter_gen_runner',
      'pubspec_generator',
      'test',
      'sqlite3_flutter_libs',
    ]) {
      expect(names, isNot(contains(name)), reason: name);
    }
    expect(names, hasLength(names.toSet().length));
  });

  test('repo, app and ui files make up the one-app list', () {
    final repo = projectTemplateRepoFiles.toSet();
    final app = projectTemplateAppFiles.toSet();
    final ui = projectTemplateUiFiles.toSet();
    expect(<String>{...repo, ...app, ...ui}, projectTemplateFiles.toSet());
    expect(
      repo.length + app.length + ui.length,
      projectTemplateFiles.length,
      reason: 'the three lists overlap or repeat a file',
    );
    expect(repo.intersection(app), isEmpty);
    expect(repo.intersection(ui), isEmpty);
    expect(app.intersection(ui), isEmpty);
  });

  test('every monorepo template file is an asset', () async {
    for (final path in monorepoTemplateFiles) {
      final text = await rootBundle.loadString('$monorepoTemplateRoot$path');
      expect(text, isNotEmpty, reason: path);
    }
  });

  test('monorepo scripts find members themselves', () async {
    final scripts = <String, String>{
      for (final name in const <String>['analyze', 'format', 'generate', 'test'])
        name: await rootBundle.loadString('${monorepoTemplateRoot}scripts/$name.bash'),
    };
    expect(scripts['test'], allOf(contains('apps/*/'), contains('packages/*/')));
    for (final entry in scripts.entries) {
      expect(entry.value, isNot(contains('apps/app')), reason: entry.key);
      expect(entry.value, isNot(contains('packages/ui')), reason: entry.key);
    }
  });

  test('monorepo Makefile runs one app', () async {
    final makefile = await rootBundle.loadString('${monorepoTemplateRoot}Makefile');
    expect(makefile, contains('run:'));
    expect(makefile, contains('APP'));
    expect(makefile, contains(r'cd apps/$(APP)'));
    expect(makefile.split('\n').where((line) => line.startsWith('\t@')), isNotEmpty);
    expect(makefile, isNot(contains('\n    @')));
  });

  test('root pubspec is a workspace of apps and packages', () {
    final pubspec = monorepoRootPubspec(name: 'shop', sdkConstraint: '^3.14.0');
    expect(pubspec, contains('name: shop_workspace'));
    expect(pubspec, contains('publish_to: none'));
    expect(pubspec, contains('sdk: ^3.14.0'));
    expect(pubspec, contains('- apps/*'));
    expect(pubspec, contains('- packages/*'));
    expect(pubspec, isNot(contains('dependencies:')));
  });

  test('pub add for a monorepo app points at the shared ui package', () {
    final arguments = skeletonPubAddArgumentsFor(uiPath: '../../packages/ui');
    expect(arguments, contains('ui@{path: ../../packages/ui}'));
    expect(arguments, isNot(contains('ui@{path: packages/ui}')));
    expect(skeletonPubAddArguments, contains('ui@{path: packages/ui}'));
  });

  /// The telemetry module and its tests as a new project `my_app` gets them, keyed by their path in
  /// the project.
  Future<Map<String, String>> copiedModule() async => <String, String>{
    for (final file in telemetryModuleFiles)
      '$telemetryModuleTarget$file': copyTelemetryModule(
        await rootBundle.loadString('$telemetryModuleRoot$file'),
        importPrefix: 'package:my_app/_core/telemetry/',
      ),
    for (final file in telemetryModuleTestFiles)
      '$telemetryModuleTestTarget$file': copyTelemetryModule(
        await rootBundle.loadString('$telemetryModuleTestRoot$file'),
        importPrefix: 'package:my_app/_core/telemetry/',
      ),
  };

  /// The template's Dart file at [path], filled for `my_app`.
  Future<String> filled(String path) async => fillProjectTemplate(
    await rootBundle.loadString('$projectTemplateRoot$path'),
    package: 'my_app',
    date: DateTime(2026, 11, 6),
  );

  /// The names of the non-generated Dart files directly in [folder].
  Set<String> dartFilesIn(String folder) => <String>{
    for (final entity in Directory(folder).listSync())
      if (entity is File && entity.path.endsWith('.dart') && !entity.path.endsWith('.g.dart'))
        entity.uri.pathSegments.last,
  };

  group('telemetry', () {
    test('telemetryModuleFiles lists the module folder', () {
      expect(telemetryModuleRoot, 'lib/src/common/telemetry/');
      expect(telemetryModuleFiles, hasLength(telemetryModuleFiles.toSet().length));
      expect(telemetryModuleFiles.toSet(), dartFilesIn(telemetryModuleRoot));
    });

    test('telemetryModuleTestFiles lists the tests of the module, not its portability check', () {
      expect(telemetryModuleTestRoot, 'test/common/telemetry/');
      expect(telemetryModuleTestFiles, hasLength(telemetryModuleTestFiles.toSet().length));
      expect(
        telemetryModuleTestFiles.toSet(),
        dartFilesIn(telemetryModuleTestRoot).difference(const <String>{'portability_test.dart'}),
      );
    });

    test('every module file and test is an asset', () async {
      for (final path in <String>[
        for (final file in telemetryModuleFiles) '$telemetryModuleRoot$file',
        for (final file in telemetryModuleTestFiles) '$telemetryModuleTestRoot$file',
      ]) {
        expect(await rootBundle.loadString(path), isNotEmpty, reason: path);
      }
    });

    test('copyTelemetryModule rewrites only the import prefix', () {
      expect(
        copyTelemetryModule(
          "import 'package:flutter_code_agent/src/common/telemetry/clip.dart';\n"
          "import 'package:l/l.dart';\n",
          importPrefix: 'package:shop/_core/telemetry/',
        ),
        "import 'package:shop/_core/telemetry/clip.dart';\n"
        "import 'package:l/l.dart';\n",
      );
    });

    test('copied module imports only itself', () async {
      final copied = await copiedModule();
      expect(copied, hasLength(telemetryModuleFiles.length + telemetryModuleTestFiles.length));
      for (final MapEntry(key: path, value: text) in copied.entries) {
        expect(text, isNot(contains('flutter_code_agent')), reason: path);
        expect(text, isNot(contains('package:flutter/')), reason: path);
      }
      expect(
        copied['lib/_core/telemetry/telemetry.dart'],
        contains('package:my_app/_core/telemetry/'),
      );
    });

    test('no old log or error stubs', () {
      for (final list in <List<String>>[projectTemplateFiles, projectTemplateAppFiles]) {
        expect(
          list,
          isNot(
            anyOf(<Matcher>[
              contains('lib/_core/database/tables/log_table.dart'),
              contains('lib/_core/utils/log_buffer.dart'),
              contains('lib/_core/utils/error_util/error_util.dart'),
              contains('lib/_core/utils/error_util/platform/error_util_vm.dart'),
              contains('lib/_core/utils/error_util/platform/error_util_js.dart'),
              contains('lib/_core/utils/app_zone.dart'),
              contains('lib/_core/controller/controller_observer.dart'),
              contains('lib/_core/utils/api_client.dart'),
              contains('lib/_core/utils/middleware/logger_mw.dart'),
            ]),
          ),
        );
        expect(
          list,
          containsAll(<String>[
            'lib/_core/telemetry/error_util.dart',
            'lib/_core/telemetry/controller_observer.dart',
            'lib/_core/telemetry/app_zone.dart',
            'lib/_core/telemetry/expected_failure.dart',
            'lib/_core/telemetry/telemetry_setup.dart',
            'lib/_core/telemetry/telemetry_setup_io.dart',
            'lib/_core/telemetry/telemetry_setup_web.dart',
            'lib/_core/telemetry/crash_reporter.dart',
            'lib/_core/api_client/api_client.dart',
            'lib/_core/api_client/expected_exception.dart',
            'lib/_core/api_client/middleware/logger_mw.dart',
            'lib/_core/api_client/middleware/authentication_interceptor.dart',
            'config/.gitkeep',
          ]),
        );
      }
      // The module comes from FAgent's own folder, not from a copy in the template.
      for (final file in telemetryModuleFiles) {
        expect(projectTemplateFiles, isNot(contains('lib/_core/telemetry/$file')), reason: file);
      }
    });

    test('the database has no log tables', () async {
      final database = await filled('lib/_core/database/database.dart');
      expect(database, isNot(contains('LogTbl')));
      expect(database, isNot(contains('log_table')));
    });

    test('the glue reports through ErrorUtil', () async {
      final observer = await filled('lib/_core/telemetry/controller_observer.dart');
      expect(observer, contains('ErrorUtil.logError'));
      expect(observer, contains('runtimeType'));
      final expected = await filled('lib/_core/telemetry/expected_failure.dart');
      for (final type in const <String>[
        'ExpectedException',
        r'APIClientException$Network',
        r'APIClientException$Authorization',
        'TimeoutException',
      ]) {
        expect(expected, contains('error is $type'), reason: type);
      }
      expect(expected, contains("<String>{'my_app', 'ui'}"));
      final zone = await filled('lib/_core/telemetry/app_zone.dart');
      expect(zone, contains('ErrorUtil.logError'));
      final main = await filled('lib/main.dart');
      expect(main, contains('appZone('));
    });

    test("the first startup step is 'Error log' and the dependencies hold the runtime", () async {
      final steps = await filled('lib/initialization/data/initialize_dependencies.dart');
      final first = RegExp(
        r"_initializationSteps = <String, _InitializationStep>\{\s*(?://[^\n]*\s*)*'([^']+)'",
      ).firstMatch(steps);
      expect(first?.group(1), 'Error log');
      expect(steps, contains('telemetryRuntime'));
      expect(steps, contains("hint: 'STARTUP ERROR'"));
      final dependencies = await filled('lib/initialization/models/dependencies.dart');
      expect(dependencies, contains('TelemetryRuntime? telemetryRuntime'));
      final initialization = await filled('lib/initialization/data/initialization.dart');
      expect(initialization, contains('closeErrorLog()'));
    });

    test('the Sentry reporter reads its DSN and sends without a switch', () async {
      final reporter = await filled('lib/_core/telemetry/crash_reporter.dart');
      expect(reporter, contains('Future<ICrashReportGateway?> createCrashReportGateway({'));
      expect(reporter, contains('required Set<String> projectPackages'));
      expect(reporter, contains('bool get crashReporterConfigured'));
      expect(reporter, contains('SentryGateway('));
      final config = await filled('lib/_core/constant/config.dart');
      expect(config, contains("String.fromEnvironment('SENTRY_DSN')"));
      final io = await filled('lib/_core/telemetry/telemetry_setup_io.dart');
      expect(io, contains('enabled: true'));
      expect(io, isNot(contains('consentSince:')));
    });

    test('web keeps compiling', () async {
      const io = 'package:my_app/_core/telemetry/telemetry_setup_io.dart';
      const web = 'package:my_app/_core/telemetry/telemetry_setup_web.dart';
      final conditional = RegExp(
        "(?:import|export) '${RegExp.escape(io)}'\\s+if \\(dart\\.library\\.js_interop\\) "
        "'${RegExp.escape(web)}'",
      );
      final setup = await filled('lib/_core/telemetry/telemetry_setup.dart');
      expect(conditional.hasMatch(setup), isTrue, reason: setup);

      // The module files the web may reach: plain Dart without dart:io, drift or sqlite3.
      const webSafe = <String>{'log_zone.dart', 'redact.dart', 'clip.dart'};
      final directive = RegExp(
        r'''^\s*(?:import|export)\s+'([^']+)'(\s+if[^;]*)?''',
        multiLine: true,
      );
      // What the web build compiles: the code of the app and of packages/ui (tools and tests run
      // on the VM).
      final compiled = projectTemplateFiles.where(
        (path) =>
            path.endsWith('.dart') && (path.startsWith('lib/') || path.startsWith('packages/')),
      );
      for (final path in compiled) {
        final text = await filled(path);
        final vmOnly =
            path.endsWith('_io.dart') ||
            path.endsWith('_vm.dart') ||
            path.endsWith('_windows.dart') ||
            path == 'lib/_core/telemetry/crash_reporter.dart';
        for (final match in directive.allMatches(text)) {
          final uri = match.group(1)!;
          if (vmOnly) continue;
          expect(uri, isNot('dart:io'), reason: path);
          expect(uri, isNot('dart:ffi'), reason: path);
          if (uri == io) {
            expect(match.group(2), contains("'$web'"), reason: '$path imports the VM half alone');
          }
          expect(uri, isNot(endsWith('/_core/telemetry/crash_reporter.dart')), reason: path);
          for (final file in telemetryModuleFiles.where((file) => !webSafe.contains(file))) {
            expect(uri, isNot('package:my_app/_core/telemetry/$file'), reason: path);
          }
        }
      }
    });
  });

  test('pub add installs what the telemetry module imports', () {
    expect(
      skeletonPubAddArguments,
      containsAll(<String>[
        'sentry',
        'clock',
        'archive',
        'sqlite3',
        'path',
        'meta',
        'dev:fake_async',
      ]),
    );
  });

  test('the Makefile runs with config/sentry.local.json when it exists', () async {
    final makefile = await rootBundle.loadString('${projectTemplateRoot}Makefile');
    expect(makefile, contains(r'$(wildcard config/sentry.local.json)'));
    expect(makefile, contains('--dart-define-from-file=config/sentry.local.json'));
    final run = RegExp(r'^run:.*\n\t@flutter run ([^\n]*)', multiLine: true).firstMatch(makefile);
    expect(run?.group(1), contains(r'$(SENTRY)'));
  });

  group('material_ui', () {
    /// The Dart files of the template, filled for `my_app`, keyed by their template path.
    Future<Map<String, String>> dartFiles() async => <String, String>{
      for (final path in projectTemplateFiles.where((path) => path.endsWith('.dart')))
        path: fillProjectTemplate(
          await rootBundle.loadString('$projectTemplateRoot$path'),
          package: 'my_app',
          date: DateTime(2026, 11, 6),
        ),
    };

    test(
      'no template file imports or exports the deprecated material.dart or cupertino.dart',
      () async {
        for (final MapEntry(key: path, value: text) in (await dartFiles()).entries) {
          expect(text, isNot(contains('package:flutter/material.dart')), reason: path);
          expect(text, isNot(contains('package:flutter/cupertino.dart')), reason: path);
        }
      },
    );

    test('ui.dart exports material_ui', () async {
      final ui = (await dartFiles())['packages/ui/lib/ui.dart']!;
      expect(ui, contains("export 'package:material_ui/material_ui.dart';"));
    });

    for (final path in const <String>[
      'lib/initialization/widget/app.dart',
      'lib/_core/widget/app_error.dart',
    ]) {
      test(
        '$path takes the delegates from material_ui, cupertino_ui and flutter_localizations',
        () async {
          final text = await rootBundle.loadString('$projectTemplateRoot$path');
          expect(
            text,
            startsWith(
              "import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;\n"
              "import 'package:flutter_localizations/flutter_localizations.dart' "
              'show GlobalWidgetsLocalizations;\n'
              "import 'package:material_ui/material_ui.dart';\n",
            ),
          );
          expect(text, contains('GlobalMaterialLocalizations.delegate'));
          expect(text, contains('GlobalCupertinoLocalizations.delegate'));
          expect(text, contains('GlobalWidgetsLocalizations.delegate'));
        },
      );
    }

    test('flutter_localizations is imported only for GlobalWidgetsLocalizations', () async {
      final import = RegExp("^import '([^']+)'([^;]*);", multiLine: true);
      for (final MapEntry(key: path, value: text) in (await dartFiles()).entries) {
        for (final match in import.allMatches(text)) {
          if (match.group(1) != 'package:flutter_localizations/flutter_localizations.dart') {
            continue;
          }
          // Only what flutter_localizations has that is not deprecated.
          expect(match.group(2)!.trim(), 'show GlobalWidgetsLocalizations', reason: path);
        }
      }
    });

    test('pub add always gets material_ui and cupertino_ui', () {
      for (final arguments in <List<String>>[
        skeletonPubAddArguments,
        skeletonPubAddArgumentsFor(uiPath: '../../packages/ui'),
      ]) {
        expect(arguments, containsAll(<String>['material_ui', 'cupertino_ui']));
      }
      expect(uiPubAddArguments, <String>['material_ui']);
    });

    test('the template imports only packages its pub add installs', () async {
      final packageImport = RegExp("(?:import|export) 'package:([a-z_0-9]+)/");
      final app = <String>[
        'my_app',
        'flutter',
        'flutter_test',
        for (final argument in skeletonPubAddArguments)
          RegExp('^(?:dev:)?([a-z_0-9]+)').firstMatch(argument)!.group(1)!,
      ];
      // packages/ui: its template pubspec, then what FAgent adds to it.
      final ui = <String>['ui', 'flutter', 'intl', 'collection', ...uiPubAddArguments];
      final usedByUi = <String>{};
      final files = <String, String>{...await dartFiles(), ...await copiedModule()};
      for (final MapEntry(key: path, value: text) in files.entries) {
        final inUi = path.startsWith('packages/ui/');
        for (final match in packageImport.allMatches(text)) {
          final name = match.group(1)!;
          expect(inUi ? ui : app, contains(name), reason: '$path: ${match.group(0)}');
          if (inUi) usedByUi.add(name);
        }
      }
      // packages/ui gets exactly the ones its files import.
      expect(
        uiPubAddArguments.toSet(),
        usedByUi.intersection(const <String>{'material_ui', 'cupertino_ui'}),
      );
    });
  });
}
