import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/controller/flutter_sdk_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/package_name.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_fields.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/option_chip.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/platform_chips.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:l/l.dart';

/// {@template add_member_form}
/// What the Add to project dialog asks: the kind of member (Flutter app, Dart app, Flutter package,
/// Dart package), its folder and package name, and, for a Flutter app, the organization, the
/// platforms and the template.
///
/// The package follows `<project>_<folder>` until it is typed. The folder and the package are
/// checked as package names, and then against the project (the folder must be free and the package
/// name not taken; the latest answer wins). A project without `packages/ui` offers only the empty
/// template, as the skeleton needs that package; so does a Flutter older than
/// [kArchitectureMinFlutter] (or an unknown one). "Create" is on only when everything is fine.
/// {@endtemplate}
class AddMemberForm extends StatefulWidget {
  /// {@macro add_member_form}
  const AddMemberForm({required this.project, super.key});

  /// The monorepo the member is added to.
  final Project project;

  @override
  State<AddMemberForm> createState() => _AddMemberFormState();
}

class _AddMemberFormState extends State<AddMemberForm> {
  late final WorkspaceConfigWidgetState _scope;
  late final FlutterSdkController _sdk;
  late final TextEditingController _folder;
  late final TextEditingController _package;
  late final TextEditingController _org;

  /// Whether the package was typed: until then it follows `<project>_<folder>`.
  bool _packageEdited = false;

  MemberKind _kind = MemberKind.flutterApp;
  Set<FlutterPlatform> _platforms = const <FlutterPlatform>{
    FlutterPlatform.ios,
    FlutterPlatform.android,
    FlutterPlatform.macos,
  };
  late NewProjectTemplate _template;

  /// Whether the project has `packages/ui`; `null` until known.
  bool? _hasUi;

  /// Whether the project is a git repository; `null` until known.
  bool? _gitRepo;

  /// Whether the project could not be asked about its `packages/ui` or git.
  bool _projectFailed = false;

  /// Number of the latest suggestion of the package name; an older answer is dropped.
  int _suggestNumber = 0;

  /// Number of the latest member check; an older answer is dropped.
  int _checkNumber = 0;

  /// Whether [_problem] answers for the current kind, folder and package.
  bool _checked = false;
  MemberProblem? _problem;

