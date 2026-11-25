import 'package:control/control.dart';
import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/localization/error_text.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/crash_reports/controller/crash_reports_controller.dart';
import 'package:flutter_code_agent/crash_reports/widgets/crash_reports_config_widget.dart';
import 'package:material_ui/material_ui.dart';

/// {@template crash_reports_settings_section}
/// The "Crash reports" section of Settings: the switch, what was recorded and sent, the last
/// errors and "Save log archive…".
/// {@endtemplate}
class CrashReportsSettingsSection extends StatelessWidget {
  /// {@macro crash_reports_settings_section}
  const CrashReportsSettingsSection({super.key});

  static const String _archiveName = 'flutter-code-agent-log.zip';

  @override
  Widget build(BuildContext context) {
    final scope = CrashReportsConfigInhWidget.of(context);
    final controller = scope.controller;
    final settings = AppSettingsConfigInhWidget.of(context).controller;
    return StateConsumer<CrashReportsController, CrashReportsState>(
      controller: controller,
      listener: (context, controller, previous, current) {
        final localization = Localization.of(context);
        final message = switch (current) {
          // A load that failed is shown in the section itself.
          CrashReports$ErrorState(:final error, :final data) when data.loadError == null =>
            errorText(localization, error),
          CrashReports$SuccessfulState(:final data) when data.archiveSaved =>
            localization.crashReportsArchiveSaved,
          _ => null,
        };
        if (message == null) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state, _) {
        final localization = Localization.of(context);
        final textTheme = Theme.of(context).textTheme;
        final colors = context.colors;
        final data = state.data;
        final configured = controller.reporterConfigured;
        return ListenableBuilder(
          listenable: settings,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SettingsCard(
                children: <Widget>[
                  SettingsRow(
                    label: localization.crashReportsSwitch,
                    hint: configured
                        ? localization.crashReportsNote
                        : localization.crashReportsNotConfigured,
                    control: Switch(
                      key: const ValueKey('crash-reports-switch'),
                      value: configured && settings.settings.crashReports,
                      onChanged: configured ? settings.setCrashReports : null,
                    ),
                  ),
                  SettingsRow(
                    label: localization.crashReportsRecorded(data.recorded),
                    hint: data.status.lastSentAt == null
                        ? localization.crashReportsNeverSent
                        : localization.crashReportsLastSent(
                            _time(context, data.status.lastSentAt!),
                          ),
                    control: OutlinedButton(
                      key: const ValueKey('crash-reports-archive'),
                      onPressed: state is CrashReports$ProcessingState ? null : () => _save(scope),
                      child: Text(localization.crashReportsSaveArchive),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(localization.crashReportsRecent, style: textTheme.titleSmall),
              const SizedBox(height: 8),
              if (data.loadError != null)
                Text(
                  errorText(localization, data.loadError),
                  style: textTheme.bodySmall!.copyWith(color: colors.danger),
                )
              else if (data.recent.isEmpty)
                Text(
                  localization.crashReportsNone,
                  style: textTheme.bodySmall!.copyWith(color: colors.muted),
                )
              else
                SettingsCard(
                  children: <Widget>[for (final entry in data.recent) _EntryRow(entry: entry)],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(CrashReportsConfigWidgetState scope) async {
    final path = await scope.pickSavePath(_archiveName);
    if (path != null) scope.controller.saveArchive(path);
  }

  static String _time(BuildContext context, DateTime time) {
    final local = time.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final OutboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = context.colors;
    final time = CrashReportsSettingsSection._time(context, entry.lastAt);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            localization.crashReportsEntry(entry.type, entry.message, entry.count),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall!.copyWith(color: colors.text),
          ),
          Text(time, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
        ],
      ),
    );
  }
}
