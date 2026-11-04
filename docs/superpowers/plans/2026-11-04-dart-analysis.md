# Dart Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completion with the analysis server's Flutter snippets, and error and warning underlines, in the Code view's Dart files, through our own LSP client talking to `dart language-server`.

**Architecture:**
- `common/dart_analysis/` holds three pieces:
  - an `LspProcess` seam, a `GroupedProcess` in the app and a scripted one in tests;
  - `LspConnection`, which does `Content-Length` framing and JSON-RPC;
  - `DartAnalysisServer`, a typed API with its models.
- In `feature/code_view/`, `DartAnalysisRepository` owns one server per project: it starts it lazily, tracks file versions, debounces changes and reports status.
- Editor pieces build on that: snippet sessions, `CodeAutocomplete`-based completion, `spanBuilder` underlines, counts on tabs and in the explorer, and a footer.

**Tech Stack:** Flutter macOS, re_editor 0.10.0 (`CodeAutocomplete`, `CodeLineSpanBuilder`, `MouseTrackerAnnotationTextSpan`), the Dart SDK's `dart language-server` (LSP), control, freezed, gen-l10n en/ru.

**Spec:** `docs/superpowers/specs/2026-11-04-dart-analysis-design.md` (Russian).

## Global Constraints

- Follow CLAUDE.md and `docs/AI_INSTRUCTIONS.md`.
  - `common/` never imports `feature/`.
  - Colors come only from `context.colors`.
  - Every `Stream` repository method follows "Stream-Returning Methods".
  - Every `Process` is killed in `dispose`.
- No new dependency.
- The server command is `<dir of flutterExecutableFor(root, which: env.which)>/dart language-server --protocol=lsp --client-id=flutter_code_agent`, started in a `GroupedProcess` with `ShellEnvironment.variables` and working directory = project root.
- Timeouts:
  - a request: 10 s;
  - `initialize`: 30 s;
  - `didChange`: 300 ms after the last edit;
  - completion requests: 50 ms after the last keystroke;
  - `dispose`: `shutdown` then `exit`, and a group kill 2 s later at the latest.
- Analysis covers only files whose path ends in `.dart`.
- Copy, en/ru:
  - «Анализ…» / "Analyzing…";
  - «Анализ Dart недоступен» / "Dart analysis unavailable";
  - **Перезапустить** / **Restart**;
  - tab counts as `ⓧ N` and `⚠ N`.
- Underline colors: error → `danger`, warning → `warn`, info and hint → `muted`. The style is `TextDecorationStyle.wavy`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Byte counts in framing.** `Content-Length` counts UTF-8 **bytes**, not characters. A message with Cyrillic or emoji text must still be framed and parsed correctly, and so must several messages in one stdout chunk and one message split across chunks (Task 1).
2. **Stale completion answers.** A completion answer that arrives after the user typed more must not replace the newer list or insert at a stale range (Task 5).
3. **LSP positions.** LSP positions are UTF-16 code units, and Dart strings are UTF-16 too. Completion on a line that starts with an emoji or a tab must insert at the right column (Tasks 4 and 5).
4. **Server lifetime.** A server that crashes or never answers `initialize` leaves the editor working, with «Анализ Dart недоступен» and **Перезапустить**. Disposing the workspace or quitting the app leaves no `dart` process behind (Task 3).
5. **Auto-import shifting lines.** An auto-import (an `additionalTextEdits` entry above the cursor) shifts lines down. The main edit and the caret must still land where the user was (Task 4).

---

### Task 1: The LSP process seam and `LspConnection`

**Files:**
- Create:
  - `lib/src/common/dart_analysis/lsp_process.dart`
  - `lib/src/common/dart_analysis/lsp_connection.dart`
  - `test/support/scripted_lsp_process.dart`
