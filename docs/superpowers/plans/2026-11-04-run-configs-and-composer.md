# Run Configurations, Message Queue and File Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A split "Запустить" button that runs Default or a `.vscode/launch.json` configuration, a ⌘↵ message queue while the agent works, and files and images dropped (or pasted) into the chat.

**Architecture:** A pure `launch.json` reader turns dart configurations into `LaunchConfig`s; the run controller keeps the selected one (stored per project) and merges it into the start call. A per-chat `ChatQueueController` holds queued prompts and sends the next one when a turn ends normally. A `DropTarget` over the chat classifies dropped paths into mentions, absolute paths and image chips; images go to the agent as ACP image blocks.

**Tech Stack:** Flutter macOS, control, freezed, drift (v9 → v10), gen-l10n (en/ru), `desktop_drop` 0.9.2, `pasteboard` 0.6.0.

**Spec:** `docs/superpowers/specs/2026-11-04-run-configs-and-composer-design.md` (Russian). Read it first; it is the authority. Branch `ux-round-1` (the Stop spinner `db14148` is already on it).

## Global Constraints

- All code follows `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md`. Feature widgets take colors only from `context.colors`, radii from `AppRadius`. Every user-facing string in both `intl_en.arb` and `intl_ru.arb`; `flutter pub get` regenerates.
- Packages, verbatim: `desktop_drop: ^0.9.2`, `pasteboard: ^0.6.0` (checked on pub.dev 2026-11-04; not discontinued).
- `launch.json`: path `<project>/.vscode/launch.json`; comments `//` and `/* */` and trailing commas accepted; only `"type": "dart"` with `"request": "launch"`; `${workspaceFolder}` → the project folder; any other `${…}` or a `cwd` other than the project folder → the config is listed disabled with the reason; "Create launch.json" writes exactly `{"version": "0.2.0", "configurations": []}` + newline.
- Arg split: `--flavor X` / `--flavor=X` → flavor; `--dart-define X` / `--dart-define=X` → define; `-d X` / `--device-id X` / `--device-id=X` → device; `--debug` / `--profile` / `--release` → mode; everything else stays in the extra args, in order. `deviceId` and `flutterMode` keys → device and mode; `env` → added to the `flutter run` environment.
- Selected configuration stored per project by name in drift `run_configs.selectedConfig` (`null` = Default), schema v10; dump/steps/generated migrations as in M5 (`drift_schemas/`, `database.steps.dart`, `test/generated_migrations/`). A name that is no longer in the file → Default; two configs with the same name → the first.
- Queue: ⌘↵ queues only while the chat status `isBusy`; plain Enter does nothing while busy; ⌘↵ when idle = send. Hint text `⌘↵ Queue` / `⌘↵ В очередь`; busy placeholder "The agent is working — ⌘↵ queues your message" / «Агент работает — ⌘↵ поставит сообщение в очередь». After a turn ends with `idle` → send the next; with `error`, `needsAuth`, or after a user Stop → pause ("Queue paused" / «Очередь на паузе», "Send next" / «Отправить следующее»).
- Drop: images are `png`, `jpg`, `jpeg`, `gif`, `webp`; at most 10 images per message, 5 MB each; image block `{"type": "image", "mimeType": <mime>, "data": <base64>}` after the text; outside-project paths as plain text, wrapped in backticks when they contain whitespace.
- After every task: `flutter analyze` → No issues found; `flutter test` → all pass. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. ⌘↵ while a permission request waits (status `awaitingPermission`) — the message is queued, the permission is NOT answered (Task 4 test).
2. A queued message of chat A while the user switches to chat B — it is sent when A's turn ends, into A, never into B (Task 4 test).
3. A drop while the caret is in the middle of the text — inserted at the caret with a separating space, the rest kept (Task 5 test).
4. A config whose `--dart-define-from-file` path is relative — passed unchanged, `flutter run` runs in the project folder (Task 2 test).
5. `launch.json` edited while the menu is closed — the next start uses the new args without reopening anything (Task 2 test).

---

### Task 1: The launch.json reader

