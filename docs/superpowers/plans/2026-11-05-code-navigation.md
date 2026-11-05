# Code Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hover documentation, go to definition, find references, back/forward history and format on save in the Code view's Dart files, plus read-only tabs for code outside the project.

**Architecture:**
- `DartAnalysisServer` gains four LSP requests (`hover`, `definition`, `references`, `formatting`), and `IDartAnalysisRepository` exposes them with the current text flushed first.
- In `feature/code_view/`:
  - `CodeWorkspace` owns the navigation history and `navigateTo`;
  - `CodeTabsController` opens files outside the project read-only and runs a format hook before saving;
  - a per-tab `CodeNavigationController` drives hover and the jumps;
  - the hover card and the references dialog are new widgets.

**Tech Stack:** Flutter macOS, re_editor 0.10.0 (`CodeEditor.readOnly`, `runRevocableOp`, `index2lineIndex`), `dart language-server` (LSP), flutter_markdown_plus (already a dependency), freezed, gen-l10n en/ru.

**Spec:** `docs/superpowers/specs/2026-11-05-code-navigation-design.md` (Russian).

## Global Constraints

- Follow CLAUDE.md and `docs/AI_INSTRUCTIONS.md`:
  - `common/` never imports `feature/`;
  - colors only from `context.colors`, radii from `AppRadius`;
  - no new dependency.
- Only paths ending in `.dart` get hover, definition, references and formatting.
- Positions sent to the server are document lines (folds mapped with `index2lineIndex`) and UTF-16 columns, as completion does.
- An answer that arrives after the text changed or the caret moved is dropped.
- Timings:
  - hover: 500 ms of rest, and 150 ms of grace to move from the name into the card;
  - format request: 2 s timeout;
  - the "not found" message: 2 s.
- History holds 50 places per project.
- Hover card: max width 480, max height 300 (scrolls).
- Keys:
  - in Dart tabs: F12 definition, ⇧F12 references, ⇧⌥F format, ⌘-click definition;
  - in the Code view: ⌃- back, ⌃⇧- forward.
- Copy, en / ru:
  - `codeNoDefinition`: "No definition found" / «Определение не найдено»;
  - `codeNoReferences`: "No references" / «Ссылок нет»;
  - `codeReferencesTitle(name, count)`: "References to {name} ({count})" / «Ссылки на {name} ({count})»;
  - `codeDefinitionsTitle(name, count)`: "Definitions of {name} ({count})" / «Определения {name} ({count})»;
  - `codeReferencesFilter`: "Filter by file or code" / «Фильтр по файлу или коду»;
  - `codeNavigateBack`: "Back (⌃-)" / «Назад (⌃-)»;
  - `codeNavigateForward`: "Forward (⌃⇧-)" / «Вперёд (⌃⇧-)»;
  - `codeReadOnly`: "Read-only" / «Только для чтения»;
  - `settingsFormatOnSave`: "Format Dart files on save" / «Форматировать Dart-файлы при сохранении»;
  - `settingsFormatOnSaveHint`: "⇧⌥F formats without saving" / «⇧⌥F форматирует без сохранения».
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Typing while formatting.** If the user types while the format request is out, the answer must be dropped and the file saved with the current text, never with the edits applied to stale offsets (Task 7).
2. **CRLF files.** Formatting a `\r\n` file applies the edits at the right offsets and keeps `\r\n` line breaks (Task 7).
3. **Folded targets.** A definition inside or below a folded block puts the caret on the right document line (Task 3).
4. **Read-only tabs everywhere else.**
   - They never count as unsaved, never make quitting or "send to agent" ask, and are not restored.
   - A restart with one open still restores the project's own tabs (Task 3).
5. **Pointer position.** The hover position is right with horizontal and vertical scroll, the find panel open, and a fold above (Task 5).

---

### Task 1: The four LSP requests in `DartAnalysisServer`

**Files:**
- Create:
  - `lib/src/common/dart_analysis/models/dart_hover.dart` (`DartHover`)
  - `lib/src/common/dart_analysis/models/lsp_location.dart` (`LspLocation`)
- Modify: `lib/src/common/dart_analysis/dart_analysis_server.dart`
- Test: `test/common/dart_analysis/dart_analysis_server_test.dart`