- Test: `test/common/dart_analysis/lsp_connection_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class LspProcess`:
    - `Stream<List<int>> get stdout`
    - `void write(List<int> bytes)`
    - `Future<int> get exitCode`
    - `Future<void> stop()`
  - `typedef LspProcessStarter = Future<LspProcess> Function(String executable, List<String> arguments, {String? workingDirectory, Map<String, String>? environment});`
  - `Future<LspProcess> startGroupedLspProcess(...)`, built on `GroupedProcess`. `stop` uses its `stop()`.
  - `final class LspConnection`:
    - constructor `LspConnection(LspProcess process)`;
    - `Future<Object?> request(String method, Object? params, {Duration timeout = const Duration(seconds: 10)})`. It throws `LspRequestException(code, message)` on an error response, `TimeoutException`, or `LspClosedException` once closed;
    - `void notify(String method, Object? params)`;
    - `Stream<LspNotification> get notifications`, a broadcast stream, where `LspNotification(method, params)`;
    - `set onServerRequest(FutureOr<Object?> Function(String method, Object? params))`, defaulting to answer `null`;
    - `Future<void> get done`, which completes when stdout ends;
    - `Future<void> close()`.
  - `ScriptedLspProcess implements LspProcess` (test support):
    - `send(Map<String, Object?> message)` frames a message to stdout;
    - `sendRaw(List<int>)`;
    - `List<Map<String, Object?>> received` holds the decoded client messages;
    - `onMessage` answers automatically;
    - `exit(int code)`;
    - `bool stopped`.

