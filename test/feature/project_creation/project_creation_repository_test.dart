import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/fake_project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppDatabase database;
  late FakeProjectCreationRepositoryImpl repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('project_creation_test');
    database = AppDatabase(NativeDatabase.memory());
    repository = FakeProjectCreationRepositoryImpl(
      database: database,
      step: Duration.zero,
      home: p.join(root.path, 'home'),
    );
  });

  tearDown(() async {
    await database.close();
    root.deleteSync(recursive: true);
  });

  Future<void> addProject(String path, DateTime? openedAt) => database
      .into(database.projectsTable)
      .insert(
        ProjectsTableCompanion.insert(
          path: path,
          name: p.basename(path),
          lastOpenedAt: .new(openedAt),
        ),
      );

  test('is a preview', () => expect(repository.isPreview, isTrue));

  group('checkTarget', () {
    test('a free name', () async {
      expect(await repository.checkTarget(root.path, 'app'), isNull);
    });

    test('an existing empty folder', () async {
      Directory(p.join(root.path, 'app')).createSync();
      expect(await repository.checkTarget(root.path, 'app'), TargetProblem.exists);
    });

    test('an existing file', () async {
      File(p.join(root.path, 'app')).writeAsStringSync('');
      expect(await repository.checkTarget(root.path, 'app'), TargetProblem.exists);
    });

    test('a missing parent', () async {
      expect(
        await repository.checkTarget(p.join(root.path, 'nope'), 'app'),
        TargetProblem.parentMissing,
      );
    });
  });

  group('defaultParent', () {
    test('prefers the last opened project', () async {
      final older = Directory(p.join(root.path, 'older'))..createSync();
      final newer = Directory(p.join(root.path, 'newer'))..createSync();
      await addProject(p.join(older.path, 'a'), DateTime(2026, 1, 1));
      await addProject(p.join(newer.path, 'b'), DateTime(2026, 2, 1));
      await addProject(p.join(root.path, 'never', 'c'), null);
      expect(await repository.defaultParent(), newer.path);
    });

    test('skips a parent that is gone, falling back to the home folder', () async {
      await addProject(p.join(root.path, 'gone', 'a'), DateTime(2026, 1, 1));
      Directory(p.join(root.path, 'home')).createSync();
      expect(await repository.defaultParent(), p.join(root.path, 'home'));
    });

    test('without projects: ~/StudioProjects if it exists, else home', () async {
      final home = p.join(root.path, 'home');
      Directory(home).createSync();
      expect(await repository.defaultParent(), home);
      Directory(p.join(home, 'StudioProjects')).createSync();
      expect(await repository.defaultParent(), p.join(home, 'StudioProjects'));
    });
  });

  group('create', () {
    NewProjectRequest request({
      NewProjectTemplate template = NewProjectTemplate.architecture,
      bool gitInit = true,
    }) => NewProjectRequest(
      name: 'avera_booking',
      org: 'com.example',
      parent: root.path,
      template: template,
      gitInit: gitInit,
    );

    test('runs the steps in order', () async {
      final snapshots = await repository.create(request()).toList();
      expect(snapshots.first.map((s) => s.status), everyElement(CreationStepStatus.pending));
      final last = snapshots.last;
      expect(last.map((s) => s.kind), [
        CreationStepKind.flutterCreate,
        CreationStepKind.gitInit,
        CreationStepKind.agentSetup,
        CreationStepKind.analyze,
        CreationStepKind.firstCommit,
      ]);
      expect(last.map((s) => s.status), everyElement(CreationStepStatus.done));
      expect(last.map((s) => s.took), everyElement(isNotNull));
      expect(last[0].took, const Duration(seconds: 6));
      expect(last[0].output, ['Creating project avera_booking...', 'Wrote 130 files.']);
      expect(last[2].output, hasLength(4));
      expect(last[3].output, ['No issues found!']);
      // One step runs at a time.
      for (final snapshot in snapshots) {
        expect(snapshot.where((s) => s.status == CreationStepStatus.running).length, lessThan(2));
      }
      expect(root.listSync(), isEmpty);
    });

    test('plain template without git skips steps', () async {
      final snapshots = await repository
          .create(request(template: NewProjectTemplate.plain, gitInit: false))
          .toList();
      expect(snapshots.last.map((s) => s.kind), [
        CreationStepKind.flutterCreate,
        CreationStepKind.analyze,
      ]);
    });

    test('cancel stops the run', () async {
      final slow = FakeProjectCreationRepositoryImpl(
        database: database,
        step: const Duration(milliseconds: 10),
        home: root.path,
      );
      var seen = 0;
      final running = slow.create(request()).listen((_) => seen++);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await running.cancel();
      final atCancel = seen;
      expect(atCancel, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen, atCancel);
    });
  });
}
