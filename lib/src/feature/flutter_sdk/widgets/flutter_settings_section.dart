import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/segmented_control.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/controller/flutter_sdk_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/widgets/flutter_sdk_config_widget.dart';

/// {@template flutter_settings_section}
/// The "Flutter" section of Settings: the SDK and the version the project pins with fvm, the
/// `flutter doctor` report with a button that hands a finding to an agent, what a new project
/// starts from, and where DevTools opens.
///
/// The Flutter version, the doctor report, the `git` template and in-app DevTools are previews
/// (milestones M4 and M2) and say so.
/// {@endtemplate}
class FlutterSettingsSection extends StatelessWidget {
  /// {@macro flutter_settings_section}
  const FlutterSettingsSection({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _SdkGroup(),
      SizedBox(height: 24),
      _DoctorGroup(),
      SizedBox(height: 24),
      _NewProjectGroup(),
      SizedBox(height: 24),
      _DevToolsGroup(),
    ],
  );
}

/// A small heading over a card.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: context.colors.text, fontWeight: FontWeight.w600),
        ),
      ),
      child,
    ],
  );
}

/// The SDK card: its path, its version and what the selected project uses.
class _SdkGroup extends StatelessWidget {
  const _SdkGroup();

  @override
  Widget build(BuildContext context) {
    final scope = FlutterSdkConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.sdk, scope.projectListenable]),
      builder: (context, _) => _build(context, scope),
    );
  }

  Widget _build(BuildContext context, FlutterSdkConfigWidgetState scope) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final state = scope.sdk.state;
    final sdk = switch (state) {
      FlutterSdk$CompletedState(:final sdk) => sdk,
      FlutterSdk$ErrorState(:final sdk) => sdk,
      _ => null,
    };
    final project = scope.project;
    return _Group(
      title: localization.flutterSdkTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (state is FlutterSdk$ErrorState) ...<Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  localization.flutterSdkLoadFailed,
                  style: textTheme.bodySmall!.copyWith(color: colors.danger),
                ),
                CompactButton(label: localization.retry, onPressed: scope.retry),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (sdk == null && state is! FlutterSdk$ErrorState)
            Text(
              localization.flutterSdkLoading,
              style: textTheme.bodySmall!.copyWith(color: colors.muted),
            )
          else if (sdk != null)
            SettingsCard(
              children: <Widget>[
                _pathRow(context, sdk),
                SettingsRow(
                  label: localization.flutterSdkVersion,
                  control: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _versionOf(sdk),
                        style: textTheme.bodyMedium!.copyWith(color: colors.text),
                      ),
                      if (sdk.isPreview) ...<Widget>[
                        const SizedBox(width: 8),
                        const PreviewBadge(),
                      ],
                    ],
                  ),
                ),
                if (project != null)
                  SettingsRow(
                    label: localization.flutterSdkProject,
                    hint: project.name,
                    control: Text(
                      sdk.fvmVersion == null
                          ? localization.flutterSdkSystem
                          : localization.flutterSdkFvm(sdk.fvmVersion!),
                      key: const ValueKey<String>('flutter-project-sdk'),
                      style: textTheme.bodyMedium!.copyWith(color: colors.text),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _versionOf(FlutterSdk sdk) {
    final version = sdk.version;
    if (version == null) return '—';
    final channel = sdk.channel;
    return channel == null ? version : '$version · $channel';
  }

  Widget _pathRow(BuildContext context, FlutterSdk sdk) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final path = sdk.path;
    if (path == null) {
      return SettingsRow(
        label: localization.flutterSdkPath,
        hint: localization.flutterSdkNotFoundHint,
        control: Text(
          localization.flutterSdkNotFound,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.danger),
        ),
      );
    }
    return SettingsRow(
      label: localization.flutterSdkPath,
      control: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Tooltip(
          message: path,
          child: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.mono(context, size: 12).copyWith(color: colors.text),
          ),
        ),
      ),
    );
  }
}

/// The doctor card: the button that runs `flutter doctor` and the report.
class _DoctorGroup extends StatelessWidget {
  const _DoctorGroup();

  @override
  Widget build(BuildContext context) {
    final scope = FlutterSdkConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.sdk, scope.projectListenable]),
      builder: (context, _) => _build(context, scope),
    );
  }

  Widget _build(BuildContext context, FlutterSdkConfigWidgetState scope) {
    final localization = Localization.of(context);
    final (ready, running, checks) = switch (scope.sdk.state) {
      FlutterSdk$CompletedState(:final checks, :final doctorRunning) => (
        true,
        doctorRunning,
        checks,
      ),
      FlutterSdk$ErrorState(:final checks) => (false, false, checks),
      _ => (false, false, null),
    };
    return _Group(
      title: localization.flutterDoctorTitle,
      child: SettingsCard(
        children: <Widget>[
          SettingsRow(
            label: localization.flutterDoctorHint,
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const PreviewBadge(),
                const SizedBox(width: 8),
                CompactButton(
                  key: const ValueKey<String>('flutter-doctor-run'),
                  label: running
                      ? localization.flutterDoctorRunning
                      : localization.flutterDoctorRun,
                  icon: Icons.medical_services_outlined,
                  onPressed: ready && !running ? scope.runDoctor : null,
                ),
              ],
            ),
          ),
          if (checks != null)
            for (final check in checks) _CheckRow(check: check),
        ],
      ),
    );
  }
}

