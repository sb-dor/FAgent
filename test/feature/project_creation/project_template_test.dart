import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_template.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
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

  test('build output under packages/ui is neither analyzed nor committed', () async {
    // `pub get` stages some plugins (firebase_core) in packages/ui/build/<platform>/SourcePackages.
    final options = await rootBundle.loadString('${projectTemplateRoot}analysis_options.yaml');
    expect(options, contains('- "**/build/**"'));
    final ignore = await rootBundle.loadString('${projectTemplateRoot}packages/ui/.gitignore');
    expect(ignore.split('\n'), contains('/build/'));
    expect(projectTemplateUiFiles, contains('packages/ui/.gitignore'));
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

  test('repo, app, ui and shared files make up the one-app list', () {
    final repo = projectTemplateRepoFiles.toSet();
    final app = projectTemplateAppFiles.toSet();
    final ui = projectTemplateUiFiles.toSet();
    final shared = sharedPackageSources.keys.toSet();
    expect(<String>{...repo, ...app, ...ui, ...shared}, projectTemplateFiles.toSet());
    expect(
      repo.length + app.length + ui.length + shared.length,
      projectTemplateFiles.length,
      reason: 'the four lists overlap or repeat a file',
    );
    for (final (a, b) in <(Set<String>, Set<String>)>[
      (repo, app),
      (repo, ui),
      (repo, shared),
      (app, ui),
      (app, shared),
      (ui, shared),
    ]) {
      expect(a.intersection(b), isEmpty);
    }
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

  /// The telemetry module and its tests as a new project `my_app` with [reporter] gets them, keyed
  /// by their path in the project.
  Future<Map<String, String>> copiedModule([CrashReporter reporter = CrashReporter.sentry]) async =>
      <String, String>{
        for (final file in telemetryModuleFilesFor(reporter))
          '$telemetryModuleTarget$file': copyTelemetryModule(
            await rootBundle.loadString('$telemetryModuleRoot$file'),
            importPrefix: 'package:my_app/_core/telemetry/',
            crashReporter: reporter,
          ),
        for (final file in telemetryModuleTestFilesFor(reporter))
          '$telemetryModuleTestTarget$file': copyTelemetryModule(
            await rootBundle.loadString('$telemetryModuleTestRoot$file'),
            importPrefix: 'package:my_app/_core/telemetry/',
            crashReporter: reporter,
          ),
      };

  /// The template's Dart file at [path], filled for `my_app`.
  Future<String> filled(String path) async => fillProjectTemplate(
    await rootBundle.loadString('$projectTemplateRoot$path'),
    package: 'my_app',
    date: DateTime(2026, 11, 6),
  );

  /// The files of the crash reporter [reporter] as `my_app` gets them, keyed by their path in the
  /// project.
  Future<Map<String, String>> reporterFiles(CrashReporter reporter) async => <String, String>{
    for (final MapEntry(key: from, value: to) in crashReporterTemplateFiles(reporter).entries)
      to: await filled(from),
  };

  /// Every Dart file a one-app project `my_app` with [reporter] gets from FAgent, keyed by its path
  /// in the project.
  Future<Map<String, String>> projectDartFiles(CrashReporter reporter) async => <String, String>{
    for (final path in projectTemplateFiles.where((path) => path.endsWith('.dart')))
      path: await filled(path),
    ...await reporterFiles(reporter),
    ...await copiedModule(reporter),
  };

  /// The package names of `pub add` [arguments].
  List<String> packagesOf(List<String> arguments) => <String>[
    for (final argument in arguments)
      RegExp('^(?:dev:)?([a-z_0-9]+)').firstMatch(argument)!.group(1)!,
  ];

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
      for (final list in <List<String>>[
        projectTemplateFiles,
        <String>[...projectTemplateAppFiles, ...sharedPackageSources.keys],
      ]) {
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
      final reporter = (await reporterFiles(CrashReporter.sentry))[crashReporterTarget]!;
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
      // The reporter and its own gateway run on the VM only: telemetry_setup_io.dart imports them.
      const vmReporter = <String>{
        'lib/_core/telemetry/crash_reporter.dart',
        'lib/_core/telemetry/crashlytics_gateway.dart',
      };
      for (final reporter in CrashReporter.values) {
        // What the web build compiles: the code of the app and of packages/ui (tools and tests
        // run on the VM; the module is checked through what imports it).
        final compiled = (await projectDartFiles(reporter)).entries.where(
          (file) =>
              (file.key.startsWith('lib/') || file.key.startsWith('packages/')) &&
              !telemetryModuleFiles.any((module) => file.key == '$telemetryModuleTarget$module'),
        );
        for (final MapEntry(key: path, value: text) in compiled) {
          final vmOnly =
              path.endsWith('_io.dart') ||
              path.endsWith('_vm.dart') ||
              path.endsWith('_windows.dart') ||
              vmReporter.contains(path);
          final reason = '${reporter.name}: $path';
          for (final match in directive.allMatches(text)) {
            final uri = match.group(1)!;
            if (vmOnly) continue;
            expect(uri, isNot('dart:io'), reason: reason);
            expect(uri, isNot('dart:ffi'), reason: reason);
            if (uri == io) {
              expect(match.group(2), contains("'$web'"), reason: '$reason imports the VM half');
            }
            for (final file in vmReporter) {
              expect(uri, isNot('package:my_app/${file.substring('lib/'.length)}'), reason: reason);
            }
            for (final file in telemetryModuleFiles.where((file) => !webSafe.contains(file))) {
              expect(uri, isNot('package:my_app/_core/telemetry/$file'), reason: reason);
            }
            expect(uri, isNot(startsWith('package:firebase_')), reason: reason);
          }
        }
      }
    });
  });

  group('crash reporter', () {
    test('pub add of each reporter', () {
      expect(crashReporterPubAddArguments(CrashReporter.sentry), <String>['sentry']);
      expect(crashReporterPubAddArguments(CrashReporter.crashlytics), <String>[
        'sentry',
        'firebase_core',
        'firebase_crashlytics',
      ]);
      expect(crashReporterPubAddArguments(CrashReporter.logOnly), isEmpty);
      for (final reporter in CrashReporter.values) {
        final arguments = skeletonPubAddArgumentsFor(
          uiPath: 'packages/ui',
          crashReporter: reporter,
        );
        final names = packagesOf(arguments);
        expect(names, hasLength(names.toSet().length), reason: reporter.name);
        expect(
          names.where(const <String>{'sentry', 'firebase_core', 'firebase_crashlytics'}.contains),
          crashReporterPubAddArguments(reporter),
          reason: reporter.name,
        );
      }
      expect(skeletonPubAddArguments, contains('sentry'));
      expect(skeletonPubAddArguments, isNot(contains('firebase_core')));
    });

    test('each reporter is one asset written as crash_reporter.dart', () async {
      expect(crashReporterTarget, 'lib/_core/telemetry/crash_reporter.dart');
      expect(
        <String>{for (final reporter in CrashReporter.values) crashReporterFile(reporter)},
        <String>{
          'lib/_core/telemetry/crash_reporter_sentry.dart',
          'lib/_core/telemetry/crash_reporter_crashlytics.dart',
          'lib/_core/telemetry/crash_reporter_log_only.dart',
        },
      );
      for (final reporter in CrashReporter.values) {
        final files = crashReporterTemplateFiles(reporter);
        expect(files[crashReporterFile(reporter)], crashReporterTarget, reason: reporter.name);
        for (final from in files.keys) {
          expect(
            await rootBundle.loadString('$projectTemplateRoot$from'),
            isNotEmpty,
            reason: from,
          );
          expect(projectTemplateFiles, isNot(contains(from)), reason: from);
        }
        final text = (await reporterFiles(reporter))[crashReporterTarget]!;
        // telemetry_setup_io.dart calls all three.
        expect(text, contains('Future<ICrashReportGateway?> createCrashReportGateway({'));
        expect(text, contains('required Set<String> projectPackages'));
        expect(text, contains('bool get crashReporterConfigured'));
        expect(text, contains('Future<void> closeCrashReportGateway(ICrashReportGateway gateway)'));
        expect(text, isNot(contains('{{')));
      }
      // Only the chosen reporter's files: Sentry and log only bring nothing else.
      expect(crashReporterTemplateFiles(CrashReporter.sentry), hasLength(1));
      expect(crashReporterTemplateFiles(CrashReporter.logOnly), hasLength(1));
      expect(crashReporterTemplateFiles(CrashReporter.crashlytics).values, <String>[
        crashReporterTarget,
        'lib/_core/telemetry/crashlytics_gateway.dart',
        'test/_core/telemetry/crash_reporter_test.dart',
      ]);
    });

    final reporterImport = RegExp(
      r'''^\s*(?:import|export)\s+'package:(sentry|firebase_[a-z_]+)/''',
      multiLine: true,
    );

    test('a log-only project has no Sentry and no Firebase', () async {
      expect(
        telemetryModuleFilesFor(CrashReporter.logOnly),
        isNot(contains('sentry_gateway.dart')),
      );
      expect(
        telemetryModuleTestFilesFor(CrashReporter.logOnly),
        isNot(contains('sentry_gateway_test.dart')),
      );
      final files = await projectDartFiles(CrashReporter.logOnly);
      for (final MapEntry(key: path, value: text) in files.entries) {
        expect(reporterImport.hasMatch(text), isFalse, reason: path);
        expect(text, isNot(contains('sentry_gateway.dart')), reason: path);
      }
      expect(files['lib/_core/telemetry/telemetry.dart'], contains('telemetry_sender.dart'));
      // Sentry and Crashlytics keep the whole module.
      for (final reporter in <CrashReporter>[CrashReporter.sentry, CrashReporter.crashlytics]) {
        expect(telemetryModuleFilesFor(reporter), telemetryModuleFiles);
        expect(telemetryModuleTestFilesFor(reporter), telemetryModuleTestFiles);
        expect(
          (await copiedModule(reporter))['lib/_core/telemetry/telemetry.dart'],
          contains('sentry_gateway.dart'),
        );
      }
    });

    test('Crashlytics sits behind the queue and only its gateway imports it', () async {
      final files = await projectDartFiles(CrashReporter.crashlytics);
      // The app's own handler (initialization.dart) sends Flutter errors to ErrorUtil; the
      // reporter never takes it over.
      for (final path in crashReporterTemplateFiles(CrashReporter.crashlytics).values) {
        expect(files[path], isNot(contains('FlutterError.onError')), reason: path);
        expect(files[path], isNot(contains('recordFlutter')), reason: path);
      }
      for (final MapEntry(key: path, value: text) in files.entries) {
        final crashlytics = text.contains("import 'package:firebase_crashlytics/");
        expect(crashlytics, path == 'lib/_core/telemetry/crashlytics_gateway.dart', reason: path);
      }
      final gateway = files['lib/_core/telemetry/crashlytics_gateway.dart']!;
      expect(gateway, contains('implements ICrashReportGateway'));
      expect(gateway, contains('recordError('));
      expect(gateway, contains('setCrashlyticsCollectionEnabled(true)'));
      final reporter = files[crashReporterTarget]!;
      expect(reporter, contains('Firebase.initializeApp'));
      expect(reporter, contains("hint: 'Firebase is not configured'"));
      expect(reporter, contains('SentryGateway('));
      expect(files, contains('test/_core/telemetry/crash_reporter_test.dart'));
    });

    test('Sentry imports no Firebase', () async {
      for (final MapEntry(key: path, value: text) in (await projectDartFiles(
        CrashReporter.sentry,
      )).entries) {
        expect(text, isNot(contains('package:firebase_')), reason: path);
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
      for (final reporter in CrashReporter.values)
        for (final from in crashReporterTemplateFiles(reporter).keys) from: await filled(from),
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
      // packages/ui: its template pubspec, then what FAgent adds to it.
      final ui = <String>['ui', 'flutter', 'intl', 'collection', ...uiPubAddArguments];
      final usedByUi = <String>{};
      for (final reporter in CrashReporter.values) {
        final app = <String>[
          'my_app',
          'flutter',
          'flutter_test',
          ...packagesOf(skeletonPubAddArgumentsFor(uiPath: 'packages/ui', crashReporter: reporter)),
        ];
        for (final MapEntry(key: path, value: text) in (await projectDartFiles(reporter)).entries) {
          final inUi = path.startsWith('packages/ui/');
          for (final match in packageImport.allMatches(text)) {
            final name = match.group(1)!;
            expect(
              inUi ? ui : app,
              contains(name),
              reason: '${reporter.name}: $path: ${match.group(0)}',
            );
            if (inUi) usedByUi.add(name);
          }
        }
      }
      // packages/ui gets exactly the ones its files import.
      expect(
        uiPubAddArguments.toSet(),
        usedByUi.intersection(const <String>{'material_ui', 'cupertino_ui'}),
      );
    });
  });

  group('monorepo shared packages', () {
    final directive = RegExp(r"""^\s*(?:import|export)\s+'([^']+)'([^;]*);""", multiLine: true);

    /// The URIs [text] imports or exports.
    List<String> directivesOf(String text) => <String>[
      for (final match in directive.allMatches(text)) match.group(1)!,
    ];

    /// The files of the three shared packages as a monorepo with [reporter] gets them, keyed by
    /// their path in the monorepo.
    Future<Map<String, String>> sharedFiles([
      CrashReporter reporter = CrashReporter.sentry,
    ]) async => <String, String>{
      for (final path in sharedPackageTemplateFiles)
        path: fillProjectTemplate(
          await rootBundle.loadString('$monorepoTemplateRoot$path'),
          package: 'shop',
          date: DateTime(2026, 11, 6),
        ),
      for (final MapEntry(key: from, value: to) in sharedPackageSources.entries)
        to: sharedPackageSource(await filled(from), package: 'my_app'),
      for (final file in telemetryModuleFilesFor(reporter))
        '$sharedTelemetryModuleTarget$file': copyTelemetryModule(
          await rootBundle.loadString('$telemetryModuleRoot$file'),
          importPrefix: sharedTelemetryImportPrefix,
          crashReporter: reporter,
        ),
      for (final file in telemetryModuleTestFilesFor(reporter))
        '$sharedTelemetryModuleTestTarget$file': copyTelemetryModule(
          await rootBundle.loadString('$telemetryModuleTestRoot$file'),
          importPrefix: sharedTelemetryImportPrefix,
          crashReporter: reporter,
        ),
    };

    /// The Dart files of a monorepo app `my_app` with [reporter], keyed by their path in the app.
    Future<Map<String, String>> appFiles(CrashReporter reporter) async => <String, String>{
      for (final path in projectTemplateAppFiles.where((path) => path.endsWith('.dart')))
        path: monorepoAppFile(await filled(path), package: 'my_app'),
      for (final MapEntry(key: path, value: text) in (await reporterFiles(reporter)).entries)
        path: monorepoAppFile(text, package: 'my_app'),
    };

    /// The files of [package] that `lib/<package>.dart` reaches through `export`s, as paths in
    /// the monorepo.
    Set<String> exportedBy(Map<String, String> files, String package) {
      final reached = <String>{};
      void visit(String path) {
        if (!reached.add(path)) return;
        final text = files[path];
        expect(text, isNotNull, reason: 'exported but not written: $path');
        for (final match in RegExp(
          "^export 'package:$package/([^']+)'",
          multiLine: true,
        ).allMatches(text!)) {
          visit('packages/$package/lib/${match.group(1)}');
        }
      }

      visit('packages/$package/lib/$package.dart');
      return reached..remove('packages/$package/lib/$package.dart');
    }

    test('three packages next to packages/ui, no core', () {
      expect(monorepoSharedPackages, <String>['telemetry', 'database', 'api_client']);
      for (final name in monorepoSharedPackages) {
        expect(
          sharedPackageTemplateFiles,
          containsAll(<String>['packages/$name/pubspec.yaml', 'packages/$name/lib/$name.dart']),
        );
      }
      for (final path in <String>[...sharedPackageTemplateFiles, ...sharedPackageSources.values]) {
        expect(
          monorepoSharedPackages.any((name) => path.startsWith('packages/$name/')),
          isTrue,
          reason: path,
        );
      }
    });

    test('every file of the three packages is an asset', () async {
      expect(sharedPackageTemplateFiles, hasLength(sharedPackageTemplateFiles.toSet().length));
      for (final path in sharedPackageTemplateFiles) {
        final text = await rootBundle.loadString('$monorepoTemplateRoot$path');
        expect(text, isNotEmpty, reason: path);
      }
      // The code of database and api_client is the one app's lib/_core/: one source.
      expect(
        sharedPackageSources.keys.toSet(),
        projectTemplateFiles
            .where(
              (path) =>
                  path.startsWith('lib/_core/database/') ||
                  path.startsWith('lib/_core/api_client/'),
            )
            .toSet(),
      );
      for (final MapEntry(key: from, value: to) in sharedPackageSources.entries) {
        final folder = from.startsWith('lib/_core/database/') ? 'database' : 'api_client';
        expect(
          to,
          'packages/$folder/lib/src/${from.substring('lib/_core/$folder/'.length)}',
          reason: from,
        );
      }
    });

    test(
      'the module lands in packages/telemetry/lib/src/ and telemetry.dart exports it all',
      () async {
        expect(sharedTelemetryModuleTarget, 'packages/telemetry/lib/src/');
        expect(sharedTelemetryModuleTestTarget, 'packages/telemetry/test/');
        expect(sharedTelemetryImportPrefix, 'package:telemetry/src/');
        for (final reporter in CrashReporter.values) {
          final files = await sharedFiles(reporter);
          expect(exportedBy(files, 'telemetry'), <String>{
            for (final file in telemetryModuleFilesFor(reporter))
              '$sharedTelemetryModuleTarget$file',
          }, reason: reporter.name);
          for (final file in telemetryModuleTestFilesFor(reporter)) {
            expect(
              files['$sharedTelemetryModuleTestTarget$file'],
              contains("'package:telemetry/src/"),
              reason: file,
            );
          }
        }
      },
    );

    test('portable.dart exports the part of the module that compiles for the web', () async {
      final files = await sharedFiles();
      expect(directivesOf(files['packages/telemetry/lib/portable.dart']!).toSet(), <String>{
        for (final file in portableTelemetryFiles) '$sharedTelemetryImportPrefix$file',
      });
      for (final file in portableTelemetryFiles) {
        for (final uri in directivesOf(files['$sharedTelemetryModuleTarget$file']!)) {
          expect(
            uri == 'dart:async' ||
                uri.startsWith('package:l/') ||
                portableTelemetryFiles.any((other) => uri == '$sharedTelemetryImportPrefix$other'),
            isTrue,
            reason: '$file: $uri',
          );
        }
      }
    });

    test('api_client.dart exports ExpectedException and RejectedException', () async {
      final files = await sharedFiles();
      final exported = exportedBy(files, 'api_client');
      expect(exported, <String>{
        for (final path in sharedPackageSources.values)
          if (path.startsWith('packages/api_client/')) path,
      });
      final declarations = exported.map((path) => files[path]!).join('\n');
      expect(declarations, contains('abstract base class ExpectedException '));
      expect(declarations, contains('final class RejectedException extends ExpectedException '));
      expect(exportedBy(files, 'database'), <String>{'packages/database/lib/src/database.dart'});
    });

    test('no package file imports package:{{package}} or an app', () async {
      for (final reporter in CrashReporter.values) {
        for (final MapEntry(key: path, value: text) in (await sharedFiles(reporter)).entries) {
          expect(text, isNot(contains('{{')), reason: path);
          expect(text, isNot(contains('flutter_code_agent')), reason: path);
          for (final uri in directivesOf(text)) {
            expect(uri, isNot(startsWith('package:my_app/')), reason: path);
            expect(uri, isNot(startsWith('package:shop')), reason: path);
            expect(uri, isNot('package:flutter/material.dart'), reason: path);
          }
        }
      }
    });

    test('each package pubspec joins the workspace', () async {
      final files = await sharedFiles();
      for (final name in monorepoSharedPackages) {
        final pubspec = files['packages/$name/pubspec.yaml']!;
        expect(pubspec, startsWith('name: $name\n'), reason: name);
        expect(pubspec, contains('\nresolution: workspace\n'), reason: name);
        expect(pubspec, contains('\nenvironment:\n  sdk: '), reason: name);
        expect(pubspec, contains("publish_to: 'none'"), reason: name);
        // The Flutter tool stages plugins in build/, and scripts/test.bash writes its reports.
        expect(files['packages/$name/.gitignore']!.split('\n'), contains('/build/'), reason: name);
      }
    });

    test('each package imports only what its pubspec and pub add give it, and uses all', () async {
      final packageImport = RegExp("(?:import|export) 'package:([a-z_0-9]+)/");
      for (final reporter in CrashReporter.values) {
        final files = await sharedFiles(reporter);
        for (final name in monorepoSharedPackages) {
          final pubspec = files['packages/$name/pubspec.yaml']!;
          final own = <String>[
            name,
            for (final match in RegExp('^  ([a-z_0-9]+):', multiLine: true).allMatches(pubspec))
              match.group(1)!,
            ...packagesOf(sharedPackagePubAddArguments(name, crashReporter: reporter)),
          ];
          final used = <String>{};
          for (final MapEntry(key: path, value: text) in files.entries) {
            if (!path.startsWith('packages/$name/') || !path.endsWith('.dart')) continue;
            for (final match in packageImport.allMatches(text)) {
              expect(own, contains(match.group(1)), reason: '${reporter.name}: $path');
              used.add(match.group(1)!);
            }
          }
          for (final argument in sharedPackagePubAddArguments(name, crashReporter: reporter)) {
            if (argument.startsWith('dev:')) continue;
            expect(
              used,
              contains(packagesOf(<String>[argument]).single),
              reason: '$name $argument',
            );
          }
        }
      }
      expect(
        sharedPackagePubAddArguments('telemetry', crashReporter: CrashReporter.logOnly),
        isNot(contains('sentry')),
      );
      for (final reporter in <CrashReporter>[CrashReporter.sentry, CrashReporter.crashlytics]) {
        expect(
          sharedPackagePubAddArguments('telemetry', crashReporter: reporter),
          contains('sentry'),
        );
      }
      // The drift databases are generated by the workspace's build_runner.
      for (final name in const <String>['telemetry', 'database']) {
        expect(
          sharedPackagePubAddArguments(name),
          containsAll(<String>['dev:build_runner', 'dev:drift_dev']),
        );
      }
    });

    test('the app glue imports the packages, not copies in lib/_core', () async {
      for (final reporter in CrashReporter.values) {
        final files = await appFiles(reporter);
        for (final MapEntry(key: path, value: text) in files.entries) {
          final uris = directivesOf(text);
          final reason = '${reporter.name}: $path';
          expect(uris, hasLength(uris.toSet().length + _exportsOfImported(text)), reason: reason);
          for (final uri in uris) {
            expect(uri, isNot(startsWith('package:my_app/_core/database/')), reason: reason);
            expect(uri, isNot(startsWith('package:my_app/_core/api_client/')), reason: reason);
            for (final file in telemetryModuleFiles) {
              expect(uri, isNot('package:my_app/_core/telemetry/$file'), reason: reason);
            }
          }
        }
        expect(
          files['lib/_core/telemetry/telemetry_setup_io.dart'],
          contains("import 'package:telemetry/telemetry.dart';"),
        );
        final expected = files['lib/_core/telemetry/expected_failure.dart']!;
        expect(expected, contains("import 'package:api_client/api_client.dart';"));
        expect(
          expected,
          contains("<String>{'my_app', 'ui', 'telemetry', 'database', 'api_client'}"),
        );
      }
      // One app keeps its own copies.
      expect(
        monorepoAppFile(await filled('lib/_core/telemetry/error_util.dart'), package: 'my_app'),
        await filled('lib/_core/telemetry/error_util.dart'),
      );
    });

    test('the web build of a monorepo app reaches only the portable part', () async {
      const vmOnly = <String>{
        'lib/_core/telemetry/crash_reporter.dart',
        'lib/_core/telemetry/crashlytics_gateway.dart',
      };
      for (final reporter in CrashReporter.values) {
        final files = await appFiles(reporter);
        for (final MapEntry(key: path, value: text) in files.entries) {
          if (!path.startsWith('lib/') ||
              path.endsWith('_io.dart') ||
              path.endsWith('_vm.dart') ||
              path.endsWith('_windows.dart') ||
              vmOnly.contains(path)) {
            continue;
          }
          for (final uri in directivesOf(text)) {
            expect(uri, isNot('package:telemetry/telemetry.dart'), reason: '$path: $uri');
            expect(uri, isNot(startsWith('package:telemetry/src/')), reason: '$path: $uri');
            expect(uri, isNot(startsWith('package:database/')), reason: '$path: $uri');
          }
        }
        expect(
          files['lib/_core/telemetry/app_zone.dart'],
          contains("import 'package:telemetry/portable.dart';"),
        );
        expect(
          files['lib/_core/telemetry/telemetry_setup_web.dart'],
          contains("import 'package:telemetry/portable.dart';"),
        );
      }
    });

    test('pub add of a monorepo app adds the three packages by path', () async {
      final arguments = skeletonPubAddArgumentsFor(
        uiPath: '../../packages/ui',
        sharedPackagesPath: '../../packages',
      );
      expect(
        arguments,
        containsAll(<String>[
          'ui@{path: ../../packages/ui}',
          'telemetry@{path: ../../packages/telemetry}',
          'database@{path: ../../packages/database}',
          'api_client@{path: ../../packages/api_client}',
        ]),
      );
      for (final one in <List<String>>[
        skeletonPubAddArguments,
        skeletonPubAddArgumentsFor(uiPath: '../../packages/ui'),
      ]) {
        for (final name in monorepoSharedPackages) {
          expect(packagesOf(one), isNot(contains(name)));
        }
      }
      // What only the packages import stays with them.
      for (final name in const <String>['http', 'drift', 'drift_flutter', 'sentry', 'clock']) {
        expect(packagesOf(arguments), isNot(contains(name)), reason: name);
      }
      final packageImport = RegExp("(?:import|export) 'package:([a-z_0-9]+)/");
      for (final reporter in CrashReporter.values) {
        final installed = <String>[
          'my_app',
          'flutter',
          'flutter_test',
          ...packagesOf(
            skeletonPubAddArgumentsFor(
              uiPath: '../../packages/ui',
              sharedPackagesPath: '../../packages',
              crashReporter: reporter,
            ),
          ),
        ];
        for (final MapEntry(key: path, value: text) in (await appFiles(reporter)).entries) {
          for (final match in packageImport.allMatches(text)) {
            expect(installed, contains(match.group(1)), reason: '${reporter.name}: $path');
          }
        }
      }
    });

    test('the crash reporter of a monorepo is kept in packages/telemetry', () {
      expect(crashReporterConfigPath, 'packages/telemetry/crash_reporter.yaml');
      for (final reporter in CrashReporter.values) {
        final config = crashReporterConfig(reporter);
        expect(config, contains('\nreporter: ${reporter.name}\n'));
        expect(readCrashReporterConfig(config), reporter);
      }
      expect(readCrashReporterConfig('reporter: firebase\n'), isNull);
      expect(readCrashReporterConfig(''), isNull);
    });

    test('the monorepo Makefile runs with the root config/sentry.local.json', () async {
      final makefile = await rootBundle.loadString('${monorepoTemplateRoot}Makefile');
      expect(makefile, contains(r'$(wildcard config/sentry.local.json)'));
      expect(makefile, contains('--dart-define-from-file=../../config/sentry.local.json'));
      final run = RegExp(
        r'^run:.*\n\t@cd apps/\$\(APP\) && flutter run ([^\n]*)',
        multiLine: true,
      ).firstMatch(makefile);
      expect(run?.group(1), contains(r'$(SENTRY)'));
    });
  });
}

/// How many `export`s of [text] repeat the URI of one of its `import`s (`export … show X` next to
/// the `import` of the same library).
int _exportsOfImported(String text) {
  final imports = <String>{
    for (final match in RegExp("^import '([^']+)'", multiLine: true).allMatches(text))
      match.group(1)!,
  };
  return RegExp(
    "^export '([^']+)'",
    multiLine: true,
  ).allMatches(text).where((match) => imports.contains(match.group(1))).length;
}
