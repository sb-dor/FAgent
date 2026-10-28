# UI foundation — deferred follow-ups

Minor findings from the task and final reviews of docs/superpowers/plans/2026-10-28-ui-foundation.md that were not fixed. Pick them up in the stage that touches the code.

- **Task 1:** AppTheme.light()/dark() rebuild ThemeData each call (memoise)
- **Task 1:** light switch off-state low contrast (white thumb on #E3E6EA, no outline)
- **Task 1:** only 4 textTheme styles set; other M3 styles default (16/14 px)
- **Task 1:** seed-derived secondary/tertiary/surfaceTint not from tokens
- **Task 1:** tests don't cover text sizes, AppText.mono, font registration, full lerp
- **Task 1:** ok/warn on soft backgrounds ~3.8–3.9:1 (spec values) — use for bold/badges only
- **Task 2:** hardcoded shadow color Color(0x1F000000) in app_menu.dart
- **Task 2:** app_menu.dart <-> selector_chip.dart import cycle for AppTone (plan-mandated location)
- **Task 2:** doc ref [AppMenu] should be [showAppMenu]; initial highlight not scrolled into view; hover steals highlight on keyboard scroll
- **Task 2:** sections: const [] opens empty box; window narrower than width+16 constraint; testApp now applies AppTheme by default; extra in-memory DBs per test
- **Task 2:** placement tests find the card via DecoratedBox ancestor .last (brittle); tall-menu test chip centered so larger-side choice weakly tested
- **Task 3:** AppCard wrap not asserted; StatusPill/selected/badge-hidden/PreviewBadge colors untested
- **Task 3:** PaneTabs separator uses tab != tabs.last identity (use index) — latent bug with identical const tabs
- **Task 3:** Colors.white in pane_tabs badge; KeyValueGrid overflows < ~136 px; SegmentedControl Row no wrap/scroll
- **Task 3:** local `theme` is a TextStyle in segmented_control; StatusDot no semantics; redundant @comingInMilestone in intl_ru.arb
- **Task 4:** width clamped on read only (NaN in update would make jsonEncode throw); no rollback on write failure; startup flash of system theme/locale; whole MaterialApp rebuild on any settings change
- **Task 4:** echo filter in AppSettingsController never clears if an update value doesn't survive fromJson normalization (width outside 340–560, NaN, Locale with country) — later DB emissions ignored. Task 5 must clamp width before update. Fix: compare normalized values or clear on first emission after write.
- **Task 4:** failed first load leaves update failing for the session; dispose doesn't complete _firstLoad (pending update hangs); second watch() shows defaults until emission
- **Task 5:** VerticalDivider uses colorScheme.outlineVariant not context.colors.border (workspace_widget.dart:77)
- **Task 5:** comingInMilestone('UI stage 4'/'UI stage 6') puts English into ru text — move to arb
- **Task 5:** ⌘\ ⌘J active on Skills/Settings (invisible toggles); ⌘, on Settings resets section; composer focus not restored after returning to chat
- **Task 5:** hidden chat still relayouts on every change (Offstage); right pane listens to settings twice
- **Task 5:** MainMenu.xib binds ⌘, (Preferences) and ⌘J (Jump to Selection) — verify in the running app that Flutter gets them
- **Task 5:** drag accumulates past the cap (pointer must travel back over the overshoot)
- **Task 6:** status dot read at build (appears after next DB write); createChat hardcodes 'claude' vs defaultAgentId; unused watchSessions(projectId); collapsed state lost on ⌘\ (doc comment wrong)
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