- [ ] **Step 1: Write the failing tests:**
  - `a request gets its result by id`
  - `an error response throws LspRequestException with code and message`
  - `a request without an answer times out`
  - `notifications arrive on the stream`
  - `a server request is answered through onServerRequest`
  - `two messages in one chunk and one message split in three chunks both parse`
  - `Content-Length counts UTF-8 bytes: a Cyrillic and emoji message round-trips` (Review Focus #1)
  - `written messages carry a correct Content-Length`
  - `after the process exits, pending and new requests fail with LspClosedException`
- [ ] **Step 2: Run** `flutter test test/common/dart_analysis/lsp_connection_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the code. The parser is a byte buffer that reads a `\r\n\r\n`-terminated header, takes `Content-Length` bytes, and decodes them with `utf8.decode`.
- [ ] **Step 4: Run** the tests. Expected: PASS. Run `flutter analyze`. Expected: clean.
- [ ] **Step 5: Commit** `feat(dart_analysis): the LSP connection`.

### Task 2: `DartAnalysisServer` and its models

**Files:**
- Create:
  - `lib/src/common/dart_analysis/dart_analysis_server.dart`
  - `lib/src/common/dart_analysis/models/dart_completion.dart`
  - `lib/src/common/dart_analysis/models/dart_diagnostic.dart`
- Test: `test/common/dart_analysis/dart_analysis_server_test.dart`

**Interfaces:**
- Consumes: `LspConnection` and `LspProcess` (Task 1).
- Produces:
  - Models:
    - `LspPosition(line, character)` and `LspRange(start, end)`; positions are 0-based UTF-16;
    - `LspTextEdit(range, newText)`;
    - `enum DartCompletionKind { classType, method, function, field, variable, keyword, snippet, enumType, constructor, property, module, other }`, mapped from LSP `CompletionItemKind`;
    - `DartCompletion`, which holds:
      - `label`, `kind` and `detail?`;
      - `filterText`, which defaults to `label`, and `sortText?`;
      - `insertText`, `isSnippet` and `edit: LspTextEdit?`;
      - `additionalEdits: List<LspTextEdit>`;
      - `Object? data` for `completionItem/resolve`;
    - `enum DartSeverity { error, warning, info, hint }`;
    - `DartDiagnostic(range, severity, message, code?)`;
    - `DartFileDiagnostics(path, List<DartDiagnostic>)`.
  - `final class DartAnalysisServer`:
    - `static Future<DartAnalysisServer> start({required String executable, required String root, required Map<String, String> environment, LspProcessStarter starter = startGroupedLspProcess})`. It sends `initialize` (30 s) with:
      - `rootUri` and `workspaceFolders` set to `root`;
      - `capabilities.textDocument.completion.completionItem` with `snippetSupport: true`, `resolveSupport.properties: ['additionalTextEdits', 'documentation']` and `documentationFormat: ['markdown', 'plaintext']`;
      - `publishDiagnostics: {}`.
      It then notifies `initialized`.
    - `void open(String path, String text, int version)`, with `languageId: 'dart'`.
    - `void change(String path, String text, int version)`, using full-text sync.
    - `void close(String path)`.
    - `Future<List<DartCompletion>> complete(String path, LspPosition position)`, which accepts both a `CompletionList` and an array.
    - `Future<DartCompletion> resolve(DartCompletion completion)`.
    - `Stream<DartFileDiagnostics> get diagnostics`.
    - `Stream<bool> get analyzing`, from `$/analyzerStatus`.
    - `Future<void> get exited`.
    - `Future<void> dispose()`: `shutdown`, then `exit`, then `stop()`, with a 2 s ceiling.

- [ ] **Step 1: Write the failing tests** on a `ScriptedLspProcess`:
  - `start sends initialize with snippet and resolve support, then initialized`
  - `start fails when initialize does not answer in 30 s` (fake async)
  - `open, change and close send the text with versions`
  - `complete parses a CompletionList: label, kind, detail, snippet insertText, textEdit, additionalTextEdits`
  - `complete accepts a plain array`
  - `resolve fills additionalEdits`
  - `publishDiagnostics becomes DartFileDiagnostics with severities`
  - `$/analyzerStatus true/false is analyzing`
  - `workspace/configuration is answered`
  - `dispose sends shutdown and exit and stops the process`
  - `dispose stops a server that ignores shutdown within 2 s`
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the code. Uses `Uri.file(path).toString()` for the URI and `Uri.parse(uri).toFilePath()` back.
- [ ] **Step 4: Run** the tests. Expected: PASS. Run `flutter analyze`. Expected: clean.
- [ ] **Step 5: Commit** `feat(dart_analysis): the analysis server client`.

### Task 3: `DartAnalysisRepository` per project, wired into the workspace and shutdown

**Files:**
- Create:
  - `lib/src/feature/code_view/data/dart_analysis_repository.dart`
  - `test/support/memory_dart_analysis_repository.dart`
- Modify:
  - `lib/src/feature/code_view/controller/code_workspace.dart`: `CodeWorkspace` takes `IDartAnalysisRepository? analysis` and disposes it.
  - `CodeViewRegistry`: takes `IDartAnalysisRepository Function(String root)? analysisFor`.
  - `lib/src/feature/initialization/`: `analysisFor` uses the real repository.
  - `test/support/test_app.dart`: the default is the memory fake.
  - `lib/src/feature/app_close/data/app_close_repository.dart`: `shutdown` disposes the code views before the hub.
- Test: `test/feature/code_view/dart_analysis_repository_test.dart`

**Interfaces:**
- Consumes: `DartAnalysisServer` (Task 2).
- Produces:
  - Freezed `DartAnalysisStatus` with `idle`, `starting`, `ready`, `analyzing` and `unavailable({required String reason})`.
  - `abstract interface class IDartAnalysisRepository`:
    - `void open(String path, String text)`
    - `void change(String path, String text)`, debounced by 300 ms per file
    - `void close(String path)`
    - `Future<List<DartCompletion>> complete(String path, String text, LspPosition position)`, which flushes a pending change first, sending `text` if it differs
    - `Future<DartCompletion> resolve(DartCompletion completion)`
    - `Stream<DartFileDiagnostics> get diagnostics`
    - `ValueListenable<DartAnalysisStatus> get status`
    - `Future<void> restart()`
    - `Future<void> dispose()`
  - `DartAnalysisRepositoryImpl({required String root, required ShellEnvironment environment, LspProcessStarter starter = startGroupedLspProcess})`:
    - it ignores paths that don't end in `.dart`;
    - it starts the server on the first `open` of a `.dart` file;
    - it keeps versions per path;
    - it re-opens the open files after `restart`;
    - a missing `dart` or `flutter` becomes `unavailable('dart not found')`;
    - a failed `initialize` or a server exit becomes `unavailable`.
  - `CodeDocument` and `CodeTabsController` call `open` when a `.dart` tab opens, `change` on edits and reloads, and `close` when a tab closes, through `CodeWorkspace.analysis`.

- [ ] **Step 1: Write the failing tests** using a starter that returns a `ScriptedLspProcess`:
  - `a non-Dart file starts nothing`
  - `the first Dart open starts the server: starting, then ready`
  - `changes within 300 ms send one didChange with the latest text and version`
  - `complete flushes the pending change before asking`
  - `diagnostics pass through`
  - `analyzing true/false maps to analyzing/ready`
  - `no flutter on PATH is unavailable("dart not found")`
  - `the server exiting is unavailable, restart starts it again and re-opens the open files` (Review Focus #4)
  - `dispose stops the server`
  - in `code_view_registry_test.dart`: `a workspace disposes its analysis` and `opening, editing and closing a .dart tab drives open/change/close`
  - in `app_close` tests: `shutdown disposes the code views`
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the code. The memory fake records its calls and lets tests push diagnostics and status.
- [ ] **Step 4: Run** `flutter test test/feature/code_view/ test/feature/app_close/` and `flutter analyze`. Expected: PASS and clean.
- [ ] **Step 5: Commit** `feat(code_view): one Dart analysis server per project`.

### Task 4: Snippets and applying a completion

**Files:**
- Create:
  - `lib/src/feature/code_view/models/snippet.dart`
  - `lib/src/feature/code_view/controller/snippet_session.dart`
  - `lib/src/feature/code_view/controller/completion_edit.dart`
- Test:
  - `test/feature/code_view/snippet_test.dart`
  - `test/feature/code_view/completion_edit_test.dart`

**Interfaces:**
- Consumes: `DartCompletion` and `LspTextEdit` (Task 2), and re_editor's `CodeLineEditingController`.
- Produces:
  - `Snippet.parse(String body)` → `Snippet(text, List<SnippetStop> stops)`, where `SnippetStop(index, offsets: List<(int start, int end)>)`:
    - it reads `$1`, `${1:default}`, `${1|a,b|}` (keeping the first choice), `$0`, and escaped `\$` and `\}`;
    - stops are ordered 1…n, then 0 last;
    - placeholders with the same index are mirrors.
  - `final class SnippetSession`:
    - constructor `SnippetSession(CodeLineEditingController editing, {required int line, required int column, required Snippet snippet})`;
    - `bool next()` and `bool previous()` select the next or previous stop and return `false` at the end;
    - `void onEdit()` shifts offsets after edits and copies the text of the active stop to its mirrors;
    - `bool get active` turns false after `$0`, Esc, or when the caret leaves the snippet;
    - `void end()`.
  - `void applyCompletion(CodeLineEditingController editing, DartCompletion completion, {required LspPosition caret})`:
    - it replaces `completion.edit?.range`, or else the word before the caret, with the text, or with `Snippet.text` for a snippet;
    - then it applies `additionalEdits` from the bottom up;
    - it returns `SnippetSession?` for a snippet;
    - positions are UTF-16 columns of the editor's lines.

- [ ] **Step 1: Write the failing tests:**
  - `parse $1, ${1:name}, ${1|a,b|}, $0 and escapes`
  - `the stful body selects the widget name first; typing renames the State class too (mirror)`
  - `Tab goes 1 → 2 → 0 and then ends; ⇧Tab goes back`
  - `an edit before a later stop shifts it`
  - `the caret leaving the snippet ends it`
  - `a plain completion replaces the word before the caret`
  - `a completion with a textEdit replaces exactly its range`
  - `an import added above shifts the main edit and the caret down one line` (Review Focus #5)
  - `a line with an emoji and a tab inserts at the UTF-16 column` (Review Focus #3)
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the code.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(code_view): snippets and completion edits`.

