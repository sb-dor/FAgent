import 'dart:io';

import 'package:flutter_code_agent/src/feature/project_rules/controller/project_rules_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_project_rules.dart';

void main() {
  late FakeProjectRules repository;
  late ProjectRulesController controller;

  setUp(() {
    repository = FakeProjectRules();
    controller = ProjectRulesController(repository: repository);
    addTearDown(controller.dispose);
  });

  Project project({int id = 1, String path = '/p', bool offered = false}) =>
      Project(id: id, path: path, name: 'p', isFlutter: true, rulesOffered: offered);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('check offers a project without docs/rules once', () async {
    controller.check(project());
    await settle();

    expect(
      controller.state,
      const ProjectRulesState.offer(projectId: 1, root: '/p', rules: FakeProjectRules.rules),
    );
  });

  test('check of a project with docs/rules says it has them', () async {
    repository.withRules.add('/with');
    controller.check(project(path: '/with'));
    await settle();

    expect(controller.state, const ProjectRulesState.present(projectId: 1));
  });

  test('check of an offered project without docs/rules says they are missing', () async {
    controller.check(project(id: 2, path: '/asked', offered: true));
    await settle();

    expect(controller.state, const ProjectRulesState.missing(projectId: 2));
  });

  test('offer shows the rules even when already offered', () async {
    controller.offer(project(offered: true));
    await settle();

    expect(controller.state, isA<ProjectRules$OfferState>());
  });

  test('add writes and marks offered', () async {
    controller.add(1, '/p', FakeProjectRules.rules.take(1).toList());
    await settle();

    expect(repository.written.single.$1, '/p');
    expect(repository.written.single.$2, <String>['a']);
    expect(repository.offered, <int>[1]);
    expect(controller.state, const ProjectRulesState.written(projectId: 1));
  });

  test('a failed write is failed and not marked', () async {
    repository.writeError = const FileSystemException('Permission denied', '/p/docs/rules');

    controller.add(1, '/p', FakeProjectRules.rules);
    await settle();

    expect(controller.state, isA<ProjectRules$FailedState>());
    expect(repository.offered, isEmpty);
  });

  test('dismiss marks offered', () async {
    controller.dismiss(3);
    await settle();

    expect(repository.offered, <int>[3]);
    expect(controller.state, const ProjectRulesState.missing(projectId: 3));
  });
}
