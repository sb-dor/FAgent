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
import 'package:flutter_code_agent/src/feature/project_creation/data/application_id.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/package_name.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_fields.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/option_chip.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/platform_chips.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:l/l.dart';

/// {@template new_project_form}
/// What the New project dialog asks: the project type, the package name, the application ID (the
/// organization for a type other than an app), the folder, the platforms, the template, the crash reporter and two switches, and below them the
/// Flutter version with Cancel and Create.
///
/// The type comes first, as in `flutter create --template`: the platforms show only for an app and
/// a plugin, the template only for an app, and the crash reporter only for "My architecture".
///
/// The name is checked as `flutter create` does; "Create" is on only when everything is fine: the
/// name, the application ID or organization, the folder (checked against the disk, the latest
/// answer wins), the platforms and a Flutter SDK. The application ID is shown whole
/// (`<org>.<name>`) and follows the name until it is typed; then it is the user's, every segment
/// of it. The organization and the template start as the Settings have them
/// (a git template starts as the architecture), but the form never changes the Settings. "My
/// architecture" needs Flutter [kArchitectureMinFlutter]: on an older or unknown SDK it is off and
/// the empty template is made.
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
  late final TextEditingController _applicationId;
  late final TextEditingController _appFolder;
  late final TextEditingController _appPackage;

  /// Whether the app package was typed: until then it follows `<name>_<folder>`.
  bool _appPackageEdited = false;

  /// Whether the application ID was typed: until then it follows `<org>.<name>`.
  bool _applicationIdEdited = false;

  /// The folder `<parent>/<name>` goes into; `null` until the suggestion has arrived.
  String? _parent;
  Set<FlutterPlatform> _platforms = const <FlutterPlatform>{
    FlutterPlatform.ios,
    FlutterPlatform.android,
    FlutterPlatform.macos,
  };
  FlutterProjectType _type = FlutterProjectType.app;
  ProjectStructure _structure = ProjectStructure.single;
  late NewProjectTemplate _template;
  CrashReporter _crashReporter = CrashReporter.sentry;
  bool _gitInit = true;
  bool _openChat = true;

  /// Number of the latest target check; an answer to an older one is dropped.
  int _checkNumber = 0;

  /// Whether [_targetProblem] answers for the current folder and name.
  bool _targetChecked = false;
  TargetProblem? _targetProblem;

  /// Whether the folder could not be checked (or no default folder could be found).
  bool _folderFailed = false;

  /// Whether the git template was tapped: it is not available yet, so the form says so inline.
  bool _gitHint = false;

  @override
  void initState() {
    super.initState();
    _scope = WorkspaceConfigInhWidget.of(context);
    final settings = _scope.settingsController.settings;
    _name = TextEditingController();
    _org = TextEditingController(text: settings.projectOrg);
    _applicationId = TextEditingController(text: '${settings.projectOrg}.');
    _appFolder = TextEditingController(text: 'app');
    _appPackage = TextEditingController();
    _template = settings.projectTemplate == NewProjectTemplate.git
        ? NewProjectTemplate.architecture
        : settings.projectTemplate;
    _sdk = FlutterSdkController(repository: Dependencies.of(context).flutterSdkRepository)
      ..addListener(_onSdk)
      ..load(null);
    _scope.projectCreation.defaultParent().then<void>(
      (parent) {
        if (!mounted || _parent != null) return;
        setState(() => _parent = parent);
        _checkTarget();
      },
      onError: (Object error, StackTrace stackTrace) {
        l.w('New project | default folder | $error', stackTrace);
        if (!mounted || _parent != null) return;
        setState(() => _folderFailed = true);
      },
    );
  }

  @override
  void dispose() {
    _checkNumber++;
    _sdk
      ..removeListener(_onSdk)
      ..dispose();
    _name.dispose();
    _org.dispose();
    _applicationId.dispose();
    _appFolder.dispose();
    _appPackage.dispose();
    super.dispose();
  }

  void _onSdk() => setState(() {});

  FlutterSdk? get _sdkInfo => switch (_sdk.state) {
    FlutterSdk$CompletedState(:final sdk) => sdk,
    FlutterSdk$ErrorState(:final sdk) => sdk,
    _ => null,
  };

  PackageNameProblem? get _nameProblem => checkPackageName(_name.text);

  bool get _monorepoSupported => supportsMonorepo(_sdkInfo?.dartVersion);

  /// Whether the SDK lookup has finished, found or not.
  bool get _sdkLoaded =>
      _sdk.state is! FlutterSdk$InitialState && _sdk.state is! FlutterSdk$InProgressState;

  /// Whether "My architecture" is off: the lookup finished with an older or unknown Flutter.
  /// Until then the card shows the chosen template as it is.
  bool get _architectureOff => _sdkLoaded && !supportsArchitecture(_sdkInfo?.version);

  /// The template the project is made from: "My architecture" falls back to the empty one on an
  /// SDK that cannot make it.
  NewProjectTemplate get _templateUsed =>
      _template == NewProjectTemplate.architecture && _architectureOff
      ? NewProjectTemplate.plain
      : _template;

  /// Whether the project is made as a workspace: only an app, and only on an SDK that can.
  bool get _monorepo =>
      _type == FlutterProjectType.app &&
      _structure == ProjectStructure.monorepo &&
      _monorepoSupported;

  static final RegExp _folderPattern = RegExp(r'^[a-z][a-z0-9_]*$');

  bool get _appFolderValid => _folderPattern.hasMatch(_appFolder.text);

  PackageNameProblem? get _appPackageProblem => checkPackageName(_appPackage.text);

  /// Whether the app package takes a name the monorepo already has: `ui` (`packages/ui`) or the
  /// root's `<name>_workspace`. Two packages of one workspace with one name break `pub get`.
  bool get _appPackageTaken =>
      _appPackage.text == 'ui' || _appPackage.text == '${_name.text}_workspace';

  /// Keeps the app package at `<name>_<folder>` until it is typed.
  void _followAppPackage() {
    if (_appPackageEdited) return;
    _appPackage.text = '${_name.text}_${_appFolder.text}';
  }

  bool get _orgValid => AppSettings.orgPattern.hasMatch(_org.text);

  bool get _applicationIdValid => applicationIdPattern.hasMatch(_applicationId.text);

  /// Whether the project is an app: an app gets the whole application ID, any other type the org.
  bool get _isApp => _type == FlutterProjectType.app;

  /// Keeps the application ID at `<org>.<name>` until it is typed.
  void _followApplicationId() {
    if (_applicationIdEdited) return;
    _applicationId.text = '${_org.text}.${_name.text}';
  }

  bool get _canCreate =>
      _nameProblem == null &&
      (_isApp ? _applicationIdValid : _orgValid) &&
      (!_monorepo || (_appFolderValid && _appPackageProblem == null && !_appPackageTaken)) &&
      _parent != null &&
      _targetChecked &&
      _targetProblem == null &&
      !_folderFailed &&
      (!_type.hasPlatforms || _platforms.isNotEmpty) &&
      _sdkInfo?.path != null;

  /// Asks whether the folder can be created; the answer counts only if nothing changed meanwhile.
  void _checkTarget() {
    final number = ++_checkNumber;
    final parent = _parent;
    final name = _name.text;
    setState(() {
      _targetChecked = false;
      _targetProblem = null;
      _folderFailed = false;
    });
    if (parent == null || checkPackageName(name) != null) return;
    _scope.projectCreation
        .checkTarget(parent, name)
        .then<void>(
          (problem) {
            if (!mounted || number != _checkNumber) return;
            setState(() {
              _targetChecked = true;
              _targetProblem = problem;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            l.w('New project | check folder | $error', stackTrace);
            if (!mounted || number != _checkNumber) return;
            setState(() {
              _targetChecked = true;
              _folderFailed = true;
            });
          },
        );
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
    // A SnackBar would show under the dialog's barrier, so the hint is inline.
    setState(() {
      _gitHint = template == NewProjectTemplate.git;
      if (!_gitHint) _template = template;
    });
  }

  void _create() {
    final parent = _parent;
    if (!_canCreate || parent == null) return;
    _scope.projectCreation.start(
      NewProjectRequest(
        name: _name.text,
        org: _isApp ? applicationIdOrg(_applicationId.text) : _org.text,
        applicationId: _isApp ? _applicationId.text : null,
        parent: parent,
        platforms: _platforms,
        type: _type,
        template: _templateUsed,
        gitInit: _gitInit,
        openChat: _openChat,
        structure: _monorepo ? ProjectStructure.monorepo : ProjectStructure.single,
        appFolder: _appFolder.text,
        appPackage: _monorepo ? _appPackage.text : null,
        crashReporter: _crashReporter,
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
        _typeField(context),
        if (_type == FlutterProjectType.app) ...<Widget>[gap, _structureField(context)],
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _nameField(context)),
            const SizedBox(width: 10),
            Expanded(child: _isApp ? _applicationIdField(context) : _orgField(context)),
          ],
        ),
        if (_monorepo) ...<Widget>[
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _appFolderField(context)),
              const SizedBox(width: 10),
              Expanded(child: _appPackageField(context)),
            ],
          ),
        ],
        gap,
        _folderField(context),
        if (_type.hasPlatforms) ...<Widget>[
          gap,
          CreationField(
            label: localization.newProjectPlatforms,
            messages: <Widget>[
              if (_platforms.isEmpty) CreationMessage.error(localization.newProjectNoPlatform),
            ],
            child: PlatformChips(selected: _platforms, onToggle: _toggle),
          ),
        ],
        if (_type == FlutterProjectType.app) ...<Widget>[
          gap,
          CreationField(
            label: localization.newProjectTemplate,
            messages: <Widget>[
              if (_architectureOff)
                CreationMessage.hint(
                  localization.newProjectTemplateArchitectureNeedsFlutter(kArchitectureMinFlutter),
                ),
              if (_gitHint) CreationMessage.hint(localization.comingLater),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CreationTemplateCard(
                  key: const ValueKey<String>('template-architecture'),
                  title: localization.newProjectTemplateArchitecture,
                  description: localization.newProjectTemplateArchitectureHint,
                  selected: _templateUsed == NewProjectTemplate.architecture,
                  enabled: !_architectureOff,
                  onTap: () {
                    // Until the SDK is known the choice could not be kept.
                    if (_sdkLoaded) _chooseTemplate(NewProjectTemplate.architecture);
                  },
                ),
                const SizedBox(height: 6),
                CreationTemplateCard(
                  key: const ValueKey<String>('template-plain'),
                  title: localization.newProjectTemplatePlain,
                  description: localization.newProjectTemplatePlainHint,
                  selected: _templateUsed == NewProjectTemplate.plain,
                  onTap: () => _chooseTemplate(NewProjectTemplate.plain),
                ),
                const SizedBox(height: 6),
                CreationTemplateCard(
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
          if (_templateUsed == NewProjectTemplate.architecture) ...<Widget>[
            gap,
            _crashReporterField(context),
          ],
        ],
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

  Widget _typeField(BuildContext context) {
    final localization = Localization.of(context);
    return CreationField(
      label: localization.newProjectType,
      messages: <Widget>[
        CreationMessage.hint(switch (_type) {
          FlutterProjectType.app => localization.newProjectTypeAppHint,
          FlutterProjectType.package => localization.newProjectTypePackageHint,
          FlutterProjectType.plugin => localization.newProjectTypePluginHint,
          FlutterProjectType.packageFfi => localization.newProjectTypePackageFfiHint,
          FlutterProjectType.module => localization.newProjectTypeModuleHint,
        }),
      ],
      child: Wrap(
        key: const ValueKey<String>('new-project-type'),
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final (type, label) in <(FlutterProjectType, String)>[
            (FlutterProjectType.app, localization.newProjectTypeApp),
            (FlutterProjectType.package, localization.newProjectTypePackage),
            (FlutterProjectType.plugin, localization.newProjectTypePlugin),
            (FlutterProjectType.packageFfi, localization.newProjectTypePackageFfi),
            (FlutterProjectType.module, localization.newProjectTypeModule),
          ])
            OptionChip(
              key: ValueKey<String>('type-${type.name}'),
              label: label,
              selected: type == _type,
              exclusive: true,
              onTap: () => setState(() {
                _type = type;
                _gitHint = false;
              }),
            ),
        ],
      ),
    );
  }

  Widget _structureField(BuildContext context) {
    final localization = Localization.of(context);
    final needsDart = _sdkInfo != null && !_monorepoSupported;
    return CreationField(
      label: localization.newProjectStructure,
      messages: <Widget>[
        CreationMessage.hint(
          needsDart
              ? localization.newProjectStructureMonorepoNeedsDart(kMonorepoMinDart)
              : _monorepo
              ? localization.newProjectStructureMonorepoHint
              : localization.newProjectStructureSingleHint,
        ),
      ],
      child: Wrap(
        key: const ValueKey<String>('new-project-structure'),
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          OptionChip(
            key: const ValueKey<String>('structure-single'),
            label: localization.newProjectStructureSingle,
            selected: !_monorepo,
            exclusive: true,
            onTap: () => setState(() => _structure = ProjectStructure.single),
          ),
          OptionChip(
            key: const ValueKey<String>('structure-monorepo'),
            label: localization.newProjectStructureMonorepo,
            selected: _monorepo,
            exclusive: true,
            enabled: _monorepoSupported,
            onTap: () => setState(() => _structure = ProjectStructure.monorepo),
          ),
        ],
      ),
    );
  }

  Widget _crashReporterField(BuildContext context) {
    final localization = Localization.of(context);
    return CreationField(
      label: localization.newProjectCrashReporter,
      child: Wrap(
        key: const ValueKey<String>('new-project-crash-reporter'),
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final (reporter, label) in <(CrashReporter, String)>[
            (CrashReporter.sentry, localization.newProjectCrashReporterSentry),
            (CrashReporter.crashlytics, localization.newProjectCrashReporterCrashlytics),
            (CrashReporter.logOnly, localization.newProjectCrashReporterLogOnly),
          ])
            OptionChip(
              key: ValueKey<String>('crash-reporter-${reporter.name}'),
              label: label,
              selected: reporter == _crashReporter,
              exclusive: true,
              onTap: () => setState(() => _crashReporter = reporter),
            ),
        ],
      ),
    );
  }

  Widget _appFolderField(BuildContext context) {
    final localization = Localization.of(context);
    return CreationField(
      label: localization.newProjectAppFolder,
      messages: <Widget>[
        if (!_appFolderValid) CreationMessage.error(localization.newProjectNameInvalid),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('new-project-app-folder'),
        controller: _appFolder,
        error: !_appFolderValid,
        onChanged: (_) => setState(_followAppPackage),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _appPackageField(BuildContext context) {
    final localization = Localization.of(context);
    final problem = _appPackageProblem;
    return CreationField(
      label: localization.newProjectAppPackage,
      messages: <Widget>[
        if (problem != null)
          CreationMessage.error(switch (problem) {
            PackageNameProblem.keyword => localization.newProjectNameKeyword,
            PackageNameProblem.dependency => localization.newProjectNameDependency,
            PackageNameProblem.invalid ||
            PackageNameProblem.empty => localization.newProjectNameInvalid,
          })
        else if (_appPackageTaken)
          CreationMessage.error(localization.newProjectAppPackageTaken),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('new-project-app-package'),
        controller: _appPackage,
        error: problem != null || _appPackageTaken,
        onChanged: (_) => setState(() => _appPackageEdited = true),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _nameField(BuildContext context) {
    final localization = Localization.of(context);
    final problem = _nameProblem;
    final messages = <Widget>[];
    switch (problem) {
      case PackageNameProblem.invalid:
        messages.add(CreationMessage.error(localization.newProjectNameInvalid));
        final suggestion = suggestPackageName(_name.text);
        if (suggestion != null) {
          messages.add(CreationMessage.error(localization.newProjectNameTry(suggestion)));
        }
      case PackageNameProblem.keyword:
        messages.add(CreationMessage.error(localization.newProjectNameKeyword));
      case PackageNameProblem.dependency:
        messages.add(CreationMessage.error(localization.newProjectNameDependency));
      case PackageNameProblem.empty || null:
        break;
    }
    final bad = problem != null && problem != PackageNameProblem.empty;
    return CreationField(
      label: localization.newProjectName,
      messages: bad ? messages : <Widget>[CreationMessage.hint(localization.newProjectNameHint)],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('new-project-name'),
        controller: _name,
        autofocus: true,
        error: bad,
        onChanged: (_) {
          setState(() {
            _followAppPackage();
            _followApplicationId();
          });
          _checkTarget();
        },
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _orgField(BuildContext context) {
    final localization = Localization.of(context);
    return CreationField(
      label: localization.newProjectOrg,
      messages: <Widget>[
        if (_orgValid)
          CreationMessage.hint(localization.newProjectOrgHint)
        else
          CreationMessage.error(localization.flutterOrgInvalid),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('new-project-org'),
        controller: _org,
        error: !_orgValid,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _applicationIdField(BuildContext context) {
    final localization = Localization.of(context);
    // An untouched ID over an empty name is not wrong yet: it waits for the name.
    final bad = !_applicationIdValid && (_applicationIdEdited || _name.text.isNotEmpty);
    return CreationField(
      label: localization.newProjectApplicationId,
      messages: <Widget>[
        if (bad)
          CreationMessage.error(localization.newProjectApplicationIdInvalid)
        else
          CreationMessage.hint(localization.newProjectApplicationIdHint),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('new-project-application-id'),
        controller: _applicationId,
        error: bad,
        onChanged: (_) => setState(() => _applicationIdEdited = true),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _folderField(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final parent = _parent;
    // Until the default folder has arrived there is nothing to show but a placeholder.
    final full = parent == null
        ? '…'
        : '${parent.endsWith('/') ? parent : '$parent/'}${_name.text}';
    final problem = _targetChecked ? _targetProblem : null;
    final failed = _folderFailed;
    return CreationField(
      label: localization.newProjectFolder,
      messages: <Widget>[
        if (failed) CreationMessage.error(localization.newProjectFolderUnreadable),
        if (problem != null)
          CreationMessage.error(switch (problem) {
            TargetProblem.exists => localization.newProjectFolderExists,
            TargetProblem.parentMissing => localization.newProjectParentMissing,
          }),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: problem == null && !failed ? colors.border : colors.danger),
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
