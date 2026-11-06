---
name: tooling
description: "Dart scripts in tool/ (arguments, subcommands, processes, exit codes), shipping a CLI, pub workspaces and Melos, and CI: caching, format, analyze, sharded tests, a coverage floor, the build."
---

# Tooling

## Rules

- The project's commands are `Makefile` targets (`make help` lists them): get, generate, format,
  analyze, test, run, the builds, and `ci`, which runs what CI runs. A target is a few lines that
  call `flutter`, `dart` or a script in `tool/`; anything longer is a Dart script. New projects
  start with one. See "The Makefile".
- A script with a condition, a loop, parsing or arguments is a Dart file in `tool/`, run with
  `dart run tool/<name>.dart`. Shell is for one or two linear commands. See "Scripts in Dart".
- New projects come with `scripts/{analyze,format,generate,test}.bash` (a few linear commands
  each, run with `bash scripts/<name>.bash`) and `tool/dart/rename_project.dart`. See "Scripts of
  a new project".
- A script's logic is a function with a unit test; `main` only parses the arguments, calls it and
  sets `exitCode`. See "Scripts in Dart".
- Start processes with an argument list (`Process.run('flutter', ['test', path])`), never a
  command string for a shell. See "Running processes".
- End a script by setting `exitCode` and returning from `main`, not with `exit()`: `exit` drops
  output that is not written yet. Use 0 for success, 1 for a failure, 64 for a wrong command line.
  See "Exit codes".
- A script with subcommands uses `CommandRunner<int>`, awaits `run` and turns a `UsageException`
  into exit code 64. See "Subcommands".
- A repository with several packages is one pub workspace. One `pub get`,
  `dart run build_runner build --workspace`, `flutter analyze` and `flutter test <members>` at the
  root cover every member: no loop over packages. See "Pub workspaces".
- Every pull request runs the format check, `flutter analyze`, the tests and a build; any failure
  blocks the merge. See "The pipeline".
- CI gets dependencies with `flutter pub get --enforce-lockfile` (why: "Dependencies" in
  `docs/rules/security.md`); later commands in the job take `--no-pub`. Cache the pub cache keyed
  on `pubspec.lock`. See "Dependencies and caching".
- The format check is `dart format --output=none --set-exit-if-changed .`, after `pub get` and
  before code generation. There is no `flutter format`. See "Format and analyze".
- Shard tests by test file, not with `flutter test --total-shards`, when files hold few tests. See
  "Sharding tests".
- Coverage has a floor at its current value that only goes up; a drop fails the build. See
  "Coverage".
- Tools that CI runs come from `dev_dependencies` (`dart run <package>`) or are activated with a
  pinned version. See "Tools in CI".

## The Makefile

A `Makefile` at the root gives every command of the project one short name, the same on every
machine and in CI. New projects start with one:

- `make` runs `generate`, `format`, `analyze` and `test`; `make help` lists every target from the
  `## description` after it.
- `make ci` is what the CI job runs: `flutter pub get --enforce-lockfile`, the format check, code
  generation, `flutter analyze` and `flutter test --coverage`, in that order.
- `ENV` picks the configuration: `config/$(ENV).json` is passed with `--dart-define-from-file`
  when the file exists (`make run ENV=production`).
- The release builds (`build-apk`, `build-appbundle`, `build-ipa`, `build-macos`,
  `build-windows`, `build-linux`) use `--obfuscate --split-debug-info=build/debug-info`; the web
  build uses `--source-maps`, since the web has no `--obfuscate`. Keep `build/debug-info` of every
  release (see "Obfuscation" in `docs/rules/security.md`).
- Recipes are indented with a tab, not spaces, or `make` stops with "missing separator".
- Project-specific steps (uploading symbols, deploying, generating icons) are added as their own
  targets; a step with logic is a `tool/` script that the target calls.
- `make` is not installed on Windows by default: the targets only call `flutter` and `dart`, so a
  Windows developer can run the same commands by hand, or install `make`.

## Scripts of a new project

