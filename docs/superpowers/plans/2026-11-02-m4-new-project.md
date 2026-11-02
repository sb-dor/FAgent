# M4 New Project Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The New project wizard really creates a project: `flutter create`, `git init`, the app's own architecture skeleton, `flutter analyze` and a first commit, then the project joins the sidebar and opens on request.

**Architecture:** A real `ProjectCreationRepositoryImpl` replaces the fake behind `IProjectCreationRepository`. It runs each command as a `DaemonProcess` (its own process group), copies the skeleton from `assets/project_template/architecture/`, and emits `CreationRun` snapshots (`steps` + `projectId`). The controller gains `stop()` and carries `projectId`; the progress screen offers Stop / Open project / Close. The Flutter SDK repository reports the real version.

**Tech Stack:** Flutter macOS, control, freezed, drift, gen-l10n (en/ru), `DaemonProcess` / `GroupedProcess`, `ShellEnvironment`.

**Spec:** `docs/superpowers/specs/2026-11-02-m4-new-project-design.md` (Russian). Read it first; it is the authority.

## Global Constraints

- All code follows `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md` (repo overrides win). Feature widgets take colors only from `context.colors`, radii from `AppRadius`. `common/` never imports `feature/`.
- Every user-facing string is in both `lib/src/common/localization/intl_en.arb` and `intl_ru.arb`; regenerate with `flutter pub get`. Never edit `generated/`.
- `Stream`-returning repository methods follow "Stream-Returning Methods"; every started process is killed on cancel and in `dispose`.
- Template files live under `assets/project_template/architecture/`; the only placeholder is `{{package}}`. `assets/**` is already excluded from analysis.
- Skeleton packages, one `flutter pub add` call, in this order: `l`, `shared_preferences`, `freezed_annotation`, `intl`, `flutter_localizations@{sdk: flutter}`, `control@{git: {url: https://github.com/PlugFox/control.git, ref: 685a9bc6ef60c987b99b5526e125813adba54e2a}}`, `dev:freezed`, `dev:build_runner` (syntax verified with `--dry-run` on Flutter 3.47.1).
- Commit message of the first commit: `Initial commit`. No git identity is ever invented.
- A step keeps its last 200 output lines (`kCreationOutputKept = 200`); the screen still shows `kCreationOutputLines = 6`.
- Opt-in tests: `FLUTTER_RUN_TEST=1`, tag `flutter` (see `dart_test.yaml`).
- After every task: `flutter analyze` → No issues found; `flutter test` → all pass. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A target folder that appears between the form's check and "Create" — `flutter create` would silently write into it; the repository must re-check and fail the first step with `The folder already exists` (Task 3 test).
2. Stop pressed while `flutter pub add` hangs — the process group dies, the step shows `Stopped`, later steps stay pending, and the project (already created) is still added (Task 3 test).
3. A `pubspec.yaml` with no top-level `flutter:` line — the skeleton step fails with a clear line instead of writing a broken file (Task 3 test).
4. A long-running command printing thousands of lines — memory stays bounded at 200 lines per step (Task 3 test).
5. Quitting the app mid-creation — no `flutter`/`git` process survives (Task 3 test on `dispose`, Task 3 wiring in `AppCloseRepositoryImpl.shutdown`).

---

### Task 1: The skeleton template

**Files:**
- Create: `assets/project_template/architecture/` with exactly these files (paths relative to the template root):
  `lib/main.dart`, `lib/src/common/utils/app_zone.dart`, `lib/src/common/utils/error_util.dart`,
  `lib/src/common/widget/app_error.dart`, `lib/src/common/localization/localization.dart`,
  `lib/src/common/localization/intl_en.arb`, `lib/src/feature/initialization/models/dependencies.dart`,
  `lib/src/feature/initialization/widget/dependencies_scope.dart`, `lib/src/feature/initialization/widget/app.dart`,
  `lib/src/feature/initialization/data/initialization.dart`,
  `lib/src/feature/initialization/data/initialize_dependencies.dart`,
  `lib/src/feature/home/widgets/home_screen.dart`, `test/widget_test.dart`, `l10n.yaml`
- Create: `lib/src/feature/project_creation/data/project_template.dart`
- Modify: `pubspec.yaml` (asset folders of the template, one entry per directory, like `assets/knowledge/`)
- Test: `test/feature/project_creation/project_template_test.dart`

