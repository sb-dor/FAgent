import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';

final RegExp _ansi = RegExp('\x1B\\[[0-9;?]*[ -/]*[@-~]');
final RegExp _header = RegExp(r'^\[(✓|!|✗|☠)\] (.+)$');
final RegExp _finding = RegExp(r'^\s+(?:✗|!)\s*(.+)$');

/// The checks of the `flutter doctor` report [output], in report order; the lines that are not a
/// check (the summary, the hints under a check, the closing verdict) are skipped.
///
/// A check is `[✓] Title - what it covers (detail)`: `✓` is ok, `!` a warning, `✗` and `☠` an
/// error. The detail of an ok check is its last parenthesis; of a check that is not fine, the first
/// `✗` or `!` line under it, else the parenthesis.
List<DoctorCheck> parseDoctorOutput(String output) {
  final lines = output.replaceAll(_ansi, '').split('\n').map((line) => line.trimRight()).toList();
  final checks = <DoctorCheck>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _header.firstMatch(lines[i]);
    if (match == null) continue;
    final status = switch (match.group(1)) {
      '✓' => DoctorStatus.ok,
      '!' => DoctorStatus.warning,
      _ => DoctorStatus.error,
    };
    final text = match.group(2)!.trim();
    final dash = text.indexOf(' - ');
    final paren = text.indexOf(' (');
    final end = <int>[
      dash,
      paren,
    ].where((index) => index >= 0).fold<int>(text.length, (a, b) => a < b ? a : b);
    final title = text.substring(0, end).trim();

    var detail = _lastParenthesis(text);
    if (status != DoctorStatus.ok) {
      for (var j = i + 1; j < lines.length && lines[j].startsWith(RegExp(r'\s')); j++) {
        final finding = _finding.firstMatch(lines[j]);
        if (finding != null) {
          detail = finding.group(1)!.trim();
          break;
        }
      }
    }
    checks.add(DoctorCheck(title: title, status: status, detail: detail));
  }
  return checks;
}

/// The text of the last `(…)` that ends [text], without the parentheses; `null` when [text] does
/// not end with one.
String? _lastParenthesis(String text) {
  if (!text.endsWith(')')) return null;
  var depth = 0;
  for (var i = text.length - 1; i >= 0; i--) {
    if (text[i] == ')') depth++;
    if (text[i] == '(' && --depth == 0) {
      final inner = text.substring(i + 1, text.length - 1).trim();
      return inner.isEmpty ? null : inner;
    }
  }
  return null;
}
