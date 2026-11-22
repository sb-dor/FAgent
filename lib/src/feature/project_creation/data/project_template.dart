import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

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
  // The glue of the error pipeline; the module next to it is FAgent's own (telemetryModuleFiles),
  // the crash reporter is the one chosen (crashReporterTemplateFiles).
  'lib/_core/telemetry/app_zone.dart',
  'lib/_core/telemetry/controller_observer.dart',
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
  'packages/ui/.gitignore',
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
/// `apps/<folder>`, through [monorepoAppFile]. The database and the HTTP client are not among them:
/// a monorepo shares them as packages ([sharedPackageSources]).
const List<String> projectTemplateAppFiles = <String>[
  'lib/main.dart',
  // The glue of the error pipeline; the module next to it is FAgent's own (telemetryModuleFiles),
  // the crash reporter is the one chosen (crashReporterTemplateFiles).
  'lib/_core/telemetry/app_zone.dart',
  'lib/_core/telemetry/controller_observer.dart',
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
  'packages/ui/.gitignore',
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

/// The module files a project with [reporter] gets: a log-only project has no Sentry, so no
/// `sentry_gateway.dart`.
List<String> telemetryModuleFilesFor(CrashReporter reporter) => reporter == CrashReporter.logOnly
    ? <String>[
        for (final file in telemetryModuleFiles)
          if (file != _sentryGatewayFile) file,
      ]
    : telemetryModuleFiles;

/// The module tests a project with [reporter] gets: no `sentry_gateway_test.dart` without Sentry.
List<String> telemetryModuleTestFilesFor(CrashReporter reporter) =>
    reporter == CrashReporter.logOnly
    ? <String>[
        for (final file in telemetryModuleTestFiles)
          if (file != _sentryGatewayTest) file,
      ]
    : telemetryModuleTestFiles;

const String _sentryGatewayFile = 'sentry_gateway.dart';
const String _sentryGatewayTest = 'sentry_gateway_test.dart';

/// Where a one-app project keeps the module, next to its glue: relative to the app.
const String telemetryModuleTarget = 'lib/_core/telemetry/';

/// Where a one-app project keeps the tests of the module: relative to the app.
const String telemetryModuleTestTarget = 'test/_core/telemetry/';

/// The prefix of every import between the files of the module in FAgent.
const String _telemetryImportPrefix = 'package:flutter_code_agent/src/common/telemetry/';

/// A file of the telemetry module (or of its tests) as a new project with [crashReporter] gets it:
/// the module's imports of itself point at [importPrefix] (`package:<package>/_core/telemetry/` in
/// one app). The module imports nothing else of FAgent, so nothing else changes, except that a
/// log-only project, which gets no `sentry_gateway.dart`, loses the lines that import or export it.
String copyTelemetryModule(
  String text, {
  required String importPrefix,
  CrashReporter crashReporter = CrashReporter.sentry,
}) {
  final copied = text.replaceAll(_telemetryImportPrefix, importPrefix);
  if (telemetryModuleFilesFor(crashReporter).contains(_sentryGatewayFile)) return copied;
  final sentryGateway = "'$importPrefix$_sentryGatewayFile';";
  return copied
      .split('\n')
      .where(
        (line) => !(line.startsWith(RegExp('(?:import|export) ')) && line.endsWith(sentryGateway)),
      )
      .join('\n');
}

/// Where the crash reporter of a new app goes: `telemetry_setup_io.dart` imports it.
const String crashReporterTarget = 'lib/_core/telemetry/crash_reporter.dart';

/// The template file, relative to [projectTemplateRoot], written as [crashReporterTarget] for
/// [reporter]. Every one has `createCrashReportGateway`, `crashReporterConfigured` and
/// `closeCrashReportGateway`.
String crashReporterFile(CrashReporter reporter) => switch (reporter) {
  CrashReporter.sentry => 'lib/_core/telemetry/crash_reporter_sentry.dart',
  CrashReporter.crashlytics => 'lib/_core/telemetry/crash_reporter_crashlytics.dart',
  CrashReporter.logOnly => 'lib/_core/telemetry/crash_reporter_log_only.dart',
};

/// The files of [reporter] a new app gets besides [projectTemplateFiles]: the template file
/// (relative to [projectTemplateRoot]) and where it goes in the app. Crashlytics brings its gateway
/// and the test of its reporter.
Map<String, String> crashReporterTemplateFiles(CrashReporter reporter) => <String, String>{
  crashReporterFile(reporter): crashReporterTarget,
  if (reporter == CrashReporter.crashlytics) ...const <String, String>{
    'lib/_core/telemetry/crashlytics_gateway.dart': 'lib/_core/telemetry/crashlytics_gateway.dart',
    'test/_core/telemetry/crash_reporter_crashlytics_test.dart':
        'test/_core/telemetry/crash_reporter_test.dart',
  },
};

/// The packages [reporter] adds to the skeleton's `pub add`. Crashlytics keeps Sentry for the
/// platforms `firebase_crashlytics` does not support (Windows, Linux).
List<String> crashReporterPubAddArguments(CrashReporter reporter) => switch (reporter) {
  CrashReporter.sentry => const <String>['sentry'],
  CrashReporter.crashlytics => const <String>['sentry', 'firebase_core', 'firebase_crashlytics'],
  CrashReporter.logOnly => const <String>[],
};

/// The macOS entitlement files `flutter create` writes, relative to the app: Debug and Profile,
/// and Release.
const List<String> macosEntitlementFiles = <String>[
  'macos/Runner/DebugProfile.entitlements',
  'macos/Runner/Release.entitlements',
];

/// The `Info.plist` files whose Crashlytics switch a Crashlytics app sets, relative to the app.
const List<String> crashlyticsPlistFiles = <String>[
  'ios/Runner/Info.plist',
  'macos/Runner/Info.plist',
];

/// The Android manifest of the app, relative to the app.
const String androidManifestFile = 'android/app/src/main/AndroidManifest.xml';

/// [plist] with `<key>[key]</key>` set to [value] (`true` or `false`) at the end of its top
/// `<dict>`; unchanged when the key is already there. `null` when [plist] has no `</dict>`.
String? _withPlistKey(String plist, String key, String value) {
  if (plist.contains('<key>$key</key>')) return plist;
  final end = plist.lastIndexOf('</dict>');
  if (end < 0) return null;
  return '${plist.substring(0, end)}\t<key>$key</key>\n\t<$value/>\n${plist.substring(end)}';
}

/// macOS [entitlements] that allow outgoing connections: Flutter's sandboxed app has none, so
/// neither Sentry nor Crashlytics could send. `null` when the file is not a plist with a `<dict>`.
String? allowOutgoingConnections(String entitlements) =>
    _withPlistKey(entitlements, 'com.apple.security.network.client', 'true');

/// An iOS or macOS [plist] where Crashlytics does not collect until the app turns it on
/// (`CrashlyticsGateway`): the native SDK starts before Dart and would collect from the first
/// launch. `null` when the file is not a plist with a `<dict>`.
String? crashlyticsOffInPlist(String plist) =>
    _withPlistKey(plist, 'FirebaseCrashlyticsCollectionEnabled', 'false');

/// The Android [manifest] where Crashlytics does not collect until the app turns it on, as
/// [crashlyticsOffInPlist] for Android. `null` when the manifest has no `<application>`.
String? crashlyticsOffInManifest(String manifest) {
  const name = 'firebase_crashlytics_collection_enabled';
  if (manifest.contains(name)) return manifest;
  final application = manifest.indexOf('<application');
  final open = application < 0 ? -1 : manifest.indexOf('>', application);
  if (open < 0) return null;
  return '${manifest.substring(0, open + 1)}\n'
      '        <meta-data\n'
      '            android:name="$name"\n'
      '            android:value="false" />'
      '${manifest.substring(open + 1)}';
}

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

/// The packages a monorepo shares between its apps, next to `packages/ui`: the telemetry module,
/// the database and the HTTP client. A one-app project keeps them in `lib/_core/` instead. There is
/// no catch-all `core` package: `ExpectedException` and `RejectedException` live in `api_client`.
const List<String> monorepoSharedPackages = <String>['telemetry', 'database', 'api_client'];

/// The files of the shared packages that only a monorepo has, relative to [monorepoTemplateRoot]
/// and to the monorepo: their pubspecs and public libraries. The code behind the libraries is the
/// one app's ([sharedPackageSources]) and, in `telemetry`, FAgent's module.
const List<String> sharedPackageTemplateFiles = <String>[
  'packages/telemetry/pubspec.yaml',
  'packages/telemetry/.gitignore',
  'packages/telemetry/lib/telemetry.dart',
  'packages/telemetry/lib/portable.dart',
  'packages/database/pubspec.yaml',
  'packages/database/.gitignore',
  'packages/database/lib/database.dart',
  'packages/api_client/pubspec.yaml',
  'packages/api_client/.gitignore',
  'packages/api_client/lib/api_client.dart',
];

/// The files of a one-app project's `lib/_core/database/` and `lib/_core/api_client/`, relative to
/// [projectTemplateRoot], and where a monorepo keeps them: in `lib/src/` of its shared packages,
/// through [sharedPackageSource].
const Map<String, String> sharedPackageSources = <String, String>{
  'lib/_core/database/database.dart': 'packages/database/lib/src/database.dart',
  'lib/_core/api_client/api_client.dart': 'packages/api_client/lib/src/api_client.dart',
  'lib/_core/api_client/expected_exception.dart':
      'packages/api_client/lib/src/expected_exception.dart',
  'lib/_core/api_client/middleware/logger_mw.dart':
      'packages/api_client/lib/src/middleware/logger_mw.dart',
  'lib/_core/api_client/middleware/authentication_interceptor.dart':
      'packages/api_client/lib/src/middleware/authentication_interceptor.dart',
};

/// Where a monorepo keeps the telemetry module: relative to the monorepo.
const String sharedTelemetryModuleTarget = 'packages/telemetry/lib/src/';

/// Where a monorepo keeps the tests of the module: relative to the monorepo.
const String sharedTelemetryModuleTestTarget = 'packages/telemetry/test/';

/// The import prefix of the module in `packages/telemetry`, for [copyTelemetryModule].
const String sharedTelemetryImportPrefix = 'package:telemetry/src/';

/// The module files that compile on the web too (no `dart:io`, drift or Sentry):
/// `package:telemetry/portable.dart` exports them, for the app code the web build reaches.
const List<String> portableTelemetryFiles = <String>['clip.dart', 'log_zone.dart', 'redact.dart'];

/// A file of a one-app project's `lib/_core/database/` or `lib/_core/api_client/`, already filled
/// for [package], as its shared package gets it: imports of its own folder point at the package's
/// `lib/src/`.
String sharedPackageSource(String text, {required String package}) => text
    .replaceAll('package:$package/_core/database/', 'package:database/src/')
    .replaceAll('package:$package/_core/api_client/', 'package:api_client/src/');

/// A file of [projectTemplateAppFiles] (or of the crash reporter), already filled for [package], as
/// a monorepo app gets it: its imports of the telemetry module, the database and the HTTP client go
/// to the shared packages' public libraries, once each, and `projectPackages` lists the packages.
/// The glue in `lib/_core/telemetry/` stays the app's own. A file that reaches only the web-safe
/// part of the module ([portableTelemetryFiles]) imports `package:telemetry/portable.dart`.
String monorepoAppFile(String text, {required String package}) {
  final directive = RegExp(
    "^((?:import|export) )'package:${RegExp.escape(package)}/_core/"
    "(telemetry|database|api_client)/([^']+)'",
  );
  bool isModule(RegExpMatch match) =>
      match.group(2) == 'telemetry' && telemetryModuleFiles.contains(match.group(3));
  final lines = text.split('\n');
  final vmModule = lines
      .map(directive.firstMatch)
      .any(
        (match) =>
            match != null && isModule(match) && !portableTelemetryFiles.contains(match.group(3)),
      );
  final written = <String>{};
  final out = <String>[];
  for (final line in lines) {
    final match = directive.firstMatch(line);
    final library = match == null
        ? null
        : switch (match.group(2)) {
            'telemetry' when !isModule(match) => null,
            'telemetry' => vmModule ? 'telemetry/telemetry.dart' : 'telemetry/portable.dart',
            'database' => 'database/database.dart',
            _ => 'api_client/api_client.dart',
          };
    if (match == null || library == null) {
      out.add(line);
      continue;
    }
    final rewritten = line.replaceRange(
      match.start,
      match.end,
      "${match.group(1)}'package:$library'",
    );
    // Two files of one package become the same import: it is written once.
    if (written.add(rewritten)) out.add(rewritten);
  }
  final shared = monorepoSharedPackages.map((name) => "'$name'").join(', ');
  return out
      .join('\n')
      .replaceAll("<String>{'$package', 'ui'}", "<String>{'$package', 'ui', $shared}");
}

/// The packages a package of [monorepoSharedPackages] gets besides those of its template pubspec,
/// newest versions: what its files import, and the generators of its drift database. The
/// telemetry module of a project with [crashReporter] `logOnly` has no Sentry.
List<String> sharedPackagePubAddArguments(
  String package, {
  CrashReporter crashReporter = CrashReporter.sentry,
}) => switch (package) {
  'telemetry' => <String>[
    'l',
    'path',
    'clock',
    'archive',
    'drift',
    'sqlite3',
    // `sentry_gateway.dart`, which a log-only project does not get.
    if (crashReporter != CrashReporter.logOnly) ...<String>['sentry', 'meta'],
    'dev:build_runner',
    'dev:drift_dev',
    // The timers of the module's tests.
    'dev:fake_async',
  ],
  'database' => const <String>['drift', 'drift_flutter', 'dev:build_runner', 'dev:drift_dev'],
  'api_client' => const <String>['http', 'l', 'meta', 'shared_preferences'],
  _ => throw ArgumentError.value(package, 'package', 'not a shared package'),
};

/// Where a monorepo keeps the crash reporter its apps are made with, relative to the monorepo:
/// "Add to project" gives a new app with the skeleton the same one.
const String crashReporterConfigPath = 'packages/telemetry/crash_reporter.yaml';

/// The text of [crashReporterConfigPath] for [reporter].
String crashReporterConfig(CrashReporter reporter) =>
    '''
# The crash reporter of this monorepo's apps (their lib/_core/telemetry/crash_reporter.dart).
# FAgent's "Add to project" gives a new app the same one. One of: ${CrashReporter.values.map((value) => value.name).join(', ')}.
reporter: ${reporter.name}
''';

/// The crash reporter that [text], the contents of [crashReporterConfigPath], names; `null` when
/// it names none.
CrashReporter? readCrashReporterConfig(String text) {
  final name = RegExp(r'^reporter:\s*(\S+)\s*$', multiLine: true).firstMatch(text)?.group(1);
  for (final reporter in CrashReporter.values) {
    if (reporter.name == name) return reporter;
  }
  return null;
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

/// The arguments of the one `flutter pub add` that installs the packages of the skeleton with
/// [crashReporter]. [uiPath] is where `packages/ui` is, relative to the package that depends on it.
///
/// With [sharedPackagesPath] (where a monorepo's `packages/` is, relative to the app) the app gets
/// [monorepoSharedPackages] by path instead of its own `lib/_core/` copies, and leaves the packages
/// only they import (the HTTP client, drift, the telemetry module's, Sentry) to them.
List<String> skeletonPubAddArgumentsFor({
  required String uiPath,
  String? sharedPackagesPath,
  CrashReporter crashReporter = CrashReporter.sentry,
}) {
  final shared = sharedPackagesPath != null;
  return <String>[
    // No versions: `pub add` takes the newest release that fits the SDK, at every creation.
    'l',
    if (!shared) 'http',
    'meta',
    'win32',
    'shared_preferences',
    'freezed_annotation',
    'intl',
    'collection',
    'async',
    if (!shared) 'path',
    'convert',
    'path_provider',
    'platform_info',
    'rxdart',
    'url_launcher',
    'window_manager',
    if (!shared) ...<String>[
      'drift',
      'drift_flutter',
      // The telemetry module (lib/_core/telemetry/): the clock of its timers, the log archive, and
      // the SQLite errors it tells apart.
      'clock',
      'archive',
      'sqlite3',
    ],
    // The crash reporter's own packages; in a monorepo Sentry is the telemetry package's.
    for (final package in crashReporterPubAddArguments(crashReporter))
      if (!shared || package != 'sentry') package,
    'web',
    'flutter_localizations@{sdk: flutter}',
    // Flutter 3.47 deprecated the SDK's Material and Cupertino: the template imports these.
    'material_ui',
    'cupertino_ui',
    'control@{git: {url: $controlGitUrl, ref: $controlGitRef}}',
    // The workspace member with the shared UI (`packages/ui`, listed under `workspace:`).
    'ui@{path: $uiPath}',
    if (shared)
      for (final package in monorepoSharedPackages) '$package@{path: $sharedPackagesPath/$package}',
    'dev:freezed',
    'dev:build_runner',
    if (!shared) ...<String>[
      'dev:drift_dev',
      // The timers of the telemetry module's tests.
      'dev:fake_async',
    ],
    'dev:flutter_launcher_icons',
    'dev:flutter_native_splash',
    'dev:integration_test@{sdk: flutter}',
  ];
}

/// [skeletonPubAddArgumentsFor] for a one-app project with Sentry, where `packages/ui` is inside
/// it.
final List<String> skeletonPubAddArguments = skeletonPubAddArgumentsFor(uiPath: 'packages/ui');
