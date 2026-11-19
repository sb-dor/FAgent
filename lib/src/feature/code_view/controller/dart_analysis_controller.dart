import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_format.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_navigation_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/dart_completion_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/dart_analysis_status.dart';

/// {@template dart_analysis_controller}
/// What the Code view's widgets use of a project's Dart analysis: its [status] and restart,
/// formatting a document, and the completion and navigation controllers of a Dart tab.
/// {@endtemplate}
final class DartAnalysisController {
  /// {@macro dart_analysis_controller}
  DartAnalysisController({required this._repository});

  final IDartAnalysisRepository _repository;

  /// What the analysis is doing.
  ValueListenable<DartAnalysisStatus> get status => _repository.status;

  /// Stops the server and starts it again with the open files.
  Future<void> restart() => _repository.restart();

  /// Formats the Dart text [document]; nothing changes when it cannot (see [formatDocument]).
  Future<void> format(CodeDocument document) async {
    await formatDocument(document, _repository);
  }

  /// The completion list of the Dart tab [document]; the caller disposes it.
  DartCompletionController completionFor(CodeDocument document) =>
      DartCompletionController(document: document, analysis: _repository);

  /// Hover, go to definition and find references of the Dart tab [document]; the caller disposes
  /// it.
  CodeNavigationController navigationFor(CodeDocument document) =>
      CodeNavigationController(document: document, analysis: _repository);
}