**Interfaces:**
- Consumes: `LspPosition`, `LspRange`, `LspTextEdit` (`models/lsp_range.dart`), `ScriptedLspProcess` (`test/support`).
- Produces:
  - `final class DartHover { const DartHover({required String markdown, LspRange? range}); factory DartHover.fromJson(Object? json); }`. It reads `contents` given as `{kind, value}`, as a plain string, or as a list of strings joined with `\n\n`. It returns `null` when there's no text.
  - `final class LspLocation { const LspLocation({required String path, required LspRange range}); static LspLocation? fromJson(Object? json); }`. It reads `Location` (`uri`, `range`) and `LocationLink` (`targetUri`, `targetSelectionRange`). It returns `null` for non-`file` URIs.
  - On `DartAnalysisServer`:
    - `Future<DartHover?> hover(String path, LspPosition position)`;
    - `Future<List<LspLocation>> definition(String path, LspPosition position)`;
    - `Future<List<LspLocation>> references(String path, LspPosition position)`, sent with `context: {includeDeclaration: true}`;
    - `Future<List<LspTextEdit>?> format(String path, {Duration timeout = const Duration(seconds: 2)})`, sent with `options: {tabSize: 2, insertSpaces: true}`. It returns `null` when the result is `null`.

- [ ] **Step 1: Write the failing tests** in a `group('navigation')`:
  - `'initialize declares hover, definition, references and formatting'`: `capabilities.textDocument.hover.contentFormat == ['markdown', 'plaintext']`, and the keys `definition`, `references` and `formatting` are present.
  - `'hover reads markdown contents and range'`: the reply is `{contents: {kind: 'markdown', value: '```dart\nint x\n```\nDoc.'}, range: …}`, giving `markdown == '```dart\nint x\n```\nDoc.'`. A `null` reply gives `null`.
  - `'definition reads Location and LocationLink'`: a `Location[]` and a `LocationLink[]` both give `LspLocation(path: '/p/lib/a.dart', range: …)`. A single `Location` object, not in a list, gives one item. A `null` reply gives `[]`.
  - `'references sends includeDeclaration'`: check the request params, and that `Location[]` is parsed.
  - `'format returns edits, null on a null result'`: also check the `options` params.

- [ ] **Step 2:** Run `flutter test test/common/dart_analysis/dart_analysis_server_test.dart`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement the models and the four methods. Add to `initialize` `capabilities.textDocument`:
  - `hover: {contentFormat: [markdown, plaintext]}`;
  - `definition: {linkSupport: true}`;
  - `references: {}`;
  - `formatting: {}`.
- [ ] **Step 4:** Run the test file again. Expected: PASS.
- [ ] **Step 5:** Commit with `feat(dart_analysis): hover, definition, references and formatting requests`.

### Task 2: The repository methods

**Files:**
- Modify: `lib/src/feature/code_view/data/dart_analysis_repository.dart`
- Test: `test/feature/code_view/dart_analysis_repository_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces on `IDartAnalysisRepository`:
  - `Future<DartHover?> hover(String path, String text, LspPosition position)`;
  - `Future<List<LspLocation>> definition(String path, String text, LspPosition position)`;
  - `Future<List<LspLocation>> references(String path, String text, LspPosition position)`;
  - `Future<List<LspTextEdit>?> format(String path, String text)`.
- Each one calls `_flush(path, text)` first, exactly like `complete`. Without a server, for a file that isn't open, or on any error, it returns `null` or `[]`.
- Every fake of `IDartAnalysisRepository` in `test/` gets the four methods, returning `null` or `[]`.

- [ ] **Step 1: Write the failing tests:**
  - `'navigation requests send the unsent text first'`: `change` with new text, then `hover` immediately. `didChange` with that text is received before `textDocument/hover`. Do the same for `definition`, `references` and `format`.
  - `'navigation requests are empty without a server'`: nothing open, so `hover` gives `null`, `definition` and `references` give `[]`, and `format` gives `null`.
  - `'format gives null when the server does not answer in 2 s'`: the scripted server stays silent, and with fake time `format` completes with `null` after 2 s.
- [ ] **Step 2:** Run `flutter test test/feature/code_view/dart_analysis_repository_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement the methods and update the fakes. Find the fakes with `grep -rln "implements IDartAnalysisRepository" test`.
- [ ] **Step 4:** Run the test file again, then `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(code_view): navigation requests in the analysis repository`.

