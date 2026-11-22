# Error handling and telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One error pipeline — `handle(error:, done:)` → observer → `ErrorUtil` → cleaned log in
`logs.sqlite` → queue of unexpected errors → crash-report gateway — in the agent rules, in FAgent,
and in every "My architecture" project (Sentry, Firebase Crashlytics or log only).

**Architecture:** The cafe_pos package `packages/telemetry` is ported into FAgent as a portable,
pure-Dart module `lib/src/common/telemetry/` (no FAgent imports but its own files). FAgent wires it
with a thin `ErrorUtil` facade, a startup step and a Settings section. The project template copies
the same folder from FAgent's assets into `lib/_core/telemetry/` (one app) or
`packages/telemetry/` (monorepo), with glue files of its own.

**Tech Stack:** Flutter 3.50 / Dart 3.14, `control` (git pin), drift, `l`, `sentry` (pure Dart),
`clock`, `archive`, `firebase_core` + `firebase_crashlytics` (template option only), freezed,
gen-l10n.

**Spec:** `docs/superpowers/specs/2026-11-22-error-telemetry-design.md`

**Sources to port from (read, never edit):** `/Users/avaz/StudioProjects/cafe_pos/packages/telemetry/`
(lib and test), `/Users/avaz/StudioProjects/cafe_pos/apps/desktop/lib/_core/telemetry/`,
`/Users/avaz/StudioProjects/cafe_pos/apps/desktop/lib/initialization/telemetry_setup.dart`,
`/Users/avaz/StudioProjects/cafe_pos/apps/desktop/lib/telemetry/`,
`/Users/avaz/StudioProjects/cafe_pos/docs/rules/`, `/Users/avaz/Desktop/error-handling-guide.md`.

## Global Constraints

- CLAUDE.md rules: desktop only; widgets → controller → repository; no IO in widgets; colours only
  from `context.colors`, radii from `AppRadius`; strings in en and ru through gen-l10n
  (`flutter pub get` regenerates); every `Process` killed; every `Stream` method follows the
  "Stream-Returning Methods" rules; never silence a lint; generated files are never edited.
- `control` stays pinned: `git: {url: https://github.com/PlugFox/control.git, ref: 685a9bc6ef60c987b99b5526e125813adba54e2a}`.
- Before adding a package, check its latest version and status on pub.dev; no discontinued
  packages. Known: `sentry` 10.6.0, `firebase_crashlytics` 6.1.0 (platforms android, ios, macos).
- The module `lib/src/common/telemetry/` imports only `package:flutter_code_agent/src/common/telemetry/…`
  and pub packages — no other FAgent file, no `package:flutter/`. `always_use_package_imports` is
  an error in FAgent and in the template, so no relative imports.
- `logs.sqlite` is its own drift database (schema version 1), in the application support
  directory, never a table of FAgent's main database.
- Controller recipe everywhere: `handle(() async {…}, error: (error, stackTrace) async => setState(…error…), done: () async => setState(…idle…))`;
  no `on Object catch`, untyped `catch` or `finally` in a controller; allowed only a typed `on X`
  with its own reaction, a typed `on X` + `rethrow`, or a side read with `on Exception` +
  `ErrorUtil.logError(…, hint: …)` + a comment.
- Only unexpected errors enter the queue; `isExpectedFailure` is the one place that decides.
- Consent: nothing recorded before the switch was turned on (message, stack, breadcrumbs, count)
  ever leaves the machine.
- FAgent's switch "Send crash reports" defaults to off. FAgent uses Sentry only.
- DSN: `config/sentry.local.json` (git-ignored) with key `SENTRY_DSN`, read by
  `String.fromEnvironment('SENTRY_DSN')`; empty DSN means no sending, the log and queue are kept.
- Template layouts: one app → `lib/_core/telemetry/`, `lib/_core/database/`, `lib/_core/api_client/`;
  monorepo → `packages/telemetry/`, `packages/database/`, `packages/api_client/` (unprefixed names,
  each `lib/<name>.dart` + `lib/src/`), app glue in `apps/<app>/lib/_core/telemetry/`. No `core`
  package; `ExpectedException` and `RejectedException` live in `api_client`.
- Template crash reporter options: `sentry` (default), `crashlytics`, `logOnly`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A log or queue entry built from agent output that holds an API key (`sk-ant-…`, `ghp_…`) or
   `/Users/<name>` — expected: `[REDACTED]` on disk, in the archive and in the event (Task 3
   test `redact_test` "agent keys", Task 8 archive test).
2. A user turns crash reports on after a week offline with 15 queued errors — expected: none of
   them is sent, and a recurrence after consent sends only its new occurrence (Task 5 tests).
3. `logs.sqlite` cannot be opened (read-only support directory) — expected: FAgent still starts,
   errors go to stderr, Settings shows the section without a queue and "Save log archive…" writes
   a note file (Task 6 test "starts without the log", Task 8 test).
4. A project created with Crashlytics before `flutterfire configure` — expected: it builds, runs
   with the log only, and `Firebase.initializeApp` failing is logged, not fatal (Task 10 test).
5. "Add to project…" into a monorepo made before this change (no `packages/telemetry`) —
   expected: the skeleton is not offered, Empty only, with a hint (Task 11 test).

---

### Task 1: Rules — the controller recipe

**Files:**
- Modify: `assets/knowledge/rules/controllers.md`, `assets/knowledge/rules/repositories.md`,
  `assets/knowledge/rules/architecture.md`
- Test: `test/knowledge/error_rules_test.dart` (create)