**Interfaces:**
- Produces (in `project_template.dart`):
  - `const String projectTemplateRoot = 'assets/project_template/architecture/';`
  - `const List<String> projectTemplateFiles` — the 14 relative paths above, in that order.
  - `String fillProjectTemplate(String text, {required String package})` — replaces every `{{package}}`.
  - `const String controlGitUrl`, `const String controlGitRef` — the pin from Global Constraints.
  - `const List<String> skeletonPubAddArguments` — the `pub add` arguments from Global Constraints, built from the two constants.

Content follows the spec, section 1: mirror this repo's own `lib/main.dart`, `app_zone.dart`, `error_util.dart`, `app_error.dart`, `localization.dart`, `l10n.yaml` and `feature/initialization/*` shapes, trimmed to one service (`SharedPreferencesWithCache`) and with every `flutter_code_agent` import as `package:{{package}}/…`. `App` is a `MaterialApp` titled from `Localization`, `home: HomeScreen()`. `l10n.yaml` is this repo's file verbatim. The arb has `appTitle` and `homeMessage`. `test/widget_test.dart` builds `Dependencies` with `SharedPreferencesWithCache` from `SharedPreferences.setMockInitialValues({})` and finds the title. The generated project must pass `flutter analyze` with fatal infos (checked in Task 3's opt-in test).

- [ ] **Step 1: Write the failing tests** in `project_template_test.dart`:
  - `every template file is an asset` — each `projectTemplateRoot + path` loads with `rootBundle.loadString` (use `TestWidgetsFlutterBinding.ensureInitialized()`).
  - `fill leaves no placeholder` — for each file, `fillProjectTemplate(text, package: 'my_app')` contains no `{{`, and every `package:` import in a `.dart` file is `package:my_app/`, `package:flutter/`, `package:flutter_test/`, `package:control/`, `package:l/`, `package:shared_preferences/` or `package:flutter_localizations/`.
  - `control pin matches the app's pubspec` — `File('pubspec.yaml')` contains `url: $controlGitUrl` and `ref: $controlGitRef`.
  - `pub add arguments` — `expect(skeletonPubAddArguments, ['l', 'shared_preferences', 'freezed_annotation', 'intl', 'flutter_localizations@{sdk: flutter}', 'control@{git: {url: https://github.com/PlugFox/control.git, ref: 685a9bc6ef60c987b99b5526e125813adba54e2a}}', 'dev:freezed', 'dev:build_runner'])`.
- [ ] **Step 2: Run** `flutter test test/feature/project_creation/project_template_test.dart` — FAIL (no `project_template.dart`).
- [ ] **Step 3: Write the template files, `project_template.dart` and the `pubspec.yaml` asset entries.**
- [ ] **Step 4: Run** the same test — PASS; `flutter analyze` — No issues found.
- [ ] **Step 5: Commit** `feat(project_creation): architecture skeleton template`.

### Task 2: Creation run model, controller stop, step rename

**Files:**
- Modify: `lib/src/feature/project_creation/models/creation_step.dart`
- Modify: `lib/src/feature/project_creation/data/project_creation_repository.dart`
- Modify: `lib/src/feature/project_creation/controller/project_creation_controller.dart`
- Modify: `lib/src/feature/project_creation/data/fake_project_creation_repository.dart` (adapt only; deleted in Task 3)
- Modify: `lib/src/feature/project_creation/widgets/creation_progress.dart` (the renamed kind and label only)
- Modify: `test/support/memory_project_creation_repository.dart`, the existing tests under `test/feature/project_creation/`
- Modify: both arb files

**Interfaces:**
- Produces:
  - `CreationStepKind.skeleton` replaces `agentSetup`; arb key `newProjectStepSkeleton` ("Architecture skeleton" / "Скелет архитектуры") replaces `newProjectStepAgentSetup`.
  - `@freezed abstract class CreationRun { required List<CreationStep> steps; int? projectId }` in `creation_step.dart`.
  - `IProjectCreationRepository.create(NewProjectRequest) → Stream<CreationRun>`; new `Future<void> stop()` (kills the running command; the stream then ends as a failure) and `Future<void> dispose()`. `isPreview` stays until Task 4.
  - Controller: `ProjectCreationState.completed` and `.failed` gain `int? projectId` (from the last `CreationRun`); new `void stop()` — calls `_repository.stop()` only while running.
  - `MemoryProjectCreationRepository` emits `CreationRun`s; `projectId` settable (`completedProjectId`, default `1`); records `stopCalls`; a `failAt` kind makes that step `failed`.

- [ ] **Step 1: Write the failing tests** in `project_creation_controller_test.dart`:
  - `completed carries the project id` — a run ending with `projectId: 7` → `ProjectCreation$CompletedState(projectId: 7)`.
  - `failed carries the project id` — a run with a failed step and `projectId: 7` → failed with `projectId: 7`.
  - `stop asks the repository while running` — `stop()` during a run → repository `stopCalls == 1`; `stop()` when idle → still `1`.
  - Update the step-list tests for `CreationStepKind.skeleton`.
- [ ] **Step 2: Run** `flutter test test/feature/project_creation/` — FAIL.
- [ ] **Step 3: Implement** the model, interface, controller, the memory stub and the adapted fake (the fake emits `CreationRun(steps: …)` with `projectId: null`; `stop` and `dispose` cancel its timer). Run `dart run build_runner build` and `flutter pub get`.
- [ ] **Step 4: Run** `flutter test` — all pass; `flutter analyze` — clean.
- [ ] **Step 5: Commit** `refactor(project_creation): CreationRun snapshots, stop, skeleton step`.

### Task 3: The real creation repository

**Files:**
- Create: `lib/src/feature/project_creation/data/project_creation_repository_impl.dart`
- Delete: `lib/src/feature/project_creation/data/fake_project_creation_repository.dart` and its test; move the `defaultParent` / `checkTarget` tests into the new test file
- Modify: `lib/src/feature/initialization/data/initialize_dependencies.dart` (build the real one), `lib/src/feature/app_close/data/app_close_repository.dart` (+ its `app_close_guard.dart` construction) to dispose it
- Modify: `test/support/memory_project_creation_repository.dart` (no import of the deleted fake: inline its sample lines and durations)
- Test: `test/feature/project_creation/project_creation_repository_impl_test.dart`, `test/feature/app_close/app_close_repository_test.dart`, opt-in `test/integration/new_project_test.dart`

**Interfaces:**
- Consumes: `projectTemplateRoot`, `projectTemplateFiles`, `fillProjectTemplate`, `skeletonPubAddArguments` (Task 1); `CreationRun`, `stop`, `dispose` (Task 2); `DaemonProcessStarter` / `startGroupedDaemonProcess` (`common/flutter_daemon/daemon_process.dart`); `IFlutterSdkRepository.sdkFor(null)` (its `path`); `ShellEnvironment` (`which('git')`, `variables` as the environment); `IProjectOpeningRepository.open(path) → Project`; `IProjectTrustRepository.trust(projectId)`.
- Produces:
  ```dart
  ProjectCreationRepositoryImpl({
    required AppDatabase database,
    required IFlutterSdkRepository flutterSdk,
    required ShellEnvironment environment,
    required IProjectOpeningRepository projectOpening,
    required IProjectTrustRepository projectTrust,
    required Future<String> Function(String key) loadAsset, // rootBundle.loadString in the app
    DaemonProcessStarter startProcess = startGroupedDaemonProcess,
    String? home,
  })
  ```
  `isPreview` → `false`. `const int kCreationOutputKept = 200`.

Commands (executable, arguments, working directory):

| Step | Command | Cwd |
| --- | --- | --- |
| flutterCreate | `<flutter> create --org <org> --project-name <name> --platforms <names joined by ",", in FlutterPlatform order> [--no-pub when architecture] <path>` | `parent` |
| gitInit | `<git> init` | `path` |
| skeleton | write files (`✎ <relative path>` each) → insert `  generate: true` on the line after the first line that is exactly `flutter:` → `<flutter> pub add <skeletonPubAddArguments>` → `<flutter> pub get` | `path` |
| analyze | `<flutter> analyze` | `path` |
| firstCommit | `<git> add -A`, then `<git> commit -m "Initial commit"` | `path` |

Rules: stdout and stderr lines go into the step's `output` as they arrive (bounded to the last 200). Non-zero exit or an exception → step `failed` (the exception's message as the last line), later steps stay pending. Before `flutter create`, `checkTarget` again; a problem fails that step with `The folder already exists` / `The folder does not exist`. No SDK path → `Flutter SDK not found`; no `which('git')` → the git step fails with `git not found`; no `flutter:` line → `pubspec.yaml has no flutter: section`. `stop()` stops the current process; the step fails with `Stopped` and nothing further runs. After the steps, if `flutterCreate` is `done`: `open(path)`, `trust(project.id)`, and a last snapshot with `projectId`; a throw there surfaces as a stream error. Cancelling the subscription or `dispose()` stops the current process and adds nothing.