- `scripts/analyze.bash`: `flutter analyze --no-pub`.
- `scripts/format.bash`: `dart format` over `lib/` and `test/`, skipping generated files
  (`*.*.dart`), with the line length from `analysis_options.yaml`.
- `scripts/generate.bash`: `flutter pub get`, `flutter gen-l10n`, build_runner, then `dart format`.
- `scripts/test.bash`: `flutter test --no-pub --coverage --file-reporter json:reports/tests.json`,
  passing on any extra arguments (`bash scripts/test.bash test/home/`).
- `tool/dart/rename_project.dart --name=shop_app --organization=com.company
  [--description="..."]` renames the package, the organization and the description everywhere:
  imports, `pubspec.yaml`, the Android application id and `namespace`, the Kotlin source folder
  and its `package` line, the iOS and macOS bundle ids (which `flutter create` writes in
  camelCase, `com.company.shopApp`). It reads the current values from the project itself and
  sorts the imports again at the end. Commit before running it. Checked on a project created by
  the app: after a rename to `shop_app` / `org.shop`, `flutter analyze` and `make ci` passed.

A script that grows a loop or a condition becomes a Dart file in `tool/` (see "Scripts in Dart");
the `.bash` files stay one or two commands, the same ones the `Makefile` runs.

## Scripts in Dart

Bash is fine for glue: one command, or a few in a row (`dart format .`). As soon as a script
branches, loops, parses output or takes arguments, write it in Dart:

- It runs the same on macOS, Linux and Windows. Shell tools differ: `sed -i 's/a/b/' file` works
  with GNU sed and fails with the BSD sed of macOS, which wants `sed -i '' ...` (checked: macOS
  prints "unterminated substitute pattern" and leaves the file as it was). Windows needs WSL or
  Git Bash to run a `.sh` at all.
- It has types, the analyzer, the lints and tests, and the agent edits it like the rest of the
  code.
- It has `dart:io` for files and processes, `dart:convert` for JSON, and packages from pub.dev.

Where things go:

- Scripts live in `tool/`, the Dart package layout's folder for a package's own tools. `tool/` is
  not part of the app: nothing in `lib/` imports it.
- The logic lives in `tool/src/<name>.dart` as plain functions; `tool/<name>.dart` holds only
  `main`. Tests import the logic by relative path (`import '../../tool/src/test_shards.dart';`
  from `test/tool/`), so `flutter test` runs them with the rest.
- Packages only the scripts need (`args`) go to `dev_dependencies`. In a pub workspace, a `tool`
  member package with its own `pubspec.yaml` keeps them out of the app's dependencies.
- A package whose product is a command-line tool is laid out differently: see "Shipping a
  command-line tool".

### Arguments

Parse arguments with `package:args`:

```dart
import 'dart:io';

import 'package:args/args.dart';

import 'src/test_shards.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('total', help: 'Number of shards.')
    ..addOption('index', help: 'This shard, counted from 0.');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on ArgParserException catch (error) {
    return _usageError(error.message, parser);
  }
  final total = int.tryParse(args.option('total') ?? '');
  final index = int.tryParse(args.option('index') ?? '');
  if (total == null || index == null || total < 1 || index < 0 || index >= total) {
    return _usageError('Need --total N and --index I with 0 <= I < N.', parser);
  }
  final shard = splitIntoShards(findTestFiles(Directory('test')), total)[index];
  stdout.writeln('Shard $index of $total: ${shard.length} test files');
  // Everything after `--` goes to `flutter test`: `-- --coverage -x golden`.
  exitCode = await runShard(shard, arguments: args.rest);
}

void _usageError(String message, ArgParser parser) {
  stderr
    ..writeln(message)
    ..writeln('Usage: dart run tool/test_shard.dart --total N --index I [-- <flutter test args>]')
    ..writeln(parser.usage);
  exitCode = 64;
}
```

- Read values with `args.option('name')` (`String?`), `args.flag('name')` and
  `args.multiOption('name')`. `args['name']` returns `dynamic` and passes unchecked into
  `int.parse`.
