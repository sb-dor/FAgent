# M6 Widget Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "Pick a widget" in the Run tab really picks a widget in the running debug app through the Flutter widget inspector, shows it with its project ancestors and a screenshot, and puts it into the chat draft.

**Architecture:** A `WidgetInspectorClient` wraps `vm_service` calls to `ext.flutter.inspector.*` over the run's own VM service connection. `WidgetPickerRepositoryImpl` replaces the fake behind `IWidgetPickerRepository`, keeps one client per running project, saves the widget PNG next to the app screenshots and returns an extended `PickedWidget`. The Run tab drives the pick outside the droppable actions handler, so Stop, Hot reload and Cancel keep working while a pick waits.

**Tech Stack:** Flutter macOS, control, freezed, `vm_service` 15.4.0 (already a dependency), gen-l10n (en/ru).

**Spec:** `docs/superpowers/specs/2026-11-02-m6-widget-picker-design.md` (Russian). Read it first; it is the authority.

## Global Constraints

- All code follows `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md`. Feature widgets take colors only from `context.colors`, radii from `AppRadius`. Every user-facing string in both `intl_en.arb` and `intl_ru.arb`; regenerate with `flutter pub get`.
- Inspector extensions, verbatim: `ext.flutter.inspector.show` (`enabled: 'true'|'false'`), `ext.flutter.inspector.getSelectedSummaryWidget` (`objectGroup`), `ext.flutter.inspector.getParentChain` (`arg`: id, `objectGroup`), `ext.flutter.inspector.screenshot` (`id`, `width: '800'`, `height: '800'`, `maxPixelRatio: '2'`), `ext.flutter.inspector.disposeGroup` (`objectGroup`). Object group: `flutter_code_agent_picker`.
- A pick ends on the `ToolEvent` stream event of kind `navigate` with `source == 'flutter.inspector'`; select mode leaving is the `Extension` stream event `Flutter.ServiceExtensionStateChanged` with `extension == 'ext.flutter.inspector.show'` and `value == 'false'`.
- Ancestors: only nodes with `createdByLocalProject == true`, from the picked widget outwards (nearest first), at most 8, the picked one excluded.
- Widget PNGs go to `kScreenshotsFolder` (`.dart_tool/flutter_code_agent/screenshots`) as `widget-<Name>.png` (name sanitized to `[A-Za-z0-9_]`, numbered on collision) and count toward `kScreenshotLimit = 20`.
- Draft text: `@widget <Name> (<file>:<line>:<column>)`, then a new line `in: <A1> › <A2> › …` when there are ancestors, then a new line `@<png path>` when there is a screenshot.
- The picker works only for `RunRunning` with `mode == BuildMode.debug` and a `vmServiceUri`.
- Select mode is always turned off at the end of a pick (success, cancel, error, dispose).
- Opt-in tests: `FLUTTER_RUN_TEST=1`, tag `flutter`.
- After every task: `flutter analyze` → No issues found; `flutter test` → all pass. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Stop or Hot reload pressed while a pick waits — the action runs at once (not dropped by the droppable handler) and the pick ends as cancelled (Task 3 test).
2. Quitting the app during a pick — select mode is turned off in the running app and the connection closed (Task 2 test).
3. Two projects running, a pick in one — the other's run and picker are untouched (Task 2 test).
4. A hot restart during a pick — the pick is cancelled and the next pick finds the new isolate (Task 2 test).
5. A widget class name that is not file-safe (e.g. `_Private`, `Foo<Bar>`) — the PNG name is sanitized and unique (Task 2 test).

---

### Task 1: The widget inspector client

**Files:**
- Create: `lib/src/feature/app_run/data/widget_inspector_client.dart`, `lib/src/feature/app_run/models/inspector_node.dart`
- Modify: `test/support/scripted_vm_service.dart` (inspector extensions, `ToolEvent`/`Extension`/`Isolate` events)
- Test: `test/feature/app_run/widget_inspector_client_test.dart`

**Interfaces:**
- Produces:
  - `@freezed InspectorNode({required String name, required String id, String? fileUri, int? line, int? column, @Default(false) bool local})` — from a node JSON: `description` → name, `valueId` → id, `creationLocation.file/line/column`, `createdByLocalProject` → local.
  - `sealed class InspectorEvent` — `InspectorNavigated(String isolateId)`, `InspectorSelectModeChanged(String isolateId, bool enabled)`, `InspectorIsolateExited(String isolateId)`.
  - `final class WidgetInspectorClient` — `static Future<WidgetInspectorClient> connect(Uri vmServiceUri)` (uses `vmServiceConnectUri`); `WidgetInspectorClient.attach(VmService service)` for tests; `Future<String?> inspectorIsolate()` (first isolate whose `extensionRPCs` contains `ext.flutter.inspector.show`); `Stream<InspectorEvent> get events` (subscribes `ToolEvent`, `Extension`, `Isolate` once, broadcast); `Future<void> setSelectMode(String isolateId, {required bool enabled})`; `Future<InspectorNode?> selectedWidget(String isolateId)`; `Future<List<InspectorNode>> parentChain(String isolateId, String id)` (root → node order as the extension returns it); `Future<List<int>?> screenshot(String isolateId, String id)` (base64-decoded; `null` when the result is null); `Future<void> disposeGroup(String isolateId)`; `Future<void> close()` (idempotent). Errors propagate as the `RPCError`/`SentinelException` of `vm_service`.

