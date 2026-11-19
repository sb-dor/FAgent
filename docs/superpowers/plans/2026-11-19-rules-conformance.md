# Rules Conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the real bugs the rules audit found (phase 1), then remove the structural coupling the rules forbid (phase 2), without changing anything else the user sees.

**Architecture:** Each task is a local change with its own failing test and its own commit on the branch `rules-conformance`. Phase 1 touches one file group per bug. Phase 2 moves calls between layers one feature at a time; interfaces change, so the fakes in `test/support/` change with them.

**Tech Stack:** Flutter desktop (macOS), Dart 3, `control` state controllers, drift, freezed, gen-l10n.

**Spec:** `docs/superpowers/specs/2026-11-19-rules-conformance-design.md`

## Global Constraints

- CLAUDE.md and `docs/AI_INSTRUCTIONS.md` stay the authority; where a rule conflicts with them, CLAUDE.md wins.
- Every visible string goes into both `lib/src/common/localization/intl_en.arb` and `intl_ru.arb`; `flutter pub get` regenerates them.
- `flutter analyze` clean and `flutter test` green after every task. Do not silence lints.
- Feature widgets take colors only from `context.colors` and radii from `AppRadius`.
- Generated files (`*.g.dart`, `*.freezed.dart`, `generated/`) are regenerated with `dart run build_runner build`, never edited.
- Branch `rules-conformance` in worktree `.worktrees/rules-conformance`, one commit per task. Nothing goes to `main` or GitHub until the owner says so.
- No renames along the way; no diff larger than the fix needs.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not re-run the opt-in real-agent tests in `test/integration/` unless a task says so.

## Review Focus

1. A chat with thousands of journal rows, one of them corrupt, opens; nothing freezes and the good rows show (Task 2 and Task 8 tests).
2. `flutter doctor` that is missing, hangs or exits non-zero gives an error state or a report, never an endless spinner (Task 6 tests).
3. Retry after a failed startup does not open a second database or install the error handlers twice (Task 9 tests).
4. A hidden secret field never shows a value, including lines without `=` or `:` and values containing the separator (Task 10 tests).
5. A diff view that is removed while its isolate still computes does not call `setState` after dispose (Task 8 test).

---

## Task 0: Worktree and documents

- [ ] **Step 1:** From the main checkout: `git worktree add .worktrees/rules-conformance -b rules-conformance main`.
- [ ] **Step 2:** Copy `docs/superpowers/specs/2026-11-19-rules-conformance-design.md` and this plan into the worktree at the same paths, then in the worktree run `flutter pub get` and `dart run build_runner build`.
- [ ] **Step 3:** Run `flutter analyze` and `flutter test > /tmp/baseline.txt 2>&1; tail -5 /tmp/baseline.txt`. Expected: analyze clean, all tests pass. Record the test count in the ledger as the baseline.
- [ ] **Step 4:** Commit the two documents: `git add docs/superpowers && git commit -m "docs: rules conformance design and plan"`. Remove the two untracked copies from the main checkout only after the owner merges.

---

# Phase 1: bugs and risks

## Task 1: One error-text function

**Files:**
- Create: `lib/src/common/localization/error_text.dart`
- Modify: `intl_en.arb`, `intl_ru.arb`; the 8 call sites below
- Test: `test/common/localization/error_text_test.dart`

**Interfaces:**
- Produces: `String errorText(GeneratedLocalization lcl, Object error, {bool debug = kDebugMode})`. Phase 2 Task 13 adds cases to it.
- Ruling made while planning: the switch imports the exception classes from `feature/*/models` and `feature/*/data`, so this one `common/` file depends on features. localization.md asks for a single switch, and the alternative (a localized `describe` on each exception) would make models import Flutter's generated localization. The single switch wins.

Call sites to switch (each keeps its localized wrapper and passes `errorText(...)` instead of `'$error'`):
`agents/widgets/agents_config_widget.dart:76`, `chat/widgets/chat_config_widget.dart:286`, `mcp_servers/widgets/mcp_servers_config_widget.dart:120`, `permission_rules/widgets/permission_rules_config_widget.dart:95`, `workspace/widgets/workspace_config_widget.dart:801` and `:838`, `project_trust/widgets/project_trust_dialog.dart:89`, `project_creation/widgets/creation_progress.dart:86`.

- [ ] **Step 1: Write the failing test**

```dart
final lcl = lookupGeneratedLocalization(const Locale('en'));
test('a file error names the path and the OS reason', () {
  final text = errorText(lcl, const FileSystemException('Cannot open', '/p/a.txt', OSError('Permission denied', 13)));
  expect(text, contains('/p/a.txt'));
  expect(text, contains('Permission denied'));
  expect(text, isNot(contains('FileSystemException')));
});
test('a process that cannot start names the command', () {
  expect(errorText(lcl, const ProcessException('npx', <String>[])), contains('npx'));
});
test('a timeout has its own sentence', () {
  expect(errorText(lcl, TimeoutException('x')), lcl.errorTimeout);
});
test('Flutter not found, a busy chat and a busy project have their own sentences', () { /* one expect each */ });
test('an unknown error is its toString in debug', () {
  expect(errorText(lcl, StateError('boom'), debug: true), contains('boom'));
});
test('an unknown error is a generic sentence in release', () {
  expect(errorText(lcl, StateError('boom'), debug: false), lcl.errorUnknown);
});
test('Russian has every key', () { /* errorText with lookupGeneratedLocalization(Locale('ru')) for each case returns non-empty and differs from English */ });
```