- Check required options yourself. `addOption(..., mandatory: true)` is checked by `parse` only
  for an option with a `callback`; otherwise `args.option('name')` throws an `ArgumentError`, an
  uncaught error with exit code 255 instead of a usage message (checked: `args` 2.7.0).
- Validate ranges (`0 <= index < total`) before doing any work, and print `parser.usage` with the
  error.

### Subcommands

A script with several tasks (`dart run tool/project.dart shard ...`) uses `CommandRunner<int>`
from `package:args/command_runner.dart`, one `Command<int>` per task. In
`tool/src/project_tool.dart`:

```dart
import 'dart:io';

import 'package:args/command_runner.dart';

import 'test_shards.dart';

/// `dart run tool/project.dart shard --total N --index I [-- <flutter test args>]`
final class ShardCommand extends Command<int> {
  ShardCommand() {
    argParser
      ..addOption('total', help: 'Number of shards.')
      ..addOption('index', help: 'This shard, counted from 0.');
  }

  @override
  String get name => 'shard';

  @override
  String get description => 'Runs one shard of the test files.';

  @override
  Future<int> run() async {
    final args = argResults!; // set by CommandRunner before run()
    final total = int.tryParse(args.option('total') ?? '');
    final index = int.tryParse(args.option('index') ?? '');
    if (total == null || index == null || total < 1 || index < 0 || index >= total) {
      usageException('Need --total N and --index I with 0 <= I < N.');
    }
    final shard = splitIntoShards(findTestFiles(Directory('test')), total)[index];
    return runShard(shard, arguments: args.rest);
  }
}

/// Runs the command line [arguments] and returns the exit code: the command's,
/// 0 for help, 64 for a wrong command line.
Future<int> runProjectTool(List<String> arguments) async {
  final runner = CommandRunner<int>('project', 'Tasks of this project.')
    ..addCommand(ShardCommand());
  try {
    // null for `--help` and `help <command>`, which only print the usage.
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    stderr.writeln(error); // the message, then the usage of the command
    return 64;
  }
}
```

`tool/project.dart` is `Future<void> main(List<String> arguments) async { exitCode = await
runProjectTool(arguments); }`.

- `run` returns the exit code. A wrong value is reported with `usageException(message)`, which
  throws a `UsageException` carrying the command's usage.
- `CommandRunner.run` throws `UsageException` for an unknown command or option. Without the
  `try` (or without `await`), it is an unhandled exception with a stack trace and exit code 255
  instead of a usage message with 64 (checked).
- `run` returns `null` for `--help`, `<command> --help` and `help <command>`: treat it as 0.
- Checked with `args` 2.7.0: unknown command, unknown option, missing and out-of-range options
  gave 64 with the message and the command's usage on `stderr`; the three help forms gave 0.

### Running processes

- `Process.run(executable, arguments)` waits and returns the exit code with the output as
  strings; `Process.start` streams. With `mode: ProcessStartMode.inheritStdio` the child writes
  straight to the script's terminal.
- Pass arguments as a list. Each element reaches the program as it is: spaces, `;` and `$HOME`
  are not interpreted (checked: `Process.run('echo', ['a b; rm -rf x', r'$HOME'])` prints them
  literally). A command string for `sh -c` is word-split and expanded, and breaks on a file name
  with a space.
- A non-zero exit code is not an exception: check `result.exitCode`. A missing executable throws
  `ProcessException`.
- On Windows, `flutter` and `dart` from the Flutter SDK are batch files (`bin/flutter.bat`). Pass
  `runInShell: Platform.isWindows` for them. The `dart:io` docs warn that a batch file may run
  through `cmd.exe` either way, so its arguments are parsed by shell rules: never pass untrusted
  text to a batch file. (Not run on Windows here.)
- Several processes at once interleave their output. Capture each with `Process.run` and print it
  when that process ends, or prefix every line with the job's name.