/// One finding of `flutter doctor`; a finding that is not fine can be handed to an agent.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final DoctorCheck check;

  @override
  Widget build(BuildContext context) {
    final scope = FlutterSdkConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = switch (check.status) {
      DoctorStatus.ok => (Icons.check_circle_outline, colors.ok),
      DoctorStatus.warning => (Icons.warning_amber_rounded, colors.warn),
      DoctorStatus.error => (Icons.error_outline, colors.danger),
    };
    final detail = check.detail;
    final canFix = scope.project != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(check.title, style: textTheme.bodyMedium!.copyWith(color: colors.text)),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
                  ),
              ],
            ),
          ),
          if (check.status != DoctorStatus.ok) ...<Widget>[
            const SizedBox(width: 12),
            Tooltip(
              message: canFix ? '' : localization.flutterDoctorNeedsProject,
              child: CompactButton(
                key: ValueKey<String>('flutter-doctor-fix-${check.title}'),
                label: localization.flutterDoctorFix,
                icon: Icons.auto_fix_high,
                onPressed: canFix ? () => scope.fixWithAgent(check) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The new-project card: the org and the template.
class _NewProjectGroup extends StatelessWidget {
  const _NewProjectGroup();

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final scope = FlutterSdkConfigInhWidget.of(context);
    final settings = AppSettingsConfigInhWidget.of(context).controller;
    return _Group(
      title: localization.flutterNewProjectTitle,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SettingsCard(
          children: <Widget>[
            SettingsRow(
              label: localization.flutterOrg,
              hint: localization.flutterOrgHint,
              control: const _OrgField(),
            ),
            SettingsRow(
              label: localization.flutterTemplate,
              hint: localization.flutterTemplateHint,
              stacked: true,
              control: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SegmentedControl<NewProjectTemplate>(
                    segments: <(NewProjectTemplate, String)>[
                      (NewProjectTemplate.architecture, localization.flutterTemplateArchitecture),
                      (NewProjectTemplate.plain, localization.flutterTemplatePlain),
                      (NewProjectTemplate.git, localization.flutterTemplateGit),
                    ],
                    selected: settings.settings.projectTemplate,
                    onChanged: (template) {
                      if (template == NewProjectTemplate.git) {
                        scope.showComingSoon('M4');
                        return;
                      }
                      settings.update((s) => s.copyWith(projectTemplate: template));
                    },
                  ),
                  const PreviewBadge(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The org of new projects. Every valid value is saved as it is typed; an invalid one is not saved
/// and the field says what is expected.
class _OrgField extends StatefulWidget {
  const _OrgField();

  @override
  State<_OrgField> createState() => _OrgFieldState();
}

class _OrgFieldState extends State<_OrgField> {
  late final TextEditingController _controller;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: AppSettingsConfigInhWidget.of(context).controller.settings.projectOrg,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final valid = AppSettings.orgPattern.hasMatch(value);
    if (valid) {
      final controller = AppSettingsConfigInhWidget.of(context).controller;
      if (controller.settings.projectOrg != value) {
        controller.update((s) => s.copyWith(projectOrg: value));
      }
    }
    if (_invalid == valid) setState(() => _invalid = !valid);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    return SizedBox(
      width: 220,
      child: TextField(
        key: const ValueKey<String>('flutter-org'),
        controller: _controller,
        style: AppText.mono(context, size: 13).copyWith(color: colors.text),
        cursorColor: colors.accent,
        onChanged: _onChanged,
        decoration: InputDecoration(
          isDense: true,
          errorText: _invalid ? Localization.of(context).flutterOrgInvalid : null,
          errorMaxLines: 2,
          enabledBorder: border(colors.border),
          focusedBorder: border(colors.accent),
          errorBorder: border(colors.danger),
          focusedErrorBorder: border(colors.danger),
        ),
      ),
    );
  }
}

/// The DevTools card: where DevTools opens.
class _DevToolsGroup extends StatelessWidget {
  const _DevToolsGroup();

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final scope = FlutterSdkConfigInhWidget.of(context);
    final settings = AppSettingsConfigInhWidget.of(context).controller;
    return _Group(
      title: localization.flutterDevToolsTitle,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SettingsCard(
          children: <Widget>[
            SettingsRow(
              label: localization.flutterDevToolsOpen,
              control: SegmentedControl<DevToolsTarget>(
                segments: <(DevToolsTarget, String)>[
                  (DevToolsTarget.browser, localization.flutterDevToolsBrowser),
                  (DevToolsTarget.app, localization.flutterDevToolsApp),
                ],
                selected: settings.settings.devToolsTarget,
                onChanged: (target) {
                  if (target == DevToolsTarget.app) {
                    scope.showComingSoon('M2');
                    return;
                  }
                  settings.update((s) => s.copyWith(devToolsTarget: target));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