- [ ] **Step 2:** Run `flutter test test/common/localization/error_text_test.dart`. Expected: FAIL, `errorText` not defined.
- [ ] **Step 3:** Add ARB keys `errorFile(path, reason)`, `errorProcess(command)`, `errorTimeout`, `errorFlutterNotFound`, `errorChatBusy`, `errorProjectBusy`, `errorUnknown` (both languages), run `flutter pub get`, implement `errorText` as a `switch` over `FileSystemException` (reason = `osError?.message ?? message`), `ProcessException`, `TimeoutException`, `FlutterNotFoundException`, `ChatBusyException`, `ProjectBusyException`, else `debug ? '$error' : lcl.errorUnknown`.
- [ ] **Step 4:** Switch the 8 call sites; at `workspace_config_widget.dart:801` drop the hand-built `'${somethingWentWrong}: ...'` join and use `errorText`.
- [ ] **Step 5:** Run the new test, then `flutter test test/feature`. Expected: PASS; fix any widget test that asserted the raw `'$error'` text by asserting the `errorText` result instead.
- [ ] **Step 6:** Commit `fix(l10n): show errors through errorText, not their toString`.

## Task 2: A bad row never blocks a feature

**Files:**
- Modify: `lib/src/common/acp/session_event_store.dart:51-57`, `lib/src/feature/mcp_servers/data/mcp_servers_repository.dart:266-280`
- Test: `test/common/acp/session_event_store_test.dart`, `test/feature/mcp_servers/mcp_servers_repository_test.dart`

**Interfaces:**
- Produces: `static SessionEvent? _fromRow(SessionEventRow row)` returns `null` for a row it cannot read (Task 8 calls it from an isolate).

- [ ] **Step 1: Write the failing tests**

```dart
test('a row with an unknown origin or a broken payload is skipped', () async {
  // insert rows seq 0 (good), 1 (origin: 'martian'), 2 (payload: 'not json'), 3 (payload: '[1]'), 4 (good)
  final store = await SessionEventStore.open(database, sessionId);
  expect(store.events.map((e) => e.seq), <int>[0, 4]);
  store.addAgentFrame('agent_message_chunk', <String, Object?>{}); // next seq follows the last stored row
  expect(store.events.last.seq, 5);
});
```
```dart
test('a server whose config has the wrong types still lists', () async {
  // insert one mcp_servers row with config '{"command": 42, "url": [], "args": "x"}' and one good row
  final servers = await repository.watchServers().first;
  expect(servers.map((s) => s.name), containsAll(<String>['broken', 'good']));
  expect(servers.firstWhere((s) => s.name == 'broken').command, isNull);
});
```

- [ ] **Step 2:** Run both test files. Expected: FAIL (`ArgumentError` from `byName`, `TypeError` from the cast).
- [ ] **Step 3:** `_fromRow`: read origin with `SessionEventOrigin.values.asNameMap()[row.origin]`, decode the payload in a `try` on `FormatException`, accept it with `if (decoded case final Map<String, Object?> payload)`; on any miss log `l.w('SessionEventStore | session $sessionId: skipped row ${row.seq}: …')` and return `null`. `open` keeps the non-null events and takes the next seq from the last **row** (`rows.last.seq + 1`), not the last event. `McpServersRepositoryImpl._fromRow`: `command` and `url` read with `switch (config['command']) { final String value => value, _ => null }`.
- [ ] **Step 4:** Run both files. Expected: PASS.
- [ ] **Step 5:** Commit `fix(data): skip a journal row or server config that cannot be read`.

## Task 3: Text cut by characters

**Files:**
- Modify: `lib/src/common/acp/agent_hub.dart:1243`, `lib/src/feature/chat/widgets/tool_call_card.dart:147`, `lib/src/feature/app_run/data/app_run_repository.dart:841-844`
- Test: `test/common/acp/agent_hub_test.dart`, `test/feature/chat/tool_call_card_test.dart` (create if missing), `test/feature/app_run/app_run_repository_test.dart`

- [ ] **Step 1: Write the failing tests**
  - hub: a first prompt of 59 `a` followed by `👍🏽` and more text gives a stored title of 59 `a` + `👍🏽` (60 characters), and `utf8.encode(title)` round-trips without `U+FFFD`.
  - tool card: output of `_maxOutputChars - 1` `a` + `👍` + more shows `…` after the whole emoji, never half of it.
  - run log: a line of `kLogLineLimit - 1` `a` + `👍` + more is cut after the emoji and the "more characters" count is in characters.
- [ ] **Step 2:** Run the three files. Expected: FAIL on the split surrogate.
- [ ] **Step 3:** Use `text.characters.take(n).toString()` (and `characters.length` for counts) at the three sites; import `package:characters/characters.dart` where Flutter does not re-export it.
- [ ] **Step 4:** Run the three files. Expected: PASS.
- [ ] **Step 5:** Commit `fix: cut titles, tool output and log lines by characters`.

## Task 4: MCP probe and LSP JSON read leniently

**Files:**
- Modify: `lib/src/feature/mcp_servers/data/mcp_probe.dart:282-300`; the casts in `lib/src/common/dart_analysis/models/dart_completion.dart:98-106`, `dart_diagnostic.dart:45`, `lsp_range.dart:16-17`, `lib/src/common/dart_analysis/lsp_connection.dart:183`, `dart_analysis_server.dart:103,226`, `lib/src/feature/session_config/models/config_option.dart:25,29` (paths as found with `grep -rn " as String\| as int\| as Map\| as List" lib/src/common/dart_analysis lib/src/feature/session_config/models`)
- Test: `test/feature/mcp_servers/mcp_probe_test.dart`, `test/common/dart_analysis/lsp_models_test.dart` (create), `test/common/dart_analysis/lsp_connection_test.dart`

- [ ] **Step 1: Write the failing tests**
  - probe: a scripted server (`test/support/scripted_mcp_server.dart`) that prints the bytes `[0xff, 0x0a]` before a valid JSON-RPC answer still connects (`McpProbeConnected`), and no error reaches the zone (`runZonedGuarded` collects none).
  - completions: `DartCompletion.listFromJson` (or the existing list parser) given `[{"label": 1}, {"label": "ok", "kind": 3}]` returns one item, `ok`.
  - diagnostics/range: an item with `"line": "x"` is skipped; the rest of the response is kept.
  - `lsp_connection`: an error object whose `message` is a number gives an `LspRequestException` with a text message, not a `TypeError`.