- [ ] **Step 1: Write the failing tests** (scripted VM service): `finds the isolate with the inspector`; `no isolate with the inspector gives null`; `setSelectMode sends show with enabled true/false`; `navigate event of flutter.inspector becomes InspectorNavigated, other sources are ignored`; `show state change to false becomes InspectorSelectModeChanged(false)`; `isolate exit becomes InspectorIsolateExited`; `selectedWidget parses name, id, creation location and local`; `parentChain keeps order and parses each node`; `screenshot decodes base64 and returns null for a null result`; `every call passes objectGroup flutter_code_agent_picker`; `close disposes the service once`.
- [ ] **Step 2: Run** `flutter test test/feature/app_run/widget_inspector_client_test.dart` — FAIL.
- [ ] **Step 3: Implement**; `dart run build_runner build`.
- [ ] **Step 4: Run** the test, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): widget inspector client`.

### Task 2: The real picker repository

**Files:**
- Create: `lib/src/feature/app_run/data/widget_picker_repository_impl.dart`
- Modify: `lib/src/feature/app_run/models/picked_widget.dart` (extend), `lib/src/feature/app_run/data/widget_picker_repository.dart` (interface), `lib/src/feature/app_run/data/app_run_repository.dart` (make the PNG save a shared top-level `Future<String> saveScreenshotPng(String root, List<int> bytes, {String name})` used by both), `lib/src/feature/initialization/data/initialize_dependencies.dart`, `lib/src/feature/app_close/data/app_close_repository.dart` (dispose the picker), every `PickedWidget` construction site and test
- Delete: `lib/src/feature/app_run/data/fake_widget_picker_repository.dart` (widget tests get `test/support/scripted_widget_picker_repository.dart`)
- Test: `test/feature/app_run/widget_picker_repository_impl_test.dart`

**Interfaces:**
- Consumes: `WidgetInspectorClient`, `InspectorNode`, `InspectorEvent` (Task 1); `IAppRunRepository.watchRun(projectId)` / `currentRun(projectId)` (`RunRunning.vmServiceUri`, `.mode`).
- Produces:
  - `PickedWidget({required String name, required String file, required int line, int column = 0, required List<PickedAncestor> ancestors, String? id, String? screenshot})` — `file` project-relative, `screenshot` the project-relative PNG path or `null`; `final class PickedAncestor({required String name, required String file, required int line, int column, required String id})`. Value equality kept. `PickedWidget.noProjectWidget` is not a field: a tap with no project widget is the sealed result below.
  - `IWidgetPickerRepository`: `isPreview` removed; `Future<PickResult> pick(int projectId)`; `Future<void> cancel(int projectId)`; `Future<PickResult> select(int projectId, String id)` (re-reads a widget of the last pick's chain); `Future<void> dispose()`.
  - `sealed class PickResult` — `PickPicked(PickedWidget widget)`, `PickCancelled()`, `PickNoProjectWidget()`, `PickGone()` (stale id), `PickFailed(String message)` with the spec's lines: `The widget inspector is not available in this app`, `The app is not running in debug`, `Lost the connection to the app`.
  - `WidgetPickerRepositoryImpl({required IAppRunRepository runs, required Future<String?> Function(int projectId) projectRoot, Future<WidgetInspectorClient> Function(Uri) connect = WidgetInspectorClient.connect})`.
  - Behaviour: one client per project, opened at the first pick from `vmServiceUri`, closed when the run leaves `RunRunning` or its `vmServiceUri` changes (follow `watchRun`); a pick: `disposeGroup` → `setSelectMode(true)` → wait for `InspectorNavigated` on that isolate, or cancel on `InspectorSelectModeChanged(false)`, `InspectorIsolateExited`, `cancel(projectId)`, the run ending → `selectedWidget` (no local node → `PickNoProjectWidget`) → `parentChain` (filter per Global Constraints) → `screenshot` → save with `saveScreenshotPng` → `setSelectMode(false)` in a `finally`; `file` made project-relative from `file://` URIs under the root (outside the root → kept absolute). `dispose` cancels running picks (each turns select mode off) and closes every client.

