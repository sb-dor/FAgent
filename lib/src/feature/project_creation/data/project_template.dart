/// Where the architecture skeleton of a new project lives in the app's assets.
const String projectTemplateRoot = 'assets/project_template/architecture/';

/// The files of the skeleton, relative to [projectTemplateRoot] and to the new project.
///
/// Shared code is in `lib/src/_core/`, and every feature is a folder of its own directly in
/// `lib/src/`, as `docs/rules/architecture.md` describes.
const List<String> projectTemplateFiles = <String>[
  'lib/main.dart',
  'lib/src/_core/utils/app_zone.dart',
  'lib/src/_core/utils/error_util.dart',
  'lib/src/_core/widget/app_error.dart',
  'lib/src/_core/localization/localization.dart',
  'lib/src/_core/localization/intl_en.arb',
  'lib/src/initialization/models/dependencies.dart',
  'lib/src/initialization/widget/dependencies_scope.dart',
  'lib/src/initialization/widget/app.dart',
  'lib/src/initialization/data/initialization.dart',
  'lib/src/initialization/data/initialize_dependencies.dart',
  'lib/src/home/widgets/home_screen.dart',
  'test/widget_test.dart',
  'l10n.yaml',
  'analysis_options.yaml',
  'build.yaml',
  'Makefile',
  'CHANGELOG.md',
  'tool/dart/rename_project.dart',
  'scripts/analyze.bash',
  'scripts/format.bash',
  'scripts/generate.bash',
  'scripts/test.bash',
];

/// Replaces every `{{package}}` in a template file with the package name of the new project, and
/// every `{{date}}` with [date] as `YYYY-MM-DD` (the first entry of `CHANGELOG.md`).
String fillProjectTemplate(String text, {required String package, required DateTime date}) =>
    text.replaceAll('{{package}}', package).replaceAll('{{date}}', _isoDate(date));

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

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