**Files:**
- Create: `lib/src/feature/app_run/models/launch_config.dart`, `lib/src/feature/app_run/data/launch_config_reader.dart`
- Test: `test/feature/app_run/launch_config_reader_test.dart`, fixture `test/fixtures/launch_json/user_launch.json` (the user's file from the spec request, verbatim, trailing commas included)

**Interfaces:**
- Produces:
  - `@freezed LaunchConfig({required String name, String target = 'lib/main.dart', String? flavor, List<String> dartDefines, String extraArgs, String? deviceId, BuildMode? mode, Map<String, String> environment, String? unsupported, bool hasPreLaunchTask})` — `extraArgs` joined so the existing `splitArgs` gives back the remaining args (quote args containing spaces); `unsupported` is the reason when the config can't run.
  - `sealed class LaunchConfigs` — `LaunchConfigsMissing()`, `LaunchConfigsUnreadable(String reason)`, `LaunchConfigsRead(List<LaunchConfig> configs)`.
  - `Future<LaunchConfigs> readLaunchConfigs(String projectRoot)` and the pure `LaunchConfigs parseLaunchConfigs(String text, {required String projectRoot})`.
  - `String launchJsonPath(String projectRoot)`; `Future<void> createLaunchJson(String projectRoot)` (creates `.vscode/` and the file per Global Constraints; never overwrites).

- [ ] **Step 1: Write the failing tests:** `the user's launch.json gives seven configs in order with their flavor, file-define in extra args and device` (assert the `--dart-define-from-file=config/avera/production.json` stays in `extraArgs`; `Run DEV Web Server (Debug)` has `deviceId: 'web-server'`); `comments and trailing commas are accepted`; `other types and attach requests are skipped`; `${workspaceFolder} in program and cwd is the project folder`; `another variable makes the config unsupported with its name`; `a cwd outside the project is unsupported`; `deviceId and flutterMode keys`; `--release in args sets the mode`; `--flavor=x and --flavor x both`; `env is kept`; `preLaunchTask is flagged`; `invalid JSON is unreadable with the parser message`; `no file is missing`; `createLaunchJson writes the empty file and never overwrites`.
- [ ] **Step 2: Run** `flutter test test/feature/app_run/launch_config_reader_test.dart` — FAIL.
- [ ] **Step 3: Implement** (JSONC: strip comments outside strings, drop commas before `]`/`}` outside strings, then `jsonDecode`); `dart run build_runner build`.
- [ ] **Step 4: Run** the test, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): read launch.json configurations`.

### Task 2: Selected configuration and the start call

**Files:**
- Modify: `lib/src/common/database/tables/run_configs_table.dart` (+ `selectedConfig`), `database.dart` (v10, `from9To10`), regenerate steps, `drift_schemas/drift_schema_v10.json`, `test/generated_migrations/`
- Modify: `lib/src/feature/app_run/data/run_config_repository.dart`, `lib/src/feature/app_run/data/app_run_repository.dart` (`start` gains `Map<String, String> environment = const {}`, merged over the shell environment), `lib/src/feature/app_run/controller/run_controller.dart`
- Test: `test/feature/app_run/run_config_repository_test.dart`, `test/feature/app_run/run_controller_test.dart`, `test/feature/app_run/app_run_repository_test.dart`, the migration test

**Interfaces:**
- Consumes: `LaunchConfig`, `readLaunchConfigs` (Task 1).
- Produces:
  - `IRunConfigRepository`: `Stream<String?> watchSelected(int projectId)`, `Future<void> saveSelected(int projectId, String? name)`.
  - `RunViewState` gains `String? selectedConfig` (`null` = Default) and `LaunchConfigs? launchConfigs` (last read).
  - `RunController`: `Future<void> refreshConfigs()` (re-reads the file for the current project); `void chooseConfig(String? name)` (saves the choice; when the config has a device or mode, `choose(deviceId:, mode:)` with them); `startArgumentsFor(...)` used by the start path: Default → today's `RunArguments` + `target`; a config → re-read the file right before start (Review Focus #5), then its flavor/defines/extraArgs/target/environment (the project's Default arguments are NOT added to a config run).
  - A selected config that is gone after a re-read → `selectedConfig` becomes `null` and the choice is saved as Default.

- [ ] **Step 1: Write the failing tests:** repository `selection round-trips and null is Default`; migration `v9 → v10 keeps run args and adds selectedConfig null`; controller `choosing a config with a device switches the device chip`, `the chip stays switchable after choosing`, `a vanished config falls back to Default`, `two configs with the same name use the first`; start `a config run passes its flavor, defines, extra args and target, not the Default args`, `env reaches the flutter process environment`, `a relative --dart-define-from-file is passed unchanged and the working directory is the project` (Review Focus #4), `editing launch.json between starts uses the new args` (Review Focus #5).
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; regenerate drift and freezed.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): selected run configuration per project`.

