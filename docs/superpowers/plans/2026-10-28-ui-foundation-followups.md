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
  - Run: log filter, search and `_atBottom` carry across projects; the badge shows a stale project's errors when `projectId` becomes null; brief idle flash on a project switch
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
