import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('Project paths are unique', () async {
    await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/tmp/app', name: 'app'));

    expect(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp/app', name: 'copy')),
      throwsA(isA<SqliteException>()),
    );
    final projects = await database.select(database.projectsTable).get();
    expect(projects.single.name, 'app');
  });
}