- [ ] **Step 2:** Run the files. Expected: FAIL (`FormatException` in the zone, `TypeError` in parsers).
- [ ] **Step 3:** Probe: `.transform(const Utf8Decoder(allowMalformed: true))` and an `onError` that logs at `l.w` and closes like `onDone`. Parsers: replace each `json['x'] as T` with a map pattern (`if (json case {'label': final String label})`), returning `null` for an item that does not match; list parsers drop `null`s.
- [ ] **Step 4:** Run the files and `flutter test test/common/dart_analysis test/feature/code_view`. Expected: PASS.
- [ ] **Step 5:** Commit `fix: read MCP probe output and LSP JSON without crashing on one bad item`.

## Task 5: (folded into Task 4)

The spec's items 4 and 5 are both "read outside input leniently" and share the test style, so Task 4 does both. Task 5 is left empty on purpose, so that Tasks 1-12 keep the spec's phase 1 item numbers and Tasks 13-18 are phase 2 items 1-6.

## Task 6: Real `flutter doctor`, localized run-error titles

**Files:**
- Create: `lib/src/feature/flutter_sdk/data/doctor_output_parser.dart`, `lib/src/feature/app_run/models/run_error_kind.dart`, `lib/src/feature/app_run/widgets/run_error_title.dart`
- Modify: `flutter_sdk_repository.dart`, `flutter_sdk_repository_impl.dart:20-73`, `flutter_sdk_controller.dart:57-64`, `flutter_settings_section.dart` (drop the `PreviewBadge` of the doctor row and the "made up" docs), `initialize_dependencies.dart:202` comment, `run_error.dart`, every `RunError(` site (`run_output_parser.dart:155,173,184,257,292`, `app_run_repository.dart:274,288,446,611,866`, `flutter_error_listener.dart:181`), `run_status.dart:64`, `run_error_block.dart:63`, `test/support/*` fakes of `IFlutterSdkRepository`
- Test: `test/feature/flutter_sdk/doctor_output_parser_test.dart`, `flutter_sdk_repository_impl_test.dart`, `test/feature/app_run/run_error_title_test.dart`

**Interfaces:**
- Produces: `List<DoctorCheck> parseDoctorOutput(String output)`; `IFlutterSdkRepository.doctor(String flutter)` (the executable; the controller passes `sdk.path` and the button is disabled when it is `null`); `FlutterSdkRepositoryImpl({..., Duration doctorTimeout = const Duration(minutes: 2)})` replacing `step`.
- Produces: `enum RunErrorKind { projectNotFound, flutterNotFound, buildFailed, appExited, compilation, unhandledException, layoutOverflow, exception, devToolsFailed, other }`; `RunError({required RunErrorKind kind, required String title, ...})`; `String runErrorTitle(GeneratedLocalization lcl, RunError error)` (`other` returns `error.title`). `title` stays English for the agent (`workspace_run_link.dart:244,264` unchanged).

- [ ] **Step 1: Write the failing parser test** with this exact input:

```text
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.27.1, on macOS 15.1 24B83 darwin-arm64, locale en-US)
[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
    ✗ cmdline-tools component is missing
      Run `path/to/sdkmanager --install "cmdline-tools;latest"`
[✓] Xcode - develop for iOS and macOS (Xcode 16.1)
[✗] Chrome - develop for the web (Cannot find Chrome executable at google-chrome)
    ! Cannot find Chrome. Try setting CHROME_EXECUTABLE to a Chrome executable.
[✓] Connected device (3 available)
[✓] Network resources
[☠] IntelliJ IDEA (the doctor check crashed)

! Doctor found issues in 3 categories.
```

Expected, in order: `Flutter` ok `Channel stable, 3.27.1, on macOS 15.1 24B83 darwin-arm64, locale en-US`; `Android toolchain` warning `cmdline-tools component is missing`; `Xcode` ok `Xcode 16.1`; `Chrome` error `Cannot find Chrome. Try setting CHROME_EXECUTABLE to a Chrome executable.`; `Connected device` ok `3 available`; `Network resources` ok `null`; `IntelliJ IDEA` error `the doctor check crashed`. Also: empty output gives `[]`; ANSI escapes (`\x1B[32m`) are stripped first.

- [ ] **Step 2: Write the failing repository tests:** `doctor('/sdk/bin/flutter')` runs `flutter doctor` with the repository's environment through `runProcess` and returns the parsed checks even with exit code 1; a runner that never completes throws `TimeoutException` after `doctorTimeout`; a `ProcessException` propagates (the controller shows it through `errorText`).
- [ ] **Step 3: Write the failing title test:** `runErrorTitle(en, RunError(kind: RunErrorKind.buildFailed, title: 'Build failed', message: ''))` is the English ARB text and differs in Russian; kind `other` with title `Rendering library` returns `Rendering library` in both.
- [ ] **Step 4:** Run the three files. Expected: FAIL (missing symbols).
- [ ] **Step 5:** Implement the parser: lines matching `^\[(✓|!|✗|☠)\] (.+)$`; title is the text before the first ` - ` or ` (`; for ok the detail is the last `(…)`; for a problem the detail is the first following line that starts (after indent) with `✗` or `!`, else the `(…)`; `✓`→ok, `!`→warning, `✗`/`☠`→error; other lines are ignored. Implement `doctor` with `_runProcess(flutter, const ['doctor'], environment: _environment).timeout(doctorTimeout)` and `parseDoctorOutput('${result.stdout}')`.
- [ ] **Step 6:** Add `kind` to `RunError` and to every construction site (the overflow branches pick `layoutOverflow`, the library-banner branch picks `other`); add one ARB key per kind except `other`; widgets show `runErrorTitle(...)`. Update the 33 `RunError(` uses in `test/` with the kind that matches their title.
- [ ] **Step 7:** Run `dart run build_runner build`, then `flutter test test/feature/flutter_sdk test/feature/app_run test/feature/workspace`. Expected: PASS.
- [ ] **Step 8:** Commit `feat(flutter_sdk): run the real flutter doctor; localize run error titles`.

## Task 7: Theme colors in the diff

