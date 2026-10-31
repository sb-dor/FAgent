# UI foundation — deferred follow-ups

Minor findings from the task and final reviews of docs/superpowers/plans/2026-10-28-ui-foundation.md that were not fixed. Pick them up in the stage that touches the code.

- **Task 1:** AppTheme.light()/dark() rebuild ThemeData each call (memoise)
- **Task 1:** light switch off-state low contrast (white thumb on #E3E6EA, no outline)
- **Task 1:** only 4 textTheme styles set; other M3 styles default (16/14 px)
- **Task 1:** seed-derived secondary/tertiary/surfaceTint not from tokens
- **Task 1:** tests don't cover text sizes, AppText.mono, font registration, full lerp
- **Task 1:** ok/warn on soft backgrounds ~3.8–3.9:1 (spec values) — use for bold/badges only
- **Task 2:** app_menu.dart <-> selector_chip.dart import cycle for AppTone (plan-mandated location)
- **Task 2:** hover steals highlight on keyboard scroll
- **Task 2:** window narrower than width+16 constraint; testApp now applies AppTheme by default; extra in-memory DBs per test
- **Task 2:** placement tests find the card via DecoratedBox ancestor .last (brittle); tall-menu test chip centered so larger-side choice weakly tested
- **Task 3:** AppCard wrap not asserted; StatusPill/selected/badge-hidden/PreviewBadge colors untested
- **Task 3:** PaneTabs separator uses tab != tabs.last identity (use index) — latent bug with identical const tabs
- **Task 3:** Colors.white in pane_tabs badge; KeyValueGrid overflows < ~136 px; SegmentedControl Row no wrap/scroll
- **Task 3:** local `theme` is a TextStyle in segmented_control; StatusDot no semantics; redundant @comingInMilestone in intl_ru.arb
- **Task 4:** state is not rolled back on write failure (only the intended base is); startup flash of system theme/locale; whole MaterialApp rebuild on any settings change
- **Task 4:** failed first load leaves update failing for the session; second watch() shows defaults until emission
- **Task 5:** VerticalDivider uses colorScheme.outlineVariant not context.colors.border (workspace_widget.dart:77)
- **Task 5:** comingInMilestone('UI stage 4'/'UI stage 6') puts English into ru text — move to arb
- **Task 5:** ⌘\ ⌘J active on Skills/Settings (invisible toggles); ⌘, on Settings resets section; composer focus not restored after returning to chat
- **Task 5:** hidden chat still relayouts on every change (Offstage); right pane listens to settings twice
- **Task 5:** MainMenu.xib binds ⌘, (Preferences) and ⌘J (Jump to Selection) — verify in the running app that Flutter gets them
- **Task 5:** drag accumulates past the cap (pointer must travel back over the overshoot)
- **Task 6:** status dot read at build (appears after next DB write); unused watchSessions(projectId); collapsed state lost on ⌘\ (doc comment wrong)
- **Task 6:** ⌘N test can't catch the selected-chat rule; onError color via colorScheme; O(n²) group sort; ⌘N on Skills/Settings stays on page; no-project ⌘N silent; hover-only group "New chat" not keyboard reachable; placeholder text while projects exist; ordering tests thin
- **Task 6:** ms-scale race between busy check and delete (a losing prompt fails at the journal write, nothing sent); idle opened sessions of a removed project stay in the hub until app close (needs hub close(sessionId))
- **Task 7:** dialog widget constructs ChatSearchRepositoryImpl/controller itself (house style: config widget); no re-entrancy guard on openChatSearch
- **Task 7:** Enter can pick a stale row while the next query runs; hover vs keyboard highlight fight; full-table read per keystroke; Enter swallowed (IME)
- **Task 7:** tests miss ↑, Enter-with-no-results, empty-title row, sidebar tap, 560 width, focus return; "'" assertion trivially empty; "Untitled" not searchable
- **Task 8:** ModalBarrier veil is bg@70% (near-white in light theme); text@38% would match the old dimming in both themes — needs an eye check
- **Task 8:** delete-project FilledButton label on danger now from theme — confirm onError contrast in dark theme (light-on-#F06A5F ≈ 3:1)
- **Task 8:** pending permission card background now solid warnSoft (was tertiaryContainer @45%) — needs an eye check; visual pass (light/dark, sizes, shortcuts) not done by anyone
- **Final review:** isDisposed check order in AppSettingsController.update; chat area briefly shows "Open a project…" while projects load.
- **Open:** no visual pass of the running window yet (light/dark, 900×600 and 1280×800, title-bar drag and traffic-light inset, ⌘, and ⌘J vs MainMenu.xib, close veil, warnSoft permission card).

## Stage 3 follow-ups

Deferred from the reviews of docs/superpowers/plans/2026-10-30-ui-stage3-chat-composer.md.

- **AppMenu:** hovered row steals highlight after filtering; empty titled section keeps header; ArrowDown clamp-vs-wrap untested
- **Defaults:** stale byAcpId entry if a chat goes terminal mid-create; config_option_update during the DB write is overwritten by session/new options; unknown defaultAgentId not validated; const AppSettings constructor doesn't sanitize bypass
- **Composer toolbar:** disabled chips look enabled; "make default" gives no feedback and can be dropped during a set; two "Agent" chips when the agent has an `agent` option; effort segments shrink below 12 px; `_selectMode` uses context after await without a mounted check; chat_screen imports workspace footer for agentDisplayName
- **Slash menu:** dismissed state stores offset only; mid-text insert can leave a double space; app command descriptions chosen by a name switch
- **Feed:** DiffView still uses Menlo; thought duration may be 0 on replayed history; pills are rectangular; overlapping mention ranges if a path contains " @"
- **Permission card:** no focus move to the composer when a request arrives; prompt_composer.dart is ~370 lines (split candidate)
- Choosing model/mode before the first message: chips are disabled until the agent session exists — start the session when a chat opens, or queue the choices and apply them like defaults.

## Stage 4 follow-ups

Deferred from the reviews of docs/superpowers/plans/2026-10-30-ui-stage4-right-pane.md. Paths are under `lib/src/feature/`.

- **Bugs and risks:**
  - Changes: "Open file" is also shown for directory entries (check `FileSystemEntityType.file`); symlink resolution and other FS calls are synchronous on every refold
  - Changes: file order is lost after each turn (alphabetical within a turn); a rename plus an edit shows two entries; refold and rebuild on every chunk (`ChangedFile` has no equality)
  - Changes: the diff handle stays stale if a chat leaves Completed; multi-diff edits open `diffs.first`
  - Run: `choose` can't clear the device; a chosen device leaving the list keeps ▶ enabled with a stale id; `pickWidget` works with nothing running
  - Run: subscriptions may leak if disposed mid-watch (check `isDisposed` after await); run streams have no `onError`; failed run actions are not surfaced; `RunFailed` is never emitted by the fake
  - Run: restart doesn't clear the log buffer (`errorCount` accumulates); `clearLogs` assumes increasing `seq` (document it in the interface) and leaves `_atBottom` false while scrolled up
  - Run: replaying the log is 2000 separate events, O(n²) copies and a `setState` per line (batch it); every log line also costs a full-list copy, filter and badge rebuild; mentions scan the whole log per line
  - Run: the badge shows a stale project's errors when `projectId` becomes null; brief idle flash on a project switch
  - Run: `RunTab` is keyed by project, so returning to a project whose pick is still pending loses the "Tap a widget…" hint (the widget still arrives) — revisit with the real inspector (M6)
  - Title bar: `PreviewBadge` adds ~60 px to the run controls; the chat title shrinks with an ellipsis, but no narrow-window test covers it
  - Run: one publish per frame could miss a fast running-to-idle change (document it); search skips `error.message`
  - Run: `RunActionsController` is a single Droppable: Stop pressed within a reload/start is dropped silently, and a pending real pick would block Stop/reload/Start everywhere — split pick into its own controller and never drop stop (matters once the real runner lands, M2) (`app_run/controller/run_actions_controller.dart:25-28`)
  - Run: `RunTab` re-implements start/stop/reload/restart and active/canStart beside `WorkspaceRunLink` and trusts `widget.projectId` over `run.state.projectId` — pass the runLink callbacks/flags in (`app_run/widgets/run_tab.dart:96-124`, `run_header.dart:79-80`)
  - Run: removing a project leaves its run running with no way to stop it — stop the run on removal or treat building/running as `ProjectBusyException` (M2) (`workspace/widgets/workspace_config_widget.dart:340-344`)
  - Changes: `ChangesTab` reads `WorkspaceConfigInhWidget` directly (changes_pane depends on workspace) — pass selectedPath/onSelect/onOpenFile/projectRoot from `WorkspaceRightPane` like `RunTab` (`changes_pane/widgets/changes_tab.dart:19`)
- **Test gaps:**
  - Changes: no tests pin post-frame coalescing, `selectedChangePath` reset or the chat-to-chat handle reset; reveal is untested; the '+2' test finds the `DiffView` header, not the list counter; icon-count asserts in the plan tests are weak
  - Run: no restart-during-build test; two weak tests in the controller; the timer, To-agent filter and pick tests are weak; fixed real-time waits (Changes tests use real 100 ms delays)
  - Run to chat: the shortcut test doesn't assert composer focus; the disabled ⚡ state is not asserted
- **Polish:**
  - Changes header: chevron `IconButton` taller than the header (status icon alignment), `iconSize` 18, default icon color; `Tooltip('')` is possible; `_Entry.shown` doc says "first" but keeps the latest
  - Plan card: status strings are duplicated with `PlanCard` (add `PlanEntry` getters or an enum); the `in_progress` spinner keeps spinning on a dead session
  - Run: misplaced doc comment (`markSent`/`setPicked`); screenshot row filters only on the English word; detail 'M2' is overloaded
  - Off-grid spacing: Changes 10/6 and `labelSmall`, Plan 2/18, Run 10/6/5/3 and a 26 px row, run-to-chat 6/2/10
  - `prompt_composer.dart` grew from 385 to 392 lines (the "From the run" section lives in a separate file; keep it out of the composer)
  - Formatting: `app_text`, `app_theme`, `app_menu`, `workspace_page_scaffold` and `app_theme_test` are not dart-formatted on the branch
- **Rulings recorded during the stage** (revisit if they cost too much):
  - "Open file" never executes an agent-created file: `openPath` uses `open -t`, refuses relative or missing paths (binary files open in a text editor)
  - Symlinked roots are compared after `resolveSymbolicLinksSync` so git's resolved root and the agent's paths merge (one extra stat per path per refold)
  - The run keeps a per-project ring buffer (up to `kRunLogLimit`) and replays it on `logs()` subscribe, including `sentToAgent` flags (up to 2000 lines of memory per project)
  - On a project switch the selected device stays while the target resets to `lib/main.dart` and the mode to debug; the device default lives in the window (first running device when the project has none)
  - `RunController.choose({deviceId, mode, target})` instead of `select`; the last picked widget lives in `RunViewState.picked` and is cleared on a project switch
  - New `onAccent` token in `AppColors` for content on accent fills (light #FFFFFF, dark = dark bg #16181B)
  - "@ from the run" sits above files in the mention menu (the mockup shows it below); ⚡ in the title bar stays visible but disabled while the app is not running

## Stage 5 follow-ups

Deferred from the reviews of docs/superpowers/plans/2026-10-30-ui-stage5-skills.md. Paths are under `lib/src/feature/`.

- **Bugs and risks:**
  - Library controller: `_watching` is set before `listen`, so a sync throw makes a retry with the same args a no-op; the error callback emits `failed` without `projectId` (`skills/controller/skill_library_controller.dart`)
  - Library: a project removed from the app stays watched by the window controller (`workspace/widgets/workspace_config_widget.dart`)
  - Repository: `lastSnapshot` is set before the rebuild, so a failed rebuild is not retried until files change; the watcher is registered before the initial states load, so the first emission has everything enabled; the drift `skill_states` listen has no `onError` (`skills/data/skills_repository.dart`)
  - Repository: `importFolder` does not apply the name rule (`My Skill` becomes an invalid id) (`skills/data/skills_repository.dart`)
  - Frontmatter: a UTF-8 BOM before `---` reads as no frontmatter; an unquoted `version: 1.10` becomes `1.1` (YAML float) (`skills/data/frontmatter.dart`)
  - Screen: with a projects `ErrorState` the library watches globally but `view.projectId` stays set (the Project source shows 0, the switch writes per project while rows show global); `setEnabled` failure shows nothing (`skills/widgets/controllers/skills_view_controller.dart`, `skills/widgets/skills_list.dart`)
  - Screen: a double Esc can open two discard dialogs
  - Screen: the name dialog reacts to any action's completed/failed (track its own submit); editor Save looks enabled while another action runs
  - Screen: "Try in chat" sends `/name` to a chat of another project (`skills/widgets/skills_config_widget.dart`)
  - Chat: skills can fill the / menu's 12 rows before app commands (cap the section); `ChatSkills.of` is recomputed on every run notification; menu F footer link is not keyboard-reachable (`prompt_sending/models/slash_commands.dart`, `skills/widgets/chat_skills_chip.dart`)
  - Scanner: it follows symlinks and walks hidden folders before filtering them out; walk by hand (skip hidden directories, do not follow links, cap the number of entries) (`skills/data/knowledge_scanner.dart`: `snapshotRoot`, `_listInto`)
  - Duplicate: a skill whose `SKILL.md` is a symlink cannot be duplicated (`copyDirectory` skips links, the copy fails with a generic error and is removed); copy the resolved targets (`skills/data/knowledge_copy.dart`)
  - Editor: saving writes a temp file and renames it, which resets the file's mode and extended attributes and needs a writable folder (`skills/data/skills_repository.dart` `write`)
  - Editor: an outside deletion of the open item still drops its unsaved edits
  - Frontmatter: keys are stringified with `'${entry.key}'`, so a YAML complex key (`? *alias`) can still expand — accept only `String` keys (`skills/data/frontmatter.dart`)
  - Enablement: `skill_states` rows outlive the deleted item, so a skill re-created under the same name starts with the old state (`skills/data/skill_states.dart`)
- **Test gaps:**
  - Builtin: the failed-load-not-cached branch of `AssetBuiltinKnowledge` is untested; the builtin test hard-codes counts and won't catch a skill folder missing from the pubspec assets (compare with the directory listing)
  - Repository: the cancel test doesn't prove the timer stops (count `builtin.load` calls)
  - Controllers: the init step is untested
  - Screen: the failed-switch test calls `actions.setEnabled` instead of tapping the row; no RED recorded for the card tests; the name dialog's `removeRoute` branch is unreachable and untested
- **Polish:**
  - Names: `SkillActionsState` and `SkillTextState` lack doc comments
  - Skills widgets: `_SourceItem` duplicates `_NavItem` (~50 lines); `':project:'` string matching in `SkillsViewController`; a source filter un-highlights the Skills/Rules section (the mockup keeps it; `''` sentinel)
  - Design: `Colors.transparent` in `skill_list_tile` and `skills_navigation` (existing convention); off-grid spacings and `fontSize` 10 in `source_tag`; vertical 6 padding in `skill_card`
- **Rulings recorded during the stage** (revisit if they cost too much):
  - Widget tests never use the real file-IO repository: `test/support/memory_skills_repository.dart` (`MemorySkillsRepository`) is `testDependencies`' default; the real repository is tested in plain `test` with temp dirs (real IO and polling timers hang or leak in fake-async `testWidgets`)
  - Project items resolve against an explicit root, not repository state: `read`, `write` and `duplicate` take `projectRoot`; a project id without it throws `KnowledgeNotFoundException`; controllers pass the root per call, and two live watches for different projects (window and Skills screen) are expected
  - Enablement of project items is per project only: `setEnabled(projectId: null)` on a `*:project:*` id throws `ArgumentError`, the card shows only the screen-project switch (ids carry no project, a global row would leak across projects sharing a skill name)
  - Sync `stat`/`exists`/`type` calls are accepted in the scanner (`avoid_slow_async_io` is an error and must not be silenced); "all IO async" means listing, reads, writes and copies
  - `MemorySkillsRepository.setEnabled` follows `setSkillEnabled`: global replaces and drops equal exceptions, a project value equal to global removes the row, project ids refuse global
  - One model `KnowledgeItem` (skill or rule) instead of `Skill`/`Rule`, one `watch` stream instead of `watchSkills`/`watchRules`; list order is the source enum, then name, in both repositories
  - Card minimum 400 px holds: the window minimum is 900x600, so the card is at least 523 px with the rail and 559 px at 1100 with the 220 px nav
  - Leaving the Skills screen with unsaved edits via "← Back to chat" or Esc asks the same discard question as a selection change; other exits are deferred (see above)
  - Git sources show only "＋ Add source…" with Preview and no fake skills; menu F has no per-chat choice until M3; skill folders are polled every 2 s; "Try in chat" and `/name` work for project skills only until M3
  - `claude-agent-acp` titles a Skill tool call `Load skill: <name>` with kind `other` (`SkillReporter`), which `skill_call.dart` relies on

## Stage 6 follow-ups

Deferred from the reviews of docs/superpowers/plans/2026-10-31-ui-stage6-settings.md. Paths are under `lib/src/feature/`.

- **Bugs and risks:**
  - Agents repository: it has no timeout of its own if a `ProcessRunner` ignores `timeout`; `openSettings` ignores the exit code of `open` and uses `File`/`Directory` directly (only `homeDirectory` is injected); `GroupedProcess.stderrLines` is a broadcast stream and can drop the first stderr lines, so a logout error text may be missing (`agents/data/agents_repository.dart`, `common/process/`)
  - Agents screen: the actions controller lives only while General/Agents is open, so leaving mid-login drops the login output view; an action failure puts the raw exception text in the SnackBar; the "note — " separator is glued in code and not localizable; the default-agent chip shows the raw id `claude` until agents load; each visit re-subscribes and runs one `auth status` probe (`agents/widgets/`, `app_settings/widgets/general_settings_section.dart`)
  - MCP repository: `setEnabled` with a `projectId` does not check that the user server exists (an unknown project is a raw FK error); `importMcpJson` lets `FileSystemException` and a UTF-8 `FormatException` through while the doc says `McpJsonException`; an unknown `type` with a `url` is treated as `http`; the reserved name `dart mcp` is unreachable because the name regex rejects the space (`mcp_servers/data/mcp_servers_repository.dart`, `mcp_json.dart`)
  - MCP screen: the per-project check ignores a user server's global `enabled`; a switch toggled during another action is dropped silently; a Droppable `add` can be dropped while another action runs and the dialog would close on an unrelated `Completed` (`mcp_servers/controller/mcp_server_actions_controller.dart`, `mcp_servers/widgets/`)
  - Permissions: the rename over `settings.local.json` resets the file mode, and an adapter write between the re-read and the rename is lost (inherent to a temp-file rename); a remove failure shows raw English exception text in the SnackBar (`permission_rules/data/permission_rules_repository.dart`, `permission_rules/widgets/`)
  - Flutter section: it waits forever if `ProjectsController` errors while a project is selected; a `doctor()` failure puts the controller into error, which shows the wrong SDK message and disables the doctor button (matters when M4 makes `doctor()` real); the org field reads `projectOrg` only in `initState`, and `copyWith(projectOrg:)` is not validated (the field validates) (`flutter_sdk/controller/flutter_sdk_controller.dart`, `flutter_sdk/widgets/flutter_settings_section.dart`, `app_settings/models/app_settings.dart`)
  - Chat feed: it regroups the whole feed (`groupFeed`) on any settings change, e.g. a pane drag; select the density only (`chat_feed`)
- **Test gaps:**
  - Flaky: `kills what a finished process left running` in `test/feature/agents/agents_repository_test.dart` is a timing-sensitive real-process test and failed once under parallel load; the stray `sleep 1` races the group kill, so under load the kill can land after the marker is written; lengthen the stray's sleep (and the wait) or have it write the marker only after a margin far above the kill latency
  - Agents: `AgentActionsController` has no direct unit tests; `MemoryAgentsRepository.login` finishes before it returns, so widget tests cannot show the in-progress state, and the double hard-codes `0.96.0` instead of `AgentDefinition.claudeAdapterVersion`
  - Settings: the language test cannot show a live UI switch (`testApp` fixes the locale); "agents and MCP show their subtitle" checks only Agents; `onRemoveFailed` of the permissions section is untested; the fvm widget test uses a double instead of a temp-dir project; the MCP repository cancel test proves no delivery after cancel, not that the drift watchers are released
- **Polish:**
  - `SettingsCard` repeats the decoration of `AppCard` (`AppCard` needs a header: make it optional and reuse); the widget `McpServerRow` clashes with drift's `McpServerRow` data class (plan-mandated name; rename one); `McpServersConfigWidget` has an unused `projectsListenable`; `AddMcpServerDialog` takes the whole config state but needs only the actions
  - The "Ask" label beside the quit `Switch` has no semantics link; the extra hint strings `settingsQuitHint` and `settingsDensityHint` can be merged into the row labels if the copy is too long
  - `_onProjects` and `refresh` in the permissions controller duplicate the load block; `SizedBox(height: 2)` in `permissions_settings_section.dart` is off the 4 px grid
- **Rulings recorded during the stage** (revisit if they cost too much):
  - Work happened on branch `ui-stage6` in the main checkout, no extra worktree
  - `AgentLogin` has a `@visibleForTesting` constructor `AgentLogin.forTest` and `addLine`/`finish`, so `MemoryAgentsRepository.login` can return the real class the hub hands out (a test-only API on a production class)
  - `ProcessRunner` takes an optional `timeout`; the default runner starts the process through `GroupedProcess` and kills the whole group on timeout and after the process ends, so a hung `npx auth status` leaves no `node` child behind (a plain `Future.timeout` on `Process.run` would leave it running)
  - The default-agent menu and the model/effort/mode menus come from the `agentOptions` catalog; an empty catalog shows the hint "open a chat with the agent" and no invented lists
  - `mcp_servers` has no `projectId`; `mcp_server_states` holds the per-project "off" switches (a row exists only while the server is off there); built-in servers can only be switched per project
  - Permissions read and edit only `permissions.allow` of `<project>/.claude/settings.local.json`; the shared `.claude/settings.json` is never touched
  - `MemoryAgentsRepository` and a real `McpServersRepositoryImpl` on an in-memory database are the defaults of `testDependencies`; real process and file repositories are tested in plain `test` with temp dirs
  - Preview until a milestone: Codex, Gemini and custom ACP agents (M5), Flutter version and `flutter doctor` (M4), the `git` project template (M4), in-app DevTools (M2), MCP status, tool counts and delivery to the agent (M3)
