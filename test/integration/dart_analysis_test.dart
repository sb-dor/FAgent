@Tags(<String>['dart_analysis'])
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Opt-in: `DART_LSP_TEST=1 flutter test --tags dart_analysis test/integration/dart_analysis_test.dart`.
///
/// Starts the real `dart language-server` on this repository (a Flutter project) and talks to it
/// about a file that exists only in the editor.
void main() {
  final enabled = io.Platform.environment['DART_LSP_TEST'] == '1';
  final root = io.Directory.current.path;
  final file = p.join(root, 'lib', '_dart_analysis_probe.dart');
  late DartAnalysisRepositoryImpl analysis;

  setUp(() {
    analysis = DartAnalysisRepositoryImpl(
      root: root,
      environment: ShellEnvironment(Map<String, String>.of(io.Platform.environment)),
    );
    addTearDown(analysis.dispose);
  });

  /// Waits for the server to come up and finish its first analysis.
  Future<void> ready() async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (analysis.status.value is! DartAnalysis$ReadyState) {
      if (analysis.status.value case DartAnalysis$UnavailableState(:final reason)) {
        fail('the server is unavailable: $reason');
      }
      if (DateTime.now().isAfter(deadline))
        fail('the server is not ready: ${analysis.status.value}');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  test('stful in an empty file returns a snippet whose body contains StatefulWidget', () async {
    analysis.open(file, 'stful');
    await ready();

    List<DartCompletion> items = const <DartCompletion>[];
    final deadline = DateTime.now().add(const Duration(minutes: 1));
    // The server labels it "Flutter Stateful Widget"; `stful` is what typing matches.
    bool isStful(DartCompletion item) => item.filterText == 'stful';
    while (!items.any(isStful) && DateTime.now().isBefore(deadline)) {
      items = await analysis.complete(file, 'stful', const LspPosition(line: 0, character: 5));
      if (!items.any(isStful)) await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    final stful = items.firstWhere(isStful);
    expect(stful.kind, DartCompletionKind.snippet);
    expect(stful.isSnippet, isTrue);
    expect(stful.insertText, contains('StatefulWidget'));
    expect(stful.insertText, contains(r'${1:'));
  }, skip: enabled ? false : 'Runs the real dart language-server; set DART_LSP_TEST=1');

  test('void main() { x; } gets an error on x', () async {
    final published = Completer<DartFileDiagnostics>();
    analysis.diagnostics.listen((diagnostics) {
      if (diagnostics.path == file &&
          diagnostics.diagnostics.any((d) => d.severity == DartSeverity.error) &&
          !published.isCompleted) {
        published.complete(diagnostics);
      }
    });

    analysis.open(file, 'void main() { x; }\n');
    await ready();
    final diagnostics = await published.future.timeout(const Duration(minutes: 1));

    final error = diagnostics.diagnostics.firstWhere((d) => d.severity == DartSeverity.error);
    expect(error.range.start, const LspPosition(line: 0, character: 14));
    expect(error.code, isNotNull);
  }, skip: enabled ? false : 'Runs the real dart language-server; set DART_LSP_TEST=1');
}
