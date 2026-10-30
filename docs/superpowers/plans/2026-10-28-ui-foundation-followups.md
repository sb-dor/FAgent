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
- **Composer toolbar:** disabled chips look enabled; "make default" gives no feedback and can be dropped during a set; ⇧Tab before the agent starts moves focus; two "Agent" chips when the agent has an `agent` option; effort segments shrink below 12 px; `_selectMode` uses context after await without a mounted check; chat_screen imports workspace footer for agentDisplayName
- **Slash menu:** dismissed state stores offset only; mid-text insert can leave a double space; app command descriptions chosen by a name switch
- **Feed:** DiffView still uses Menlo; thought duration may be 0 on replayed history; pills are rectangular; overlapping mention ranges if a path contains " @"
- **Permission card:** ↵/Esc hints shown on non-latest pending cards; no focus move to the composer when a request arrives; unused `permissionTitle` key; prompt_composer.dart is ~370 lines (split candidate)