- Read the CPU count with `Platform.numberOfProcessors`, not `nproc` or `sysctl`.
- To find the packages of a pub workspace, ask `dart pub workspace list` (a table of package names
  and paths) or read the `workspace:` list of the root `pubspec.yaml`. When walking directories,
  skip `.dart_tool`, `build` and hidden folders by comparing path segments, not substrings: a
  substring test for `pub-cache` also skips a package named `my_pub-cache_tools`.

### Exit codes

- `exit(code)` stops the VM at once: it does not wait for asynchronous work or run `finally`
  blocks, so output still buffered is lost (`dart:io` docs). Set `exitCode = code` and return from
  `main`.
- 0 means success, 1 a failure the script found (tests failed, coverage too low), 64 a wrong
  command line: `dart` and `flutter` exit with 64 on an unknown option (checked).
- Keep codes in 0 to 127. On Linux and macOS only the low 8 bits survive (`-1` becomes 255), and
  Dart itself exits with 254 for a compile error and 255 for an uncaught exception.

### Shipping a command-line tool

For a package whose product is a CLI (scripts in `tool/` stay `dart run tool/<name>.dart`):

- The entry points are `bin/<name>.dart`, only `main`; the runner, the commands and the logic are
  in `lib/src/`, where tests and other code can use them. A CLI that only some users of a library
  need is its own package (a workspace member, see "Pub workspaces").
- `executables:` in `pubspec.yaml` names the commands. Users install them with
  `dart install <package>` (also `<package>@^1.0.0`, a git or a path descriptor) or
  `dart pub global activate <package>`.
- `dart compile exe bin/<name>.dart -o <name>` builds a self-contained executable for the host
  OS. The only other target is Linux: from macOS, `--target-os=linux --target-arch=x64` gave an
  x86-64 ELF binary, and `windows`, `android` and `ios` were refused (checked, Dart 3.13). Build
  each other OS on its own CI runner. A Dart executable does not run on Android or iOS. A CLI
  that uses native code assets is built with `dart build cli` (a bundle of `bin/` and `lib/`).
- The tool's code does not import Flutter: `dart compile exe` of a file importing
  `package:flutter/foundation.dart` failed with "Dart library 'dart:ui' is not available on this
  platform". A dependency with build hooks (`shared_preferences` brings `objective_c`) stops it
  with "'dart compile' does not support build hooks, use 'dart build' instead" (checked).

## Pub workspaces

A repository with several packages (the app, `packages/*`, a `tool` package) is one pub workspace
(Dart 3.6 and Flutter 3.27 or later):

```yaml
# pubspec.yaml at the root
name: shop_workspace
publish_to: none
environment:
  sdk: ^3.11.0 # globs in `workspace:` need 3.11; without them ^3.6.0
workspace:
  - app
  - packages/*

# packages/shop_core/pubspec.yaml
name: shop_core
version: 1.0.0
publish_to: none
environment:
  sdk: ^3.11.0
resolution: workspace

# app/pubspec.yaml
name: shop_app
publish_to: none
environment:
  sdk: ^3.11.0
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
  shop_core: ^1.0.0 # the member: found by name, no `path:`
```

Checked with Flutter 3.47 / Dart 3.13:

- One `flutter pub get`, at the root or in any member, resolves the whole workspace into the
  root's `pubspec.lock` and `.dart_tool/package_config.json`. A member gets only
  `.dart_tool/pub/workspace_ref.json`. A member that depends on another by name and version uses
  that member (`package_config.json` points at `../packages/shop_core`): no `path:` and no
  `dependency_overrides` are needed.
- Every pubspec of the workspace needs an SDK lower bound of at least 3.5 (with `^3.4.0`:
  "`workspace` and `resolution` requires at least language version 3.5"). Globs (`packages/*`)
  need 3.11 ("Glob syntax is only supported from language version 3.11"); a folder they match
  without a `pubspec.yaml` is skipped. A listed member without `resolution: workspace` fails the
  resolution.