**Files:**
- Modify: `lib/src/common/widget/diff_view.dart:39-90`, `lib/src/common/widget/pane_tabs.dart:120`
- Test: `test/common/widget/common_widgets_test.dart`

Ruling made while planning: `AppColors` already has `ok`, `okSoft`, `danger`, `dangerSoft`, `border` and `onAccent` in both palettes, so no new token is added; the spec's "new tokens" are these existing ones.

- [ ] **Step 1: Write the failing test:** pump `DiffView` (old `a\nb`, new `a\nc`) under `AppTheme.dark()`; the added line's `ColoredBox.color` equals `AppColors.dark.okSoft`, the removed one `AppColors.dark.dangerSoft`, the `+1` text color `AppColors.dark.ok`; the frame's `BorderRadius` is `AppRadius.medium`. `PaneTabs` with `errors: 2` shows `2` in `AppColors.dark.onAccent`.
- [ ] **Step 2:** Run it. Expected: FAIL (green shades, `Colors.white`).
- [ ] **Step 3:** Replace `Colors.*`, `theme.colorScheme.*` and `BorderRadius.circular(8)` in `diff_view.dart` with `context.colors.*` and `AppRadius.medium`; `pane_tabs.dart:120` uses `colors.onAccent`.
- [ ] **Step 4:** Run it. Expected: PASS.
- [ ] **Step 5:** Commit `fix(design): diff and tab badge colors from the theme`.

## Task 8: Line diff and journal decode off the UI isolate

**Files:**
- Modify: `lib/src/common/utils/line_diff.dart`, `lib/src/feature/chat/models/diff_lines_cache.dart`, `lib/src/common/widget/diff_view.dart`, `lib/src/feature/chat/widgets/tool_call_card.dart:75-100,160-175`, `lib/src/feature/changes_pane/widgets/changes_view.dart:51-80`, `lib/src/feature/permission_request/widgets/permission_card.dart:121`, `lib/src/common/acp/session_event_store.dart:30-50`, `intl_*.arb`
- Test: `test/common/utils/line_diff_test.dart`, `test/feature/chat/diff_lines_cache_test.dart` (create or extend), `test/common/widget/common_widgets_test.dart`, `test/common/acp/session_event_store_test.dart`

**Interfaces:**
- Consumes: Task 2's `_fromRow` returning `SessionEvent?`.
- Produces: `LineDiff.syncCells = 40000`; `static Future<List<DiffLine>> LineDiff.computeAsync(String? oldText, String newText)` (sync below `syncCells`, `Isolate.run` above); `DiffLinesCache({required VoidCallback onReady})` with `List<List<DiffLine>?> resolve(List<ToolDiffContent> diffs)` (`null` = still computing; `onReady` fires once a background diff lands, never after `dispose()`); `void DiffLinesCache.dispose()`; `DiffView.lines` stays `List<DiffLine>?`, and `null` now means "computing": it shows the `diffComputing` placeholder and never computes itself.

- [ ] **Step 1: Write the failing tests**
  - `computeAsync` of two 400-line texts equals `compute` of them.
  - cache: a small diff resolves at once; a 300×300-line diff resolves `null`, then `onReady` fires once and the next `resolve` returns the lines; `dispose()` before it lands means `onReady` never fires.
  - `DiffView(lines: null)` shows `lcl.diffComputing` and no diff lines.
  - event store: 600 rows (one corrupt) open to 599 events in order, with the decode running in `Isolate.run` above `SessionEventStore.isolateRows = 500`.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement as in Interfaces. The three widget users create their cache in `initState` with `onReady: () { if (mounted) setState(() {}); }` and dispose it; counters (`_DiffCounter`, `_sum`) skip `null` entries. `permission_card.dart` gets its own cache. `SessionEventStore.open` decodes with `Isolate.run(() => [for (final r in rows) ?_fromRow(r)])` when `rows.length > isolateRows`, sync otherwise; logging of skipped rows happens in the isolate (the `l` logger works there) or is returned as a count and logged after; pick one and keep it in one place.
- [ ] **Step 4:** Run them, then `flutter test test/feature/chat test/feature/changes_pane test/feature/permission_request`. Expected: PASS.
- [ ] **Step 5:** Commit `perf: compute large diffs and decode long journals off the UI isolate`.

## Task 9: Startup with Retry

**Files:**
- Modify: `lib/main.dart`, `lib/src/feature/initialization/data/initialization.dart`, `initialize_dependencies.dart:55-75`, `lib/src/common/widget/app_error.dart`, `intl_*.arb`
- Create: `lib/src/feature/initialization/models/initialization_exception.dart`
- Test: `test/feature/initialization/initialize_dependencies_test.dart`, `test/common/widget/app_error_test.dart`

**Interfaces:**
- Produces: `final class InitializationException implements Exception { const InitializationException(this.step, this.cause); final String step; final Object cause; }`.
- Produces: `typedef InitializationStep = FutureOr<void> Function(Dependencies)`, `typedef InitializationCloser = FutureOr<void> Function(Dependencies)`; `$initializeDependencies({onProgress, @visibleForTesting Map<String, InitializationStep>? steps, @visibleForTesting Map<String, InitializationCloser>? closers})`. `closers` is keyed by step name; on a failed step the closers of the steps that finished run in reverse order, each in its own `try` (a failing closer is logged, the rest still run), then `InitializationException(step, error)` is thrown with the original stack trace.
- Produces: `AppError({Object? error, VoidCallback? onRetry})` shows `errorText(...)` of the cause and a Retry button when `onRetry` is set.

Closers to register (the step names as in `_initializationSteps`): database → `database.close()`; agent hub → `agentHub.dispose()`; app MCP server → `close()`; MCP probe → `dispose()`; agent probe → `dispose()`; app run, devices, widget picker → `dispose()`; the custom-agents follow subscription → `cancel()`; code views → their stop. Read each step and add one closer per resource it opens; steps that open nothing get none.

- [ ] **Step 1: Write the failing tests**