### Task 3: Read-only tabs for code outside the project

**Files:**
- Create: `lib/src/feature/code_view/data/code_package_labels.dart`
- Modify:
  - `lib/src/feature/code_view/controller/code_document.dart`
  - `lib/src/feature/code_view/controller/code_tabs_controller.dart`
  - `lib/src/feature/code_view/controller/code_workspace.dart`
  - `lib/src/feature/code_view/widgets/code_tab_bar.dart`
  - `lib/src/feature/code_view/widgets/code_editor_view.dart`
  - `lib/src/feature/code_view/widgets/code_view.dart`
  - arb files: `codeReadOnly`
- Test:
  - `test/feature/code_view/code_package_labels_test.dart`
  - `code_tabs_controller_test.dart`
  - `code_editor_test.dart`

**Interfaces:**
- Produces:
  - `final class CodePackageLabels`:
    - `CodePackageLabels.parse(String packageConfigJson, {required String configDir, required String home})`, where `configDir` is the `.dart_tool` folder that relative `rootUri`s resolve against;
    - `const CodePackageLabels.none({required String home})`;
    - `String labelFor(String path)`.
  - `labelFor` returns:
    - `package:<name>/<path under the package's lib dir>`;
    - for a path containing `/dart-sdk/lib/`, `dart:` plus the rest (`/…/dart-sdk/lib/core/int.dart` becomes `dart:core/int.dart`);
    - otherwise the path with the home folder replaced by `~`.
  - `CodeDocument.open(path, {required files, bool readOnly = false})`, plus `bool get readOnly`. For a read-only document, `save` is a no-op, `dirty` is always `false`, and `onDiskChange` is ignored.
  - `CodeDocument.unfoldAll()`. Move `_unfoldAll` here from `DartCompletionController`, which then calls it.
  - `CodeTabsController.open(String path, {int? line, int column = 0})`:
    - `line` is 1-based and `column` is 0-based UTF-16;
    - with a line, it unfolds and then selects `(line - 1, column)`;
    - a path not within `root` opens read-only.
  - Read-only tabs:
    - are left out of the saved `CodeViewState`;
    - don't count toward `unsavedCount`;
    - aren't matched by `_onChange`.
  - `CodeWorkspace.labels`, a `Future<CodePackageLabels>` loaded once from `<root>/.dart_tool/package_config.json` through `files.read`. It falls back to `.none`.
  - `CodeTabBar(…, labelFor: String Function(CodeDocument))`. A read-only tab shows `Icons.lock_outline` (14 px, `muted`, tooltip `codeReadOnly`) and the label as its tooltip.
  - `CodeEditorView` passes `readOnly: document.readOnly` to `CodeEditor`. `CodeFindPanel` hides replace when it's read-only; it already receives `readOnly`.

- [ ] **Step 1: Write the failing tests:**
  - `code_package_labels_test`:
    - a `package_config.json` with `flutter` (`rootUri: file:///sdk/packages/flutter`, `packageUri: lib/`) and `app` (`rootUri: ../`) gives:
      - `/sdk/packages/flutter/lib/src/widgets/container.dart` → `package:flutter/src/widgets/container.dart`;
      - `<root>/lib/main.dart` → `package:app/main.dart`;
    - `/x/bin/cache/dart-sdk/lib/core/int.dart` → `dart:core/int.dart`;
    - `/Users/me/other.dart` with home `/Users/me` → `~/other.dart`.
  - `code_tabs_controller_test`:
    - `'a file outside the project opens read-only and is not restored'`: open `/outside/a.dart` and `<root>/lib/b.dart`, dispose, then restore with a new controller. Only `lib/b.dart` comes back, and `unsavedCount == 0` after typing into the read-only document's controller. Type straight into its controller, since the editor blocks typing.
    - `'open with line and column unfolds and places the caret'`: a file with a foldable block at lines 1–5, fold it, then `open(path, line: 4, column: 2)` gives selection `(3, 2)`.
  - `code_editor_test`, macOS variant: `'a read-only tab cannot be edited, find works, replace is hidden'`.