- There is one version of each package for all members: two members with incompatible
  constraints fail the resolution for everyone. A pure Dart member is resolved together with the
  versions the Flutter SDK pins through `flutter_test`. With Flutter 3.47.9, a member with `test`
  in `dev_dependencies` and `build_runner` 2.17.1 in the workspace failed to resolve (the `test`
  versions that fit the pinned `test_api` need an older analyzer than `build_runner`); with
  `flutter_test` instead of `test` in that member's `dev_dependencies` it resolved, and its tests
  ran with `flutter test`. The same holds in a single Flutter package: tests use `flutter_test`,
  not `package:test`.
- `dependency_overrides` in a member applies to the whole workspace (`direct overridden` in the
  lockfile): keep overrides in the root pubspec, where they are visible.
- Migrating: the first `pub get` deletes each member's old `pubspec.lock` and
  `.dart_tool/package_config.json` ("Deleting old lock-file"). Delete them from git too.
- `--enforce-lockfile` covers the members: after a new dependency was added to a member,
  `flutter pub get --enforce-lockfile` exited with 65, at the root and in the member.
- `dart pub get` resolves Flutter members too, when `dart` is the Flutter SDK's.

### Commands at the root

- Code generation: `dart run build_runner build --workspace -d` builds every member in one run,
  with one compile of the builders (`-d` is `--delete-conflicting-outputs`). `--workspace` exists
  since build_runner 2.11 and is stable since 2.14; `dart run build_runner clean --workspace`
  clears its cache. It ran at the root with `build_runner` only in the members'
  `dev_dependencies` (checked). See also `docs/rules/generated-files.md`.
- Analysis: `flutter analyze --no-pub` (or `dart analyze`) at the root analyzes every member,
  each with its own `analysis_options.yaml` (checked: an error set only in a member's file was
  reported from the root).
- Tests: since Flutter 3.32, `flutter test --no-pub --coverage app packages/shop_core` at the
  root runs the tests of both members in one run and writes one `coverage/lcov.info` at the root,
  with paths relative to the root (`SF:packages/shop_core/lib/shop_core.dart`). Pass the members
  that have a `test/` folder (from `dart pub workspace list`): a plain `flutter test` at a root
  without its own `test/` stops with 'Test directory "test" not found'. The working directory of
  every test is then the root, not the member: a test reading `File('test/data.txt')` passed in
  the member and failed from the root. Such a test finds its files another way, or its package is
  tested on its own.
- `flutter clean` cleans only the package it runs in.
- So a workspace's `Makefile` runs `generate`, `analyze` and `test` once at the root, with the
  commands above. Only commands that work per package (`flutter clean`, a build) need the list
  of members.

### Melos

A workspace of local packages needs no Melos: the commands above cover resolution, code
generation, analysis and tests. Melos is for publishing several packages (versions and
changelogs from conventional commits with `melos version`, then `melos publish`) and for running a
command only in the packages a change touched. When the project uses it (checked with melos
8.10.1):

- It is a dev dependency of the root, run with `dart run melos <command>` (see "Tools in CI"),
  not an unpinned `dart pub global activate melos`.
- Since Melos 7 its configuration is under `melos:` in the root `pubspec.yaml`; `melos.yaml` is
  no longer read. Since Melos 8 a script has either `run:` (once, at the root) or `exec:` (in
  every package: a command string, or a map with `command:` and the options); both together are
  an error.
- `--diff=<ref>` keeps only the packages changed since `<ref>`
  (`dart run melos exec --diff=origin/main...HEAD -- flutter analyze --no-pub`). The ref must
  exist in the clone: otherwise Melos stops with "is not an existing commit, tag or range of
  commits" and exit code 1. A shallow CI clone has no `origin/main`; on GitHub Actions check out
  with `fetch-depth: 0`.

## CI

### The pipeline

CI runs on clean runners: every job starts from a checkout and leaves nothing behind for the next
run, so each step must give the same result every time. Feedback within minutes; a pipeline that
takes half an hour slows every change.

On every push to a pull request:

