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
        'lib/_core/utils/api_client.dart',
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

  group('material_ui', () {
    test('Flutter 3.47 and newer use it; older, unknown or garbled versions do not', () {
      expect(kMaterialUiMinFlutter, '3.47');
      for (final version in const <String?>[null, '', 'abc', '3', '3.44.0', '3.46.9', '2.99.0']) {
        expect(usesMaterialUi(version), isFalse, reason: version);
      }
      for (final version in const <String>[
        '3.47.0',
        '3.47.0-1.0.pre',
        '3.50.0',
        '3.100.1',
        '4.0.0',
      ]) {
        expect(usesMaterialUi(version), isTrue, reason: version);
      }
    });

    test('rewrites the export of material.dart', () {
      expect(
        useMaterialUi("library;\n\nexport 'package:flutter/material.dart';\n"),
        "library;\n\nexport 'package:material_ui/material_ui.dart';\n",
      );
    });

    test('rewrites material and cupertino imports', () {
      expect(
        useMaterialUi(
          "import 'dart:async';\n"
          "import 'package:flutter/material.dart';\n"
          "import 'package:flutter/cupertino.dart';\n"
          "import 'package:flutter/widgets.dart';\n",
        ),
        "import 'dart:async';\n"
        "import 'package:material_ui/material_ui.dart';\n"
        "import 'package:cupertino_ui/cupertino_ui.dart';\n"
        "import 'package:flutter/widgets.dart';\n",
      );
    });

    test('leaves a file without those imports as it is', () {
      const source = "import 'package:flutter/widgets.dart';\n\nvoid main() {}\n";
      expect(useMaterialUi(source), source);
    });

    test(
      'app.dart takes the delegates from material_ui, cupertino_ui and flutter_localizations',
      () async {
        final text = await rootBundle.loadString(
          '${projectTemplateRoot}lib/initialization/widget/app.dart',
        );
        final rewritten = useMaterialUi(text);
        expect(
          rewritten,
          startsWith(
            "import 'package:material_ui/material_ui.dart';\n"
            "import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;\n"
            "import 'package:flutter_localizations/flutter_localizations.dart' "
            'show GlobalWidgetsLocalizations;\n',
          ),
        );
        // The code itself is untouched.
        expect(
          rewritten.substring(rewritten.indexOf('\n\n')),
          text.substring(text.indexOf('\n\n')),
        );
      },
    );

    test('a file that names a delegate without importing material_ui gets it shown', () {
      expect(
        useMaterialUi(
          "import 'package:flutter_localizations/flutter_localizations.dart';\n"
          'final a = GlobalMaterialLocalizations.delegate;\n',
        ),
        "import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;\n"
        'final a = GlobalMaterialLocalizations.delegate;\n',
      );
    });

    test('no template file imports a deprecated library after the rewrite', () async {
      final import = RegExp("^import '([^']+)'([^;]*);", multiLine: true);
      for (final path in projectTemplateFiles.where((path) => path.endsWith('.dart'))) {
        final text = await rootBundle.loadString('$projectTemplateRoot$path');
        final rewritten = useMaterialUi(
          fillProjectTemplate(text, package: 'my_app', date: DateTime(2026, 11, 6)),
        );
        expect(rewritten, isNot(contains('package:flutter/material.dart')), reason: path);
        expect(rewritten, isNot(contains('package:flutter/cupertino.dart')), reason: path);
        for (final match in import.allMatches(rewritten)) {
          if (match.group(1) != 'package:flutter_localizations/flutter_localizations.dart')
            continue;
          // Only what flutter_localizations has that is not deprecated.
          expect(match.group(2)!.trim(), 'show GlobalWidgetsLocalizations', reason: path);
        }
      }
    });

    test('the rewritten template imports only packages its pub add installs', () async {
      final packageImport = RegExp("import 'package:([a-z_0-9]+)/");
      List<String> names(List<String> arguments) => <String>[
        for (final argument in arguments)
          RegExp('^(?:dev:)?([a-z_0-9]+)').firstMatch(argument)!.group(1)!,
      ];
      final app = <String>[
        'my_app',
        'flutter',
        'flutter_test',
        ...names(skeletonPubAddArgumentsFor(uiPath: 'packages/ui', materialUi: true)),
      ];
      // packages/ui: its template pubspec, then what FAgent adds to it.
      final ui = <String>['ui', 'flutter', 'intl', 'collection', ...uiMaterialUiPackages];
      final usedByUi = <String>{};
      for (final path in projectTemplateFiles.where((path) => path.endsWith('.dart'))) {
        final text = await rootBundle.loadString('$projectTemplateRoot$path');
        final rewritten = useMaterialUi(
          fillProjectTemplate(text, package: 'my_app', date: DateTime(2026, 11, 6)),
        );
        final inUi = path.startsWith('packages/ui/');
        for (final match in packageImport.allMatches(rewritten)) {
          final name = match.group(1)!;
          expect(inUi ? ui : app, contains(name), reason: '$path: ${match.group(0)}');
          if (inUi) usedByUi.add(name);
        }
      }
      // packages/ui gets exactly the ones its files import.
      expect(
        uiMaterialUiPackages.toSet(),
        usedByUi.intersection(const <String>{'material_ui', 'cupertino_ui'}),
      );
    });

    test('pub add gets material_ui and cupertino_ui only when asked', () {
      final arguments = skeletonPubAddArgumentsFor(uiPath: 'packages/ui', materialUi: true);
      expect(arguments, containsAll(<String>['material_ui', 'cupertino_ui']));
      expect(
        arguments.where((argument) => argument != 'material_ui' && argument != 'cupertino_ui'),
        skeletonPubAddArguments,
      );
      expect(skeletonPubAddArguments, isNot(contains('material_ui')));
      expect(skeletonPubAddArguments, isNot(contains('cupertino_ui')));
    });
  });
}