### Task 3: The split Run button

**Files:**
- Create: `lib/src/feature/app_run/widgets/run_split_button.dart`
- Modify: `lib/src/feature/app_run/widgets/run_header.dart`, `lib/src/feature/app_run/widgets/run_tab.dart`, `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (open a file in the editor already exists: `openRunFile` / `openPath`), both arb files
- Test: `test/feature/app_run/run_split_button_test.dart`, `test/feature/app_run/run_tab_test.dart`

**Interfaces:**
- Consumes: `RunController.chooseConfig/refreshConfigs`, `RunViewState.selectedConfig/launchConfigs` (Task 2); `createLaunchJson`, `launchJsonPath` (Task 1).
- Produces: `RunSplitButton({required String label, required bool enabled, String? disabledReason, required VoidCallback onRun, required List<AppMenuSection<String?>> menu, required ValueChanged<String?> onSelected, required VoidCallback onOpenLaunchJson})` — the main part runs, the ▾ part opens the menu (call `refreshConfigs` before showing it). Label `▶ Запустить · <name>` / `▶ Run · <name>` (ellipsized; full name in the tooltip); Default shows just `▶ Запустить`. Menu: Default, then the configs (disabled ones with `unsupported` as subtitle; `hasPreLaunchTask` subtitle "pre-launch task is skipped" / «задача перед запуском пропускается»), then "Open launch.json" or "Create launch.json"; `LaunchConfigsUnreadable` → one disabled row "launch.json can't be read: <reason>" / «launch.json не читается: <причина>». While running, Stop stays as today (the ▾ still opens the menu). A config device not among the connected devices → disabled with "Device <id> isn't available" / «Устройство <id> недоступно».

- [ ] **Step 1: Write the failing tests:** `label shows the selected config`; `tap runs, ▾ opens the menu with Default and the configs`; `choosing a config calls chooseConfig`; `unsupported config is disabled with its reason`; `unreadable file shows one row`; `missing file offers Create launch.json, which writes it and opens it`; `existing file offers Open launch.json`; `config device not connected disables Run with the reason`; `while running the main part is Stop and the menu still opens`; RU strings render.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(app_run): split Run button with launch.json configurations`.

### Task 4: The message queue

**Files:**
- Create: `lib/src/feature/chat/controller/chat_queue_controller.dart`, `lib/src/feature/chat/widgets/chat_queue_view.dart`
- Modify: `lib/src/feature/prompt_sending/widgets/prompt_composer.dart` (⌘↵, hint, busy placeholder), `lib/src/feature/chat/widgets/chat_config_widget.dart` (owns the queue controller per chat, `queue()` next to `send()`), `lib/src/feature/chat/widgets/chat_screen.dart`, `lib/src/feature/app_close/data/app_close_repository.dart` + its guard (count chats with queued messages as busy for the quit question), both arb files
- Test: `test/feature/chat/chat_queue_controller_test.dart`, `test/feature/prompt_sending/prompt_composer_test.dart`, `test/feature/chat/chat_queue_view_test.dart`, `test/feature/app_close/app_close_repository_test.dart`