1. **Prepare**: SDK, `flutter pub get --enforce-lockfile`, code generation.
2. **Format** and **analyze**, in parallel with the tests.
3. **Test**: unit and widget tests, sharded when the job grows past 5 to 8 minutes. Golden and
   integration tests run as their own jobs: they fail for other reasons, and golden images are
   compared on one fixed OS.
4. **Coverage**: merge the shards' reports and compare with the floor.
5. **Build**: compile the app for each platform it ships on. This catches what analysis and
   tests do not see: Gradle, CocoaPods, native code, signing configuration. iOS and macOS builds
   need a macOS runner. Values for the build: "Build-time values" in
   `docs/rules/configuration.md`.

A new push cancels the run it replaces (`concurrency: cancel-in-progress` on GitHub Actions,
`interruptible: true` on GitLab). Anything longer than a couple of commands is a script in
`tool/` that the YAML only calls, so it runs the same on a laptop.

### The SDK on the runner

- Pin the Flutter version: `subosito/flutter-action` with `flutter-version` or
  `flutter-version-file: pubspec.yaml` (which needs an exact version under `environment:
  flutter:`), or a container image with a version tag, never `latest`.
- Use the smallest image a job needs: analysis and tests need only the Flutter SDK; an Android
  build needs the Android SDK as well.

### Dependencies and caching

- The prepare step runs `flutter pub get --enforce-lockfile`. `flutter analyze` and `flutter test`
  run a plain `pub get` themselves unless given `--no-pub`: pass it, so the job resolves once,
  with the enforced lockfile.
- Cache the pub cache, keyed on the hash of the `pubspec.lock` files, with a fallback to the last
  cache of the branch. `subosito/flutter-action` does this with `pub-cache: true` (key:
  `hashFiles('**/pubspec.lock')`). GitLab caches only paths inside the project: set
  `PUB_CACHE: "$CI_PROJECT_DIR/.pub-cache"` and cache `.pub-cache/`.
- A repository with several packages is a pub workspace: one `flutter pub get --enforce-lockfile`
  at the root resolves every member into one `pubspec.lock` (see "Pub workspaces").
- Generated files are not committed (`docs/rules/generated-files.md`), so CI runs
  `dart run build_runner build --delete-conflicting-outputs` before analyzing or testing. On
  GitLab one prepare job can pass `.dart_tool/` and the generated files to later jobs as short-lived
  artifacts; on GitHub Actions each job runs the setup itself, with the cache.

### Format and analyze

- `dart format --output=none --set-exit-if-changed .` writes nothing and exits with 1 when a file
  is not formatted (checked). `flutter format` does not exist.
- Run it after `pub get` and before code generation. The formatter takes the language version from
  `.dart_tool/package_config.json`: without it, a package with `sdk: ^3.6.0` was formatted in the
  new tall style instead of its own (checked). Before generation the tree holds only committed
  files; `dart format .` skips hidden folders but formats `build/` and generated files when they
  exist (checked).
- The line length is `formatter: page_width: 100` in `analysis_options.yaml`, which the editor
  and CI both read (checked), not `--line-length` in a CI script.
- New projects start with a strict `analysis_options.yaml`: `flutter_lints` plus `strict-casts`,
  `strict-raw-types` and about 150 more lints, with package imports enforced as errors
  (`always_use_package_imports`), generated code and the platform folders excluded, and
  `scripts/**` left out of analysis. The examples in `docs/rules/` are checked with the same file,
  so what the rules show passes in such a project. A rule is turned off only for the whole
  project, with a comment saying why; a single `// ignore:` names the lint and the reason.
- `directives_ordering` sorts imports by package name, so a renamed package needs
  `dart fix --apply --code=directives_ordering`; new projects run it when they are created, and
  `tool/dart/rename_project.dart` after renaming.
- `flutter analyze --no-pub` fails on infos by default; a pure Dart package uses
  `dart analyze --fatal-infos`. Fix what it reports; never turn lints off to get a green build.
  Deprecations: "Deprecations, `flutter analyze` and CI" in `docs/rules/architecture.md`.