```dart
test('a failed step closes the finished ones in reverse and names the step', () async {
  final closed = <String>[];
  final future = $initializeDependencies(
    steps: {'a': (_) {}, 'b': (_) {}, 'c': (_) => throw const FileSystemException('locked')},
    closers: {'a': (_) => closed.add('a'), 'b': (_) => closed.add('b'), 'c': (_) => closed.add('c')},
  );
  await expectLater(future, throwsA(isA<InitializationException>()
      .having((e) => e.step, 'step', 'c').having((e) => e.cause, 'cause', isA<FileSystemException>())));
  expect(closed, <String>['b', 'a']);
});
test('a failing closer does not stop the others', ...);
testWidgets('AppError shows the cause and Retry calls onRetry', ...);
```
Plus, in `initialization.dart`: a test that calling `$initializeApp` twice with a failing step installs `PlatformDispatcher.instance.onError` once (keep a `@visibleForTesting int handlerInstalls` counter or compare the handler identity).

- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. `initialization.dart`: get the binding before the `try` (no `late` read in `finally`), install the handlers behind a `static bool _handlersInstalled`. `main.dart`: a local `void start()` that calls `$initializeApp(onError: (e, s) => runApp(AppError(error: e, onRetry: start)), ...)`; `ErrorUtil.logError` stays.
- [ ] **Step 4:** Run them and `flutter test test/feature/initialization test/common/widget`. Expected: PASS.
- [ ] **Step 5:** Commit `fix(initialization): retry a failed startup and close what it opened`.

## Task 10: Secrets typed by the user

**Files:**
- Create: `lib/src/common/widget/secret_lines_field.dart`
- Modify: `lib/src/feature/agents/widgets/custom_agent_dialog.dart` (environment), `lib/src/feature/mcp_servers/widgets/add_mcp_server_dialog.dart` (env, headers), `lib/src/feature/app_run/widgets/run_arguments_dialog.dart` (dart-defines), `intl_*.arb`, `README.md`, `.gitignore`
- Test: `test/common/widget/secret_lines_field_test.dart`, the three dialogs' tests

Ruling made while planning: these fields are multi-line, and Flutter's `obscureText` needs `maxLines: 1`, so "obscured" means a read-only masked view with a Show toggle.

**Interfaces:**
- Produces: `SecretLinesField({required TextEditingController controller, required String separator, required String label, String? hint, String? errorText, VoidCallback? onChanged, int maxLines = 4, Key? key})`. Hidden: shows each line as `KEY<sep>••••••` (a line without the separator shows as `••••••`), not editable, with a Show button. Shown: the plain editable `TextField` with a Hide button. It starts hidden when the controller has text and shown when it is empty. Under the field, always: `lcl.secretsStoredUnencrypted`.
- Produces: `String maskSecretLines(String text, String separator)` (top-level, tested on its own).

- [ ] **Step 1: Write the failing tests:** `maskSecretLines('A=1\nB=x=y\nC', '=')` is `'A=••••••\nB=••••••\n••••••'`; `maskSecretLines('Authorization: Bearer t', ':')` is `'Authorization: ••••••'` (keeps the space after `:`); the widget with text starts hidden and `find.text('1')`/`find.textContaining('Bearer')` finds nothing; tapping Show reveals and edits; an empty controller starts shown; the unencrypted notice is present in both states.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement the widget and use it for the four fields (their `_field(...)` helpers keep the other fields). Add ARB keys `secretShow`, `secretHide`, `secretsStoredUnencrypted` ("Kept unencrypted in the app's database on this Mac." / Russian). README: one sentence under the MCP and custom-agent features saying the same. `.gitignore`: add exactly the patterns `security.md` lists: `*.jks`, `*.keystore`, `key.properties`, `local.properties`, `serviceAccountKey.json`, `AuthKey_*.p8`, `*.p12`, `*.mobileprovision`, `.env`, `.env.*`, `!.env.example`, `env.g.dart`. Do not add `google-services.json` or `GoogleService-Info.plist`: the rule says they are not secrets.
- [ ] **Step 4:** Run the new test and the three dialog tests. Expected: PASS (dialog tests that typed into these fields tap Show first or use an empty start).
- [ ] **Step 5:** Commit `fix(security): hide typed secrets and say they are stored unencrypted`.

## Task 11: Small ones

**Files:**
- Modify: `lib/src/feature/code_view/widgets/code_file_bars.dart:137`; `lib/src/feature/workspace/widgets/workspace_config_widget.dart:279-282,446-452` and `workspace_chat_area.dart:49`; `lib/src/feature/mcp_servers/data/mcp_servers_repository.dart` and `lib/src/feature/app_close/data/app_close_repository.dart:133-160` and `initialize_dependencies.dart` (pass the stop); `lib/src/feature/initialization/data/platform_initialization.dart:22`, `intl_*.arb` `appTitle`
- Test: `test/feature/code_view/` image test, `test/feature/workspace/workspace_shell_test.dart:140`, `test/feature/mcp_servers/mcp_servers_repository_test.dart`, `test/feature/app_close/` shutdown test

One commit per bullet (four commits), each with its failing test first:

- [ ] **Image:** test that `CodeImageView` in a 400×300 box builds an `Image` whose `image` is a `ResizeImage` with `width <= 400 * devicePixelRatio`. Fix: `LayoutBuilder` + `Image.file(..., cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round())`. Commit `fix(code_view): decode images at the pane size`.
- [ ] **CodeWorkspace:** test that building `WorkspaceChatArea` (or pumping the workspace with a project) calls `codeViews.workspaceFor` from the selection listener, not from `build`: a counting fake `CodeViewRegistry` sees one call per project selection, and `0` additional calls after `tester.pump()` rebuilds. Fix: a `CodeWorkspace? _codeWorkspace` field set in `_followSelectedProject` (and `null` without a project); the getter returns the field. Commit `fix(workspace): create the code view when the project is selected`.
- [ ] **MCP dispose:** test that `McpServersRepositoryImpl.dispose()` completes and a `watchServers()` subscription gets `onDone`; and that `AppCloseRepositoryImpl.shutdown` calls the MCP-servers stop it was given. Fix: `Future<void> dispose()` on `IMcpServersRepository` closing `_changed`; `AppCloseRepositoryImpl({..., Future<void> Function()? stopMcpServers})` called with `_stopQuietly('MCP servers', ...)` before the probes. Commit `fix(mcp_servers): close the change stream at shutdown`.
- [ ] **Title:** change `workspace_shell_test.dart:140` to expect `FAgent`; run it, expect FAIL. Fix: `appTitle` is `FAgent` in both ARB files and `title: 'FAgent'` in `platform_initialization.dart`. Commit `fix: the window title says FAgent`.

