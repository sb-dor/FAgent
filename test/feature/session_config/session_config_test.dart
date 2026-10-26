import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/session_config_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

List<Map<String, Object?>> _recordedOptions() {
  final result = jsonDecode(
    File('test/fixtures/acp/new_session_result.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return <Map<String, Object?>>[
    for (final option in result['configOptions']! as List<Object?>) option! as Map<String, Object?>,
  ];
}

const _mode = SelectConfigOption(
  id: 'mode',
  name: 'Mode',
  currentValue: 'default',
  choices: <ConfigChoice>[
    ConfigChoice(value: 'default', name: 'Manual'),
    ConfigChoice(value: 'acceptEdits', name: 'Accept edits'),
    ConfigChoice(value: 'bypassPermissions', name: 'Bypass permissions'),
  ],
);

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

  testWidgets('choosing bypass asks first and a cancel changes nothing', (tester) async {
    final changes = <(String, Object)>[];
    await tester.pumpWidget(
      testApp(
        SessionConfigBar(
          options: const <ConfigOption>[_mode],
          enabled: true,
          onChanged: (id, value) => changes.add((id, value)),
        ),
      ),
    );

    expect(find.text('Mode: Manual'), findsOneWidget);
    await tester.tap(find.text('Mode: Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bypass permissions'));
    await tester.pumpAndSettle();
    expect(find.text('Allow bypassing permissions?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.tap(find.text('Mode: Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bypass permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow for this chat'));
    await tester.pumpAndSettle();
    expect(changes, <(String, Object)>[('mode', bypassPermissionMode)]);
  });

  testWidgets('other modes change without a dialog', (tester) async {
    final changes = <(String, Object)>[];
    await tester.pumpWidget(
      testApp(
        SessionConfigBar(
          options: const <ConfigOption>[_mode],
          enabled: true,
          onChanged: (id, value) => changes.add((id, value)),
        ),
      ),
    );

    await tester.tap(find.text('Mode: Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept edits'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(changes, <(String, Object)>[('mode', 'acceptEdits')]);
  });
}