**Interfaces:** Produces the wording later tasks cite: sections "Where the error goes",
"Expected and unexpected errors", "Typed `on` with `rethrow`", "An action of two steps",
"Reporting an error" in `controllers.md`.

- [ ] **Step 1: Write the failing test** `test/knowledge/error_rules_test.dart`, reading the files
  with `File('assets/knowledge/rules/<name>.md').readAsStringSync()`:
  - `controllers.md has the handle recipe`: contains `error: (error, stackTrace) async =>` and
    `done: () async =>`, and the headings `### Where the error goes`, `#### Typed \`on\` with \`rethrow\``,
    `### An action of two steps`, `### Reporting an error`.
  - `no controller example catches everything`: in every ```` ```dart ```` block of
    `controllers.md` and `architecture.md` that contains `handle(`, there is no `on Object catch`
    and no `} finally {`.
  - `no cafe specifics`: none of `controllers.md`, `repositories.md`, `architecture.md` contains
    `CAFEPOS`, `deviceGuard`, `venue`, `заведени`, `PIN`.
  - `repositories.md reports with ErrorUtil`: contains `**Report with \`ErrorUtil\`, nothing else.**`.
- [ ] **Step 2: Run** `flutter test test/knowledge/error_rules_test.dart` — Expected: FAIL (headings missing).
- [ ] **Step 3: Port** the sections from `cafe_pos/docs/rules/controllers.md`, `repositories.md`,
  `architecture.md` (diff each against FAgent's file; take only error-handling changes), rewritten
  generically. Keep FAgent's own changes (monorepo layout, `material_ui`, the project's
  `ApiClient`). Pipeline sentences are conditional, per the spec: "a project that has `ErrorUtil`
  reports through it; a project with another reporter keeps it and follows the same split; a new
  project starts with the pipeline". Add to `controllers.md`: showing a message is `error:` +
  `errorText` in the widget's `listener`; a special reaction is a typed `on` in the body; no
  callbacks from a controller into the UI. `architecture.md` names where the pieces live in both
  layouts (one app `lib/_core/{telemetry,database,api_client}/`, monorepo `packages/…`).
- [ ] **Step 4: Run** the test — Expected: PASS. Run `flutter test test/screenshots/readme_screenshots_test.dart test/fixtures` only if they read these files (grep first).
- [ ] **Step 5: Commit** `docs(rules): controllers report through handle(error:, done:)`.

### Task 2: Rules — crash reports, DSN, startup, widgets, tests

**Files:**
- Modify: `assets/knowledge/rules/security.md`, `configuration.md`, `dependencies.md`,
  `widgets.md`, `testing.md`
- Test: `test/knowledge/error_rules_test.dart` (extend)

- [ ] **Step 1: Add failing tests**:
  - `security.md has Crash reports`: heading `## Crash reports`; mentions `sendDefaultPii`,
    `redactSecrets`, `HiddenDetailsError`, `Firebase Crashlytics`, and the sentence fragment
    `recorded before` (consent).
  - `configuration.md has the DSN`: heading `### The Sentry DSN`; contains `config/sentry.local.json`,
    `--dart-define-from-file`, `SENTRY_DSN`.
  - `dependencies.md has the error log step`: heading `### The error log and the reporter`;
    contains `catchExceptions` and `STARTUP ERROR`.
  - `widgets.md names the five places`: contains `LoadErrorView`, `RefreshFailedNotice`, `errorText`.
  - the "no cafe specifics" test now covers these five files too.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Port** from `cafe_pos/docs/rules/` the sections "Crash reports" (generic: drop
  owner permission, audit event, device log, `CAFEPOS`, device key; add the agent API keys of
  Task 3, the consent rule, and the Crashlytics option: gateway behind the queue, never
  `FlutterError.onError = FirebaseCrashlytics…`), "The Sentry DSN" (one key `SENTRY_DSN` per app;
  Makefile passes the file when it exists), "The error log and the reporter" (first step, both
  layouts), and the widget and testing lines about errors (guide sections 14–18).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `docs(rules): crash reports, the DSN and the error log step`.

### Task 3: Telemetry module — text, log and queue

**Files:**
- Create in `lib/src/common/telemetry/`: `clip.dart`, `redact.dart`, `log_record.dart`,
  `log_buffer.dart`, `telemetry_database.dart` (+ generated `.g.dart`), `log_storage.dart`,
  `fingerprint.dart`, `error_outbox.dart`, `hidden_details_error.dart`
- Test: `test/common/telemetry/{redact,log_format,log_buffer,log_storage,fingerprint,error_outbox}_test.dart`,
  `test/common/telemetry/portability_test.dart`
- Modify: `pubspec.yaml` (`clock`), CLAUDE.md nothing yet.

**Interfaces:**
- Produces: `String redactSecrets(String text)`, `String cleanForLog(String text)`,
  `const String redactedMark = '[REDACTED]'`, `String clipForLog(String)`, `String cutSafely(String, int)`;
  `LogBuffer` (`limit = 10000`, `add`, `addAll`, `clear`, `logs`, `lastLines(int)`, `rawLines(int)`);
  `RawLogLine`, `formatLogLine`, `formatRawLogLine(s)`; `TelemetryDatabase` (`forTesting(executor)`),
  `TelemetryDatabase openTelemetryDatabase(File file)`; `readStoredLogs`, `trimStoredLogs`,
  `LogStorage attachLogStorage({required Stream<LogMessage> logs, required TelemetryDatabase db, required LogBuffer buffer})`;
  `String errorFingerprint(Object error, StackTrace stack, {required Set<String> projectPackages})`;
  `ReportedError`, `String errorTypeName(Object)`, `OutboxEntry`,
  `ErrorOutbox(TelemetryDatabase db, {required String appVersion, required String platform, required Set<String> projectPackages, int capacity = 200})`
  with `add`, `oldest`, `newest`, `recent`, `remove`, `markAttempt`, `clear`, `length`, `onChanged`;
  `final class HiddenDetailsError implements Exception, ReportedError` (`HiddenDetailsError(Object original)`).

- [ ] **Step 1: Port the tests** from `cafe_pos/packages/telemetry/test/` (`redact_test`,
  `log_format_test`, `log_buffer_test`, `log_storage_test`, `fingerprint_test`,
  `error_outbox_test`) to `flutter_test`, English names, `package:flutter_code_agent/src/common/telemetry/…`
  imports. Drop the cafe-only cases (`CAFEPOS-`, `Device <key>`, recovery code, `<uuid>.<token>`).
  Add:
  - `redact_test` group `agent keys`: each of `sk-ant-api03-AbCdEf0123456789AbCdEf0123456789`,
    `sk-proj-AbCdEf0123456789AbCdEf01`, `sk-AbCdEf0123456789AbCdEf0123`, `ghp_AbCdEf0123456789AbCdEf0123456789AbCd`,
    `gho_AbCdEf0123456789AbCdEf0123456789AbCd`, `github_pat_11ABCDEFG0123456789_abcdefghijklmnop`,
    `AIzaSyA-AbCdEf0123456789AbCdEf0123456`, `xoxb-1234567890-abcdefghij` inside `key=` -less free text
    becomes `[REDACTED]`; look-alikes stay: `task-manager`, `sk-ip`, `ghp`, `xox`.
  - `fingerprint_test` `uses the given project packages`: two stacks that differ only in frames of
    `package:other/` give the same fingerprint with `projectPackages: {'my_app'}`, and frames of
    `package:my_app/` decide it.
  - `portability_test`: every `.dart` file in `lib/src/common/telemetry/` (not `.g.dart`) has no
    `import 'package:flutter/`, no `import '../`, no relative import, and every
    `package:flutter_code_agent/` import starts with `package:flutter_code_agent/src/common/telemetry/`.
    The same holds for every test in `test/common/telemetry/` (they are copied into new projects
    too: no `test/support/` helpers, only `flutter_test`, the module and pub packages).
- [ ] **Step 2: Run** `flutter test test/common/telemetry` — Expected: FAIL (files missing).
- [ ] **Step 3: Port the sources** from `cafe_pos/packages/telemetry/lib/src/` with English comments,
  the cafe-only patterns removed, the agent-key patterns added (each with a left boundary
  `(?<![A-Za-z0-9_-])` so the scan stays linear), and `package:cafe_` replaced by
  `projectPackages` (a frame is the project's when it contains `package:<name>/` for a name in the
  set, or `+0x`). `HiddenDetailsError` as in the guide section 12. Add `clock` with `flutter pub add`.
  Run `dart run build_runner build` for `telemetry_database.g.dart`.
- [ ] **Step 4: Run** `flutter test test/common/telemetry` and `flutter analyze lib/src/common/telemetry test/common/telemetry` — Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat(telemetry): log, queue and cleaning of the error pipeline`.

### Task 4: Telemetry module — reporter, hub, sender, gateways, startup

**Files:**
- Create in `lib/src/common/telemetry/`: `error_reporter.dart`, `error_hub.dart`,
  `telemetry_status.dart`, `crash_report_gateway.dart`, `sentry_gateway.dart`,
  `telemetry_sender.dart`, `telemetry_runtime.dart`, `start_telemetry.dart`, `log_zone.dart`,
  `log_archive.dart`, `telemetry.dart` (barrel exporting every module file)
- Test: `test/common/telemetry/{error_reporter,error_hub,telemetry_sender,sentry_gateway,telemetry_runtime,start_telemetry,log_zone,log_archive}_test.dart`
- Modify: `pubspec.yaml` (`sentry`, `archive`)

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - `LoggedMessage`; `ErrorReporter({required ErrorOutbox outbox, required LogBuffer buffer, required bool Function(Object) isExpected, void Function(String)? console})`
    with `logError(error, stack, {hint, fatal, at, breadcrumbs})`, `logMessage(...)`, `settled()`.
  - `ErrorHub({void Function(String)? console})`: `configure(TelemetryRuntime)`,
    `disconnect(TelemetryRuntime)`, `settled()`, `reset()`, `logError`, `logMessage`,
    `pendingLimit = 100`.
  - `abstract interface class ICrashReportGateway { Future<bool> reachable(); Future<bool> send(OutboxEntry entry); }`
  - `SentryGateway({required String dsn, required Set<String> projectPackages, String environment = 'production', String? release, Duration timeout = const Duration(seconds: 5)})`
    implements it; `bool get enabled`, `Future<void> start()`, `Future<void> close()`.
  - `TelemetryStatus` (`queued`, `sending`, `lastSentAt`, `lastCheckAt`, `reachable`, `initial`).
  - `TelemetrySender({required ErrorOutbox outbox, required ICrashReportGateway gateway, required bool Function() enabled, Duration every = const Duration(minutes: 5), int perPass = 50, int maxAttempts = 3})`
    with `start`, `stop`, `dispose`, `runPass`, `refreshQueued`, `status`, `current`, `settled`.
  - `TelemetryRuntime({required TelemetryDatabase db, required ICrashReportGateway gateway, required String appVersion, required String platform, required bool Function(Object) isExpected, required Set<String> projectPackages, bool enabled = false, bool reporterConfigured = true, Future<void> Function()? releaseGateway, LogBuffer? buffer})`
    with `toggle`, `buffer`, `outbox`, `reporter`, `sender`, `storage`, `setEnabled(bool)`,
    `settled()`, `resetData()`.
  - `Future<TelemetryRuntime?> startTelemetry({required Future<Directory> Function() supportDirectory, required ErrorHub hub, required ICrashReportGateway gateway, required bool reporterConfigured, required String appVersion, required bool Function(Object) isExpected, required Set<String> projectPackages, required void Function(String name, Future<void> Function() step) defer, Future<void> Function()? releaseGateway, String? platform, bool enabled = false})`.
  - `void logZone(Future<void> Function() fn, {required void Function(Object, StackTrace) onError, LogOptions options = const LogOptions(outputInRelease: false, handlePrint: true)})`.
  - `List<int> buildLogArchive(Map<String, String> files)`.

- [ ] **Step 1: Port the tests** from `cafe_pos/packages/telemetry/test/` (`error_reporter_test`,
  `error_hub_test`, `telemetry_sender_test`, `sentry_gateway_test`, `telemetry_runtime_test`,
  `start_telemetry_test`, `app_zone_test` → `log_zone_test`, `log_archive_test`), renamed to the
  new names (`ICrashReportGateway`, `reporterConfigured`, `logZone`) and with
  `projectPackages: {'flutter_code_agent'}`. Add `sentry_gateway_test` `marks frames of the project packages inApp`:
  a frame `package:my_app/x.dart` is `inApp: true`, `package:other/y.dart` is `inApp: false`, with
  `projectPackages: {'my_app'}`.
- [ ] **Step 2: Run** `flutter test test/common/telemetry` — Expected: FAIL.
- [ ] **Step 3: Port the sources**; `ISentryGateway` → `ICrashReportGateway`, `dsnConfigured` →
  `reporterConfigured`, `appZone` → `logZone` (file `log_zone.dart`: the template's glue has its own
  `app_zone.dart` in the same folder). Add `sentry` and `archive` with `flutter pub add`.
- [ ] **Step 4: Run** `flutter test test/common/telemetry` and analyze on the folder — Expected: PASS, no issues.
- [ ] **Step 5: Commit** `feat(telemetry): reporter, hub, sender and the Sentry gateway`.

### Task 5: Consent covers only what comes after it

**Files:**
- Modify: `lib/src/common/telemetry/error_outbox.dart`, `telemetry_runtime.dart`,
  `telemetry_sender.dart`, `start_telemetry.dart`
- Test: `test/common/telemetry/consent_test.dart` (create)

**Interfaces:**
- Produces: `ErrorOutbox.consentSince` (`DateTime?`, mutable); `ErrorOutbox.sendable(int n, {required bool newestFirst})`;
  `TelemetryRuntime.setEnabled(bool enabled, {DateTime? since})`; `TelemetryRuntime(…, DateTime? consentSince)`
  and `startTelemetry(…, DateTime? consentSince)`.

Algorithm (the tests pin it):
- The sender takes its batch from `sendable`, which returns only entries with
  `firstAt >= consentSince` (all entries when `consentSince` is `null` — a project without a switch).
- `ErrorOutbox.add` for a fingerprint whose stored entry has `firstAt < consentSince` replaces that
  row's data with the new occurrence (`firstAt = lastAt = now`, `count = 1`, `attempts = 0`, new
  message, stack, hint, breadcrumbs) instead of incrementing it.
- `setEnabled(true, since: t)` sets `outbox.consentSince = t` before the pass it starts.

- [ ] **Step 1: Write the failing tests** in `consent_test.dart` (fake gateway that records sent entries,
  `fake_async` or `clock` fixed times):
  - `entries from before consent are never sent`: add 3 errors at `t0`; `setEnabled(true, since: t1)` with `t1 > t0`; run a pass; the gateway received nothing; `outbox.length()` is 3.
  - `a recurrence after consent sends only the new occurrence`: add error E at `t0` with breadcrumbs `['old']`; consent at `t1`; add E again at `t2` with breadcrumbs `['new']`; pass; the gateway got one entry with `count == 1`, `firstAt == t2`, `breadcrumbs == ['new']`.
  - `an error after consent is sent`: consent at `t1`; add at `t2`; pass; one entry sent.
  - `no consent time sends everything`: runtime with `consentSince: null`, `enabled: true`; an entry at `t0` is sent.
  - `turning off and on again moves the consent`: consent `t1`, error at `t2`, off, error F at `t3`, on with `since: t4`; pass sends nothing of F.
- [ ] **Step 2: Run** `flutter test test/common/telemetry/consent_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** the algorithm above; the existing sender tests stay green.
- [ ] **Step 4: Run** `flutter test test/common/telemetry` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(telemetry): crash reports send only what happens after consent`.

### Task 6: FAgent wiring — ErrorUtil, observer, zone, startup, DSN

**Files:**
- Modify: `lib/src/common/utils/error_util.dart`, `lib/src/common/utils/app_zone.dart`,
  `lib/src/common/controller/controller_observer.dart`,
  `lib/src/feature/initialization/data/initialization.dart`,
  `lib/src/feature/initialization/data/initialize_dependencies.dart`,
  `lib/src/feature/initialization/models/dependencies.dart`,
  `lib/src/feature/app_close/data/app_close_repository.dart`, `lib/main.dart`, `.gitignore`,
  `CLAUDE.md`
- Create: `lib/src/common/utils/expected_failure.dart`, `lib/src/common/constant/config.dart`
  (or the existing config file if there is one — grep `String.fromEnvironment` first)
- Test: `test/common/utils/error_util_test.dart`, `test/common/utils/expected_failure_test.dart`,
  `test/common/controller/controller_observer_test.dart`,
  `test/feature/initialization/error_log_step_test.dart`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: `abstract final class ErrorUtil` with `static final ErrorHub hub`,
  `configure(TelemetryRuntime)`, `disconnect(TelemetryRuntime)`, `settled()`,
  `@visibleForTesting reset()`, `@visibleForTesting set console(...)`, and the unchanged
  `logError(Object, StackTrace, {String? hint, bool fatal = false})` and
  `logMessage(String, {StackTrace? stackTrace, String? hint, bool warning = false})`;
  `bool isExpectedFailure(Object error)`; `Dependencies.telemetryRuntime` (`TelemetryRuntime?`)
  and `Dependencies.sentryGateway` (`SentryGateway`); `Config.sentryDsn`;
  `const Set<String> fagentPackages = {'flutter_code_agent'}`.

- [ ] **Step 1: Write the failing tests**:
  - `expected_failure_test`: `true` for an `ExpectedException` subtype (`FlutterNotFoundException`), `TimeoutException`, `SocketException('x')`; `false` for `StateError`, `TypeError`, `ArgumentError`, `FormatException` (decide and list every other expected type FAgent throws — grep `extends ExpectedException` and `throw` in `lib/src/common/` — each gets a case).
  - `controller_observer_test` (as cafe_pos `controller_observer_test.dart`): with a configured runtime over `TelemetryDatabase.forTesting(NativeDatabase.memory())`, a controller failing with an `ExpectedException` gives processing → error → idle, one log line, an empty queue; with a `StateError`, one queue entry; a state change logs `A -> B` by runtime type only (the log text has no `toString()` of the state).
  - `error_util_test` (as cafe_pos `error_util_test.dart`): before `configure` an error goes to the console and into the queue after `configure`; `logError` never throws when the outbox fails.
  - `error_log_step_test`: the step list starts with `'Error log'`; running it with a support directory that cannot be created leaves `telemetryRuntime == null` and the next steps still run.
- [ ] **Step 2: Run** these tests — Expected: FAIL.
- [ ] **Step 3: Implement**: `ErrorUtil` facade (port `cafe_pos/apps/desktop/lib/_core/telemetry/error_util.dart`);
  `appZone` over `logZone` with `onError: ErrorUtil.logError(…, hint: 'ROOT ERROR')`;
  `ControllerObserver` passes every error to `ErrorUtil.logError(…, hint: '${controller.name} failed')`
  and logs `l.v('${controller.name}: ${prev.runtimeType} -> ${next.runtimeType}')`;
  first step `'Error log'` creates `SentryGateway(dsn: Config.sentryDsn, projectPackages: fagentPackages, release: <app version>)`
  and `startTelemetry(supportDirectory: getApplicationSupportDirectory, hub: ErrorUtil.hub, isExpected: isExpectedFailure, reporterConfigured: gateway.enabled, …)`;
  its closing (stop sender → `ErrorUtil.settled()` → disconnect → flush → close db → `gateway.close()`)
  runs from `$disposeApp` and from `AppCloseRepository.shutdown`; `_catchExceptions` keeps its
  handlers (silent Flutter errors as `l.w`, others `ErrorUtil.logError(…, hint: 'FLUTTER ERROR')`);
  a failing step is logged with `hint: 'STARTUP ERROR', fatal: true`. `.gitignore` gets
  `config/sentry.local.json`; CLAUDE.md "Commands" gets
  `flutter run -d macos --dart-define-from-file=config/sentry.local.json   # with crash reports`.
- [ ] **Step 4: Run** `flutter test` (whole suite) and `flutter analyze` — Expected: all pass; analyze shows only the known `deprecated_member_use` infos.
- [ ] **Step 5: Commit** `feat(errors): FAgent reports through the telemetry module`.

### Task 7: FAgent controllers on handle(error:, done:)

**Files:**
- Modify: `lib/src/feature/project_creation/controller/project_creation_controller.dart`,
  `lib/src/feature/app_run/controller/run_actions_controller.dart`,
  `lib/src/feature/permission_rules/controller/permission_rules_controller.dart`,
  `lib/src/feature/app_close/controller/app_close_controller.dart`, and any other controller the
  audit finds (`app_settings_controller.dart`, `chat_recovery_controller.dart`,
  `workspace_data_controller.dart`, `dart_completion_controller.dart` have `finally` or `catch (`)
- Test: their existing tests in `test/feature/**`; add `test/common/controller/controller_rules_test.dart`

- [ ] **Step 1: Write the failing test** `controller_rules_test`: for every `lib/src/**/*_controller.dart`,
  no `on Object catch`, no `catch (` without a preceding `on `, no `finally`; a line
  `on Exception catch` must be followed within 3 lines by `ErrorUtil.logError(`. (Allowlist nothing.)
- [ ] **Step 2: Run** it — Expected: FAIL listing the files above.
- [ ] **Step 3: Rewrite** each action to the recipe of the Global Constraints. Where `finally` did
  more than `idle`, that moves to `done:`; a typed reaction stays a typed `on`. User-visible states
  and texts do not change: the existing controller tests stay as they are and pass.
- [ ] **Step 4: Run** `flutter test` — Expected: all pass.
- [ ] **Step 5: Commit** `refactor(controllers): errors reach the observer through handle(error:, done:)`.

### Task 8: FAgent Settings — "Crash reports"

**Files:**
- Modify: `lib/src/feature/app_settings/models/app_settings.dart` (`crashReports` default
  `false`, `crashReportsSince` `DateTime?`, JSON keys `crashReports`, `crashReportsSince` as ISO-8601),
  `app_settings_controller.dart` (`setCrashReports(bool enabled)`: on → `crashReportsSince = clock.now().toUtc()`),
  the Settings view that lists sections, `lib/src/common/localization/*.arb` (en, ru)
- Create: `lib/src/feature/crash_reports/data/crash_reports_repository.dart`,
  `lib/src/feature/crash_reports/controller/crash_reports_controller.dart` (+ state, freezed),
  `lib/src/feature/crash_reports/widgets/crash_reports_settings_section.dart`
- Test: `test/feature/crash_reports/{crash_reports_repository,crash_reports_controller,crash_reports_settings_section}_test.dart`,
  `test/feature/app_settings/app_settings_test.dart` (extend)

**Interfaces:**
- Consumes: `Dependencies.telemetryRuntime`, `Dependencies.sentryGateway`, Task 5 `setEnabled(…, since:)`.
- Produces: `abstract interface class ICrashReportsRepository { TelemetryStatus get status; Stream<TelemetryStatus> get statusChanges; bool get reporterConfigured; Future<List<OutboxEntry>> recent(); Future<void> apply({required bool enabled, DateTime? since}); Future<void> saveArchive(String path); }`;
  `CrashReportsController` (`load()`, `apply(...)`, `saveArchive(String path)`, Sequential);
  states idle/processing/successful/error carrying `CrashReportsData {List<OutboxEntry> recent, bool archiveSaved, Object? loadError}`.

- [ ] **Step 1: Write the failing tests**:
  - `app_settings_test`: `crashReports` defaults to `false`; JSON round-trip keeps `crashReportsSince`; unreadable `crashReportsSince` becomes `null`.
  - `crash_reports_repository_test` (runtime over an in-memory db, fake gateway): `recent()` returns at most 20, newest first; `apply(enabled: true, since: t)` sets `runtime.toggle.enabled` and `outbox.consentSince == t`; `saveArchive` writes a zip with `app.log`, `outbox.json`, `meta.json`, and a stored line containing `sk-ant-api03-AbCdEf0123456789AbCdEf0123456789` appears as `[REDACTED]` in `app.log`; with `runtime == null` the zip holds `log-unavailable.txt` and `meta.json`.
  - `crash_reports_controller_test`: `saveArchive` success → processing, successful(archiveSaved: true), idle; failure → processing, error, idle.
  - `crash_reports_settings_section_test`: switch off by default (`ValueKey('crash-reports-switch')`); with `reporterConfigured == false` the switch is disabled and the text `This build has no crash reporting` shows; tapping it on calls `setCrashReports(true)`; the queue count and up to 20 errors render; "Save log archive…" (`ValueKey('crash-reports-archive')`) calls the controller with the path a fake save dialog returns; a failed save shows the `errorText` message in a SnackBar.
- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement**. The archive is built in `Isolate.run` (a top-level function, not a
  closure over the repository). The save dialog goes through the existing `file_selector` usage
  pattern of FAgent (grep `getSaveLocation`); the widget gets the path and passes it to the
  controller. A listener on `AppSettings` (where the app already reacts to settings changes)
  calls `CrashReportsController.apply(enabled: s.crashReports, since: s.crashReportsSince)` when
  either changes, and once at start. Strings en/ru: section title "Crash reports"/"Отчёты о сбоях",
  switch "Send crash reports"/"Отправлять отчёты о сбоях", note "Only errors after you turn this on are sent. The log stays on this Mac."/"Отправляются только ошибки после включения. Журнал остаётся на этом Mac.",
  "This build has no crash reporting"/"В этой сборке отчёты о сбоях не настроены",
  "In queue: {count}"/"В очереди: {count}", "Save log archive…"/"Сохранить архив журналов…".
- [ ] **Step 4: Run** `flutter test` and `flutter analyze` — Expected: pass.
- [ ] **Step 5: Commit** `feat(settings): crash reports section with consent and log archive`.

### Task 9: Template, one app — telemetry, database and api_client in lib/_core

**Files:**
- Modify: `pubspec.yaml` (assets: `lib/src/common/telemetry/` and `test/common/telemetry/`), `lib/src/feature/project_creation/data/project_template.dart`,
  `lib/src/feature/project_creation/data/project_creation_repository_impl.dart`,
  template assets under `assets/project_template/architecture/`
- Create (template assets): `lib/_core/telemetry/{error_util,controller_observer,app_zone,expected_failure,telemetry_setup,telemetry_setup_io,telemetry_setup_web,crash_reporter}.dart`,
  `lib/_core/api_client/{api_client,expected_exception}.dart`, `lib/_core/api_client/middleware/{logger_mw,authentication_interceptor}.dart` (moved),
  `config/.gitkeep`, `.gitignore` line for `config/sentry.local.json`
- Delete (template assets): `lib/_core/database/tables/log_table.dart`, `lib/_core/utils/log_buffer.dart`,
  `lib/_core/utils/error_util/` (3 files), `lib/_core/utils/app_zone.dart`, `lib/_core/controller/controller_observer.dart`,
  `lib/_core/utils/api_client.dart`, `lib/_core/utils/middleware/`
- Test: `test/feature/project_creation/project_template_test.dart` (extend), `test/integration/new_project_test.dart`

**Interfaces:**
- Consumes: the module folder (Tasks 3–5).
- Produces: `const String telemetryModuleRoot = 'lib/src/common/telemetry/'`;
  `const List<String> telemetryModuleFiles` (every non-generated `.dart` of the folder);
  `String copyTelemetryModule(String text, {required String importPrefix})` — replaces
  `package:flutter_code_agent/src/common/telemetry/` with `importPrefix`
  (`package:<package>/_core/telemetry/` for one app); the copied tests from `test/common/telemetry/`
  go to `test/_core/telemetry/` through the same function. `skeletonPubAddArgumentsFor` gains
  `sentry`, `clock`, `archive` (and `sqlite3` only if analyze asks for it).

- [ ] **Step 1: Write the failing tests** in `project_template_test`:
  - `telemetryModuleFiles lists the module folder`: equals the set of `.dart` files under
    `lib/src/common/telemetry/` without `.g.dart`.
  - `copied module imports only itself`: every file after `copyTelemetryModule(…, importPrefix: 'package:my_app/_core/telemetry/')` has no `flutter_code_agent`.
  - `no old log or error stubs`: `projectTemplateFiles` contains none of `lib/_core/database/tables/log_table.dart`, `lib/_core/utils/log_buffer.dart`, `lib/_core/utils/error_util/error_util.dart`; contains `lib/_core/telemetry/error_util.dart`, `lib/_core/api_client/api_client.dart`, `lib/_core/api_client/expected_exception.dart`.
  - `the glue reports through ErrorUtil`: `lib/_core/telemetry/controller_observer.dart` contains `ErrorUtil.logError` and `runtimeType`; `expected_failure.dart` names `ExpectedException`, `APIClientException\$Network`, `APIClientException\$Authorization`, `TimeoutException`.
  - `web keeps compiling`: `telemetry_setup.dart` imports `telemetry_setup_io.dart` with `if (dart.library.js_interop) 'telemetry_setup_web.dart'`, and no file outside `_io`/module imports `dart:io`.
  - Integration (`FLUTTER_RUN_TEST=1`, one-app case): the created project's `flutter analyze` and `flutter test` pass, and `test/_core/telemetry/` exists.
- [ ] **Step 2: Run** `flutter test test/feature/project_creation` — Expected: FAIL.
- [ ] **Step 3: Implement**. Creation writes the module files and their tests with
  `copyTelemetryModule`. The glue ports `cafe_pos/apps/desktop/lib/_core/telemetry/` and
  `telemetry_setup.dart` (`projectPackages: {'{{package}}', 'ui'}`); `main.dart` runs in
  `appZone`, the first initialization step is `'Error log'`, `initialize_dependencies.dart` and
  `dependencies.dart` hold `telemetryRuntime`. `telemetry_setup_web.dart` returns `null` (console
  only). `AppDatabase` drops `LogTbl`/`LogPrefixTbl` (keep it compiling; `build_runner` must
  succeed). The template's Makefile `run` adds `--dart-define-from-file=config/sentry.local.json`
  when the file exists. Every import of the moved files is updated.
- [ ] **Step 4: Run** `flutter test test/feature/project_creation`, then
  `FLUTTER_RUN_TEST=1 flutter test test/integration/new_project_test.dart` (one-app case) — Expected: PASS.
- [ ] **Step 5: Commit** `feat(project_creation): new apps start with the telemetry pipeline`.

### Task 10: Template — choosing the crash reporter

**Files:**
- Modify: `lib/src/feature/project_creation/models/new_project_request.dart` (+ freezed),
  `new_member_request.dart`, `creation_step.dart` (notes), `project_template.dart`,
  `project_creation_repository_impl.dart`, `lib/src/feature/project_creation/widgets/new_project_form.dart`,
  `lib/src/common/localization/*.arb`, template assets `lib/_core/telemetry/crash_reporter*.dart`
- Create (template assets): `lib/_core/telemetry/crashlytics_gateway.dart`,
  `crash_reporter_sentry.dart`, `crash_reporter_crashlytics.dart`, `crash_reporter_log_only.dart`
  (one of them is written as `crash_reporter.dart`)
- Test: `test/feature/project_creation/{new_project_form,project_template,project_creation_repository_impl}_test.dart`

**Interfaces:**
- Produces: `enum CrashReporter { sentry, crashlytics, logOnly }`; `NewProjectRequest.crashReporter`
  (`@Default(CrashReporter.sentry)`); `List<String> crashReporterPubAddArguments(CrashReporter r)`
  (`sentry` → `['sentry']`; `crashlytics` → `['sentry', 'firebase_core', 'firebase_crashlytics']`;
  `logOnly` → `[]`); `String crashReporterFile(CrashReporter r)` (the asset written as
  `lib/_core/telemetry/crash_reporter.dart`), exposing in every variant
  `Future<ICrashReportGateway?> createCrashReportGateway({required Set<String> projectPackages})`
  and `bool get crashReporterConfigured`.
- `CrashlyticsGateway implements ICrashReportGateway`: `reachable()` → `true`; `send(entry)` →
  `FirebaseCrashlytics.instance.log(line)` for each breadcrumb, then
  `recordError(entry.type + ': ' + entry.message, StackTrace.fromString(entry.stack), reason: entry.hint, fatal: entry.level == 'fatal')`,
  returns `true` when it completes. On Android, iOS and macOS the crashlytics variant uses it;
  elsewhere `SentryGateway` when `SENTRY_DSN` is set, else `null`. It calls
  `Firebase.initializeApp()` once; a failure is logged with `ErrorUtil.logError(…, hint: 'Firebase is not configured')` and the variant returns `null`.
  `setCrashlyticsCollectionEnabled(true)` only once telemetry is enabled.

- [ ] **Step 1: Write the failing tests**:
  - `new_project_form_test`: for "My architecture" a row `ValueKey('new-project-crash-reporter')` with three options "Sentry", "Firebase Crashlytics", "Log only" (ru: "Sentry", "Firebase Crashlytics", "Только журнал"); default Sentry; hidden for "Empty"; the request carries the choice.
  - `project_template_test`: `crashReporterPubAddArguments` as above; `logOnly` project files contain no `sentry` and no `firebase` import; the crashlytics variant does not assign `FlutterError.onError` and imports `firebase_crashlytics` only in `crashlytics_gateway.dart`.
  - `project_creation_repository_impl_test`: creating with `crashlytics` runs one `pub add` with `firebase_core` and `firebase_crashlytics`; the run's notes contain `flutterfire configure`.
  - Template file test (copied into the project): `crash_reporter.dart` (crashlytics variant) returns `null` and logs once when `Firebase.initializeApp` throws (inject the initializer).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**; the creation notes for crashlytics (en/ru): "Run `flutterfire configure` in the project to connect Firebase; until then errors stay in the log." / "Запустите в проекте `flutterfire configure`, чтобы подключить Firebase; до этого ошибки остаются в журнале."
- [ ] **Step 4: Run** `flutter test test/feature/project_creation` and the integration test with `crashlytics` and `logOnly` one-app cases (analyze + test of the created project) — Expected: PASS.
- [ ] **Step 5: Commit** `feat(project_creation): choose Sentry, Crashlytics or log only for crash reports`.

### Task 11: Template, monorepo — packages telemetry, database, api_client

**Files:**
- Modify: `project_template.dart`, `project_creation_repository_impl.dart` (monorepo creation,
  `addMember`, `checkMember`/the skeleton gate), the add-member form and its hint strings,
  `lib/src/common/localization/*.arb`
- Create (template assets): `packages/telemetry/{pubspec.yaml,lib/telemetry.dart}`,
  `packages/database/{pubspec.yaml,lib/database.dart}` (+ `lib/src/` from `lib/_core/database/`),
  `packages/api_client/{pubspec.yaml,lib/api_client.dart}` (+ `lib/src/` from `lib/_core/api_client/`)
- Test: `project_template_test.dart`, `project_creation_repository_impl_test.dart`, `add_member_form_test.dart`,
  `test/integration/new_project_test.dart` (monorepo case)

**Interfaces:**
- Consumes: Tasks 9–10.
- Produces: `const List<String> monorepoSharedPackages = ['telemetry', 'database', 'api_client']`;
  `List<String> skeletonPubAddArgumentsFor({required String uiPath, String? sharedPackagesPath})` adds
  `telemetry@{path: …}`, `database@{path: …}`, `api_client@{path: …}` when `sharedPackagesPath` is set;
  `Future<bool> hasSharedPackages(String projectPath)` on the creation repository (+ controller pass-through);
  the crash reporter of a monorepo is stored in `packages/telemetry/crash_reporter.yaml`
  (`reporter: sentry|crashlytics|logOnly`) and read by an add.

- [ ] **Step 1: Write the failing tests**:
  - `project_template_test`: every file of the three packages is an asset; module files land in
    `packages/telemetry/lib/src/` via `copyTelemetryModule(…, importPrefix: 'package:telemetry/src/')`,
    and `lib/telemetry.dart` exports them all; `packages/api_client/lib/api_client.dart` exports
    `ExpectedException` and `RejectedException`; no package file imports `package:{{package}}`.
  - `project_creation_repository_impl_test`: a monorepo creation writes `packages/{ui,telemetry,database,api_client}`
    and the app's `pub add` includes the three path dependencies `../../packages/<name>`; the app's
    glue sits in `apps/app/lib/_core/telemetry/` and imports `package:telemetry/telemetry.dart`;
    `addMember` of a Flutter app with the skeleton adds the same path dependencies and writes the
    reporter read from `crash_reporter.yaml`; `hasSharedPackages` is `false` without `packages/telemetry`.
  - `add_member_form_test`: when `hasSharedPackages` is `false`, only "Empty" is offered and the hint
    `This project was made before the shared packages; add the app empty.` / `Проект создан до общих пакетов: добавьте приложение пустым.` shows.
  - Integration (`FLUTTER_RUN_TEST=1`, monorepo case): `make analyze` and `make test` of the created
    project pass (the workspace scripts find the three packages), and the package tests of
    `packages/telemetry/test/` run.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**. `packages/database` runs `build_runner` (the workspace build covers it);
  `packages/telemetry` too (its drift database). Package pubspecs use `resolution: workspace` and the
  root SDK constraint, like the members FAgent writes; Flutter or pure Dart is the implementer's
  call as long as `pub get` resolves and the package tests run in `scripts/test.bash`. The module's
  tests go to `packages/telemetry/test/` through `copyTelemetryModule(…, importPrefix: 'package:telemetry/src/')`.
  The monorepo Makefile's `run` (`assets/project_template/monorepo/Makefile`) passes
  `--dart-define-from-file=../../config/sentry.local.json` when the root file exists.
- [ ] **Step 4: Run** `flutter test test/feature/project_creation` and the integration test, monorepo case — Expected: PASS.
- [ ] **Step 5: Commit** `feat(project_creation): monorepos share telemetry, database and api_client packages`.

### Task 12: Docs and the full run

**Files:**
- Modify: `docs/PLAN.md` (M-line for the error pipeline), `CLAUDE.md` (if a command or rule changed beyond Task 6)

- [ ] **Step 1: Run** `flutter pub get && dart run build_runner build && flutter analyze && flutter test` —
  Expected: all tests pass; analyze shows only the known `deprecated_member_use` infos.
- [ ] **Step 2: Run** `FLUTTER_RUN_TEST=1 flutter test test/integration/new_project_test.dart` — Expected: PASS (one app × three reporters where the test covers them, monorepo).
- [ ] **Step 3: Commit** `docs: error pipeline in the plan`.
