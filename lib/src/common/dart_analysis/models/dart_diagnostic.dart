import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:meta/meta.dart';

export 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';

/// How bad a [DartDiagnostic] is.
enum DartSeverity {
  /// An error.
  error,

  /// A warning.
  warning,

  /// An info.
  info,

  /// A hint (a lint).
  hint;

  /// The severity of the LSP `DiagnosticSeverity` [value]; an error when it is missing.
  static DartSeverity ofLsp(int? value) => switch (value) {
    2 => warning,
    3 => info,
    4 => hint,
    _ => error,
  };
}

/// {@template dart_diagnostic}
/// An error, warning or hint of the analysis server.
/// {@endtemplate}
@immutable
final class DartDiagnostic {
  /// {@macro dart_diagnostic}
  const DartDiagnostic({
    required this.range,
    required this.severity,
    required this.message,
    this.code,
  });

  /// Parses an LSP `Diagnostic`.
  factory DartDiagnostic.fromJson(Map<String, Object?> json) => DartDiagnostic(
    range: LspRange.fromJson(json['range']),
    severity: DartSeverity.ofLsp((json['severity'] as num?)?.toInt()),
    message: '${json['message'] ?? ''}',
    code: json['code']?.toString(),
  );

  /// Where.
  final LspRange range;

  /// How bad.
  final DartSeverity severity;

  /// What the server says.
  final String message;

  /// Its code (`undefined_identifier`).
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is DartDiagnostic &&
      other.range == range &&
      other.severity == severity &&
      other.message == message &&
      other.code == code;

  @override
  int get hashCode => Object.hash(range, severity, message, code);

  @override
  String toString() => 'DartDiagnostic(${severity.name} $range $code)';
}

/// {@template dart_file_diagnostics}
/// Every diagnostic of one file, as the server published it last.
/// {@endtemplate}
@immutable
final class DartFileDiagnostics {
  /// {@macro dart_file_diagnostics}
  const DartFileDiagnostics(this.path, this.diagnostics);

  /// The file's absolute path.
  final String path;

  /// Its diagnostics.
  final List<DartDiagnostic> diagnostics;
}
