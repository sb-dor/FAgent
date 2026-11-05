import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_hover.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_location.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';

/// [IDartAnalysisRepository] in memory: every call lands in [calls], completions come from
/// [onComplete], and the test pushes [push] diagnostics and sets [status].
final class MemoryDartAnalysisRepository implements IDartAnalysisRepository {
  /// Creates the repository.
  MemoryDartAnalysisRepository({this.onComplete, this.onResolve});

  /// Answers [complete]; empty when `null`.
  FutureOr<List<DartCompletion>> Function(String path, String text, LspPosition position)?
  onComplete;

  /// Answers [resolve]; the item itself when `null`.
  FutureOr<DartCompletion> Function(DartCompletion completion)? onResolve;

  /// Answers [hover]; `null` when not set.
  FutureOr<DartHover?> Function(String path, String text, LspPosition position)? onHover;

  /// Answers [definition]; empty when not set.
  FutureOr<List<LspLocation>> Function(String path, String text, LspPosition position)?
  onDefinition;

  /// Answers [references]; empty when not set.
  FutureOr<List<LspLocation>> Function(String path, String text, LspPosition position)?
  onReferences;

  /// Answers [format]; `null` when not set.
  FutureOr<List<LspTextEdit>?> Function(String path, String text)? onFormat;

  /// `open`, `change`, `close` and `complete` calls in order, with their path and text.
  final List<(String, String, String?)> calls = <(String, String, String?)>[];

  /// The caret of every [complete], in order.
  final List<LspPosition> positions = <LspPosition>[];

  /// How often [restart] was called.
  int restarts = 0;

  /// Whether [dispose] was called.
  bool disposed = false;

  final StreamController<DartFileDiagnostics> _diagnostics =
      StreamController<DartFileDiagnostics>.broadcast();

  @override
  final ValueNotifier<DartAnalysisStatus> status = ValueNotifier<DartAnalysisStatus>(
    const DartAnalysisStatus.ready(),
  );

  /// Publishes [diagnostics] as the server would.
  void push(DartFileDiagnostics diagnostics) => _diagnostics.add(diagnostics);

  @override
  void open(String path, String text) => calls.add(('open', path, text));

  @override
  void change(String path, String text) => calls.add(('change', path, text));

  @override
  void close(String path) => calls.add(('close', path, null));

  @override
  Future<List<DartCompletion>> complete(String path, String text, LspPosition position) async {
    calls.add(('complete', path, text));
    positions.add(position);
    return await onComplete?.call(path, text, position) ?? const <DartCompletion>[];
  }

  @override
  Future<DartCompletion> resolve(DartCompletion completion) async =>
      await onResolve?.call(completion) ?? completion;

  @override
  Future<DartHover?> hover(String path, String text, LspPosition position) async =>
      await onHover?.call(path, text, position);

  @override
  Future<List<LspLocation>> definition(String path, String text, LspPosition position) async =>
      await onDefinition?.call(path, text, position) ?? const <LspLocation>[];

  @override
  Future<List<LspLocation>> references(String path, String text, LspPosition position) async =>
      await onReferences?.call(path, text, position) ?? const <LspLocation>[];

  @override
  Future<List<LspTextEdit>?> format(String path, String text) async =>
      await onFormat?.call(path, text);

  @override
  Stream<DartFileDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  Future<void> restart() async => restarts++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _diagnostics.close();
  }
}
