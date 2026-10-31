import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late AgentOptionsCatalogImpl catalog;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    catalog = AgentOptionsCatalogImpl(database: database);
  });

  tearDown(() => database.close());

  /// What a chat reports: the choices of the agent and the value that chat holds.
  List<Map<String, Object?>> model(String value, {String name = 'Opus'}) => [
    {
      'id': 'model',
      'type': 'select',
      'currentValue': value,
      'options': [
        {'value': 'opus', 'name': name},
      ],
    },
  ];

  /// What the catalog keeps of [model]: the same without the value of the chat.
  List<Map<String, Object?>> kept(String name) => [
    {
      'id': 'model',
      'type': 'select',
      'options': [
        {'value': 'opus', 'name': name},
      ],
    },
  ];

  Future<DateTime?> updatedAt() async => (await (database.select(
    database.appSettingsTable,
  )..where((r) => r.key.equals('agentOptions'))).getSingleOrNull())?.updatedAt;

  test('nothing is stored at first', () async {
    expect(await catalog.watch().first, isEmpty);
  });

  test('saved options are watched, per agent', () async {
    await catalog.save('claude', model('opus'));
    await catalog.save('codex', model('gpt'));

    expect(await catalog.watch().first, {'claude': kept('Opus'), 'codex': kept('Opus')});
  });

  test('an empty list is not saved', () async {
    await catalog.save('claude', const []);

    expect(await updatedAt(), isNull);
    expect(await catalog.watch().first, isEmpty);
  });

  test('equal options are not written again, changed ones are', () async {
    await catalog.save('claude', model('opus'));
    final first = await updatedAt();
    await Future<void>.delayed(const Duration(seconds: 1, milliseconds: 100));

    await catalog.save('claude', model('opus'));
    expect(await updatedAt(), first);

    await catalog.save('claude', model('opus', name: 'Opus 5'));
    expect((await catalog.watch().first)['claude'], kept('Opus 5'));
    expect((await updatedAt())!.isAfter(first!), isTrue);
  });

  test('options that differ only in the value of the chat are written once', () async {
    await catalog.save('claude', model('opus'));
    final first = await updatedAt();
    await Future<void>.delayed(const Duration(seconds: 1, milliseconds: 100));

    await catalog.save('claude', model('sonnet'));

    expect(await updatedAt(), first);
    expect((await catalog.watch().first)['claude'], kept('Opus'));
  });

  test('saves made at once keep every agent', () async {
    await Future.wait([catalog.save('claude', model('opus')), catalog.save('codex', model('gpt'))]);

    expect((await catalog.watch().first).keys, unorderedEquals(['claude', 'codex']));
  });
}