## Task 12: Text scaling

**Files:**
- Modify: `lib/src/feature/initialization/widget/app.dart:58-62`, any widget the screenshot run shows overflowing
- Test: `test/feature/initialization/app_text_scale_test.dart`, `test/screenshots/readme_screenshots_test.dart`

- [ ] **Step 1: Write the failing test:** pump `App` (through the existing test app in `test/support/test_app.dart`) with `tester.platformDispatcher.textScaleFactorTestValue = 2.0`; a `Text` inside reads `MediaQuery.textScalerOf(context).scale(10)` as `15` (clamped); with `0.8` it reads `10`.
- [ ] **Step 2:** Run it. Expected: FAIL (`noScaling` gives 10 for both).
- [ ] **Step 3:** `builder: (context, child) => MediaQuery.withClampedTextScaling(minScaleFactor: 1, maxScaleFactor: 1.5, child: child ?? const SizedBox.shrink())`. Remove `builderKey` only if the workspace tests stay green without it; otherwise keep it on a `KeyedSubtree`.
- [ ] **Step 4:** Run `FLUTTER_SCREENSHOTS=1 flutter test test/screenshots/readme_screenshots_test.dart` once with the view's text scale set to 1.5 (add a temporary `platformDispatcher.textScaleFactorTestValue = 1.5` in its setup, do not commit that line). Expected: no `A RenderFlex overflowed` in the output. Fix each overflow it reports in the widget that overflows (`Flexible`/`ellipsis`, no fixed heights). Do not commit regenerated screenshots.
- [ ] **Step 5:** Run `flutter test`. Expected: PASS.
- [ ] **Step 6:** Commit `fix(a11y): follow the system text size up to 1.5x`.

---

# Phase 2: structure

## Task 13: Expected failures are not crashes

**Files:**
- Create: `lib/src/common/utils/expected_exception.dart`
- Modify: `lib/src/common/controller/controller_observer.dart:50-60`; the exception classes listed below; `lib/src/common/localization/error_text.dart`
- Test: `test/common/controller/controller_observer_test.dart` (create), `test/common/localization/error_text_test.dart`

**Interfaces:**
- Produces: `abstract base class ExpectedException implements Exception { const ExpectedException(); }`. Subclasses are `final class X extends ExpectedException`.
- `ControllerObserver.onError`: an `ExpectedException` is logged with `l.i` and is not passed to `ErrorUtil.logError`; everything else is unchanged. Give the observer an optional `@visibleForTesting void Function(Object, StackTrace)? report` (defaults to `ErrorUtil.logError`) so the test can see what was reported.

Classes that become `ExpectedException` (the user or the outside world causes them; the UI shows them): `ProjectBusyException`, `OpenPathRefusedException` (both also become `final`), `ChatBusyException`, `InvalidMcpServerException`, `McpJsonException`, `ReadOnlyKnowledgeException`, `InvalidKnowledgeNameException`, `KnowledgeExistsException`, `KnowledgeNotFoundException`, `InvalidKnowledgeException`, `KnowledgeConflictException`, `AgentSettingsMissingException`, `RunConfigNotStartable`, `FileNotTextException`, `FileTooLargeException`, `FileChangedOnDiskException`, `BypassNotAllowedException`, `FlutterNotFoundException`, `PermissionRulesUnreadableException`. Private ones (`_StepFailure`, `_Cancelled`, `_ProbeCancelled`) and the transport/daemon/LSP ones stay as they are.

- [ ] **Step 1: Write the failing tests:** the observer given `ChatBusyException()` reports nothing and given `StateError('x')` reports once; `errorText` has a sentence for each class above that has no case yet (add the ARB keys).
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement. If a class has a `const` constructor, keep it const (`const X() : super();`). If one cannot extend because it already extends something, leave it and ledger why.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit `refactor: expected failures extend ExpectedException and are not crash reports`.

## Task 14: Exceptions for outside failures

**Files:**
- Modify: `lib/src/common/acp/agent_connection.dart:192`, `lib/src/common/acp/agent_hub.dart:306`, `lib/src/feature/app_run/data/app_run_repository.dart:421,678,687`, `lib/src/feature/mcp_servers/data/mcp_probe.dart:312`, `lib/src/feature/sessions/data/sessions_repository.dart:105-126`, `error_text.dart`, `intl_*.arb`
- Create: `lib/src/common/acp/agent_exceptions.dart`, `lib/src/feature/app_run/models/app_run_exceptions.dart`
- Test: the existing test files of those classes

**Interfaces:**
- Produces: `final class AgentExitedException extends ExpectedException { const AgentExitedException(this.exitCode); final int exitCode; }`; `final class AgentStoppedException extends ExpectedException` (hub:306); `final class ProjectFolderUnknownException`, `final class NoRootWidgetException`, `final class ScreenshotFailedException` (all `extends ExpectedException`, app run); `final class McpServerClosedException implements Exception` (transport level, not shown to the user directly); `ChatBusyException` reused for the four `sessions_repository.dart` throws.
- `agent_slot_registry`, `permission_broker`, `session_event_store`, `agent_hub` "disposed"/"not allowed" `StateError`s stay: they are bugs or shutdown races, not outside failures.