### Sharding tests

`flutter test --total-shards N --shard-index I` (index from 0) splits the tests inside each test
file by position (checked in `test_core` 0.6.18, which `flutter_tools` uses). Two consequences:

- Every shard loads and compiles every test file, so the time spent loading is not divided.
- A file with fewer tests than shards puts them all on the low shards. With four files of one test
  each and two shards, shard 0 ran all four and shard 1 found none and exited with 79, which fails
  the job (checked).

The native flags work for a package whose files hold many tests each. Otherwise split by file:
list the test files, sort them (every shard job must compute the same split, and
`Directory.list` promises no order), deal them round-robin, and pass the shard's files to
`flutter test`. Dealing in turn keeps shard sizes within one file of each other; cutting the list
into chunks of `ceil(n / N)` leaves shards empty (4 files in 3 shards: 2, 2, 0).

In a workspace, `flutter test` at the root takes member folders and test files of any member
(see "Commands at the root"): deal the `member/test/x_test.dart` paths of all members the same
way. On GitHub Actions the shard is a `matrix` value
(`shard: [0, 1, 2]`); GitLab's `parallel: 3` sets `CI_NODE_INDEX` from 1, so subtract one.

### Coverage

- `flutter test --coverage` writes `coverage/lcov.info`. A library that no test imports is not in
  it at all and does not lower the percentage (checked); a test that imports every file of
  `lib/` puts them in with their lines at 0.
- Leave generated code out (`*.g.dart`, `*.freezed.dart`, `generated/`): it inflates or deflates
  the number without saying anything about the tests.
- With shards, merge the reports file by file before computing the percentage: a file tested by
  two shards appears in both, and adding up their `LF`/`LH` totals counts it twice.
- In a workspace, one `flutter test --coverage <members>` run at the root writes paths relative
  to the root (`SF:packages/shop_core/lib/...`), ready to merge. A run inside a package writes
  paths relative to that package (`SF:lib/...`): prefix them with the package's folder before
  merging the reports of separate per-package runs.
- The floor is the current value, stored in the repository (an `--min` argument in the workflow),
  and raised when coverage rises. It is not lowered to merge a change. A fixed target such as 80%
  says nothing about the tests: coverage shows which lines ran, not what was checked.

A `tool/check_coverage.dart` reads the shards' files, calls `lineCoverage` from the example below,
prints the percentage and sets `exitCode = 1` below `--min`. That needs no `lcov` or `bc` on the
runner, and works on Windows.

### Tools in CI

A tool fetched in the pipeline runs with the CI's secrets.

- Prefer a dev dependency run with `dart run <package>`: its version and hash are in the lockfile
  that `--enforce-lockfile` checks.
- A global tool is activated with a version: `dart pub global activate cobertura 1.0.5`, never
  without one, which installs whatever was published last.
- Pin third-party CI actions to a version (`@v2`), or to a commit SHA for actions that see
  secrets.

### Example workflow

`.github/workflows/ci.yaml` for one package on GitHub Actions, using the scripts in "Examples".
The action versions are examples: look up the current ones.

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]
concurrency: # a new push cancels the run it replaces
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: pubspec.yaml # needs an exact `flutter:` version there
          cache: true # the SDK
          pub-cache: true # the pub cache, keyed on the pubspec.lock files
      - run: flutter pub get --enforce-lockfile
      - run: dart format --output=none --set-exit-if-changed .
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze --no-pub

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false # a failing shard does not cancel the others
      matrix:
        shard: [0, 1, 2]
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          flutter-version-file: pubspec.yaml
          cache: true
          pub-cache: true
      - run: flutter pub get --enforce-lockfile
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart run tool/test_shard.dart --total 3 --index ${{ matrix.shard }} -- --coverage
      - uses: actions/upload-artifact@v7
        with:
          name: lcov-${{ matrix.shard }}
          path: coverage/lcov.info
