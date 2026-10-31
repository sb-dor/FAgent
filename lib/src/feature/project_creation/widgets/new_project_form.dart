import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/controller/flutter_sdk_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/package_name.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/platform_chips.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template new_project_form}
/// What the New project dialog asks: the package name, the organization, the folder, the
/// platforms, the template and two switches, and below them the Flutter version with Cancel and
/// Create.
///
/// The name is checked as `flutter create` does; "Create" is on only when everything is fine: the
/// name, the organization, the folder (checked against the disk, the latest answer wins), the
/// platforms and a Flutter SDK. The organization and the template start as the Settings have them
/// (a git template starts as the architecture), but the form never changes the Settings.
/// {@endtemplate}
class NewProjectForm extends StatefulWidget {
  /// {@macro new_project_form}
  const NewProjectForm({super.key});

  @override
  State<NewProjectForm> createState() => _NewProjectFormState();
}

class _NewProjectFormState extends State<NewProjectForm> {
  late final WorkspaceConfigWidgetState _scope;
  late final FlutterSdkController _sdk;
  late final TextEditingController _name;
  late final TextEditingController _org;

  /// The folder `<parent>/<name>` goes into; `null` until the suggestion has arrived.
  String? _parent;
  Set<FlutterPlatform> _platforms = const <FlutterPlatform>{
    FlutterPlatform.ios,
    FlutterPlatform.android,
    FlutterPlatform.macos,
  };
  late NewProjectTemplate _template;
  bool _gitInit = true;
  bool _openChat = true;

  /// Number of the latest target check; an answer to an older one is dropped.
  int _checkNumber = 0;

  /// Whether [_targetProblem] answers for the current folder and name.
  bool _targetChecked = false;
  TargetProblem? _targetProblem;

  @override
  void initState() {
    super.initState();
    _scope = WorkspaceConfigInhWidget.of(context);
    final settings = _scope.settingsController.settings;
    _name = TextEditingController();
    _org = TextEditingController(text: settings.projectOrg);
    _template = settings.projectTemplate == NewProjectTemplate.git
        ? NewProjectTemplate.architecture
        : settings.projectTemplate;
    _sdk = FlutterSdkController(repository: Dependencies.of(context).flutterSdkRepository)
      ..addListener(_onSdk)
      ..load(null);
    _scope.projectCreation.defaultParent().then<void>((parent) {
      if (!mounted || _parent != null) return;
      setState(() => _parent = parent);
      _checkTarget();
    }).ignore();
  }

  @override
  void dispose() {
    _checkNumber++;
    _sdk
      ..removeListener(_onSdk)
      ..dispose();
    _name.dispose();
    _org.dispose();
    super.dispose();
  }

  void _onSdk() => setState(() {});

  FlutterSdk? get _sdkInfo => switch (_sdk.state) {
    FlutterSdk$CompletedState(:final sdk) => sdk,
    FlutterSdk$ErrorState(:final sdk) => sdk,
    _ => null,
  };

  PackageNameProblem? get _nameProblem => checkPackageName(_name.text);

  bool get _orgValid => AppSettings.orgPattern.hasMatch(_org.text);

  bool get _canCreate =>
      _nameProblem == null &&
      _orgValid &&
      _parent != null &&
      _targetChecked &&
      _targetProblem == null &&
      _platforms.isNotEmpty &&
      _sdkInfo?.path != null;

  /// Asks whether the folder can be created; the answer counts only if nothing changed meanwhile.
  void _checkTarget() {
    final number = ++_checkNumber;
    final parent = _parent;
    final name = _name.text;
    if (parent == null || checkPackageName(name) != null) {
      setState(() {
        _targetChecked = false;
        _targetProblem = null;
      });
      return;
    }
    setState(() {
      _targetChecked = false;
      _targetProblem = null;
    });
    _scope.projectCreation.checkTarget(parent, name).then<void>((problem) {
      if (!mounted || number != _checkNumber) return;
      setState(() {
        _targetChecked = true;
        _targetProblem = problem;
      });
    }).ignore();
  }

  Future<void> _pickFolder() async {
    final path = await _scope.pickNewProjectParent();
    if (path == null || !mounted) return;
    setState(() => _parent = path);
    _checkTarget();
  }