- [ ] **Step 1:** For each site, change or add the test that drives it (agent process exiting during start, a run without a project folder, a screenshot of an app with no root widget, a send on a closed probe transport, changing the agent of a starting chat) to `throwsA(isA<NewException>())`.
- [ ] **Step 2:** Run them. Expected: FAIL (`StateError`).
- [ ] **Step 3:** Throw the named exceptions; add `errorText` cases and ARB keys for the user-visible ones.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit `refactor: named exceptions for agent, run and MCP failures`.

## Task 15: No repository takes another repository (five cases plus project creation)

One commit per case. Each case: change the constructor, move the call, update `initialize_dependencies.dart`, the config widgets that build the repository, and the fakes in `test/support/`. Test first in each case: the controller test that now passes both fakes and asserts the moved behavior.

- [ ] **15a Chat → Agents.** Remove `watchLoginMethods`, `cancelLogin`, `login` from `IChatRepository`; `ChatRepositoryImpl({required AgentHub hub})`. `ChatLoginMethodsController` takes `IAgentsRepository` and maps `watchAgents()` to `{agent.id: agent.methods}`; `ChatRecoveryController` takes `IAgentsRepository` for `login`/`cancelLogin` and keeps the terminal-output listening it had in `ChatRepositoryImpl.login` (move that code into the controller). Move the `chat_problem_banner_test.dart:170-219` cases to the controller tests. Commit `refactor(chat): sign-in through the agents repository in the controller`.
- [ ] **15b SessionConfig → AppSettings.** Remove `saveDefaults` from `ISessionConfigRepository`; the controller that saved defaults takes `IAppSettingsRepository` and does the read-modify-update itself. Commit `refactor(session_config): defaults saved by the controller`.
- [ ] **15c McpServers → FlutterSdk.** `McpServersRepositoryImpl({..., required Future<String?> Function() flutter})` replacing `IFlutterSdkRepository`; initialization passes `() => flutterExecutableFor(null, which: environment.which)` (same pattern as `AppRunRepositoryImpl`). Commit `refactor(mcp_servers): take the flutter path, not the SDK repository`.
- [ ] **15d WidgetPicker → AppRun.** `IWidgetPickerRepository.pick(int projectId, {required Uri? vmServiceUri})`; `RunActionsController` reads the current run from `IAppRunRepository` (it already has it) and passes `run is RunRunning && run.mode == BuildMode.debug ? run.vmServiceUri : null`; the picker returns `PickFailed(PickFailure.notDebug)` for `null`. `WidgetPickerRepositoryImpl` drops `runs`. Commit `refactor(app_run): the controller tells the picker which app to pick in`.
- [ ] **15e Agents + CustomAgents merged.** Move `CustomAgentsRepositoryImpl`'s database code into `AgentsRepositoryImpl` (it takes `AppDatabase`); `IAgentsRepository` gains `Stream<List<AgentDefinition>> watchCustomAgents()` and keeps `addCustom/updateCustom/removeCustom`; delete `custom_agents_repository.dart`; the "Follow custom agents" step uses `dependencies.agentsRepository.watchCustomAgents()` (move the step after the agents repository step if it runs earlier). Move its tests into `agents_repository_test.dart`. Commit `refactor(agents): one repository for built-in and custom agents`.
- [ ] **15f ProjectCreation.** `ProjectCreationRepositoryImpl` drops `IProjectOpeningRepository`, `IProjectTrustRepository`, `IProjectRulesRepository`, `IFlutterSdkRepository`: it takes `required Future<String?> Function() flutter` and the rule writing service it calls through `_projectRules.write` today (`ProjectRulesFiles` or whatever `write` delegates to; it is a file service, not a repository). `NewProjectRequest` gains `required List<KnowledgeItem> rules` (the enabled built-in rules, read by the controller before `create`). `CreationRun` emits `completed` with the path; `ProjectCreationController` takes `IProjectOpeningRepository`, `IProjectTrustRepository`, `IProjectRulesRepository` and, after the stream completes successfully and was not cancelled, runs `open(path)`, `trust(id)`, `markOffered(id)` and then sets the completed state with the project id. Test first: the controller test with three fakes sees open → trust → markOffered in that order, and none of them after a cancel. Commit `refactor(project_creation): the controller opens, trusts and marks the new project`.
- [ ] **15g Comments.** At the constructors of `SessionContextRepositoryImpl`, `ProjectRulesRepositoryImpl` and `AppCloseRepositoryImpl`, one line each saying why they take other repositories (the hub, not a controller, uses the first two; the last is shutdown plumbing). Fold into 15f's commit or commit `docs: why three repositories still orchestrate`.
- [ ] After all: `flutter analyze` and `flutter test`. Expected: clean, PASS.

## Task 16: Code view widgets go through a controller

**Files:**
- Create: `lib/src/feature/code_view/controller/dart_analysis_controller.dart`; move `DartAnalysisStatus` to `lib/src/feature/code_view/models/dart_analysis_status.dart` (update imports, regenerate freezed)
- Modify: `code_workspace.dart:32,48-57,67-69,111-133`, `code_editor_view.dart:54,150-158,518-519`, `code_view.dart:214,264,276-277`, `code_analysis_footer.dart:5`, `workspace_config_widget.dart:454-456` and `workspace_chat_area.dart:91`
- Create: `lib/src/feature/workspace/controller/project_files_controller.dart` (or reuse `FileMentionController` if it already lists project files; check first and ledger which)
- Test: `test/feature/code_view/dart_analysis_controller_test.dart`, existing code-view widget tests

**Interfaces:**
- Produces: `final class DartAnalysisController { DartAnalysisController({required IDartAnalysisRepository repository}); ValueListenable<DartAnalysisStatus> get status; Future<void> restart(); Future<void> format(CodeDocument document); DartCompletionController completionFor(CodeDocument document); CodeNavigationController navigationFor(CodeDocument document, ...same extra args the widget passes today); }`. `CodeWorkspace.analysis` becomes `DartAnalysisController?`; it keeps the repository privately for diagnostics and open/change/close.
- The editor widgets take `DartAnalysisController?`; no file in `code_view/widgets/` imports `code_view/data/`.

