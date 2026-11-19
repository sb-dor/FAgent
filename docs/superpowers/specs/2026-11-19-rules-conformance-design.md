# The app's own code follows its built-in rules — design

## Why

FAgent gives agents 17 built-in rules (`assets/knowledge/rules/`). The app's own code should follow
them where they apply, so the rules are proven in a real project and the app gets the bugs those
rules prevent. An audit of `lib/` and `test/` against every rule (four reports, 2026-11-19) found
that most of the code already complies; this design covers what does not.

The owner chose: **real bugs first, then structure**. Cosmetic deviations are left out.

## Goals

- Phase 1: fix every real bug or user-visible risk the audit found, each with a test that fails
  before the fix.
- Phase 2: fix the structural deviations that remove real coupling: repositories calling
  repositories, widgets calling a repository, ACP runtime objects crossing the chat repository,
  `Error` thrown for outside failures, expected failures logged as crashes.

## Non-goals

- The folder layout: `lib/src/common/` + `lib/src/feature/` stays (architecture.md allows an
  existing layout).
- The controller state recipe (`idle/processing/successful/error` in controllers.md vs
  `initial/inProgress/completed/error` in AI_INSTRUCTIONS.md): a separate decision by the owner.
- Stateful repositories that own processes (Agents, Devices, AppRun, WidgetPicker, DartAnalysis,
  McpServers, Skills): CLAUDE.md requires them; they stay. Changing the rule text is a separate
  decision.
- Cosmetic: member order (97 classes), file-name prefixes (51), widget-returning helpers (37),
  optional model fields (~84), `extends ChangeNotifier`, `Colors.transparent`, `EdgeInsets` literals,
  `AppMenu` rebuilt on `MenuAnchor`.
- Tests rewritten from real-time waits to `fakeAsync` (144 sites), and repo tooling (Makefile,
  CHANGELOG, CI): separate work.

## Anti-goals

- A behaviour change the user notices other than the fixes listed (no redesign of screens).
- A larger diff than each fix needs; no renames along the way.

## Constraints

- CLAUDE.md and docs/AI_INSTRUCTIONS.md stay the authority for this repo; where a rule conflicts
  with them, CLAUDE.md wins.
- Every visible string goes into both `intl_en.arb` and `intl_ru.arb`.
- `flutter analyze` clean and `flutter test` green after every fix.
- Work happens on a branch `rules-conformance` in a worktree (`.worktrees/rules-conformance`), one
  commit per fix. Nothing goes to `main` or GitHub until the owner says so.

## Approaches considered

1. **Bugs, then structure (chosen).** Phase 1 is small, local fixes with tests; phase 2 the
   structural moves, one feature at a time. Lowest risk, every step ships on its own.
2. Bugs only. Cheapest, but leaves the coupling the rules exist to prevent.
3. Everything the rules cover, cosmetic included. Proves the rules fully, but touches ~300 files for
   little runtime benefit and blocks on the state-recipe decision.

## Phase 1 — bugs and risks

Each item: a failing test first, then the fix.