  void _toggle(FlutterPlatform platform) => setState(() {
    _platforms = _platforms.contains(platform)
        ? (<FlutterPlatform>{..._platforms}..remove(platform))
        : <FlutterPlatform>{..._platforms, platform};
  });

  void _chooseTemplate(NewProjectTemplate template) {
    if (template == NewProjectTemplate.git) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(Localization.of(context).comingInMilestone('M4'))));
      return;
    }
    setState(() => _template = template);
  }

  void _create() {
    final parent = _parent;
    if (!_canCreate || parent == null) return;
    _scope.projectCreation.start(
      NewProjectRequest(
        name: _name.text,
        org: _org.text,
        parent: parent,
        platforms: _platforms,
        template: _template,
        gitInit: _gitInit,
        openChat: _openChat,
      ),
    );
  }

  void _openFlutterSettings() {
    final data = _scope.dataController;
    Navigator.of(context).pop();
    data.openView(WorkspaceView.settings, section: 'flutter');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: _buildFields(context),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: _buildFooter(context),
          ),
        ),
      ],
    );
  }

  Widget _buildFields(BuildContext context) {
    final localization = Localization.of(context);
    const gap = SizedBox(height: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _nameField(context)),
            const SizedBox(width: 10),
            Expanded(child: _orgField(context)),
          ],
        ),
        gap,
        _folderField(context),
        gap,
        _Field(
          label: localization.newProjectPlatforms,
          messages: <Widget>[
            if (_platforms.isEmpty) _Message.error(localization.newProjectNoPlatform),
          ],
          child: PlatformChips(selected: _platforms, onToggle: _toggle),
        ),
        gap,
        _Field(
          label: localization.newProjectTemplate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TemplateCard(
                key: const ValueKey<String>('template-architecture'),
                title: localization.newProjectTemplateArchitecture,
                description: localization.newProjectTemplateArchitectureHint,
                selected: _template == NewProjectTemplate.architecture,
                onTap: () => _chooseTemplate(NewProjectTemplate.architecture),
              ),
              const SizedBox(height: 6),
              _TemplateCard(
                key: const ValueKey<String>('template-plain'),
                title: localization.newProjectTemplatePlain,
                description: localization.newProjectTemplatePlainHint,
                selected: _template == NewProjectTemplate.plain,
                onTap: () => _chooseTemplate(NewProjectTemplate.plain),
              ),
              const SizedBox(height: 6),
              _TemplateCard(
                key: const ValueKey<String>('template-git'),
                title: localization.newProjectTemplateGit,
                description: localization.newProjectTemplateGitHint,
                selected: false,
                preview: true,
                onTap: () => _chooseTemplate(NewProjectTemplate.git),
              ),
            ],
          ),
        ),
        gap,
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: <Widget>[
            _Switch(
              key: const ValueKey<String>('new-project-git'),
              label: localization.newProjectGitInit,
              value: _gitInit,
              onChanged: (value) => setState(() => _gitInit = value),
            ),
            _Switch(
              key: const ValueKey<String>('new-project-chat'),
              label: localization.newProjectOpenChat,
              value: _openChat,
              onChanged: (value) => setState(() => _openChat = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameField(BuildContext context) {
    final localization = Localization.of(context);
    final problem = _nameProblem;
    final messages = <Widget>[];
    switch (problem) {
      case PackageNameProblem.invalid:
        messages.add(_Message.error(localization.newProjectNameInvalid));
        final suggestion = suggestPackageName(_name.text);
        if (suggestion != null) {
          messages.add(_Message.error(localization.newProjectNameTry(suggestion)));
        }
      case PackageNameProblem.keyword:
        messages.add(_Message.error(localization.newProjectNameKeyword));
      case PackageNameProblem.dependency:
        messages.add(_Message.error(localization.newProjectNameDependency));
      case PackageNameProblem.empty || null:
        break;
    }
    final bad = problem != null && problem != PackageNameProblem.empty;
    return _Field(
      label: localization.newProjectName,
      messages: bad ? messages : <Widget>[_Message.hint(localization.newProjectNameHint)],
      child: _TextInput(
        fieldKey: const ValueKey<String>('new-project-name'),
        controller: _name,
        autofocus: true,
        error: bad,
        onChanged: (_) {
          setState(() {});
          _checkTarget();
        },
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _orgField(BuildContext context) {
    final localization = Localization.of(context);
    return _Field(
      label: localization.newProjectOrg,
      messages: <Widget>[
        if (_orgValid)
          _Message.hint(localization.newProjectOrgHint)
        else
          _Message.error(localization.flutterOrgInvalid),
      ],
      child: _TextInput(
        fieldKey: const ValueKey<String>('new-project-org'),
        controller: _org,
        error: !_orgValid,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _folderField(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final parent = _parent ?? '';
    final path = parent.endsWith('/') ? parent : '$parent/';
    final full = '$path${_name.text}';
    final problem = _targetChecked ? _targetProblem : null;
    return _Field(
      label: localization.newProjectFolder,
      messages: <Widget>[
        if (problem != null)
          _Message.error(switch (problem) {
            TargetProblem.exists => localization.newProjectFolderExists,
            TargetProblem.parentMissing => localization.newProjectParentMissing,
          }),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: problem == null ? colors.border : colors.danger),
          borderRadius: BorderRadius.circular(AppRadius.medium - 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Tooltip(
                  message: full,
                  child: Text(
                    full,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(context).copyWith(color: colors.text),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CompactButton(
                key: const ValueKey<String>('new-project-pick'),
                label: localization.newProjectChoose,
                onPressed: _pickFolder,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final state = _sdk.state;
    final sdk = _sdkInfo;
    final Widget info;
    if (sdk == null) {
      info = state is FlutterSdk$ErrorState
          ? Text(
              localization.flutterSdkLoadFailed,
              style: textTheme.bodySmall!.copyWith(color: colors.danger),
            )
          : const SizedBox.shrink();
    } else if (sdk.path == null) {
      info = Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            localization.flutterSdkNotFound,
            style: textTheme.bodySmall!.copyWith(color: colors.danger),
          ),
          InkWell(
            key: const ValueKey<String>('new-project-sdk-settings'),
            borderRadius: BorderRadius.circular(AppRadius.small),
            onTap: _openFlutterSettings,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                localization.newProjectSdkSettings,
                style: textTheme.bodySmall!.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      );
    } else {
      final version = sdk.version;
      final fvm = sdk.fvmVersion == null ? '' : ' · fvm';
      info = Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            '${version == null ? 'Flutter' : localization.newProjectSdkVersion(version)}$fvm',
            style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
          ),
          if (sdk.isPreview) const PreviewBadge(),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: info),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey<String>('new-project-cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.text,
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium - 2),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey<String>('new-project-create'),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium - 2),
            ),
          ),
          onPressed: _canCreate ? _create : null,
          child: Text(localization.newProjectCreate),
        ),
      ],
    );
  }
}

/// A label over a control with the hint or the errors under it.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.messages = const <Widget>[]});

  final String label;
  final Widget child;
  final List<Widget> messages;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: context.colors.muted, fontWeight: FontWeight.w600),
        ),
      ),
      child,
      for (final message in messages)
        Padding(padding: const EdgeInsets.only(top: 4), child: message),
    ],
  );
}

/// A line under a field: a muted hint or a red error.
class _Message extends StatelessWidget {
  const _Message.hint(this.text) : error = false;

  const _Message.error(this.text) : error = true;

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall!
        .copyWith(fontSize: 11, color: error ? context.colors.danger : context.colors.muted),
  );
}

/// A single-line monospace field with the border of the dialog.
class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.fieldKey,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.error,
    this.autofocus = false,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool error;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium - 2),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      style: AppText.mono(context, size: 13).copyWith(color: colors.text),
      cursorColor: colors.accent,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: border(error ? colors.danger : colors.border),
        focusedBorder: border(error ? colors.danger : colors.accent),
      ),
    );
  }
}

/// One of the template radio cards.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.preview = false,
    super.key,
  });

  final String title;
  final String description;
  final bool selected;
  final bool preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.medium);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? colors.accentSoft : colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected ? colors.accent : colors.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: textTheme.bodyMedium!.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(description, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
                    ],
                  ),
                ),
                if (preview) ...<Widget>[const SizedBox(width: 8), const PreviewBadge()],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A checkbox with a label.
class _Switch extends StatelessWidget {
  const _Switch({required this.label, required this.value, required this.onChanged, super.key});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => onChanged(value ?? false),
            ),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
