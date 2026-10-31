import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'new_project_request.freezed.dart';

/// A platform a Flutter project can target.
enum FlutterPlatform {
  /// iOS.
  ios,

  /// Android.
  android,

  /// macOS.
  macos,

  /// Web.
  web,

  /// Windows.
  windows,

  /// Linux.
  linux,
}

/// What the New project wizard asks for.
@freezed
abstract class NewProjectRequest with _$NewProjectRequest {
  /// Creates a request.
  const factory NewProjectRequest({
    /// The package name, also the folder's name.
    required String name,

    /// The organization, for example `com.example`.
    required String org,

    /// The folder `<parent>/<name>` is created in.
    required String parent,

    /// The platforms to generate.
    @Default(<FlutterPlatform>{FlutterPlatform.ios, FlutterPlatform.android, FlutterPlatform.macos})
    Set<FlutterPlatform> platforms,

    /// What the project starts from.
    @Default(NewProjectTemplate.architecture) NewProjectTemplate template,

    /// Whether to start a git repository.
    @Default(true) bool gitInit,

    /// Whether to open a chat in the new project.
    @Default(true) bool openChat,
  }) = _NewProjectRequest;

  const NewProjectRequest._();

  /// The project folder.
  String get path => p.join(parent, name);
}
