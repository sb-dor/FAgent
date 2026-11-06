/// Where the architecture skeleton of a new project lives in the app's assets.
const String projectTemplateRoot = 'assets/project_template/architecture/';

/// The files of the skeleton, relative to [projectTemplateRoot] and to the new project.
///
/// Shared code is in `lib/src/_core/`, and every feature is a folder of its own directly in
/// `lib/src/`, as `docs/rules/architecture.md` describes.
const List<String> projectTemplateFiles = <String>[
  'lib/main.dart',
  'lib/src/_core/utils/api_client.dart',
  'lib/src/_core/utils/app_zone.dart',
  'lib/src/_core/utils/error_util/error_util.dart',
  'lib/src/_core/utils/error_util/platform/error_util_vm.dart',
  'lib/src/_core/utils/error_util/platform/error_util_js.dart',
  'lib/src/_core/model/virtual_key_codes.dart',
  'lib/src/_core/utils/color_util.dart',
  'lib/src/_core/utils/date_util.dart',
  'lib/src/_core/utils/json_util.dart',
  'lib/src/_core/utils/keyboard_observer.dart',
  'lib/src/_core/utils/log_buffer.dart',
  'lib/src/_core/utils/placeholders.dart',
  'lib/src/_core/utils/screen_util.dart',
  'lib/src/_core/utils/stream_util.dart',
  'lib/src/_core/utils/timeouts.dart',
  'lib/src/_core/utils/token_util.dart',
  'lib/src/_core/utils/middleware/logger_mw.dart',
  'lib/src/_core/utils/middleware/authentication_interceptor.dart',
  'lib/src/_core/utils/platform/keyboard_observer_interface.dart',
  'lib/src/_core/utils/platform/keyboard_observer_vm.dart',
  'lib/src/_core/utils/platform/keyboard_observer_js.dart',
  'lib/src/_core/utils/platform/keyboard_observer_windows.dart',
  'lib/src/_core/utils/platform/availability/platform_availability.dart',
  'lib/src/_core/utils/platform/availability/platform_availability_vm.dart',
  'lib/src/_core/utils/platform/availability/platform_availability_js.dart',
  'lib/src/_core/widget/app_error.dart',
  'lib/src/_core/localization/localization.dart',
  'lib/src/_core/localization/intl_en.arb',
  'lib/src/_core/constant/config.dart',
  'lib/src/_core/controller/controller_observer.dart',
  'lib/src/_core/database/database.dart',
  'lib/src/_core/database/tables/log_table.dart',
  'lib/src/_core/model/app_metadata.dart',
  'lib/src/_core/utils/extensions.dart',
  'lib/src/_core/utils/local_pagination.dart',
  'lib/src/_core/utils/pagination_util.dart',
  'lib/src/_core/utils/performance_overlay_tool.dart',
  'lib/src/_core/utils/text_controller_listener.dart',
  'lib/src/_core/utils/text_input_formatters/currency_input_formatter.dart',
  'lib/src/_core/utils/text_input_formatters/decimal_text_input_formatter.dart',
  'lib/src/_core/utils/text_input_formatters/decimal_text_input_formatter_with_specific_length.dart',
  'lib/src/_core/utils/text_input_formatters/decimal_text_input_space_formatter.dart',
  'lib/src/_core/utils/text_input_formatters/decimal_text_input_space_formatter_with_specific_length.dart',
  'lib/src/_core/utils/text_input_formatters/integer_text_input_formatter.dart',
  'lib/src/_core/utils/text_input_formatters/integer_text_input_space_formatter.dart',
  'lib/src/_core/utils/text_input_formatters/text_input_config.dart',
  'lib/src/_core/utils/text_input_formatters/year_input_formatter.dart',
  'lib/src/_core/widget/adaptive_date_picker.dart',
  'lib/src/_core/widget/common_actions.dart',
  'lib/src/_core/widget/common_header.dart',
  'lib/src/_core/widget/input_text_field.dart',
  'lib/src/_core/widget/not_found_screen.dart',
  'lib/src/_core/widget/outlined_text.dart',
  'lib/src/_core/widget/output_text_field.dart',
  'lib/src/_core/widget/scaffold_padding.dart',
  'lib/src/_core/widget/scroll_with_mouse_behavior.dart',
  'lib/src/_core/widget/sizer.dart',
  'lib/src/_core/widget/try_again_widget.dart',
  'lib/src/_core/widget/window_scope.dart',
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
  'lib/src/_core/localization/intl_ru.arb',
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
  'control@{git: {url: $controlGitUrl, ref: $controlGitRef}}',
  // The workspace member with the shared UI (`packages/ui`, listed under `workspace:`).
  'ui@{path: packages/ui}',
  'dev:freezed',
  'dev:build_runner',
  'dev:drift_dev',
  'dev:flutter_launcher_icons',
  'dev:flutter_native_splash',
  'dev:integration_test@{sdk: flutter}',
];