- [ ] **Step 1: Write the failing tests** (scripted processes via `scriptedStarter` from `test/support/scripted_daemon_process.dart`, a temp dir for `parent`, an in-memory `AppDatabase`, stubs for opening/trust/SDK, `loadAsset` reading `projectTemplateRoot` files from disk; each scripted process prints a line and `exit(0)` unless the test says otherwise):
  - `architecture with git runs the five steps' commands` — exact executable/arguments/cwd of every started process, in order, including `--no-pub` and `--platforms ios,android,macos`.
  - `plain without git runs create and analyze only` — no `--no-pub`, no git processes.
  - `skeleton writes every template file filled` — files exist under `path` with `package:<name>/` imports; output has a `✎ lib/main.dart` line.
  - `generate true goes under flutter` — given a `pubspec.yaml` written by the scripted `flutter create`, the result has `flutter:\n  generate: true`.
  - `pubspec without flutter section fails the skeleton step` — last line `pubspec.yaml has no flutter: section`, analyze pending.
  - `failing step stops the run` — analyze exits 1 → `failed`, firstCommit `pending`, output kept.
  - `target that appeared fails flutter create` — create the folder after the form's check → no process started, first step failed with `The folder already exists`.
  - `git not found` — `which('git')` null → gitInit failed with `git not found`.
  - `stop kills the running command` — `stop()` while `pub add` runs → that process `stopped`, step failed with last line `Stopped`, later pending, project still added (`open` called once).
  - `cancel kills and adds nothing` — cancel the subscription mid-step → process `stopped`, `open` never called.
  - `dispose kills the running command` — same through `dispose()`.
  - `output is bounded` — a process printing 1000 lines → step output length 200, last line is the 1000th.
  - `success adds and trusts the project` — `open(path)` then `trust(id)`; last snapshot `projectId == id`.
  - `flutter create failure adds nothing` — `projectId` null, `open` never called.
  - Moved: `defaultParent` and `checkTarget` cases from the deleted fake's test.
  - In `app_close_repository_test.dart`: `shutdown disposes the project creation`.