```

A `coverage` job (`needs: test`) downloads the `lcov-*` artifacts and runs
`dart run tool/check_coverage.dart --min <floor> lcov-*/lcov.info`; a `build` job runs
`flutter build <platform>` on the runner that platform needs. Checked with `actionlint`.

## Examples

### `test_shards.dart`

The logic of `tool/test_shard.dart` (above), in `tool/src/test_shards.dart`. Its test checked that
every file lands in exactly one shard, that no shard is empty while there are at least as many
files as shards, that an empty shard starts nothing, and that `runShard` returns the exit code of
a failing file.

```dart
// file: test_shards.dart
import 'dart:io';

/// The `*_test.dart` files under [directory], sorted.
///
/// Every shard job lists the files itself, so the order must not depend on
/// the file system: `Directory.list` promises none.
List<String> findTestFiles(Directory directory) => [
  for (final entity in directory.listSync(recursive: true))
    if (entity is File && entity.path.endsWith('_test.dart')) entity.path,
]..sort();

/// Deals [files] to [total] shards in turn: shard `i` gets files `i`,
/// `i + total`, `i + 2 * total`, ... Shard sizes differ by at most one, so no
/// shard is empty while there are at least [total] files.
List<List<String>> splitIntoShards(List<String> files, int total) {
  if (total < 1) {
    throw ArgumentError.value(total, 'total', 'must be at least 1');
  }
  return [
    for (var shard = 0; shard < total; shard++)
      [for (var i = shard; i < files.length; i += total) files[i]],
  ];
}

/// Runs `flutter test` with [arguments] (`--coverage`, `-x golden`) on [files]
/// and returns its exit code.
///
/// An empty shard returns 0 without starting anything: `flutter test` with no
/// paths runs every test in the package.
Future<int> runShard(
  List<String> files, {
  List<String> arguments = const [],
  String? workingDirectory,
}) async {
  if (files.isEmpty) return 0;
  final process = await Process.start(
    'flutter',
    ['test', '--no-pub', ...arguments, ...files],
    workingDirectory: workingDirectory,
    // `flutter` is `flutter.bat` on Windows: batch files run through cmd.exe.
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
```

### `line_coverage.dart`

The logic of `tool/check_coverage.dart`, in `tool/src/line_coverage.dart`. Its test checked the
merge of one file across two shards, that generated files are left out, and Windows line endings
and paths.

```dart
// file: line_coverage.dart
/// Whether [path] is generated code, which coverage leaves out.
bool isGenerated(String path) {
  final unix = path.replaceAll(r'\', '/'); // lcov from Windows has `\`
  return unix.endsWith('.g.dart') ||
      unix.endsWith('.freezed.dart') ||
      unix.contains('/generated/');
}

/// The line coverage of lcov [reports] (the `coverage/lcov.info` of each test
/// shard), with the files for which [include] returns false left out.
///
/// A file in several reports is merged line by line: a line counts as hit when
/// any shard ran it. Adding up the reports' `LF`/`LH` totals instead would
/// count such a file once per shard.
({int hit, int found}) lineCoverage(
  Iterable<String> reports, {
  bool Function(String path) include = _notGenerated,
}) {
  final hitsByFile = <String, Map<int, int>>{};
  for (final report in reports) {
    Map<int, int>? lines;
    for (final line in report.split('\n')) {
      if (line.startsWith('SF:')) {
        final path = line.substring(3).trim();
        lines = include(path) ? hitsByFile.putIfAbsent(path, () => {}) : null;
      } else if (line.startsWith('DA:') && lines != null) {
        // DA:<line>,<hits>[,<checksum>]
        final [number, hits, ...] = line.substring(3).split(',');
        final n = int.parse(number);
        lines[n] = (lines[n] ?? 0) + int.parse(hits.trim());
      } else if (line.startsWith('end_of_record')) {
        lines = null;
      }
    }
  }
  final all = hitsByFile.values.expand((lines) => lines.values);
  return (hit: all.where((hits) => hits > 0).length, found: all.length);
}

bool _notGenerated(String path) => !isGenerated(path);
```