- [ ] **Step 2:** Run the three test files. Expected: FAIL.
- [ ] **Step 3:** Implement. `CodeView` passes `labelFor` from the resolved `workspace.labels`, or the path relative to the root while that's loading.
- [ ] **Step 4:** Run `flutter test test/feature/code_view` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(code_view): read-only tabs for code outside the project`.

### Task 4: Navigation history, back and forward

**Files:**
- Create: `lib/src/feature/code_view/controller/code_navigation_history.dart`
- Modify:
  - `code_workspace.dart`
  - `code_view.dart`
  - `code_tab_bar.dart`
  - arb files: `codeNavigateBack`, `codeNavigateForward`
- Test:
  - `test/feature/code_view/code_navigation_history_test.dart`
  - `test/feature/code_view/code_view_navigation_test.dart`

**Interfaces:**
- Consumes: Task 3, `tabs.open(path, line:, column:)`.
- Produces:
  - `typedef CodePlace = ({String path, LspPosition position});`, with a 0-based line and column.
  - `final class CodeNavigationHistory extends ChangeNotifier`:
    - `static const int limit = 50`;
    - `void record(CodePlace from)`: pushes onto back, clears forward, and drops the oldest past the limit;
    - `CodePlace? back(CodePlace current)`: pops back and pushes `current` onto forward;
    - `CodePlace? forward(CodePlace current)`;
    - `bool get canGoBack`, `bool get canGoForward`.
  - On `CodeWorkspace`:
    - `final CodeNavigationHistory history`;
    - `Future<void> navigateTo(String path, {LspPosition? at})`: records the active text tab's caret as a document position, if there is one, then calls `tabs.open(path, line: at == null ? null : at.line + 1, column: at?.character ?? 0)`;
    - `Future<void> goBack()` and `Future<void> goForward()`: they open the place without recording, and skip places whose file is gone (`PathNotFoundException`).
  - `CodeView`:
    - ⌘P calls `workspace.navigateTo(path)`;
    - ⌃- (`LogicalKeyboardKey.minus, control: true`) calls `goBack`, and ⌃⇧- calls `goForward`.
  - `CodeTabBar(…, history, onBack, onForward)`: the right end gets ← and → `IconButton`s (16 px), disabled when the move isn't possible, with tooltips `codeNavigateBack` and `codeNavigateForward`.

- [ ] **Step 1: Write the failing tests:**
  - `code_navigation_history_test`:
    - record A, B, then `back(C)` gives B and `back(B)` gives A;
    - `forward` gives B, then C;
    - recording after a back clears forward;
    - 51 records keep the newest 50.
  - `code_view_navigation_test`, macOS:
    - `'⌘P records the place it leaves; ⌃- and ⌃⇧- go back and forward'`;
    - `'the back button is disabled without history'`;
    - `'a place whose file was deleted is skipped'`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/feature/code_view` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(code_view): back and forward through navigation history`.

### Task 5: Hover documentation

**Files:**
- Create:
  - `lib/src/feature/code_view/controller/code_navigation_controller.dart`
  - `lib/src/feature/code_view/widgets/code_pointer_position.dart`
  - `lib/src/feature/code_view/widgets/code_hover_card.dart`
- Modify:
  - `code_editor_view.dart`
  - `code_diagnostic_spans.dart` (remove `onEnter`/`onExit`: underlines only)
- Test:
  - `test/feature/code_view/code_pointer_position_test.dart`
  - `test/feature/code_view/code_hover_test.dart`
  - update the hover tests in `code_diagnostics_test.dart`

**Interfaces:**
- Consumes: Task 2 (`hover`), `CodeDocument.diagnostics`.
- Produces:
  - `LspPosition? codePositionAt(CodeLineEditingController editing, Offset local, {required double gutterWidth, required double charWidth, required double lineHeight, required double scrollX, required double scrollY, double topInset = 0})`.
    - `local` is relative to the editor box, and `topInset` is the height of the find panel.
    - The visual line is `((local.dy - padding - topInset + scrollY) / lineHeight).floor()`, mapped to a document line with `index2lineIndex`.
    - The column is `((local.dx - gutterWidth - padding + scrollX) / charWidth).floor()`, where `padding` is `CodeEditorView.padding`.
    - It returns `null` outside the text of a line.
    - Move the find-panel height (`(replaceMode ? 72 : 36) + 8`) from `_listPosition` into a shared helper `codeFindPanelHeight(CodeFindValue?)` and use it in both places.
  - `final class CodeHoverInfo { DartHover? doc; List<DartDiagnostic> diagnostics; Offset anchor; }`, where `anchor` is global, under the pointer.
  - `final class CodeNavigationController extends ChangeNotifier`:
    - constructor `({required CodeDocument document, required IDartAnalysisRepository analysis})`;
    - `static const Duration hoverDelay = Duration(milliseconds: 500)`;
    - `static const Duration hoverGrace = Duration(milliseconds: 150)`;
    - `void pointerAt(LspPosition? position, Offset global)`: restarts the delay. When it fires, the controller asks for `hover` and collects the diagnostics whose range contains the position. It sets `hover` only if the text, the caret and the pointer's position didn't change meanwhile, and something was found.
    - `void pointerLeft()`: hides after the grace period unless `keepHover()` is called;
    - `void keepHover()`: called by the card on enter;
    - `CodeHoverInfo? get hover`;
    - `void dismissHover()`;
    - any edit or Esc dismisses.
  - `CodeHoverCard(info, onEnter, onExit)` shows:
    - the error and warning messages first, colored like the underline (`diagnosticColor`);
    - then the first fenced ` ```dart ` block of the markdown in mono;
    - then the rest through `MarkdownBody` from flutter_markdown_plus.
    - Its constraints are max width 480 and max height 300, inside a `SingleChildScrollView`.
  - `CodeEditorView` creates `_navigation` next to `_completion`, for Dart files with an analysis. It wraps the editor in a `MouseRegion(onHover:, onExit:)` that feeds `pointerAt` and `pointerLeft`. The card replaces the current diagnostic hover overlay, using the same `OverlayPortal`.

