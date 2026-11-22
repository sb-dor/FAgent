/// Where the architecture skeleton of a new project lives in the app's assets.
const String projectTemplateRoot = 'assets/project_template/architecture/';

/// The files of the skeleton, relative to [projectTemplateRoot] and to the new project.
///
/// An app has no `lib/src/`: shared code is in `lib/_core/`, and every feature is a folder of its
/// own directly in `lib/`, as `docs/rules/architecture.md` describes. The `packages/ui` package
/// keeps the package layout (`lib/ui.dart` and `lib/src/`).
const List<String> projectTemplateFiles = <String>[
  'lib/main.dart',
  'lib/_core/api_client/api_client.dart',
  'lib/_core/api_client/expected_exception.dart',
  'lib/_core/api_client/middleware/logger_mw.dart',
  'lib/_core/api_client/middleware/authentication_interceptor.dart',
  // The glue of the error pipeline; the module next to it is FAgent's own (telemetryModuleFiles).
  'lib/_core/telemetry/app_zone.dart',
  'lib/_core/telemetry/controller_observer.dart',
  'lib/_core/telemetry/crash_reporter.dart',
  'lib/_core/telemetry/error_util.dart',
  'lib/_core/telemetry/expected_failure.dart',
  'lib/_core/telemetry/telemetry_setup.dart',
  'lib/_core/telemetry/telemetry_setup_io.dart',
  'lib/_core/telemetry/telemetry_setup_web.dart',
  'lib/_core/model/virtual_key_codes.dart',
  'lib/_core/utils/color_util.dart',
  'lib/_core/utils/date_util.dart',
  'lib/_core/utils/json_util.dart',
  'lib/_core/utils/keyboard_observer.dart',
  'lib/_core/utils/placeholders.dart',
  'lib/_core/utils/screen_util.dart',
  'lib/_core/utils/stream_util.dart',
  'lib/_core/utils/timeouts.dart',
  'lib/_core/utils/token_util.dart',
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
  'lib/_core/database/database.dart',
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
  'config/.gitkeep',
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
  'lib/_core/api_client/api_client.dart',
  'lib/_core/api_client/expected_exception.dart',
  'lib/_core/api_client/middleware/logger_mw.dart',
  'lib/_core/api_client/middleware/authentication_interceptor.dart',
  // The glue of the error pipeline; the module next to it is FAgent's own (telemetryModuleFiles).
  'lib/_core/telemetry/app_zone.dart',
  'lib/_core/telemetry/controller_observer.dart',
  'lib/_core/telemetry/crash_reporter.dart',
  'lib/_core/telemetry/error_util.dart',
  'lib/_core/telemetry/expected_failure.dart',
  'lib/_core/telemetry/telemetry_setup.dart',
  'lib/_core/telemetry/telemetry_setup_io.dart',
  'lib/_core/telemetry/telemetry_setup_web.dart',
  'lib/_core/model/virtual_key_codes.dart',
  'lib/_core/utils/color_util.dart',
  'lib/_core/utils/date_util.dart',
  'lib/_core/utils/json_util.dart',
  'lib/_core/utils/keyboard_observer.dart',
  'lib/_core/utils/placeholders.dart',
  'lib/_core/utils/screen_util.dart',
  'lib/_core/utils/stream_util.dart',
  'lib/_core/utils/timeouts.dart',
  'lib/_core/utils/token_util.dart',
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
  'lib/_core/database/database.dart',
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
  'config/.gitkeep',
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

/// Where the telemetry module lives in FAgent: its own folder, declared as assets. A new project
/// gets it as [telemetryModuleTarget], so FAgent's tests test what the project gets.
const String telemetryModuleRoot = 'lib/src/common/telemetry/';

/// The files of the module, relative to [telemetryModuleRoot]: every Dart file but the generated
/// `telemetry_database.g.dart`, which the project's `build_runner` writes.
const List<String> telemetryModuleFiles = <String>[
  'clip.dart',
  'crash_report_gateway.dart',
  'error_hub.dart',
  'error_outbox.dart',
  'error_reporter.dart',
  'fingerprint.dart',
  'hidden_details_error.dart',
  'log_archive.dart',
  'log_buffer.dart',
  'log_record.dart',
  'log_storage.dart',
  'log_zone.dart',
  'redact.dart',
  'sentry_gateway.dart',
  'start_telemetry.dart',
  'telemetry.dart',
  'telemetry_database.dart',
  'telemetry_runtime.dart',
  'telemetry_sender.dart',
  'telemetry_status.dart',
];

/// Where the tests of the module live in FAgent.
const String telemetryModuleTestRoot = 'test/common/telemetry/';

/// The tests of the module, relative to [telemetryModuleTestRoot]. `portability_test.dart` stays:
/// it checks FAgent's own folder layout.
const List<String> telemetryModuleTestFiles = <String>[
  'consent_test.dart',
  'error_hub_test.dart',
  'error_outbox_test.dart',
  'error_reporter_test.dart',
  'fingerprint_test.dart',
  'hidden_details_error_test.dart',
  'log_archive_test.dart',
  'log_buffer_test.dart',
  'log_format_test.dart',
  'log_storage_test.dart',
  'log_zone_test.dart',
  'redact_test.dart',
  'sentry_gateway_test.dart',
  'start_telemetry_test.dart',
  'telemetry_runtime_test.dart',
  'telemetry_sender_test.dart',
];

/// Where a one-app project keeps the module, next to its glue: relative to the app.
const String telemetryModuleTarget = 'lib/_core/telemetry/';

/// Where a one-app project keeps the tests of the module: relative to the app.
const String telemetryModuleTestTarget = 'test/_core/telemetry/';

/// The prefix of every import between the files of the module in FAgent.
const String _telemetryImportPrefix = 'package:flutter_code_agent/src/common/telemetry/';

/// A file of the telemetry module (or of its tests) as a new project gets it: the module's imports
/// of itself point at [importPrefix] (`package:<package>/_core/telemetry/` in one app). The module
/// imports nothing else of FAgent, so nothing else changes.
String copyTelemetryModule(String text, {required String importPrefix}) =>
    text.replaceAll(_telemetryImportPrefix, importPrefix);

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

/// The packages `packages/ui` gets besides those of its template pubspec, newest versions: its
/// files import `material_ui`, none `cupertino_ui`.
const List<String> uiPubAddArguments = <String>['material_ui'];

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
/// [uiPath] is where `packages/ui` is, relative to the package that depends on it.
List<String> skeletonPubAddArgumentsFor({required String uiPath}) => <String>[
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
  // The telemetry module (lib/_core/telemetry/): Sentry on plain Dart, the clock of its timers,
  // the log archive, and the SQLite errors it tells apart.
  'sentry',
  'clock',
  'archive',
  'sqlite3',
  'web',
  'flutter_localizations@{sdk: flutter}',
  // Flutter 3.47 deprecated the SDK's Material and Cupertino: the template imports these.
  'material_ui',
  'cupertino_ui',
  'control@{git: {url: $controlGitUrl, ref: $controlGitRef}}',
  // The workspace member with the shared UI (`packages/ui`, listed under `workspace:`).
  'ui@{path: $uiPath}',
  'dev:freezed',
  'dev:build_runner',
  'dev:drift_dev',
  // The timers of the telemetry module's tests.
  'dev:fake_async',
  'dev:flutter_launcher_icons',
  'dev:flutter_native_splash',
  'dev:integration_test@{sdk: flutter}',
];

/// [skeletonPubAddArgumentsFor] for a one-app project, where `packages/ui` is inside it.
final List<String> skeletonPubAddArguments = skeletonPubAddArgumentsFor(uiPath: 'packages/ui');
