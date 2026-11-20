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

/// The kind of project `flutter create --template` makes.
enum FlutterProjectType {
  /// An application: `lib/main.dart` and, with the architecture template, the skeleton.
  app('app'),

  /// A package of Dart code to share: `lib/<name>.dart` and `lib/src/`.
  package('package'),

  /// A package with platform code behind method channels.
  plugin('plugin'),

  /// A package with platform code called through `dart:ffi`.
  packageFfi('package_ffi'),

  /// Flutter to add to an existing Android or iOS app.
  module('module');

  const FlutterProjectType(this.template);

  /// The value of `flutter create --template`.
  final String template;

  /// Whether `flutter create --platforms` applies: only to an app and a plugin.
  bool get hasPlatforms => this == app || this == plugin;
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

    /// What kind of project to create.
    @Default(FlutterProjectType.app) FlutterProjectType type,

    /// What an app starts from; any other [type] is a plain `flutter create`.
    @Default(NewProjectTemplate.architecture) NewProjectTemplate template,

    /// Whether to start a git repository.
    @Default(true) bool gitInit,

    /// Whether to open a chat in the new project.
    @Default(true) bool openChat,
  }) = _NewProjectRequest;

  const NewProjectRequest._();

  /// The project folder.
  String get path => p.join(parent, name);

  /// Whether the architecture skeleton is written: only into an app that starts from it.
  bool get skeleton =>
      type == FlutterProjectType.app && template == NewProjectTemplate.architecture;
}