- [ ] **Step 1: Write the failing test:** the controller over `MemoryDartAnalysisRepository` (`test/support/memory_dart_analysis_repository.dart`) forwards `status`, `restart` (counted by the fake) and `format` (applies the fake's edits to the document).
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement, switch the widgets, then `listProjectFiles`: the widget calls a controller method instead of building `ProjectFilesRepositoryImpl` per call.
- [ ] **Step 4:** Check: `grep -rn "code_view/data/" lib/src/feature/code_view/widgets` prints nothing. Run `flutter test test/feature/code_view test/feature/workspace`. Expected: PASS.
- [ ] **Step 5:** Commit `refactor(code_view): widgets use the analysis through a controller`.

## Task 17: The chat repository returns the feature's models

**Files:**
- Create: `lib/src/feature/chat/models/chat_runtime.dart`, `lib/src/feature/prompt_sending/models/prompt_attachment.dart`, `lib/src/feature/prompt_sending/data/prompt_blocks.dart`
- Modify: `chat/data/chat_repository.dart`, `chat/controller/chat_controller.dart:44-130`, `chat/widgets/chat_screen.dart`, `chat_problem_banner.dart`, `prompt_sending/data/prompt_sending_repository.dart`, `prompt_sending/controller/prompt_sending_controller.dart:30-37`, `chat/widgets/chat_config_widget.dart:345-400`, the fakes in `test/feature/chat/chat_controller_test.dart` and `test/support/`
- Test: `test/feature/chat/chat_repository_test.dart` (create), `test/feature/prompt_sending/prompt_blocks_test.dart` (create), existing chat tests

**Interfaces:**
- Produces: `@immutable final class ChatRuntime { required int sessionId; required String agentId; required List<SessionEvent> events; required Set<String> openPermissionIds; required SessionStatus status; required SessionProblem? problem; required bool canForceStop; required bool canRetryPrompt; required List<ConfigOption> configOptions; required bool bypassBlocked; required bool preparingTurn; required List<SlashCommand> commands; }` (all `required`).
- Produces: `IChatRepository.watch(int sessionId) -> Stream<ChatRuntime>` (first value once the session is open, a new one on every journal append or live-state change; cancelling removes every listener it added) replacing `open` and `openPermissionIds`. `ChatController` subscribes to it and keeps folding the transcript; it no longer imports `live_session.dart`. `SessionStatus`/`SessionProblem` stay importable by widgets (they are value types).
- Produces: `sealed class PromptAttachment` with `PromptFileLink(String path)`, `PromptImage(String mimeType, String base64Data)`, `PromptSkill(String name, String markdown)`; `List<Map<String, Object?>> promptBlocks(String projectRoot, List<PromptAttachment> attachments)` in `prompt_blocks.dart` (moves `resourceLinks`, `skillResource`, `toBlock` logic there); `IPromptSendingRepository.send(int sessionId, String text, {List<PromptAttachment> attachments = const []})`, which calls `promptBlocks` before `_hub.prompt`.
- Ruling made while planning: `promptFor` reads several controllers of the chat (file mentions, run context, skills, skill text), which the widget layer is allowed to coordinate; it stays in `ChatConfigWidgetState` but returns `({String text, List<PromptAttachment> attachments})`. The pure parts (which files, which skill) move to functions in `prompt_sending/models/`. The point of the spec item, no raw ACP maps above the repository, is met.

- [ ] **Step 1: Write the failing tests:** `promptBlocks` turns each attachment into the block the old helpers built (copy the expected maps from the current helper tests); `ChatRepositoryImpl.watch` over a `FakeAgent` hub emits a `ChatRuntime` with the journal events, a new one after `status` changes, and none after cancel.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement; move the folding inputs from `ChatController._emit` into `ChatRuntime` construction in the repository; `ChatController.status` (used by widgets) becomes a value read from the last `ChatRuntime` or a `ValueNotifier` the controller owns.
- [ ] **Step 4:** Check: `grep -rln "live_session.dart" lib/src/feature` lists only `chat/data/` and `turn_files/data/`. `grep -rn "Map<String, Object?>> resources" lib/src/feature` prints nothing above `data/`. Run `flutter test test/feature/chat test/feature/prompt_sending`. Expected: PASS.
- [ ] **Step 5:** Commit `refactor(chat): the repository returns chat models, prompts carry typed attachments`.

## Task 18: Small Dart fixes

**Files:** `lib/src/common/acp/agent_hub.dart:312,374,867,941,1002`, `lib/src/feature/app_run/data/devices_repository.dart:244-264,346-348`, `lib/src/feature/chat/models/chat_transcript.dart:253,254,267`

- [ ] **Step 1:** Replace each `x!` after a check with a local (`final prompt = live.lastPrompt; if (prompt == null) return;`) or a pattern (`if (option case {'optionId': final String id})`); `devices_repository.dart:246-254` `Future.wait<Object?>` + casts becomes `final (daemons, emulators) = await (a, b).wait;` with typed futures. (`ProjectBusyException`/`OpenPathRefusedException` became `final` in Task 13.)
- [ ] **Step 2:** For `agent_hub`, add one test where the state changes across the awaited call (session closed while the prompt is prepared) and expect no `TypeError`/`Null check operator` failure. Run it before the change. Expected: FAIL or, if it already passes, ledger that the `!` was safe there and keep the change as a refactor.
- [ ] **Step 3:** Run `flutter test test/common/acp test/feature/app_run test/feature/chat`. Expected: PASS.
- [ ] **Step 4:** Commit `refactor: locals and patterns instead of ! after a check; typed record wait`.

---

## Task 19: Final check

- [ ] `flutter analyze` → clean. `flutter test > <workspace>/final.txt 2>&1; tail -5` → all pass, count ≥ the baseline from Task 0 plus the new tests.
- [ ] `flutter run -d macos` is the owner's; do not start it. Instead run the screenshot test once (`FLUTTER_SCREENSHOTS=1 ...`) and look at the images for the diff colors and the doctor row.
- [ ] Whole-branch review (subagent-driven or executing-plans final review), then superpowers:finishing-a-development-branch. Nothing is pushed or merged without the owner.