  /// Whether the member could not be checked.
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    _scope = WorkspaceConfigInhWidget.of(context);
    final settings = _scope.settingsController.settings;
    _folder = TextEditingController();
    _package = TextEditingController();
    _org = TextEditingController(text: settings.projectOrg);
    _template = settings.projectTemplate == NewProjectTemplate.plain
        ? NewProjectTemplate.plain
        : NewProjectTemplate.architecture;
    _sdk = FlutterSdkController(repository: Dependencies.of(context).flutterSdkRepository)
      ..addListener(_onSdk)
      ..load(null);
    _loadProject();
  }

  @override
  void dispose() {
    _suggestNumber++;
    _checkNumber++;
    _sdk
      ..removeListener(_onSdk)
      ..dispose();
    _folder.dispose();
    _package.dispose();
    _org.dispose();
    super.dispose();
  }

  String get _path => widget.project.path;

  void _onSdk() => setState(() {});

  FlutterSdk? get _sdkInfo => switch (_sdk.state) {
    FlutterSdk$CompletedState(:final sdk) => sdk,
    FlutterSdk$ErrorState(:final sdk) => sdk,
    _ => null,
  };

  bool get _architectureSupported => supportsArchitecture(_sdkInfo?.version);

  /// The template the app is made from: the skeleton falls back to the empty one without
  /// `packages/ui` or on an SDK that cannot make it.
  NewProjectTemplate get _templateUsed =>
      _template == NewProjectTemplate.architecture && (_hasUi != true || !_architectureSupported)
      ? NewProjectTemplate.plain
      : _template;

  Future<void> _loadProject() async {
    try {
      final hasUi = await _scope.projectCreation.hasUiPackage(_path);
      final gitRepo = await _scope.projectCreation.isGitRepo(_path);
      if (!mounted) return;
      setState(() {
        _hasUi = hasUi;
        _gitRepo = gitRepo;
        // The skeleton needs packages/ui.
        if (!hasUi) _template = NewProjectTemplate.plain;
      });
    } on Object catch (error, stackTrace) {
      l.w('Add to project | read the project | $error', stackTrace);
      if (mounted) setState(() => _projectFailed = true);
    }
  }

  PackageNameProblem? get _folderProblem => checkPackageName(_folder.text);

  PackageNameProblem? get _packageProblem => checkPackageName(_package.text);

  bool get _orgValid => AppSettings.orgPattern.hasMatch(_org.text);

  bool get _canCreate =>
      _folderProblem == null &&
      _packageProblem == null &&
      _checked &&
      _problem == null &&
      !_checkFailed &&
      _gitRepo != null &&
      !_projectFailed &&
      (!_kind.hasPlatforms || (_orgValid && _platforms.isNotEmpty));

  /// Keeps the package at `<project>_<folder>` until it is typed.
  void _followPackage() {
    if (_packageEdited) return;
    final folder = _folder.text;
    final number = ++_suggestNumber;
    if (folder.isEmpty) {
      _package.clear();
      return;
    }
    _scope.projectCreation
        .suggestedPackageName(_path, folder)
        .then<void>(
          (name) {
            if (!mounted || number != _suggestNumber || _packageEdited) return;
            _package.text = name;
            _checkMember();
          },
          onError: (Object error, StackTrace stackTrace) {
            l.w('Add to project | suggest the package | $error', stackTrace);
          },
        );
  }

  /// Asks whether the member can be added; the answer counts only if nothing changed meanwhile.
  void _checkMember() {
    final number = ++_checkNumber;
    final kind = _kind;
    final folder = _folder.text;
    final package = _package.text;
    setState(() {
      _checked = false;
      _problem = null;
      _checkFailed = false;
    });
    if (checkPackageName(folder) != null || checkPackageName(package) != null) return;
    _scope.projectCreation
        .checkMember(_path, kind, folder, package)
        .then<void>(
          (problem) {
            if (!mounted || number != _checkNumber) return;
            setState(() {
              _checked = true;
              _problem = problem;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            l.w('Add to project | check the member | $error', stackTrace);
            if (!mounted || number != _checkNumber) return;
            setState(() {
              _checked = true;
              _checkFailed = true;
            });
          },
        );
  }

  void _toggle(FlutterPlatform platform) => setState(() {
    _platforms = _platforms.contains(platform)
        ? (<FlutterPlatform>{..._platforms}..remove(platform))
        : <FlutterPlatform>{..._platforms, platform};
  });

  void _create() {
    if (!_canCreate) return;
    _scope.projectCreation.startAdd(
      NewMemberRequest(
        projectId: widget.project.id,
        projectPath: _path,
        kind: _kind,
        folder: _folder.text,
        packageName: _package.text,
        org: _org.text,
        platforms: _kind.hasPlatforms ? _platforms : const <FlutterPlatform>{},
        template: _kind.hasPlatforms ? _templateUsed : NewProjectTemplate.plain,
        gitRepo: _gitRepo ?? false,
      ),
    );
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
        _kindField(context),
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _folderField(context)),
            const SizedBox(width: 10),
            Expanded(child: _packageField(context)),
          ],
        ),
        if (_kind.hasPlatforms) ...<Widget>[
          gap,
          _orgField(context),
          gap,
          CreationField(
            label: localization.newProjectPlatforms,
            messages: <Widget>[
              if (_platforms.isEmpty) CreationMessage.error(localization.newProjectNoPlatform),
            ],
            child: PlatformChips(selected: _platforms, onToggle: _toggle),
          ),
          gap,
          _templateField(context),
        ],
      ],
    );
  }

  Widget _kindField(BuildContext context) {
    final localization = Localization.of(context);
    final labels = <MemberKind, (String, String)>{
      MemberKind.flutterApp: (
        localization.memberKindFlutterApp,
        localization.memberKindFlutterAppHint,
      ),
      MemberKind.dartApp: (localization.memberKindDartApp, localization.memberKindDartAppHint),
      MemberKind.flutterPackage: (
        localization.memberKindFlutterPackage,
        localization.memberKindFlutterPackageHint,
      ),
      MemberKind.dartPackage: (
        localization.memberKindDartPackage,
        localization.memberKindDartPackageHint,
      ),
    };
    return CreationField(
      label: localization.newProjectType,
      messages: <Widget>[CreationMessage.hint(labels[_kind]!.$2)],
      child: Wrap(
        key: const ValueKey<String>('add-member-kind'),
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final kind in MemberKind.values)
            OptionChip(
              key: ValueKey<String>('kind-${kind.name}'),
              label: labels[kind]!.$1,
              selected: kind == _kind,
              exclusive: true,
              onTap: () {
                setState(() => _kind = kind);
                _checkMember();
              },
            ),
        ],
      ),
    );
  }

  static String _nameProblemText(BuildContext context, PackageNameProblem problem) {
    final localization = Localization.of(context);
    return switch (problem) {
      PackageNameProblem.keyword => localization.newProjectNameKeyword,
      PackageNameProblem.dependency => localization.newProjectNameDependency,
      PackageNameProblem.invalid || PackageNameProblem.empty => localization.newProjectNameInvalid,
    };
  }

  Widget _folderField(BuildContext context) {
    final localization = Localization.of(context);
    final problem = _folderProblem;
    // An empty field is not an error yet: the user has not typed.
    final bad = problem != null && problem != PackageNameProblem.empty;
    final exists = _checked && _problem == MemberProblem.folderExists;
    return CreationField(
      label: localization.addMemberFolder,
      messages: <Widget>[
        if (bad) CreationMessage.error(_nameProblemText(context, problem)),
        if (exists) CreationMessage.error(localization.addMemberFolderExists),
        if (_checkFailed) CreationMessage.error(localization.newProjectFolderUnreadable),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('add-member-folder'),
        controller: _folder,
        autofocus: true,
        error: bad || exists || _checkFailed,
        onChanged: (_) {
          setState(() {});
          _followPackage();
          _checkMember();
        },
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _packageField(BuildContext context) {
    final localization = Localization.of(context);
    final problem = _packageProblem;
    final bad = problem != null && problem != PackageNameProblem.empty;
    final taken = _checked && _problem == MemberProblem.packageTaken;
    return CreationField(
      label: localization.addMemberPackage,
      messages: <Widget>[
        if (bad) CreationMessage.error(_nameProblemText(context, problem)),
        if (taken) CreationMessage.error(localization.addMemberPackageTaken),
      ],
      child: CreationTextInput(
        fieldKey: const ValueKey<String>('add-member-package'),
        controller: _package,
        error: bad || taken,
        onChanged: (_) {
          _packageEdited = true;
          setState(() {});
          _checkMember();
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
        fieldKey: const ValueKey<String>('add-member-org'),
        controller: _org,
        error: !_orgValid,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _create(),
      ),
    );
  }

  Widget _templateField(BuildContext context) {
    final localization = Localization.of(context);
    // Until it is known whether packages/ui exists, only the empty template is safe to show.
    final skeleton = _hasUi ?? false;
    return CreationField(
      label: localization.newProjectTemplate,
      messages: <Widget>[
        if (_hasUi == false) CreationMessage.hint(localization.addMemberNoUiPackage),
        if (skeleton && _sdkInfo != null && !_architectureSupported)
          CreationMessage.hint(
            localization.newProjectTemplateArchitectureNeedsFlutter(kArchitectureMinFlutter),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (skeleton) ...<Widget>[
            CreationTemplateCard(
              key: const ValueKey<String>('template-architecture'),
              title: localization.newProjectTemplateArchitecture,
              description: localization.newProjectTemplateArchitectureHint,
              selected: _templateUsed == NewProjectTemplate.architecture,
              enabled: _architectureSupported,
              onTap: () => setState(() => _template = NewProjectTemplate.architecture),
            ),
            const SizedBox(height: 6),
          ],
          CreationTemplateCard(
            key: const ValueKey<String>('template-plain'),
            title: localization.newProjectTemplatePlain,
            description: localization.newProjectTemplatePlainHint,
            selected: _templateUsed == NewProjectTemplate.plain,
            onTap: () => setState(() => _template = NewProjectTemplate.plain),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        OutlinedButton(
          key: const ValueKey<String>('add-member-cancel'),
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
          key: const ValueKey<String>('add-member-create'),
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
