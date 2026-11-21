import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NewProjectRequest project({
    String name = 'shop',
    FlutterProjectType type = FlutterProjectType.app,
    ProjectStructure structure = ProjectStructure.single,
    NewProjectTemplate template = NewProjectTemplate.architecture,
    bool gitInit = true,
  }) => NewProjectRequest(
    name: name,
    org: 'com.example',
    parent: '/work',
    type: type,
    structure: structure,
    template: template,
    gitInit: gitInit,
  );

  NewMemberRequest member({
    MemberKind kind = MemberKind.flutterApp,
    NewProjectTemplate template = NewProjectTemplate.architecture,
    bool gitRepo = true,
  }) => NewMemberRequest(
    projectId: 1,
    projectPath: '/work/shop',
    kind: kind,
    folder: 'admin',
    packageName: 'shop_admin',
    org: 'com.example',
    platforms: const <FlutterPlatform>{FlutterPlatform.macos},
    template: template,
    gitRepo: gitRepo,
  );

  group('creationStepsFor', () {
    test('one-app steps are unchanged', () {
      expect(creationStepsFor(project()), <CreationStepKind>[
        CreationStepKind.flutterCreate,
        CreationStepKind.gitInit,
        CreationStepKind.skeleton,
        CreationStepKind.analyze,
        CreationStepKind.rules,
        CreationStepKind.firstCommit,
      ]);
      expect(
        creationStepsFor(project(template: NewProjectTemplate.plain, gitInit: false)),
        <CreationStepKind>[
          CreationStepKind.flutterCreate,
          CreationStepKind.analyze,
          CreationStepKind.rules,
        ],
      );
    });

    test('monorepo steps', () {
      expect(creationStepsFor(project(structure: ProjectStructure.monorepo)), <CreationStepKind>[
        CreationStepKind.workspace,
        CreationStepKind.flutterCreate,
        CreationStepKind.gitInit,
        CreationStepKind.skeleton,
        CreationStepKind.analyze,
        CreationStepKind.rules,
        CreationStepKind.firstCommit,
      ]);
      expect(
        creationStepsFor(
          project(structure: ProjectStructure.monorepo, template: NewProjectTemplate.plain),
        ),
        <CreationStepKind>[
          CreationStepKind.workspace,
          CreationStepKind.flutterCreate,
          CreationStepKind.gitInit,
          CreationStepKind.pubGet,
          CreationStepKind.analyze,
          CreationStepKind.rules,
          CreationStepKind.firstCommit,
        ],
      );
    });

    test('structure is ignored for a package', () {
      final request = project(
        type: FlutterProjectType.package,
        structure: ProjectStructure.monorepo,
      );
      expect(request.monorepo, isFalse);
      expect(
        creationStepsFor(request),
        creationStepsFor(project(type: FlutterProjectType.package)),
      );
      expect(creationStepsFor(request), isNot(contains(CreationStepKind.workspace)));
    });
  });

  group('memberStepsFor', () {
    test('Flutter app with the architecture and git', () {
      expect(memberStepsFor(member()), <CreationStepKind>[
        CreationStepKind.memberCreate,
        CreationStepKind.skeleton,
        CreationStepKind.commit,
        CreationStepKind.analyze,
      ]);
    });

    test('Dart package without git', () {
      expect(
        memberStepsFor(member(kind: MemberKind.dartPackage, gitRepo: false)),
        <CreationStepKind>[
          CreationStepKind.memberCreate,
          CreationStepKind.pubGet,
          CreationStepKind.analyze,
        ],
      );
    });

    test('only a Flutter app has a skeleton', () {
      expect(member(kind: MemberKind.dartApp).skeleton, isFalse);
      expect(member(kind: MemberKind.flutterApp).skeleton, isTrue);
      expect(member(template: NewProjectTemplate.plain).skeleton, isFalse);
    });
  });

  group('MemberKind and NewMemberRequest', () {
    test('parent, platforms and commit label', () {
      expect(MemberKind.flutterApp.parent, 'apps');
      expect(MemberKind.dartApp.parent, 'apps');
      expect(MemberKind.flutterPackage.parent, 'packages');
      expect(MemberKind.dartPackage.parent, 'packages');
      expect(MemberKind.values.where((kind) => kind.hasPlatforms), <MemberKind>[
        MemberKind.flutterApp,
      ]);
      expect(MemberKind.flutterPackage.commitLabel, 'Flutter package');
      expect(MemberKind.dartApp.commitLabel, 'Dart app');
    });

    test('path and relative', () {
      final request = member(kind: MemberKind.dartPackage);
      expect(request.path, '/work/shop/packages/admin');
      expect(request.relative, 'packages/admin');
    });
  });

  group('NewProjectRequest', () {
    test('app package defaults to name_folder', () {
      final request = project(structure: ProjectStructure.monorepo);
      expect(request.appPackageName, 'shop_app');
      expect(request.appPath, endsWith('shop/apps/app'));
      expect(request.copyWith(appFolder: 'desktop').appPackageName, 'shop_desktop');
      expect(request.copyWith(appPackage: 'custom').appPackageName, 'custom');
    });

    test('a one-app project builds in its own folder', () {
      expect(project().appPath, '/work/shop');
    });
  });

  group('supportsMonorepo', () {
    test('needs Dart 3.14', () {
      expect(supportsMonorepo('3.14.0'), isTrue);
      expect(supportsMonorepo('3.15.1'), isTrue);
      expect(supportsMonorepo('3.13.9'), isFalse);
      expect(supportsMonorepo(null), isFalse);
      expect(supportsMonorepo('3.15.0-12.0.dev'), isTrue);
      expect(supportsMonorepo('3.13.0-1.0.dev'), isFalse);
      expect(supportsMonorepo(''), isFalse);
      expect(supportsMonorepo('abc'), isFalse);
    });
  });

  group('supportsArchitecture', () {
    test('needs Flutter 3.50', () {
      expect(kArchitectureMinFlutter, '3.50');
      for (final version in const <String>[
        '3.50.0',
        '3.50.0-0.1.pre',
        '3.51.2',
        '3.100.0',
        '4.0.0',
      ]) {
        expect(supportsArchitecture(version), isTrue, reason: version);
      }
      for (final version in const <String?>[null, '', 'abc', '3', '3.47.2', '3.49.9', '2.99.0']) {
        expect(supportsArchitecture(version), isFalse, reason: version);
      }
    });
  });
}