- [ ] **Step 1: Write the failing tests:**
  - `code_pointer_position_test`:
    - line 2, column 4 is found with no scroll;
    - the same point with `scrollY = 2 * lineHeight` gives line 4;
    - with `scrollX = 3 * charWidth` it gives column 7;
    - with `topInset = 44` it gives the same line as without the panel when `local.dy` grows by 44;
    - with lines 1–4 folded into one, the visual line 2 gives document line 5;
    - past the end of a line gives `null`.
  - `code_hover_test`, macOS:
    - `'resting 500 ms on a name shows its declaration and docs'`: a fake hover reply with `'```dart\nclass Foo\n```\nA foo.'`. Before 500 ms nothing shows; after it, `find.text('class Foo')` and `find.text('A foo.')` both show.
    - `'an error under the pointer shows in the same card'`;
    - `'typing or Esc closes the card'`;
    - `'a hover answer after an edit is dropped'`;
    - `'moving into the card keeps it open'`;
    - `'the card fits at 900×600 in en and ru, light and dark'`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/feature/code_view` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(code_view): hover documentation`.

### Task 6: Go to definition and find references

**Files:**
- Create: `lib/src/feature/code_view/widgets/code_references_dialog.dart`
- Modify:
  - `code_navigation_controller.dart`
  - `code_editor_view.dart`
  - `code_view.dart`
  - `code_workspace.dart`
  - arb files: `codeNoDefinition`, `codeNoReferences`, `codeReferencesTitle`, `codeDefinitionsTitle`, `codeReferencesFilter`
- Test: `test/feature/code_view/code_definition_test.dart`

**Interfaces:**
- Consumes:
  - Task 2 (`definition`, `references`);
  - Task 3 (labels, read-only);
  - Task 4 (`navigateTo`);
  - Task 5 (`CodeNavigationController`).
