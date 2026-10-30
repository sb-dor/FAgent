import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _recordedOptions() {
  final result = jsonDecode(
    File('test/fixtures/acp/new_session_result.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return <Map<String, Object?>>[
    for (final option in result['configOptions']! as List<Object?>) option! as Map<String, Object?>,
  ];
}

void main() {
  test('the recorded Claude options parse into selects with readable values', () {
    final options = ConfigOption.parseAll(_recordedOptions());

    expect(options.map((o) => o.id), <String>['mode', 'model', 'effort', 'agent']);
    expect(options, everyElement(isA<SelectConfigOption>()));
    final mode = permissionModeOf(options)!;
    expect(mode.currentName, 'Manual');
    expect(mode.choices.map((c) => c.value), contains(bypassPermissionMode));
  });

  test('unknown option types are kept read-only and entries without an id are skipped', () {
    final options = ConfigOption.parseAll(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'thinking',
        'name': 'Thinking',
        'type': 'boolean',
        'currentValue': true,
      },
      <String, Object?>{'id': 'budget', 'name': 'Budget', 'type': 'number'},
      <String, Object?>{'name': 'No id', 'type': 'select'},
    ]);

    expect(options, hasLength(2));
    expect((options.first as BooleanConfigOption).currentValue, isTrue);
    expect((options.last as UnknownConfigOption).type, 'number');
    expect(permissionModeOf(options), isNull);
  });
}
