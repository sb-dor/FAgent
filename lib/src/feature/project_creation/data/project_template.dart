/// Where the architecture skeleton of a new project lives in the app's assets.
const String projectTemplateRoot = 'assets/project_template/architecture/';

/// The files of the skeleton, relative to [projectTemplateRoot] and to the new project.
const List<String> projectTemplateFiles = <String>[
  'lib/main.dart',
  'lib/src/common/utils/app_zone.dart',
  'lib/src/common/utils/error_util.dart',
  'lib/src/common/widget/app_error.dart',
  'lib/src/common/localization/localization.dart',
  'lib/src/common/localization/intl_en.arb',
  'lib/src/feature/initialization/models/dependencies.dart',
  'lib/src/feature/initialization/widget/dependencies_scope.dart',
  'lib/src/feature/initialization/widget/app.dart',
  'lib/src/feature/initialization/data/initialization.dart',
  'lib/src/feature/initialization/data/initialize_dependencies.dart',
  'lib/src/feature/home/widgets/home_screen.dart',
  'test/widget_test.dart',
  'l10n.yaml',
];

/// Replaces every `{{package}}` in a template file with the package name of the new project.
String fillProjectTemplate(String text, {required String package}) =>
    text.replaceAll('{{package}}', package);

/// The repository of the `control` package. It is pinned to a commit because the release on
/// pub.dev lacks `handle(..., error:)`; the pin equals the one in this app's `pubspec.yaml`.
const String controlGitUrl = 'https://github.com/PlugFox/control.git';

/// The commit of [controlGitUrl] the skeleton depends on.
const String controlGitRef = '685a9bc6ef60c987b99b5526e125813adba54e2a';

/// The arguments of the one `flutter pub add` that installs the packages of the skeleton.
const List<String> skeletonPubAddArguments = <String>[
  'l',
  'shared_preferences',
  'freezed_annotation',
  'intl',
  'flutter_localizations@{sdk: flutter}',
  'control@{git: {url: $controlGitUrl, ref: $controlGitRef}}',
  'dev:freezed',
  'dev:build_runner',
];
