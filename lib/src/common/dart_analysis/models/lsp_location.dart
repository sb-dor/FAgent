import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:meta/meta.dart';

/// {@template lsp_location}
/// A range in a file on disk: where a name is declared or used.
/// {@endtemplate}
@immutable
final class LspLocation {
  /// {@macro lsp_location}
  const LspLocation({required this.path, required this.range});

  /// Parses a `Location` (`uri`, `range`) or a `LocationLink` (`targetUri`,
  /// `targetSelectionRange`); `null` for anything that is not a `file:` URI.
  static LspLocation? fromJson(Object? json) {
    if (json is! Map) return null;
    final link = json.containsKey('targetUri');
    final uri = Uri.tryParse('${link ? json['targetUri'] : json['uri']}');
    if (uri == null || !uri.isScheme('file')) return null;
    final range = link ? json['targetSelectionRange'] ?? json['targetRange'] : json['range'];
    return LspLocation(path: uri.toFilePath(), range: LspRange.fromJson(range));
  }

  /// Parses a `Location`, a list of `Location`s or `LocationLink`s, or `null`.
  static List<LspLocation> listFromJson(Object? json) => <LspLocation>[
    for (final entry in json is List ? json : <Object?>[?json]) ?LspLocation.fromJson(entry),
  ];

  /// The file's absolute path.
  final String path;

  /// The range in it.
  final LspRange range;

  @override
  bool operator ==(Object other) =>
      other is LspLocation && other.path == path && other.range == range;

  @override
  int get hashCode => Object.hash(path, range);

  @override
  String toString() => 'LspLocation($path, $range)';
}
