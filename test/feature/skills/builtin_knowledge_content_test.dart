@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Checks the files under `assets/knowledge/` on disk: the set of built-in rules, their
/// frontmatter, that they carry the skills merged into them, and that their code examples compile.
void main() {
  final knowledge = Directory('assets/knowledge');
  final rulesDirectory = Directory(p.join(knowledge.path, 'rules'));

  final ruleFiles = rulesDirectory.listSync().whereType<File>().toList();
  String name(FileSystemEntity entity) => p.basenameWithoutExtension(entity.path);
  String rule(String name) => File(p.join(rulesDirectory.path, '$name.md')).readAsStringSync();

  /// The `## ` headings of every skill merged into a rule, by rule, as the skills had them.
  const mergedHeadings = <String, List<String>>{
    'controllers': <String>[
      'Single responsibility',
      'Mutation features (creation, deletion)',
      'Multiple controllers in one feature',
      'Template',
      'Convenience getters on the state',
      'Triggering `paginate` from the widget',
      'Non-paginated lists',
      'Refinements, where the screen earns them',
    ],
    'dependencies': <String>[
      'Global: `Dependencies` and `DependenciesScope`',
      'Feature level: config widgets',
      'Reaching feature dependencies',
      'Interfaces and constructor injection',
    ],
    'repositories': <String>[
      'Pattern 1: `onListen` / `onCancel` (lazy, resource-safe)',
      'Pattern 2: `async Future` wrapper (simpler)',
      'One-shot helpers',
      'Steps',
      'Checks',
    ],
    'architecture': <String>[
      'Project structure',
      'Layers and dependency direction',
      'List / screen feature',
      'Creation / update feature',
      'Deletion feature',
      'By-id loader feature',
      'Models and JSON converters',
      'Repositories',
      'Local database tables',
      'Localization',
      'Reusable widgets',
      'Widgets',
      'Steps for a new feature',
    ],
    'package-freshness': <String>['Steps', 'Notes'],
    // The widget-test skill, then moved with the unit-test knowledge into `testing`.
    'testing': <String>['Steps', 'Rules', 'Widget test', 'Time in unit tests: fakeAsync'],
  };

  /// The template files the skills shipped; each is now a `// file:` block of a rule.
  const exampleFiles = <String>{
    'example_creation_controller.dart',
    'example_deletion_controller.dart',
    'example_deletion_dialog.dart',
    'example_mutation_repositories.dart',
    'dependencies.dart',
    'example.dart',
    'example_config_widget.dart',
    'example_controller.dart',
    'example_data_controller.dart',
    'example_json_converter.dart',
    'example_repository.dart',
    'example_widget.dart',
    'local_pagination_util.dart',
    'product.dart',
    'products_controller.dart',
    'products_data_controller.dart',
    'products_list_widget.dart',
    'products_repository.dart',
    'example_stream_repository.dart',
    'app_pages.dart',
    'app_navigator.dart',
    'app.dart',
    'patterns.dart',
    'flip_card.dart',
    'message_bubble.dart',
    'initialization.dart',
    'context_extension.dart',
    'dispose_all.dart',
    'sign_in_form.dart',
    'loading_overlay.dart',
    'analytics_reporter.dart',
    'story_repository.dart',
    'disposer.dart',
    'preferences_entry.dart',
    'auth_session.dart',
    'rpc_connection.dart',
    'ticket.dart',
    'size_reporter.dart',
    'value_types.dart',
    'app_theme.dart',
    'app_brand.dart',
    'order_status.dart',
    'anchored_popup.dart',
    'app_exception.dart',
    'background_prefs.dart',
    'camera.dart',
    'cancellable_import.dart',
    'isolate_worker.dart',
    'lazy_future.dart',
    'line_coverage.dart',
    'listenable_select.dart',
    'markup_text.dart',
    'payments_data_provider.dart',
    'save_shortcut.dart',
    'section_sliver.dart',
    'sign_in_guards.dart',
    'test_shards.dart',
    'ui_button.dart',
    'window_class.dart',
    // Lazebny, page 2.
    'analytics_event.dart',
    'map_in_chunks.dart',
    'profile_screen_data.dart',
    'settings_model.dart',
  };

  /// The `dart` blocks of every rule that start with `// file: <name>.dart`, by name.
  Map<String, String> examples() {
    final blocks = <String, String>{};
    final fence = RegExp(r'```dart\n// file: ([\w.]+\.dart)\n([\s\S]*?)\n```');
    for (final file in ruleFiles) {
      for (final match in fence.allMatches(file.readAsStringSync())) {
        expect(blocks.containsKey(match.group(1)), isFalse, reason: 'Duplicate ${match.group(1)}');
        blocks[match.group(1)!] = '${match.group(2)}\n';
      }
    }
    return blocks;
  }

  test('the built-in rules are the expected set', () {
    expect(ruleFiles.map(name).toSet(), <String>{
      'architecture',
      'controllers',
      'repositories',
      'dependencies',
      'widgets',
      'testing',
      'navigation',
      'configuration',
      'dart',
      'localization',
      'package-freshness',
      'generated-files',
      'web',
      'security',
      'documentation',
      'isolates',
      'tooling',
    });
  });

  test('no built-in skills ship', () {
    expect(Directory(p.join(knowledge.path, 'skills')).existsSync(), isFalse);
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('assets/knowledge/skills')));
  });

  test('every merged rule keeps the sections of its skills', () {
    for (final MapEntry(key: name, value: headings) in mergedHeadings.entries) {
      final text = rule(name);
      for (final heading in headings) {
        expect(
          RegExp('^#{2,3} ${RegExp.escape(heading)}\$', multiLine: true).hasMatch(text),
          isTrue,
          reason: '$name.md has no "$heading" section',
        );
      }
    }
  });

  test('every example of the skills is a block of a rule', () {
    expect(examples().keys.toSet(), exampleFiles);
  });

  test('every rule has frontmatter with its name and a description', () {
    for (final file in ruleFiles) {
      final fields = parseFrontmatter(file.readAsStringSync())?.fields;
      expect(fields, isNotNull, reason: '${file.path} has no frontmatter');
      expect(fields!['name'], name(file), reason: file.path);
      expect(fields['description'], isNotEmpty, reason: file.path);
    }
  });

  test('no built-in file carries this repository\'s own overrides', () {
    const forbidden = <String>['Desktop only', 'No ApiClient', 'flutter_code_agent'];
    for (final entity in knowledge.listSync(recursive: true).whereType<File>()) {
      final text = entity.readAsStringSync();
      for (final phrase in forbidden) {
        expect(text, isNot(contains(phrase)), reason: '${entity.path} contains "$phrase"');
      }
    }
  });

  test(
    'the code examples compile',
    () async {
      final fixture = Directory('test/fixtures/knowledge_templates');
      final lib = Directory(p.join(fixture.path, 'lib'));
      if (lib.existsSync()) lib.deleteSync(recursive: true);
      lib.createSync();
      addTearDown(() => lib.deleteSync(recursive: true));

      final seen = <String>{};
      for (final MapEntry(key: fileName, value: code) in examples().entries) {
        seen.add(fileName);
        File(p.join(lib.path, fileName)).writeAsStringSync(code);
      }
      expect(seen, isNotEmpty);
      // The rules build on the HTTP client a new project gets; their examples import it by name.
      expect(seen, isNot(contains('api_client.dart')));
      File(
        'assets/project_template/architecture/lib/src/_core/utils/api_client.dart',
      ).copySync(p.join(lib.path, 'api_client.dart'));

      Future<void> run(String executable, List<String> arguments) async {
        final result = await Process.run(executable, arguments, workingDirectory: fixture.path);
        expect(
          result.exitCode,
          0,
          reason: '$executable ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
        );
      }

      await run('flutter', <String>['pub', 'get']);
      await run('dart', <String>['run', 'build_runner', 'build', '--delete-conflicting-outputs']);
      await run('dart', <String>['analyze', '--fatal-infos']);
    },
    tags: 'flutter',
    timeout: const Timeout(Duration(minutes: 10)),
    skip: Platform.environment['FLUTTER_RUN_TEST'] == '1'
        ? false
        : 'Compiles the templates with the real toolchain; set FLUTTER_RUN_TEST=1',
  );

  test('the knowledge passes added their sections', () {
    const sections = <String, List<String>>{
      'controllers': <String>[
        'One recipe for states',
        'Other state management packages',
        'Testing a controller',
        'Creating a controller for a screen',
        'What a controller is',
        'One queue per controller',
        'Publishers and subscribers',
        'Observer, publish/subscribe and a state machine',
        'Filters and reloading',
        'Cached data first, then fresh',
        'Where the rethrown error goes',
        'Ephemeral and application state',
        'Optimistic update',
        'Expected and unexpected errors',
      ],
      'dependencies': <String>[
        'HTTP middleware',
        'Pure DI, not a service locator',
        'Startup and creating dependencies',
        'HTTP clients',
        'Initialization steps',
        'Uncaught errors',
        'Callbacks instead of references',
        'Context shortcuts',
        'Retrying a failed startup',
      ],
      'repositories': <String>[
        'Errors',
        'No state in a repository',
        'Choosing a transport',
        'Long-lived connections (WebSocket, SSE)',
        'Mistakes with streams',
        'Release in reverse order',
        'Preference entries',
        'Releasing resources',
        'Local storage',
        'Searching text',
        'Files and blobs',
        'A type for each failure the app acts on',
        'Cancelling a multi-step operation',
        'Decoding response bodies',
      ],
      'configuration': <String>[
        'Build-time values',
        'Flavors',
        'Versioning',
        'Changelog',
        'Secrets',
        'Assets and fonts',
        'Icons',
        'Asset transformers',
        'Web bundle size',
      ],
      'dart': <String>[
        'Patterns',
        '`Never`',
        'Platform-specific code',
        r'Names with `$`',
        'Zones',
        'Enums',
        'Value types with extension types',
        'Cached futures',
        'Debug-only code',
        'Sorting',
        'Errors and exceptions',
        'Waiting for several futures',
        'Class modifiers',
        'Hooks for subclasses',
        'Collections',
        'Strings and text length',
        'Null checks without `!`',
        'Records',
      ],
      'architecture': <String>[
        'Law of Demeter',
        'Single source of truth',
        'Users, user info and sessions',
        'No use cases or services',
        'Models at the data boundary',
        'Member order',
        'Data providers',
        'What the repository does',
        'What a feature is',
        'Side effects',
        'Changing shared code',
        'Several services behind one interface',
        'Cache and network as two methods',
        'Analytics events',
      ],
      'widgets': <String>[
        'Performance',
        'Animations',
        'Listeners and dispose',
        'Lifecycle of a `State`',
        'Keys',
        'Adaptive and responsive',
        'Text scaling',
        '`BuildContext` after `await`',
        'Small layout habits',
        'Splitting files',
        'Forms',
        'Magic numbers',
        'Message time in a chat bubble',
        'Constraints',
        'Hiding a widget',
        'State in list rows',
        'Measuring in production',
        'Loading overlay',
        'Painters, clippers and layout delegates',
        'Custom render objects',
        'One-time codes and PINs',
        'Themes',
        'Scrolling and slivers',
        'Focus and keyboard',
        'Anchored popups',
        'Components',
        'Replaced APIs',
        'Rebuilding on one part of a notifier',
        'Diagnostics',
        'Window size classes',
        'Repaint boundaries',
        'Opacity and filters',
        'Image sizes',
      ],
      'testing': <String>[
        'Testability',
        'Mocks with mocktail',
        'What to mock',
        'Fakes for wide interfaces',
        'Test-only code',
        'Integration tests',
        'Testing the data layer',
        'Sharding',
      ],
      'web': <String>[
        'Renderers',
        'Semantics',
        'Search engines',
        'Caching and installing',
        'Browser automation',
      ],
      'security': <String>[
        'What an installed app gives away',
        'Untrusted input',
        'Secrets',
        'Secrets in the project folder',
        'Obfuscation',
        'Network traffic',
        'Tokens',
        'Storing tokens',
        'Biometrics',
        'Dependencies',
        'What the server checks',
        'Sign-in through a browser (OAuth)',
        'Expected errors',
      ],
      'navigation': <String>[
        'The navigator',
        'Pages',
        'Guards',
        'Controlled stack',
        'System back',
        'Returning after sign-in',
        'Dialogs and sheets',
        'Tabs',
        'No navigator key outside the widgets',
      ],
      'localization': <String>['Error messages', 'Styled parts of a sentence'],
      'generated-files': <String>['Repository statistics', 'build.yaml'],
      'documentation': <String>[
        'A task',
        'Docs change with the code',
        'Agent instructions',
        'A plan',
      ],
      'isolates': <String>[
        'Choosing',
        'Sending data',
        'State is per isolate',
        'A worker isolate',
        'Health and stopping',
        'Plugins in an isolate',
        'Android: background work and foreground services',
        '`map_in_chunks.dart`',
      ],
      'tooling': <String>[
        'The Makefile',
        'Scripts of a new project',
        'Scripts in Dart',
        'CI',
        'The pipeline',
        'Sharding tests',
        'Coverage',
        'Subcommands',
        'Shipping a command-line tool',
        'Pub workspaces',
        'Commands at the root',
        'Melos',
      ],
    };
    for (final MapEntry(key: name, value: headings) in sections.entries) {
      for (final heading in headings) {
        expect(
          RegExp('^#{2,3} ${RegExp.escape(heading)}\$', multiLine: true).hasMatch(rule(name)),
          isTrue,
          reason: '$name.md has no "$heading" section',
        );
      }
    }
  });

  test('no rule teaches the old state names', () {
    for (final file in ruleFiles) {
      final text = file.readAsStringSync();
      for (final old in <String>[r'$InProgressState', r'$CompletedState', r'$InitialState']) {
        expect(text, isNot(contains(old)), reason: '${file.path} still uses $old');
      }
    }
  });
}
