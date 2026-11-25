import 'package:flutter_code_agent/app_settings/models/app_settings.dart';
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

  /// Whether the project picks a [StateManagement]: an app and a module have screens and business
  /// logic. A package, a plugin and an FFI package leave that to the apps that use them.
  bool get hasStateManagement => this == app || this == module;
}

/// How an app project is laid out.
enum ProjectStructure {
  /// One Flutter app at the project root.
  single,

  /// A pub workspace: the app in `apps/<folder>`, more apps and packages added later.
  monorepo,
}

/// Where an app with the architecture skeleton sends its unexpected errors. The log
/// (`logs.sqlite`) and the queue are there with every choice; only the gateway differs.
enum CrashReporter {
  /// Sentry on every platform, its DSN from `config/sentry.local.json`.
  sentry,

  /// Firebase Crashlytics on Android, iOS and macOS (Sentry elsewhere, when a DSN is set);
  /// `flutterfire configure` connects the project.
  crashlytics,

  /// No service: the errors stay in the log on the machine.
  logOnly,
}

/// The package a project's business logic is written with. The project gets the rule of this one
/// only (`docs/rules/controllers.md` or `docs/rules/bloc.md`) and, with the architecture skeleton,
/// its observer and packages.
enum StateManagement {
  /// `package:control`: controllers with `handle(...)`.
  control,

  /// `package:bloc` and `flutter_bloc`: one event, one `on<>`, the global sequential queue.
  bloc;

  /// The name of the built-in rule (`docs/rules/<ruleName>.md`) a project with this one gets.
  String get ruleName => switch (this) {
    StateManagement.control => 'controllers',
    StateManagement.bloc => 'bloc',
  };

  /// The rules a project with this one leaves out: those of the others.
  Set<String> get otherRuleNames => <String>{
    for (final other in StateManagement.values)
      if (other != this) other.ruleName,
  };

  /// The rules of every state management package.
  static Set<String> get ruleNames => <String>{
    for (final value in StateManagement.values) value.ruleName,
  };
}

/// What the New project wizard asks for.
@freezed
abstract class NewProjectRequest with _$NewProjectRequest {
  /// Creates a request.
  const factory NewProjectRequest({
    /// The package name, also the folder's name.
    required String name,

    /// The organization, for example `com.example`: `flutter create --org`.
    required String org,

    /// The full application ID of an app, for example `com.example.shop`; `null` keeps what
    /// `flutter create` makes of [org] and the package name. Its segments before the last are
    /// [org].
    String? applicationId,

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

    /// One app or a workspace; only an app can be a monorepo.
    @Default(ProjectStructure.single) ProjectStructure structure,

    /// The folder of the first app under `apps/` in a monorepo.
    @Default('app') String appFolder,

    /// The package name of the first app in a monorepo; `null` means `<name>_<appFolder>`.
    String? appPackage,

    /// Where the skeleton's app reports its errors; only the architecture skeleton has one.
    @Default(CrashReporter.sentry) CrashReporter crashReporter,

    /// The state management package: decides the rule the project gets and, with the skeleton,
    /// its observer and packages. Only a [type] that [FlutterProjectType.hasStateManagement] uses it.
    @Default(StateManagement.control) StateManagement stateManagement,
  }) = _NewProjectRequest;

  const NewProjectRequest._();

  /// The project folder.
  String get path => p.join(parent, name);

  /// Whether the project is a pub workspace: [structure] only applies to an app.
  bool get monorepo => type == FlutterProjectType.app && structure == ProjectStructure.monorepo;

  /// The package name of the first app in a monorepo.
  String get appPackageName => appPackage ?? '${name}_$appFolder';

  /// Where the app is: the project folder, or `apps/<appFolder>` in a monorepo.
  String get appPath => monorepo ? p.join(path, 'apps', appFolder) : path;

  /// The built-in rules the project leaves out: those of the other state management packages, or
  /// all of them for a type without one.
  Set<String> get rulesLeftOut =>
      type.hasStateManagement ? stateManagement.otherRuleNames : StateManagement.ruleNames;

  /// Whether the architecture skeleton is written: only into an app that starts from it.
  bool get skeleton =>
      type == FlutterProjectType.app && template == NewProjectTemplate.architecture;
}