- [ ] **Step 1: Write the failing tests** (scripted VM service through an injected `connect`, a temp project root, a scripted `IAppRunRepository` emitting run states): `pick returns the widget, project-relative file, column, ancestors nearest first and at most 8, local only`; `screenshot saved as widget-<Name>.png under the screenshots folder`; `a non-file-safe name is sanitized and numbered on collision` (Review Focus #5); `select mode off after success, cancel and error`; `cancel ends the pick as PickCancelled`; `leaving select mode in the app cancels`; `hot restart (isolate exit) cancels and the next pick uses the new isolate` (Review Focus #4); `run stop cancels and closes the client`; `no inspector isolate fails with the spec line`; `a dropped VM service connection fails with "Lost the connection to the app" and the next pick connects again`; `tap outside project widgets gives PickNoProjectWidget`; `null screenshot keeps the widget without a screenshot`; `select by a chain id returns that widget`; `select after the group was released gives PickGone`; `two projects use separate clients` (Review Focus #3); `dispose during a pick turns select mode off and closes` (Review Focus #2); `the group is disposed before each pick`.
- [ ] **Step 2: Run** the test file — FAIL.
- [ ] **Step 3: Implement**; wire `WidgetPickerRepositoryImpl` in `initialize_dependencies.dart` (project root query like the M3 app MCP tools); add it to `AppCloseRepositoryImpl.shutdown`; keep `RunActionsController` compiling (Task 3 changes its flow); delete the fake.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): real widget picker over the inspector`.

### Task 3: The Run tab, the card and the chat draft

**Files:**
- Modify: `lib/src/feature/app_run/controller/run_actions_controller.dart`, `lib/src/feature/app_run/controller/run_controller.dart`, `lib/src/feature/app_run/widgets/run_tab.dart`, `lib/src/feature/app_run/widgets/picked_widget_card.dart`, `lib/src/feature/workspace/widgets/controllers/workspace_run_link.dart`, `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (`pickerIsPreview` removed)
- Modify: both arb files
- Test: `test/feature/app_run/run_tab_test.dart`, `test/feature/app_run/picked_widget_card_test.dart`, `test/feature/app_run/run_chat_link_test.dart`, `test/feature/app_run/run_preview_badge_test.dart`

**Interfaces:**
- Consumes: `PickResult`, `PickedWidget`, `PickedAncestor`, `pick/cancel/select` (Task 2).
- Produces:
  - `RunActionsController`: `void pickWidget(int projectId)` and `void selectAncestor(int projectId, String id)` run OUTSIDE the droppable handler (they may wait without limit), with a separate state `picking: bool` (or a `RunPickState` the card reads); `void cancelPick(int projectId)`; Stop, Hot reload and Hot restart while a pick waits call `cancel` and run normally.
  - Pick button: enabled only for `RunRunning` + debug + `vmServiceUri`; disabled tooltips (new arb keys) "The app is not running", "Picking works in debug builds only", "Waiting for the app's VM service". The "Coming in M6" path and `pickerIsPreview` are removed.
  - Card states: picking (hint + Cancel), picked (name, `file:line:column`, the PNG thumbnail when present via `Image.file`, the chain as tappable links with the current one highlighted — `context.colors.accent` text on a tinted background — Add to message, Open file), no project widget (message, Add disabled), gone (message, last data kept), failed (the `PickFailed.message`), no screenshot (a small note).
  - `WorkspaceRunLink.addWidget(PickedWidget)` writes the Global Constraints draft text; the PNG path is remembered for the `@` menu as `addScreenshot` does.

- [ ] **Step 1: Write the failing tests:** `pick button disabled with each reason`; `stop while picking stops the run and cancels the pick` (Review Focus #1); `hot reload while picking runs`; `cancel ends the pick and shows the hint again`; card — each state above, `tapping an ancestor selects it and moves the highlight`, `the thumbnail shows when a screenshot exists`; link — `add to message writes the widget line, the ancestors line and the @png line`, `without ancestors or screenshot only the widget line`; `no preview badge on the picker`.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; arb keys added and old ones unused removed (grep).
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): pick widgets in the Run tab, chain and screenshot to the chat`.

### Task 4: Real-app check and the milestone docs

**Files:**
- Create: `test/integration/widget_picker_test.dart` (tag `flutter`, skips unless `FLUTTER_RUN_TEST=1`)
- Modify: `docs/PLAN.md` (M6 ticks, «Решения M6» from the spec's last section plus anything decided during implementation), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (the Run tab section and the §4 `widget_picker` row → Real; every stale "M6"), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` ("## M6 follow-ups" from the deferred review notes)

**Interfaces:**
- Consumes: everything above; the real `AppRunRepositoryImpl` like `test/integration/flutter_run_test.dart`.

- [ ] **Step 1: Write the opt-in test:** generate a tiny app (`flutter create` in a temp dir, `lib/main.dart` with a `MaterialApp` → a project widget `Greeting` with a `Text`), `flutter run -d macos` in debug through the real run repository, start `pick`, then select the `Greeting` element through a second VM service connection with `ext.flutter.inspector.setSelectionById` (find its id via `getRootWidgetSummaryTree`), assert the pick returns `Greeting`, `lib/main.dart`, a line > 0, a non-empty PNG file, and that select mode was turned off; stop the run; delete the temp dir in `tearDown`.
- [ ] **Step 2: Run** `FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/widget_picker_test.dart` — pass (needs Xcode/macOS desktop and the network for `pub get`).
- [ ] **Step 3: Update the docs.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `test(app_run): real widget pick; docs: M6`.