- [ ] **Step 2: Run** the new test file — FAIL.
- [ ] **Step 3: Implement** the repository, delete the fake, wire it in `initialize_dependencies.dart` (build `ProjectOpeningRepositoryImpl` / `ProjectTrustRepositoryImpl` from `dependencies.database`, `loadAsset: rootBundle.loadString`) and in `AppCloseRepositoryImpl.shutdown` (`_stopQuietly('project creation', _projectCreation.dispose)`).
- [ ] **Step 4: Write the opt-in test** `test/integration/new_project_test.dart` (tag `flutter`, skips unless `FLUTTER_RUN_TEST=1`): the real repository with the real SDK path, `architecture` template, `gitInit: false`, in a temp folder; all steps `done`; then `flutter test` inside the project exits 0; the temp folder is deleted in `tearDown` even on failure.
- [ ] **Step 5: Run** `flutter test` — all pass; `FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/new_project_test.dart` — passes (fix the template from Task 1 if analyze reports anything).
- [ ] **Step 6: Commit** `feat(project_creation): real flutter create, skeleton, git`.

### Task 4: The wizard's end states and copy

**Files:**
- Modify: `lib/src/feature/project_creation/widgets/creation_progress.dart`, `new_project_dialog.dart`, `new_project_form.dart`
- Modify: `lib/src/feature/project_creation/data/project_creation_repository.dart`, `project_creation_repository_impl.dart`, `controller/project_creation_controller.dart` (remove `isPreview`)
- Modify: `lib/src/feature/workspace/widgets/workspace_config_widget.dart`, `workspace_sidebar.dart`; `lib/src/feature/flutter_sdk/widgets/flutter_settings_section.dart`
- Modify: both arb files; `test/support/memory_project_creation_repository.dart`
- Test: `test/feature/project_creation/creation_progress_test.dart`, `new_project_form_test.dart`, a workspace widget test for opening a created project (next to the existing workspace tests)

