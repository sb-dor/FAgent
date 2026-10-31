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

  List<Map<String, Object?>> model(String value) => [
    {
      'id': 'model',
      'type': 'select',
      'currentValue': value,
      'options': [
        {'value': 'opus', 'name': 'Opus'},
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

    expect(await catalog.watch().first, {'claude': model('opus'), 'codex': model('gpt')});
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

    await catalog.save('claude', model('sonnet'));
    expect((await catalog.watch().first)['claude'], model('sonnet'));
    expect((await updatedAt())!.isAfter(first!), isTrue);
  });

  test('saves made at once keep every agent', () async {
    await Future.wait([catalog.save('claude', model('opus')), catalog.save('codex', model('gpt'))]);

    expect((await catalog.watch().first).keys, unorderedEquals(['claude', 'codex']));
  });
}
