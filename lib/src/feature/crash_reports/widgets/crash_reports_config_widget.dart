import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/crash_reports/controller/crash_reports_controller.dart';
import 'package:flutter_code_agent/src/feature/crash_reports/data/crash_reports_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// Gives the widgets below access to [CrashReportsConfigWidgetState].
class CrashReportsConfigInhWidget extends InheritedWidget {
  const CrashReportsConfigInhWidget({super.key, required this.state, required super.child});

  final CrashReportsConfigWidgetState state;

  static CrashReportsConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<CrashReportsConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'CrashReportsConfigInhWidget was not found in element tree');
    return (widget! as CrashReportsConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(CrashReportsConfigInhWidget oldWidget) => false;
}

/// {@template crash_reports_config_widget}
/// Owns the [CrashReportsController] and hands the user's switch from the window settings to it:
/// once at start (when the settings are loaded) and whenever the switch or the moment of consent
/// changes.
/// {@endtemplate}
class CrashReportsConfigWidget extends StatefulWidget {
  /// {@macro crash_reports_config_widget}
  const CrashReportsConfigWidget({required this.child, this.repository, super.key});

  /// The window.
  final Widget child;

  /// Replaces the repository over the app's telemetry; for tests.
  @visibleForTesting
  final ICrashReportsRepository? repository;

  @override
  State<CrashReportsConfigWidget> createState() => CrashReportsConfigWidgetState();
}

class CrashReportsConfigWidgetState extends State<CrashReportsConfigWidget> {
  late final CrashReportsController controller;
  late final AppSettingsController _settings;
  bool? _appliedEnabled;
  DateTime? _appliedSince;

  /// Asks where to save the log archive; `null` when the user cancels. Tests replace it, because
  /// the native dialog cannot be driven from a widget test.
  Future<String?> Function(String suggestedName) pickSavePath = (suggestedName) async =>
      (await getSaveLocation(suggestedName: suggestedName))?.path;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    controller = CrashReportsController(
      repository:
          widget.repository ??
          CrashReportsRepositoryImpl(
            runtime: dependencies.telemetryRuntime,
            configured: dependencies.sentryGateway.enabled,
          ),
    )..load();
    _settings = AppSettingsConfigInhWidget.of(context).controller..addListener(_applySettings);
    _applySettings();
  }

  @override
  void dispose() {
    _settings.removeListener(_applySettings);
    controller.dispose();
    super.dispose();
  }

  void _applySettings() {
    // Before the stored settings are read they are the defaults: the switch is not theirs to apply.
    if (_settings.state is AppSettings$InitialState ||
        _settings.state is AppSettings$InProgressState) {
      return;
    }
    final settings = _settings.settings;
    // On without a moment of consent cannot happen through the switch; never send everything then.
    final since = settings.crashReportsSince;
    final enabled = settings.crashReports && since != null;
    if (enabled == _appliedEnabled && since == _appliedSince) return;
    _appliedEnabled = enabled;
    _appliedSince = since;
    controller.apply(enabled: enabled, since: since);
  }

  @override
  Widget build(BuildContext context) =>
      CrashReportsConfigInhWidget(state: this, child: widget.child);
}