**Interfaces:**
- Produces:
  - `QueuedPrompt({required String text, required List<Map<String, Object?>> resources})` (value class; resources as `promptFor` built them at queue time, images included once Task 5 lands).
  - `ChatQueueController` (control `StateController<ChatQueueState>`; state: `List<QueuedPrompt> items`, `bool paused`): `void add(QueuedPrompt)`, `QueuedPrompt? edit(int index)` (removes and returns it), `void remove(int index)`, `void sendNext()`; it follows the chat's `ValueListenable<SessionStatus>`: a busy → `idle` move with items and not paused sends the first (`IPromptSendingRepository.send`); busy → `error`/`needsAuth`, or a Stop the user pressed (the chat calls `pauseAfterStop()` from `stop()`), sets `paused`. One instance per chat, disposed with the chat widget; it never sends into another chat (Review Focus #2).
  - A process-wide `ChatQueueRegistry` (or a counter on an existing app-wide service) so `AppCloseRepositoryImpl.busyChats` also counts chats whose queue is not empty.
  - `PromptComposer`: new `bool busy` and `VoidCallback onQueue`; ⌘↵ with non-empty text: `busy` → `onQueue`, else `onSend`; ⌘↵ never answers a waiting permission (Review Focus #1); the hint and the placeholder per Global Constraints.

- [ ] **Step 1: Write the failing tests:** composer `⌘↵ while busy queues and plain Enter does nothing`, `⌘↵ when idle sends`, `⌘↵ during awaitingPermission queues and does not accept the permission`, `the hint shows only while busy with text`, `the busy placeholder`; controller `a turn ending idle sends the first queued, then the next after its turn`, `error and needsAuth pause`, `a user stop pauses`, `send next resumes`, `edit returns the item and removes it`, `remove`, `a queue of chat A is never sent into chat B` (two chats, Review Focus #2); view `rows with first line and attachment count, ✎ and ✕, paused banner`; app close `queued messages count as busy`.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(chat): queue messages with ⌘↵ while the agent works`.

### Task 5: Dropping files, images, and the docs

**Files:**
- Modify: `pubspec.yaml` (`desktop_drop: ^0.9.2`, `pasteboard: ^0.6.0`), macOS entitlements only if the packages require it (check their README)
- Create: `lib/src/feature/chat/widgets/chat_drop_target.dart`, `lib/src/feature/prompt_sending/models/composer_image.dart`, `lib/src/feature/prompt_sending/widgets/image_chips.dart`
- Modify: `chat_config_widget.dart` (drop insertion at the caret; image list; images into `promptFor` resources), `prompt_composer.dart` (chips above the text, ⌘V image paste), `lib/src/feature/chat/models/chat_transcript.dart` + `chat_item.dart` (`UserMessageItem.images`), the user message widget (thumbnails), `lib/src/feature/agents/models/agent_probe_result.dart` + `agent_probe.dart` (+ `image` from `promptCapabilities.image`), `AgentInfo` (`acceptsImages`: Claude, Codex, Gemini `true`; custom from the probe), both arb files
- Modify (docs): `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` ("## Round 1 follow-ups" from deferred review notes), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (§3.4 the composer: queue, drop, images; the Run tab: the split button and configurations)
- Test: `test/feature/chat/chat_drop_target_test.dart`, `test/feature/prompt_sending/image_chips_test.dart`, `test/feature/chat/chat_transcript_test.dart`, `test/feature/agents/agent_probe_test.dart`

**Interfaces:**
- Consumes: `QueuedPrompt` (Task 4) — queued prompts keep their image blocks.
- Produces:
  - `ComposerImage({required String name, required String mimeType, required Uint8List bytes})`; `List<ComposerImage>` on the chat (cleared on send/queue).
  - `DropClassification classifyDrop(List<String> paths, {required String projectRoot})` → for each path: `DropMention(String relative, {bool folder})`, `DropAbsolute(String path)`, `DropImage(String path)`; the chat inserts mentions/paths at the caret (Review Focus #3) and loads images (size check, limit check, agent check).
  - Prompt resources: image blocks per Global Constraints after the text/resource blocks.

- [ ] **Step 1: Write the failing tests:** classify `project file → @relative`, `project folder → @relative/`, `outside file → absolute`, `outside path with spaces → backticks`, `image extension → image`, `several in drop order`; insertion `a drop with the caret mid-text inserts there with a space and keeps the rest` (Review Focus #3); images `chips show and ✕ removes`, `over 5 MB refused with one line`, `the 11th refused`, `agent without images refuses`, `⌘V pastes an image from the clipboard` (fake the pasteboard read behind a small interface), `send puts image blocks after the text`, `queue keeps the images`; transcript `image blocks become thumbnails in the user message`; probe `promptCapabilities.image is read`; drop overlay `dragging over the chat shows the drop hint` (simulate through the `DropTarget` callbacks).
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; `flutter pub get`; update the docs.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean. Run the app once (`flutter run -d macos`) only if a package needs native setup, and note it in the report.
- [ ] **Step 5: Commit** `feat(chat): drop files and images into the chat`.
