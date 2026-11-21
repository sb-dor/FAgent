/// Where the architecture skeleton of a new project lives in the app's assets.
const String projectTemplateRoot = 'assets/project_template/architecture/';

/// The files of the skeleton, relative to [projectTemplateRoot] and to the new project.
///
/// An app has no `lib/src/`: shared code is in `lib/_core/`, and every feature is a folder of its
/// own directly in `lib/`, as `docs/rules/architecture.md` describes. The `packages/ui` package
/// keeps the package layout (`lib/ui.dart` and `lib/src/`).
const List<String> projectTemplateFiles = <String>[
  'lib/main.dart',
  'lib/_core/utils/api_client.dart',
  'lib/_core/utils/app_zone.dart',
  'lib/_core/utils/error_util/error_util.dart',
  'lib/_core/utils/error_util/platform/error_util_vm.dart',
  'lib/_core/utils/error_util/platform/error_util_js.dart',
  'lib/_core/model/virtual_key_codes.dart',
  'lib/_core/utils/color_util.dart',
  'lib/_core/utils/date_util.dart',
  'lib/_core/utils/json_util.dart',
  'lib/_core/utils/keyboard_observer.dart',
  'lib/_core/utils/log_buffer.dart',
  'lib/_core/utils/placeholders.dart',
  'lib/_core/utils/screen_util.dart',
  'lib/_core/utils/stream_util.dart',
  'lib/_core/utils/timeouts.dart',
  'lib/_core/utils/token_util.dart',
  'lib/_core/utils/middleware/logger_mw.dart',
  'lib/_core/utils/middleware/authentication_interceptor.dart',
  'lib/_core/utils/platform/keyboard_observer_interface.dart',
  'lib/_core/utils/platform/keyboard_observer_vm.dart',
  'lib/_core/utils/platform/keyboard_observer_js.dart',
  'lib/_core/utils/platform/keyboard_observer_windows.dart',
  'lib/_core/utils/platform/availability/platform_availability.dart',
  'lib/_core/utils/platform/availability/platform_availability_vm.dart',
  'lib/_core/utils/platform/availability/platform_availability_js.dart',
  'lib/_core/widget/app_error.dart',
  'lib/_core/localization/localization.dart',
  'lib/_core/localization/intl_en.arb',
  'lib/_core/constant/config.dart',
  'lib/_core/controller/controller_observer.dart',
  'lib/_core/database/database.dart',
  'lib/_core/database/tables/log_table.dart',
  'lib/_core/model/app_metadata.dart',
  'lib/_core/utils/extensions.dart',
  'lib/_core/utils/local_pagination.dart',
  'lib/_core/utils/pagination_util.dart',
  'lib/_core/utils/performance_overlay_tool.dart',
  'lib/_core/utils/text_controller_listener.dart',
  'lib/_core/utils/text_input_formatters/currency_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_formatter_with_specific_length.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_space_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_space_formatter_with_specific_length.dart',
  'lib/_core/utils/text_input_formatters/integer_text_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/integer_text_input_space_formatter.dart',
  'lib/_core/utils/text_input_formatters/text_input_config.dart',
  'lib/_core/utils/text_input_formatters/year_input_formatter.dart',
  'lib/_core/widget/adaptive_date_picker.dart',
  'lib/_core/widget/common_actions.dart',
  'lib/_core/widget/common_header.dart',
  'lib/_core/widget/input_text_field.dart',
  'lib/_core/widget/not_found_screen.dart',
  'lib/_core/widget/outlined_text.dart',
  'lib/_core/widget/output_text_field.dart',
  'lib/_core/widget/scaffold_padding.dart',
  'lib/_core/widget/scroll_with_mouse_behavior.dart',
  'lib/_core/widget/sizer.dart',
  'lib/_core/widget/try_again_widget.dart',
  'lib/_core/widget/window_scope.dart',
  'packages/ui/lib/ui.dart',
  'packages/ui/shaders/shimmer.frag',
  'packages/ui/lib/src/components/components.dart',
  'packages/ui/lib/src/components/layout/popup.dart',
  'packages/ui/lib/src/components/layout/layout.dart',
  'packages/ui/lib/src/components/placeholders/placeholders.dart',
  'packages/ui/lib/src/components/placeholders/shimmer.dart',
  'packages/ui/lib/src/components/placeholders/form_placeholder.dart',
  'packages/ui/lib/src/components/placeholders/radial_progress_indicator.dart',
  'packages/ui/lib/src/components/placeholders/text_placeholder.dart',
  'packages/ui/lib/src/components/charts/charts.dart',
  'packages/ui/lib/src/components/charts/pie_chart.dart',
  'packages/ui/lib/src/theme/theme.dart',
  'packages/ui/lib/src/theme/extensions/colors.dart',
  'packages/ui/pubspec.yaml',
  'lib/_core/localization/intl_ru.arb',
  'lib/initialization/models/dependencies.dart',
  'lib/initialization/widget/dependencies_scope.dart',
  'lib/initialization/widget/app.dart',
  'lib/initialization/data/initialization.dart',
  'lib/initialization/data/initialize_dependencies.dart',
  'lib/home/widgets/home_screen.dart',
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

/// The files of [projectTemplateFiles] that belong to the repository root: in a monorepo they stay
/// at the root, next to `apps/` and `packages/`.
const List<String> projectTemplateRepoFiles = <String>[
  'analysis_options.yaml',
  'Makefile',
  'CHANGELOG.md',
  'tool/dart/rename_project.dart',
  'scripts/analyze.bash',
  'scripts/format.bash',
  'scripts/generate.bash',
  'scripts/test.bash',
];

/// The files of [projectTemplateFiles] that belong to one app: in a monorepo they go to
/// `apps/<folder>`.
const List<String> projectTemplateAppFiles = <String>[
  'lib/main.dart',
  'lib/_core/utils/api_client.dart',
  'lib/_core/utils/app_zone.dart',
  'lib/_core/utils/error_util/error_util.dart',
  'lib/_core/utils/error_util/platform/error_util_vm.dart',
  'lib/_core/utils/error_util/platform/error_util_js.dart',
  'lib/_core/model/virtual_key_codes.dart',
  'lib/_core/utils/color_util.dart',
  'lib/_core/utils/date_util.dart',
  'lib/_core/utils/json_util.dart',
  'lib/_core/utils/keyboard_observer.dart',
  'lib/_core/utils/log_buffer.dart',
  'lib/_core/utils/placeholders.dart',
  'lib/_core/utils/screen_util.dart',
  'lib/_core/utils/stream_util.dart',
  'lib/_core/utils/timeouts.dart',
  'lib/_core/utils/token_util.dart',
  'lib/_core/utils/middleware/logger_mw.dart',
  'lib/_core/utils/middleware/authentication_interceptor.dart',
  'lib/_core/utils/platform/keyboard_observer_interface.dart',
  'lib/_core/utils/platform/keyboard_observer_vm.dart',
  'lib/_core/utils/platform/keyboard_observer_js.dart',
  'lib/_core/utils/platform/keyboard_observer_windows.dart',
  'lib/_core/utils/platform/availability/platform_availability.dart',
  'lib/_core/utils/platform/availability/platform_availability_vm.dart',
  'lib/_core/utils/platform/availability/platform_availability_js.dart',
  'lib/_core/widget/app_error.dart',
  'lib/_core/localization/localization.dart',
  'lib/_core/localization/intl_en.arb',
  'lib/_core/constant/config.dart',
  'lib/_core/controller/controller_observer.dart',
  'lib/_core/database/database.dart',
  'lib/_core/database/tables/log_table.dart',
  'lib/_core/model/app_metadata.dart',
  'lib/_core/utils/extensions.dart',
  'lib/_core/utils/local_pagination.dart',
  'lib/_core/utils/pagination_util.dart',
  'lib/_core/utils/performance_overlay_tool.dart',
  'lib/_core/utils/text_controller_listener.dart',
  'lib/_core/utils/text_input_formatters/currency_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_formatter_with_specific_length.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_space_formatter.dart',
  'lib/_core/utils/text_input_formatters/decimal_text_input_space_formatter_with_specific_length.dart',
  'lib/_core/utils/text_input_formatters/integer_text_input_formatter.dart',
  'lib/_core/utils/text_input_formatters/integer_text_input_space_formatter.dart',
  'lib/_core/utils/text_input_formatters/text_input_config.dart',
  'lib/_core/utils/text_input_formatters/year_input_formatter.dart',
  'lib/_core/widget/adaptive_date_picker.dart',
  'lib/_core/widget/common_actions.dart',
  'lib/_core/widget/common_header.dart',
  'lib/_core/widget/input_text_field.dart',
  'lib/_core/widget/not_found_screen.dart',
  'lib/_core/widget/outlined_text.dart',
  'lib/_core/widget/output_text_field.dart',
  'lib/_core/widget/scaffold_padding.dart',
  'lib/_core/widget/scroll_with_mouse_behavior.dart',
  'lib/_core/widget/sizer.dart',
  'lib/_core/widget/try_again_widget.dart',
  'lib/_core/widget/window_scope.dart',
  'lib/_core/localization/intl_ru.arb',
  'lib/initialization/models/dependencies.dart',
  'lib/initialization/widget/dependencies_scope.dart',
  'lib/initialization/widget/app.dart',
  'lib/initialization/data/initialization.dart',
  'lib/initialization/data/initialize_dependencies.dart',
  'lib/home/widgets/home_screen.dart',
  'test/widget_test.dart',
  'l10n.yaml',
  'build.yaml',
];

/// The files of [projectTemplateFiles] of the shared `packages/ui` package.
const List<String> projectTemplateUiFiles = <String>[
  'packages/ui/lib/ui.dart',
  'packages/ui/shaders/shimmer.frag',
  'packages/ui/lib/src/components/components.dart',
  'packages/ui/lib/src/components/layout/popup.dart',
  'packages/ui/lib/src/components/layout/layout.dart',
  'packages/ui/lib/src/components/placeholders/placeholders.dart',
  'packages/ui/lib/src/components/placeholders/shimmer.dart',
  'packages/ui/lib/src/components/placeholders/form_placeholder.dart',
  'packages/ui/lib/src/components/placeholders/radial_progress_indicator.dart',
  'packages/ui/lib/src/components/placeholders/text_placeholder.dart',
  'packages/ui/lib/src/components/charts/charts.dart',
  'packages/ui/lib/src/components/charts/pie_chart.dart',
  'packages/ui/lib/src/theme/theme.dart',
  'packages/ui/lib/src/theme/extensions/colors.dart',
  'packages/ui/pubspec.yaml',
];

/// Where the scripts and the Makefile of a monorepo live in the app's assets.
const String monorepoTemplateRoot = 'assets/project_template/monorepo/';

/// The files of a monorepo's root, relative to [monorepoTemplateRoot]. They find the members
/// (`apps/*`, `packages/*`) themselves, so adding a member never edits them.
const List<String> monorepoTemplateFiles = <String>[
  'Makefile',
  'scripts/analyze.bash',
  'scripts/format.bash',
  'scripts/generate.bash',
  'scripts/test.bash',
];

/// The root `pubspec.yaml` of a monorepo: a workspace of `apps/*` and `packages/*` without code of
/// its own. `dependencies:` and `dev_dependencies:` are added by `pub add` afterwards.
String monorepoRootPubspec({required String name, required String sdkConstraint}) =>
    '''
name: ${name}_workspace
description: Workspace of $name.
publish_to: none

environment:
  sdk: $sdkConstraint

workspace:
  - apps/*
  - packages/*
''';

/// The oldest Flutter whose `material.dart` and `cupertino.dart` (and the Material and Cupertino
/// delegates of `flutter_localizations`) are deprecated in favour of the `material_ui` and
/// `cupertino_ui` packages. `flutter analyze` fails a new project on their infos.
const String kMaterialUiMinFlutter = '3.47';

/// Whether a project made with Flutter [flutterVersion] (for example `3.50.0`) imports
/// `material_ui` and `cupertino_ui` instead of the SDK's libraries; `false` when it is unknown.
bool usesMaterialUi(String? flutterVersion) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(flutterVersion ?? '');
  if (match == null) return false;
  final min = kMaterialUiMinFlutter.split('.').map(int.parse).toList();
  final major = int.parse(match[1]!);
  final minor = int.parse(match[2]!);
  return major != min[0] ? major > min[0] : minor >= min[1];
}