- Produces:
  - `typedef CodeJump = ({String name, List<LspLocation> locations});`
  - On `CodeNavigationController`:
    - `Future<CodeJump?> definitionAtCaret()` and `Future<CodeJump?> referencesAtCaret()`;
    - `name` is the identifier at the caret (`[A-Za-z0-9_$]+`);
    - they return `null` when the text or the caret changed before the answer arrived.
  - `typedef CodeReference = ({String path, String label, int line, int start, int end, String text});`, where `line` is 0-based and `text` is the trimmed code line, `''` if unreadable.
  - `Future<List<CodeReference>> CodeWorkspace.referencesFor(List<LspLocation> locations)`:
    - it reads each distinct file once, from an open tab if there is one, otherwise through `files.read`;
    - it sorts files inside `root` first, then by path, then by line;
    - `start` and `end` are shifted for the trimmed leading whitespace.
  - `Future<CodeReference?> showCodeReferences(BuildContext context, {required String title, required List<CodeReference> references})`:
    - it's modeled on `showCodeQuickOpen`: a filter field with hint `codeReferencesFilter` that matches the label or the text, case-insensitively;
    - rows show `label:line+1`, then the text in mono with `[start, end)` bold;
    - ↑↓, Enter and Esc work.
  - In `CodeEditorView`, through `onJump: Future<void> Function(CodeJump jump, {required bool references})`, which `CodeView` provides:
    - F12 and ⌘-click jump to the definition. For ⌘-click, a `Listener.onPointerUp` with `HardwareKeyboard.instance.isMetaPressed` waits a post-frame callback, then uses the caret.
    - ⇧F12 shows references.
    - One definition goes through `navigateTo(path, at: range.start)`.
    - Several definitions, or any references, open the dialog titled `codeDefinitionsTitle` or `codeReferencesTitle`. A picked row goes through `navigateTo(path, at: LspPosition(line, start))`, using the original column.
    - None shows `codeNoDefinition` or `codeNoReferences` at the bottom of the editor for 2 s (`CodeEditorView.messageDuration`).
    - A single definition whose file is gone (`navigateTo` throws `PathNotFoundException`) shows `codeNoDefinition` too.

- [ ] **Step 1: Write the ⌘-click probe test first:**
  - `'⌘-click puts the caret on the clicked name'`: tap with `meta` held at a known position, then assert the selection.
  - If re_editor doesn't move the caret on a ⌘-click, change the `Listener` to compute the position with `codePositionAt` from the event. Note the change in the commit message.
- [ ] **Step 2: Write the failing tests**, all macOS:
  - `'F12 opens the definition with the caret on the name'`: a fake definition gives `/root/lib/b.dart` 3:6, so tab `b.dart` is active with selection `(3, 6)`, and `history.canGoBack` is true.
  - `'⌘-click opens the definition'`;
  - `'a definition outside the project opens a read-only tab'`;
  - `'two definitions open the list; Enter opens the highlighted one'`;
  - `'⇧F12 lists references: project files first, filter narrows, Esc closes'`;
  - `'no definition shows the message for 2 s'`;
  - `'a definition in a deleted file shows the message'`;
  - `'a definition answer after the caret moved is dropped'`;
  - `'the references dialog fits at 900×600 in en and ru'`.
- [ ] **Step 3:** Run `flutter test test/feature/code_view/code_definition_test.dart`. Expected: FAIL, except the probe.
- [ ] **Step 4:** Implement.
- [ ] **Step 5:** Run `flutter test test/feature/code_view` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 6:** Commit with `feat(code_view): go to definition and find references`.

### Task 7: Format on save, ⇧⌥F and the setting

**Files:**
- Create: `lib/src/feature/code_view/controller/code_format.dart`
- Modify:
  - `code_tabs_controller.dart`
  - `code_workspace.dart`
  - `code_view.dart`
  - `code_editor_view.dart`
  - `lib/src/feature/app_settings/models/app_settings.dart`
  - `general_settings_section.dart`
  - `workspace_config_widget.dart`
  - arb files: `settingsFormatOnSave`, `settingsFormatOnSaveHint`
- Test:
  - `test/feature/code_view/code_format_test.dart`
  - `test/feature/code_view/code_format_on_save_test.dart`
  - the AppSettings JSON test

