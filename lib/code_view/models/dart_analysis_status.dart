import 'package:freezed_annotation/freezed_annotation.dart';

part 'dart_analysis_status.freezed.dart';

/// What the Dart analysis of a project is doing.
@freezed
sealed class DartAnalysisStatus with _$DartAnalysisStatus {
  /// No Dart file was opened yet: nothing runs.
  const factory DartAnalysisStatus.idle() = DartAnalysis$IdleState;

  /// The server is starting.
  const factory DartAnalysisStatus.starting() = DartAnalysis$StartingState;

  /// The server is up and done analyzing.
  const factory DartAnalysisStatus.ready() = DartAnalysis$ReadyState;

  /// The server is analyzing.
  const factory DartAnalysisStatus.analyzing() = DartAnalysis$AnalyzingState;

  /// No analysis: `dart` is missing, or the server failed or stopped ([reason]).
  const factory DartAnalysisStatus.unavailable({required String reason}) =
      DartAnalysis$UnavailableState;
}