/// The packages `packages/ui` gets when the project uses `material_ui`: its files import
/// `material.dart`, none `cupertino.dart`.
const List<String> uiMaterialUiPackages = <String>['material_ui'];

const String _material = "'package:flutter/material.dart'";
const String _materialUi = "'package:material_ui/material_ui.dart'";
const String _cupertino = "'package:flutter/cupertino.dart'";
const String _cupertinoUi = "'package:cupertino_ui/cupertino_ui.dart'";
const String _localizationsImport =
    "import 'package:flutter_localizations/flutter_localizations.dart';";
const String _localizationsWidgetsImport =
    "import 'package:flutter_localizations/flutter_localizations.dart' "
    'show GlobalWidgetsLocalizations;';

/// [dartSource] (a template file) for a Flutter that [usesMaterialUi]: every import and export of
/// `material.dart` becomes one of `material_ui`, of `cupertino.dart` one of `cupertino_ui`, and a
/// plain import of `flutter_localizations` (which also exports the deprecated Material and
/// Cupertino delegates) shows only `GlobalWidgetsLocalizations`, the other delegates coming from
/// `material_ui` and `cupertino_ui`. `dart fix --code=directives_ordering` sorts the imports
/// afterwards.
String useMaterialUi(String dartSource) {
  var text = dartSource.replaceAll(_material, _materialUi).replaceAll(_cupertino, _cupertinoUi);
  if (!text.contains(_localizationsImport)) return text;
  final imports = <String>[
    if (text.contains('GlobalMaterialLocalizations') && !text.contains('import $_materialUi;'))
      "import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;",
    if (text.contains('GlobalCupertinoLocalizations') && !text.contains('import $_cupertinoUi;'))
      "import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;",
    if (text.contains('GlobalWidgetsLocalizations')) _localizationsWidgetsImport,
  ];
  return text.replaceFirst(
    imports.isEmpty ? '$_localizationsImport\n' : _localizationsImport,
    imports.join('\n'),
  );
}

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
/// [uiPath] is where `packages/ui` is, relative to the package that depends on it; with
/// [materialUi] (see [usesMaterialUi]) it adds `material_ui` and `cupertino_ui`.
List<String> skeletonPubAddArgumentsFor({required String uiPath, bool materialUi = false}) =>
    <String>[
      // No versions: `pub add` takes the newest release that fits the SDK, at every creation.
      'l',
      'http',
      'meta',
      'win32',
      'shared_preferences',
      'freezed_annotation',
      'intl',
      'collection',
      'async',
      'path',
      'convert',
      'path_provider',
      'platform_info',
      'rxdart',
      'url_launcher',
      'window_manager',
      'drift',
      'drift_flutter',
      'web',
      'flutter_localizations@{sdk: flutter}',
      if (materialUi) ...<String>['material_ui', 'cupertino_ui'],
      'control@{git: {url: $controlGitUrl, ref: $controlGitRef}}',
      // The workspace member with the shared UI (`packages/ui`, listed under `workspace:`).
      'ui@{path: $uiPath}',
      'dev:freezed',
      'dev:build_runner',
      'dev:drift_dev',
      'dev:flutter_launcher_icons',
      'dev:flutter_native_splash',
      'dev:integration_test@{sdk: flutter}',
    ];

/// [skeletonPubAddArgumentsFor] for a one-app project, where `packages/ui` is inside it.
final List<String> skeletonPubAddArguments = skeletonPubAddArgumentsFor(uiPath: 'packages/ui');