**Interfaces:**
- Consumes: Task 2 (`format`), Task 3 (`readOnly`).
- Produces:
  - `void applyTextEdits(CodeLineEditingController editing, List<LspTextEdit> edits)`. It runs inside one `editing.runRevocableOp`:
    - join the document lines (after `unfoldAll`) with `\n`;
    - apply the edits from the last to the first, after normalizing `\r\n` in `newText` to `\n`;
    - set the value with `CodeLines.fromText` and the caret moved to its new offset. A caret inside a replaced range goes to that edit's start plus `min(old offset into it, newText.length)`.
    - The line-break option (CRLF) stays as it was.
  - `Future<bool> formatDocument(CodeDocument document, IDartAnalysisRepository analysis)`:
    - it returns `false`, changing nothing, for a document that isn't Dart, isn't text or is read-only;
    - also for an answer of `null` or empty, or when `document.editing.codeLines` changed while waiting;
    - otherwise it applies the edits and returns `true`.
  - `CodeTabsController.beforeSave` (`Future<void> Function(CodeDocument)?`) and `Future<void> save(CodeDocument document, {bool overwrite = false})`. `save` awaits `beforeSave`, then calls `document.save`. `saveAll` uses `save`, and `CodeView._save` calls `tabs.save`.
  - `CodeViewRegistry.formatOnSave` (`bool`, default `true`). The registry hands each workspace `formatOnSave: () => this.formatOnSave`.
  - `CodeWorkspace` sets `tabs.beforeSave` to format when `formatOnSave()` is true and there's an `analysis`.
  - `WorkspaceConfigWidget` copies `settingsController.settings.formatOnSave` into `Dependencies.of(context).codeViews.formatOnSave` on init and on every settings change.
  - `AppSettings.formatOnSave`:
    - default `true`;
    - JSON key `formatOnSave` (`is! bool || value`);
    - added to `toJson` and `copyWith`.
  - A `SettingsRow` in General with a `Switch`.
  - ⇧⌥F (`keyF, shift: true, alt: true`) in Dart tabs calls `formatDocument`.

- [ ] **Step 1: Write the failing tests:**
  - `code_format_test`:
    - `'applies edits bottom-up and keeps the caret on the same code'`: text `'void  main( ){}\n'` with the caret on `m`, and the edits the server gives for it. The result is `'void main() {}\n'`, with the caret before `m`.
    - `'one undo restores the unformatted text'`;
    - `'a CRLF file keeps CRLF'`;
    - `'formatDocument drops the answer when the text changed meanwhile'`: the fake `format` completes after a `replaceSelection`, so the text equals the edited one and the result is `false`.
    - `'read-only and non-Dart documents are not formatted'`.
  - `code_format_on_save_test`, macOS:
    - `'⌘S formats then saves'`: the file on disk is the formatted text;
    - `'with the setting off ⌘S saves unformatted'`;
    - `'a null format answer (syntax error) saves as is'`;
    - `'⇧⌥F formats without saving'`: the tab is dirty;
    - `'save all formats Dart tabs'`;
    - `'typing during the format request saves the typed text unformatted'`: the fake `format` completes only after a keystroke, so the file on disk equals the editor's text.
  - AppSettings: `formatOnSave` defaults to `true`, survives a JSON round trip, and a non-bool value gives `true`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/feature/code_view test/feature/app_settings` and `flutter analyze`. Expected: PASS and no issues.
- [ ] **Step 5:** Commit with `feat(code_view): format on save, ⇧⌥F and its setting`.

### Task 8: The real server, docs and the full suite

**Files:**
- Modify:
  - `test/integration/dart_analysis_test.dart`
  - `docs/PLAN.md` (tick the Code view's "next milestone" line and name the spec)

- [ ] **Step 1:** Add opt-in tests (`DART_LSP_TEST=1`, tag `dart_analysis`) in the existing temp Flutter project:
  - hover on `StatelessWidget` gives markdown containing `StatelessWidget`;
  - the definition of `StatelessWidget` gives a path ending in `framework.dart` outside the project;
  - the references to a local function include its declaration and its call;
  - formatting `void  main( ){}` gives `void main() {}`.
- [ ] **Step 2:** Run `DART_LSP_TEST=1 flutter test test/integration/dart_analysis_test.dart`. Expected: PASS. Run it once only.
- [ ] **Step 3:** Run the full suite in the background with `flutter test`, then `flutter analyze`. Expected: all pass and no issues.
- [ ] **Step 4:** Commit with `test(dart_analysis): navigation against the real server; docs`.