1. **One error-text function.** `lib/src/common/localization/error_text.dart`:
   `String errorText(Localization lcl, Object error)`, a switch over the app's exception types
   (`FileSystemException`, `ProcessException`, the app's named exceptions); unknown errors give
   `error.toString()` in debug and a generic sentence in release. The 8 widget call sites that show
   `'$error'` use it. New ARB keys in both languages.
2. **A bad row never blocks a feature.** `SessionEventStore._fromRow` skips and logs a row whose
   `origin` or `payload` does not decode; `McpServersRepositoryImpl._fromRow` reads `config` with
   map patterns inside the guarded decode, so one malformed server shows as invalid instead of
   breaking the stream.
3. **Chat title cut by characters.** `agent_hub.dart` cuts the title with
   `characters.take(60)`; the same for tool output (`tool_call_card.dart`) and log lines
   (`app_run_repository.dart`).
4. **MCP probe output decoded leniently.** `mcp_probe.dart` uses
   `Utf8Decoder(allowMalformed: true)` and handles stream errors, like the rest of the app.
5. **LSP JSON read with patterns.** The 15 `json['x'] as T` casts in `dart_completion.dart`,
   `dart_diagnostic.dart`, `lsp_range.dart`, `lsp_connection.dart`, `dart_analysis_server.dart`,
   `config_option.dart` become map patterns; a malformed item is skipped, not the whole response.
6. **Real Flutter doctor in Settings.** `FlutterSdkRepositoryImpl.doctor()` runs `flutter doctor`
   with the project's SDK and parses its `[✓] / [!] / [✗]` lines into `DoctorCheck`s; the hard-coded
   sample goes. Run-error titles (`RunError`) get a kind enum so the widget localizes the title
   (the text sent to the agent stays English).
7. **Theme colors in the diff.** `diff_view.dart` and `pane_tabs.dart` take added/removed/on-accent
   colors from new `AppColors` tokens (light and dark) and radii from `AppRadius`.
8. **Line diff off the UI isolate.** `DiffLinesCache.resolve` computes `LineDiff` in `Isolate.run`
   and the diff view shows a placeholder until it is ready; `SessionEventStore.open` decodes rows in
   `Isolate.run`.
9. **Startup with Retry.** `AppError` gets a Retry button that runs initialization again; each
   step registers how to close what it opened, and a failed step closes them in reverse order; the
   error handlers are installed once; a failed step throws an `InitializationException(step, cause)`
   instead of a string.
10. **Secrets typed by the user.** Env and header values in the custom-agent, MCP-server and
    run-config dialogs are shown obscured with a reveal toggle; the dialogs and the README say the
    values are kept unencrypted in the app's database. `.gitignore` gets the secret-file patterns
    from security.md. (Moving them to the Keychain is left out: large, and the database sits in the
    same trust zone as `~/.claude`.)
11. **Small ones.** `Image.file` in the code view decodes at the pane size (`cacheWidth`);
    `WorkspaceConfigWidgetState` creates the project's `CodeWorkspace` when the project is selected,
    not from a getter read in `build`; `McpServersRepositoryImpl` gets a `dispose` that closes
    `_changed`, called from the shutdown; the window title says FAgent.
12. **Text scaling.** `app.dart` clamps the system text scale to 1–1.5 instead of turning it off.
    The README screenshot test runs once at 1.5 to catch overflow; any overflow it shows is fixed in
    the same step.

## Phase 2 — structure

One commit per feature, tests updated with it.

1. **Expected failures are not crashes.** `ExpectedException` base in `lib/src/common/` (an
   `abstract base class implements Exception`); the app's domain exceptions (invalid server name,
   taken skill name, busy chat, project busy, …) extend it; `ControllerObserver.onError` logs them
   at info and does not pass them to `ErrorUtil`.
2. **Exceptions for outside failures.** The ~10 `StateError`/`UnsupportedError` throws for an
   agent exiting, the app run failing, a closed MCP server and the chat-busy race become named
   exceptions (most of them `ExpectedException`s).
3. **No repository takes another repository**, for the five small cases: Chat→Agents,
   SessionConfig→AppSettings, McpServers→FlutterSdk (the `flutter` path passed as an argument),
   WidgetPicker→AppRun, Agents→CustomAgents (merged into one repository). The controller that needs
   both takes both. `ProjectCreation`: the controller runs open, trust and rules after the creation
   stream completes. `SessionContext`, `ProjectRules` (used by the hub, not a controller) and
   `AppClose` (shutdown plumbing) stay, with the reason in a comment.
4. **Code view widgets go through a controller.** A `DartAnalysisController` (status, restart,
   format) owned by `CodeWorkspace`; the editor widgets take it instead of
   `IDartAnalysisRepository`. `listProjectFiles` moves to a controller.
5. **The chat repository returns the feature's models.** `IChatRepository.open` returns a chat
   snapshot plus a stream of changes instead of the hub's `LiveSession`; raw ACP maps stop crossing
   `IPromptSendingRepository`; `promptFor`/`resourcesFor` move from the config widget into the
   prompt-sending layer.
6. **Small Dart fixes found on the way:** `!` after a check in `agent_hub.dart`,
   `devices_repository.dart` and `chat_transcript.dart` becomes a local or a pattern;
   `Future.wait<Object?>` plus casts in `devices_repository.dart` becomes a record `.wait`;
   `ProjectBusyException` and `OpenPathRefusedException` become `final`.

## Left to the builder

- Exact names of new ARB keys, `AppColors` tokens and exception classes.
- How the diff placeholder looks while the isolate works (a short line in the muted text color is
  enough).
- The order of items inside each phase.

## Calls made without the owner

- Secrets: obscure + notice, not Keychain.
- Flutter doctor: parse the real text output (there is no machine format).
- Text scaling: included in phase 1, checked with the screenshot test at 1.5.
- Phase 2 leaves `SessionContext`, `ProjectRules` and `AppClose` as orchestrating repositories.
