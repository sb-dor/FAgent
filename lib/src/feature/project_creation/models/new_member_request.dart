import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'new_member_request.freezed.dart';

/// What can be added to a monorepo.
enum MemberKind {
  /// A Flutter app in `apps/`.
  flutterApp('apps', 'Flutter app'),

  /// A Dart app in `apps/`.
  dartApp('apps', 'Dart app'),

  /// A Flutter package in `packages/`.
  flutterPackage('packages', 'Flutter package'),

  /// A Dart package in `packages/`.
  dartPackage('packages', 'Dart package');

  const MemberKind(this.parent, this.commitLabel);

  /// The folder of the workspace the member lives in: `apps` or `packages`.
  final String parent;

  /// The kind as the commit message names it.
  final String commitLabel;

  /// Whether the member has platforms to pick: only a Flutter app.
  bool get hasPlatforms => this == flutterApp;
}

/// What the Add to project dialog asks for.
@freezed
abstract class NewMemberRequest with _$NewMemberRequest {
  /// Creates a request.
  const factory NewMemberRequest({
    /// The project the member is added to.
    required int projectId,

    /// The monorepo's root folder.
    required String projectPath,
    required MemberKind kind,

    /// The folder under `apps/` or `packages/`.
    required String folder,

    /// The package name.
    required String packageName,

    /// The organization, for example `com.example`.
    required String org,

    /// The platforms to generate; only a Flutter app has them.
    required Set<FlutterPlatform> platforms,

    /// What a Flutter app starts from.
    required NewProjectTemplate template,

    /// Whether the project is a git repository, so the member is committed.
    ///
    /// An app with the skeleton reports its errors where the monorepo's other apps do: the add
    /// reads it from the monorepo (`crash_reporter.yaml` of `packages/telemetry`).
    required bool gitRepo,
  }) = _NewMemberRequest;

  const NewMemberRequest._();

  /// The member's folder.
  String get path => p.join(projectPath, kind.parent, folder);

  /// The member's folder relative to the project: `<apps|packages>/<folder>`.
  String get relative => '${kind.parent}/$folder';

  /// Whether the architecture skeleton is written: only into a Flutter app that starts from it.
  bool get skeleton => kind == MemberKind.flutterApp && template == NewProjectTemplate.architecture;
}