**Interfaces:**
- Consumes: `projectId` on completed/failed, `stop()` (Task 2).
- Produces:
  - `WorkspaceConfigWidgetState.openCreatedProject(int projectId, {required bool openChat})` — with `openChat`: `createChat(projectId: projectId)`; without: `dataController.whenMayLeave` → `selectProject(projectId)` and back to the chat view.
  - `CreationProgress({required controller, required VoidCallback onClose, required void Function(int projectId) onOpenProject})`.
  - Button keys: `creation-stop`, `creation-minimize` (running); `creation-close`, `creation-open-project` (finished; open only when `projectId != null`). Removed: `creation-open-chat`, `creation-done`.
  - Arb: add `newProjectStop` ("Stop" / "Остановить"), `newProjectOpenProject` ("Open project" / "Открыть проект"), `newProjectClose` ("Close" / "Закрыть"), `comingLater` ("Coming later" / "Появится позже"); change `newProjectTemplateArchitectureHint` to "flutter create, then the app lays out lib/src/common + feature" / "flutter create, затем приложение раскладывает lib/src/common + feature"; remove `newProjectCreatedPreview`, `newProjectPreviewNote`, `newProjectProgressNote`, `newProjectAgentName`, `newProjectOpenAgentChat`, `newProjectDone`.

- [ ] **Step 1: Write the failing tests:**
  - `running offers stop and minimize` — keys present; tapping `creation-stop` → repository `stopCalls == 1`.
  - `completed offers open project and close` — both keys; title `newProjectCreated` (no "(Preview)").
  - `failed after create offers open project` / `failed without project offers only close`.
  - `no preview note` — neither old note text is found in any state.
  - `open project with chat starts a chat` / `open project without chat only selects it` — workspace test: after `creation-open-project`, the selected project is the created one; a session creation was requested only with `openChat: true`; the dialog is gone and the controller is idle.
  - `git template says coming later` — form hint and sidebar "Clone from git…" SnackBar show `comingLater`.
- [ ] **Step 2: Run** the tests — FAIL.
- [ ] **Step 3: Implement** the buttons, `_openProject` in the dialog (close as `_done` does, then `openCreatedProject`), remove `isPreview` and the `_Note` widget, switch the three "Coming in M4" uses to `comingLater` (the form's git hint, the sidebar's "Clone from git…", and the Settings git segment — `FlutterSdkConfigWidget.showComingSoon(String milestone)` becomes `showComingLater()`), update arb files, `flutter pub get`.
- [ ] **Step 4: Run** `flutter test` — all pass; `flutter analyze` — clean.
- [ ] **Step 5: Commit** `feat(project_creation): open the created project, stop, final copy`.

### Task 5: Real Flutter version and the milestone docs

**Files:**
- Create: `lib/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart` (`FlutterSdkRepositoryImpl`)
- Delete: `lib/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart`; rename its test to `flutter_sdk_repository_impl_test.dart`
- Modify: `initialize_dependencies.dart`, `flutter_settings_section.dart` (doc comment only)
- Modify: `docs/PLAN.md` (M4 ticks, a «Решения M4» list from the spec's last section), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (§3.9: real creation, Stop/Open project/Close, no agent step; §4 table row `project_creation` → Real), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` ("M4 follow-ups" for anything deferred)

**Interfaces:**
- Produces:
  ```dart
  typedef ProcessRunner = Future<io.ProcessResult> Function(
    String executable, List<String> arguments, {Map<String, String>? environment});
  FlutterSdkRepositoryImpl({
    required String? Function(String name) which,
    Map<String, String>? environment,
    ProcessRunner runProcess = io.Process.run,
  })
  ```
  `sdkFor(projectPath)`: `path` from `flutterExecutableFor(projectPath, which: which)`; `version` / `channel` from `frameworkVersion` / `channel` of `<path> --version --machine`; `isPreview: false`; `fvmVersion` as before. No path, non-zero exit or unparsable JSON → `version: null`, `channel: null` (one `l.w` line). `doctor()` keeps the made-up report unchanged.

- [ ] **Step 1: Write the failing tests:** `reads version and channel` (stdout `{"frameworkVersion":"3.47.1","channel":"stable"}` → `3.47.1`, `stable`, `isPreview` false); `failed command has no version`; `bad JSON has no version`; `no flutter has no path and runs nothing`; the existing fvm and doctor cases, renamed.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**, wire it, update the docs.
- [ ] **Step 4: Run** `flutter test` — all pass; `flutter analyze` — clean.
- [ ] **Step 5: Commit** `feat(flutter_sdk): real Flutter version; docs: M4`.