### Task 5: The completion list in the editor

**Files:**
- Create:
  - `lib/src/feature/code_view/controller/dart_completion_controller.dart`
  - `lib/src/feature/code_view/widgets/code_completion_list.dart`
- Modify:
  - `lib/src/feature/code_view/widgets/code_editor_view.dart`: wrap `CodeEditor` in `CodeAutocomplete` for `.dart` files; Tab and ⇧Tab go to the snippet session while one is active; bind ⌃Space.
  - `CodeView`: pass the workspace's analysis.
  - Both arb files.
- Test: `test/feature/code_view/code_completion_test.dart`

**Interfaces:**
- Consumes: `IDartAnalysisRepository.complete/resolve` (Task 3) and `applyCompletion` and `SnippetSession` (Task 4).
- Produces:
  - `final class DartCompletionController extends ChangeNotifier`:
    - constructor `DartCompletionController({required CodeDocument document, required IDartAnalysisRepository analysis})`;
    - `List<DartCompletion> get items`;
    - `void trigger({bool explicit = false})`;
    - `void dismiss()`;
    - `Future<void> select(DartCompletion item)`, which resolves when the item has `data`, applies the edit, and starts a snippet session;
    - `SnippetSession? get snippet`.
  - **Behaviour:**
    - it triggers after a letter, a digit, `_` or `.`, 50 ms after the last keystroke;
    - each request remembers the text version, and an answer for an older version is dropped (Review Focus #2);
    - the list is filtered client-side by the word before the caret (prefix first, then substring), then sorted by `sortText`.
  - `CodeCompletionList` is the `viewBuilder`:
    - at most 8 rows of 24 px, 360 px wide;
    - each row has a kind icon, the label and the detail in muted text;
    - the highlighted row uses `accentSoft`.
  - The prompts builder returns the controller's current items as `CodePrompt`s. When an answer arrives, the controller notifies and the editor rebuilds the open list.
  - **Fallback** (decide in Step 1 and record the ruling): if `CodeAutocomplete` can't refresh asynchronously, build an `OverlayPortal` list positioned at the caret's rect with the same keys.

- [ ] **Step 1: Spike.** In a widget test, a `CodeAutocomplete` whose builder reads a list that fills 30 ms after a keystroke: does the open list show the new rows? Keep the test as `an answer that arrives later fills the open list`, then pick the path.
- [ ] **Step 2: Write the failing tests** on `MemoryDartAnalysisRepository`, which answers by script:
  - `typing a letter opens the list with the answer's rows`
  - `typing more narrows it`
  - `. opens it`
  - `⌃Space opens it with nothing typed`
  - `Enter and Tab insert, Esc closes`
  - `↑↓ move`
  - `stful inserts the widget with the caret on its name, typing renames State`
  - `a stale answer is dropped`
  - `an empty answer opens nothing`
  - `a non-Dart file never asks`
  - `choosing an auto-import item adds the import`
  - layout: `the list fits at 900×600 in ru and en, light and dark`
- [ ] **Step 3: Run** the tests. Expected: FAIL.
- [ ] **Step 4: Implement** the code.
- [ ] **Step 5: Run** `flutter test test/feature/code_view/` and `flutter analyze`. Expected: PASS and clean.
- [ ] **Step 6: Commit** `feat(code_view): Dart completion in the editor`.

### Task 6: Underlines, counts and the analysis footer

**Files:**
- Modify:
  - `lib/src/feature/code_view/controller/code_document.dart`: add `ValueListenable<List<DartDiagnostic>> diagnostics` and build the controller with `CodeLineEditingController(codeLines: CodeLines.fromText(text), options: ..., spanBuilder: ...)`.
  - `CodeTabsController`: route `analysis.diagnostics` to documents by path, and keep `Map<String, int> errorCounts` for the explorer.
  - `code_tab_bar.dart`: the counts.
  - `code_explorer.dart`: a file with errors in `danger`.
  - `code_view.dart`: the footer.
  - Both arb files.
- Create:
  - `lib/src/feature/code_view/widgets/code_diagnostic_spans.dart`
  - `lib/src/feature/code_view/widgets/code_analysis_footer.dart`
- Test: `test/feature/code_view/code_diagnostics_test.dart`

**Interfaces:**
- Consumes: `DartFileDiagnostics` and `DartAnalysisStatus` (Tasks 2 and 3).
- Produces:
  - `TextSpan diagnosticSpans({required TextSpan textSpan, required int line, required List<DartDiagnostic> diagnostics, required AppColors colors, required void Function(DartDiagnostic, Rect) onEnter, required VoidCallback onExit})`:
    - it splits the highlighted span at diagnostic ranges on that line, including multi-line ranges clipped per line;
    - it adds a wavy underline in the severity color;
    - it wraps each range in a `MouseTrackerAnnotationTextSpan` that shows an overlay tooltip with `message` and `(code)`.
  - **Footer:**
    - `starting` or `analyzing` show «Анализ…» with a small progress indicator;
    - `unavailable` shows «Анализ Dart недоступен» and the reason muted, with **Перезапустить** (`restart`);
    - `ready` shows nothing, and so does a non-Dart active tab.

- [ ] **Step 1: Write the failing tests:**
  - `an error, a warning and a hint are underlined in danger, warn and muted`
  - `text outside the ranges keeps its highlight style`
  - `a multi-line range underlines each line's part`
  - `hovering the range shows the message and code`
  - `the tab shows ⓧ 2 ⚠ 1`
  - `the explorer shows a file with errors in danger, without when they are gone`
  - `closing a tab drops its diagnostics`
  - `the footer says Analyzing… while starting and analyzing`
  - `unavailable shows the line and Restart restarts`
  - layout: `the footer and counts fit at 900×600 ru/en light/dark`
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** the code.
- [ ] **Step 4: Run** `flutter test`, the full suite, and `flutter analyze`. Expected: PASS and clean.
- [ ] **Step 5: Commit** `feat(code_view): Dart errors and warnings in the editor`.

### Task 7: The real server opt-in test and docs

**Files:**
- Create: `test/integration/dart_analysis_test.dart`. It is skipped unless `DART_LSP_TEST=1`, like `FLUTTER_RUN_TEST`.
- Modify:
  - `docs/superpowers/specs/2026-10-28-ui-system-design.md`: §3.4.1 gains completion and errors.
  - `docs/PLAN.md`: tick the LSP line for completion and errors, and add hover, definition and format.
  - `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`: a "## Dart analysis follow-ups" section with hover, go to definition, format on save, quick fixes, rename and a Problems panel.

- [ ] **Step 1: Write** the opt-in tests:
  - `stful in an empty lib/w.dart of a temp Flutter project returns a snippet whose body contains StatefulWidget`;
  - `void main() { x; } gets an error diagnostic on x`.
  Each uses the real `DartAnalysisRepositoryImpl`.
- [ ] **Step 2: Run** `DART_LSP_TEST=1 flutter test test/integration/dart_analysis_test.dart`. Expected: PASS. Run plain `flutter test`. Expected: skipped.
- [ ] **Step 3: Update** the docs.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze`. Expected: PASS and clean.
- [ ] **Step 5: Commit** `test(dart_analysis): the real server, opt-in; docs`.
