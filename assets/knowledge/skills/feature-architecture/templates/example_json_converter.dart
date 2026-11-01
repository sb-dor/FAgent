import 'dart:convert';

import 'example.dart';

/// Turns a response map into an [Example]. All API keys live here, not in widgets.
final class ExampleJsonConverter extends Converter<Map<String, Object?>, Example> {
  /// Creates the converter.
  const ExampleJsonConverter();

  @override
  Example convert(Map<String, Object?> input) => Example(
    // Backend numbers may arrive as int, double or String: parse tolerantly.
    id: int.tryParse('${input['id']}') ?? 0,
    name: '${input['name'] ?? ''}',
    description: input['description'] as String?,
  );
}
