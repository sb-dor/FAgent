# Error handling and telemetry: rules, FAgent, the architecture template — design

## Why

The owner has a tested error pipeline in cafe_pos (`/Users/avaz/StudioProjects/cafe_pos`) and a
guide that describes it (`/Users/avaz/Desktop/error-handling-guide.md`). The same thing should be
how FAgent itself handles errors, how every project FAgent creates with "My architecture" starts,
and what the agents are told to write. Today the three disagree with the guide:

- **The agent rules** (`assets/knowledge/rules/`) are an older copy of `cafe_pos/docs/rules/`. Their
  controller recipe catches in the body (`try { … } on Object catch { setState(error); if (error is!
  ExpectedException) rethrow; } finally { idle }`), which the guide forbids, and which reports a
  `TimeoutException` or `SocketException` to the crash reporter because they are not
  `ExpectedException`s. cafe_pos rewrote these sections (plan
  `cafe_pos/docs/superpowers/plans/2026-11-14-controller-errors.md`) and added "Crash reports",
  "The Sentry DSN" and "The error log and the reporter".
- **FAgent** logs to the console only (`lib/src/common/utils/error_util.dart`); its
  `ControllerObserver` filters `ExpectedException` itself; four controllers catch everything in the
  body. Agent output in FAgent carries API keys and `/Users/<name>` paths, so cleaning matters more
  than in cafe_pos.
- **The template** has a stub `$captureException(...).ignore()` that would bypass any cleaning, a log
  table in the app's main database (`_core/database/tables/log_table.dart`) and a `LogBuffer`
  singleton.

Success: an agent working in a FAgent-made project, FAgent's own code and the cafe_pos guide all
follow one recipe; an unexpected error in FAgent or in a new project is in `logs.sqlite` with its
breadcrumbs and, when the user allowed it and a DSN is set, in Sentry, cleaned.

## Goals

### 1. Agent rules (`assets/knowledge/rules/*.md`)

Port the error sections of `cafe_pos/docs/rules/` into FAgent's rules, rewritten so they hold for
any project (no venue, PIN, device key, license, money, server, `deviceGuard`). FAgent's own
changes in the same files (monorepo layout, `material_ui`, the project's `ApiClient`) stay.

The rules reach agents in every project FAgent opens, not only "My architecture" ones. The generic
parts (the controller recipe, expected vs unexpected, never swallow, `errorText`, no secrets in
messages) apply everywhere. The pipeline parts (`ErrorUtil` over `ErrorHub`, `logs.sqlite`, the
queue, Sentry) are written as "a project that has `ErrorUtil` reports through it; a project with
another reporter keeps it and follows the same split; a new project starts with the pipeline", the
way `architecture.md` already keeps an existing layout. An agent is never told to add the whole
pipeline to an existing project unasked.

- `controllers.md`: the recipe is `handle(body, error:, done:)`; no `on Object catch`, untyped
  `catch` or `finally` in a controller; the three exceptions (typed `on` with its own reaction,
  typed `on` + `rethrow`, a side read with `on Exception` + `ErrorUtil.logError(hint:)` + a comment);
  the order observer → `error:` → `done:`; a guard before `handle`; optimistic change with
  `late final previous`; an action of two steps (`applied`); `Sequential` for loads, `Droppable`
  for changes; "Expected and unexpected errors": the observer sees every error, `ErrorUtil` splits
  them with the app's one `isExpectedFailure`; "Reporting an error": who calls `ErrorUtil`, never a
  widget, never `print`/`debugPrint`/`developer.log`.
- `repositories.md`: "Report with `ErrorUtil`, nothing else"; the `try`/`finally` line names
  `handle(error:, done:)`.
- `security.md`: a generic "Crash reports" section: only unexpected errors leave the machine, what
  an event holds, `sendDefaultPii = false`, `package_config` removed in `beforeSend`, what
  `redactSecrets` replaces, a new kind of secret comes with a test, `HiddenDetailsError` (an opt-in),
  the user's switch. Owner's decision 2026-11-22: every exception is sent with its full text (as Sentry's
  `captureException` and Crashlytics' `recordError` do) after `redactSecrets`; SQLite, drift and
  `FormatException` errors are not hidden by default.
- `configuration.md`: "The Sentry DSN": `config/sentry.local.json` (git-ignored, key `SENTRY_DSN`),
  `--dart-define-from-file`, an empty DSN switches sending off and the queue is still kept.
- `dependencies.md`: "The error log and the reporter": the log is the first initialization step;
  `catchExceptions` installs the handlers once; a failing step is logged with `STARTUP ERROR` and the
  steps before it are disposed.
- `architecture.md`: where the pieces live in both layouts (below), and the example controller in
  the new recipe.
- `widgets.md`: the five places an error is shown (SnackBar with retry, under the field, inside the
  dialog, `LoadErrorView`, `RefreshFailedNotice`), only through `errorText`, from the `listener`.
- `testing.md`: the tests of section 18 of the guide.

Every code example in the rules compiles against the pinned `control` (`handle(..., error:, done:)`
exists at `685a9bc6…`).

### 2. FAgent

- **The telemetry module** `lib/src/common/telemetry/`: the cafe_pos package `packages/telemetry`
  (`ErrorHub`, `ErrorReporter`, `LogBuffer`, `LogStorage`, `logs.sqlite` with `log_entries` and
  `error_outbox_entries`, `ErrorOutbox`, `errorFingerprint`, `TelemetrySender`, `ISentryGateway`,
  `SentryGateway`, `redactSecrets`, `cleanForLog`, `HiddenDetailsError`/`ReportedError`, `appZone`,
  `startTelemetry`, `TelemetryRuntime`, `TelemetryStatus`, the log archive). Changes on the way:
  - Portable: the module imports only its own files and pub packages, no Flutter. Both FAgent and
    the template set `always_use_package_imports: error`, so its own files are imported as
    `package:flutter_code_agent/src/common/telemetry/…` and nothing else of FAgent is. A test
    enforces this; the template copy rewrites that one prefix (goal 3), the way member creation
    already renames Dart imports.
  - The project's packages are a parameter, not `package:cafe_` in code: `startTelemetry(...,
    projectPackages: {...})` feeds the fingerprint (which frames are the project's) and the
    gateway (`inApp`).
  - The cafe-only patterns go (`CAFEPOS-…`, the `Device` scheme, the recovery code, the device key
    `<uuid>.<token>`). Added, each with a positive and a look-alike test: API keys agents print —
    `sk-ant-…`, `sk-…`/`sk-proj-…`, `ghp_…`/`gho_…`/`github_pat_…`, `AIza…`, `xox[abp]-…`.
  - Texts in English; doc comments as the rest of FAgent.
- **The glue** in `lib/src/common/utils/` (where `ErrorUtil` already is): `ErrorUtil` becomes the
  facade over `ErrorHub` (same `logError`/`logMessage` signatures, so every caller keeps
  compiling); `isExpectedFailure` (FAgent: `ExpectedException`, `TimeoutException`,
  `SocketException`, `ProcessException` when the executable is missing is already wrapped as
  `FlutterNotFoundException` — the builder lists what FAgent throws as expected); `appZone` around
  `main`; `ControllerObserver` passes every error to `ErrorUtil` and logs state changes by type only.
- **Startup**: a first initialization step "Error log" opens `logs.sqlite` in the application
  support directory (`path_provider`), separate from FAgent's main database and its backups; the
  existing `_catchExceptions` keeps its handlers and routes to the new `ErrorUtil`; disposal stops
  the sender, waits `settled`, disconnects, flushes the log, closes the database.
- **Controllers**: `project_creation_controller.dart`, `run_actions_controller.dart`,
  `permission_rules_controller.dart`, `app_close_controller.dart` move to `handle(error:, done:)`;
  every other controller is checked against the rule (a `finally` or untyped `catch` anywhere in a
  controller). The states a user sees do not change: processing → successful|error → idle, same
  data, same texts.
- **Settings → "Crash reports"** (en/ru): a switch "Send crash reports" (`AppSettings.crashReports`,
  default **off**: FAgent is open source and installed by others), off and explained when the
  build has no DSN; the queue count and the last check/send time from `TelemetryStatus`; the last
  20 errors (type, cleaned message, count, time); "Save log archive…" (`file_selector` save dialog)
  writes a zip of `app.log`, `outbox.json` and `meta.json`, cleaned and built in `Isolate.run`, for
  a GitHub issue. Turning the switch on runs a pass at once; off closes the gateway.
- **Consent covers only what comes after it** (the owner's decision). The log and the queue are
  kept while the switch is off, so Settings and the archive show them, but nothing recorded before
  the switch was turned on — its message, stack, breadcrumbs or count — ever leaves the machine.
  The moment of consent is stored with the setting (`AppSettings.crashReportsSince`); turning the
  switch off and on again moves it. This lives in the module (`TelemetryRuntime`), so every
  gateway and every new project with a switch gets it; cafe_pos sends the backlog, and this port
  differs on purpose, with a test: an entry from before consent, and the same fingerprint
  recurring after it, do not send the earlier occurrence's data.
- **The DSN**: `config/sentry.local.json` (git-ignored) with `SENTRY_DSN`, read by
  `String.fromEnvironment('SENTRY_DSN')`; CLAUDE.md "Commands" shows
  `flutter run -d macos --dart-define-from-file=config/sentry.local.json`. No DSN: no sending, the
  log and the queue are still kept.

### 3. The "My architecture" template

Where the shared pieces go is the owner's decision:

```
One app                               Monorepo
lib/_core/                            apps/<app>/lib/_core/telemetry/
  telemetry/   module + glue            error_util.dart, controller_observer.dart,
  database/    the app's drift base     app_zone.dart, expected_failure.dart  (glue only)
  api_client/  ApiClient, middleware, packages/telemetry/   lib/telemetry.dart + lib/src/  (module)
               ExpectedException,     packages/database/    lib/database.dart + lib/src/
               RejectedException      packages/api_client/  lib/api_client.dart + lib/src/
packages/ui/   (as today)             packages/ui/          (as today)
```

- Three packages in a monorepo, no `core` (the owner's choice): `ExpectedException` and
  `RejectedException` live in `api_client`, and in a one-app project in `lib/_core/api_client/`.
  The template's `ApiClient` does not change: it still throws `APIClientException$…`, and data
  providers map a server code to `RejectedException` or a feature's own subtype, as
  `repositories.md` says today (the template has no wire format for a refusal). The template's
  `isExpectedFailure` treats `ExpectedException`, `APIClientException$Network`,
  `APIClientException$Authorization`, `TimeoutException` and `SocketException` as expected (the
  last one on the VM only).
- **The module is FAgent's own folder**: `lib/src/common/telemetry/` is declared as assets of FAgent
  and written into the new project as `lib/_core/telemetry/` (one app) or `packages/telemetry/lib/src/`
  plus a barrel `lib/telemetry.dart` (monorepo). One source; FAgent's tests test what the user gets.
  Its tests go the same way (`test/_core/telemetry/` or `packages/telemetry/test/`).
- The glue is template files with `{{package}}`; `projectPackages` lists the app's package and the
  shared packages (`ui`, `telemetry`, `database`, `api_client` in a monorepo).
- Removed from the template: `_core/database/tables/log_table.dart` (and its tables in
  `AppDatabase`), `_core/utils/log_buffer.dart`, `_core/utils/error_util/` with its `platform/`
  stubs.
- **Web**: the template keeps its `_js`/`_vm` variants, and the module uses `dart:io`
  (`NativeDatabase`, `HttpClient`, `stderr`). The glue imports the module's starter through a
  conditional import; on the web `ErrorUtil` writes to the console only (no `logs.sqlite`, no
  Sentry). The template still compiles for the web.
- **The crash reporter is chosen at creation.** The New project dialog, for "My architecture",
  gets a row "Crash reports" (en/ru) with three options; `NewProjectRequest` carries the choice:
  1. **Sentry** (default): `SentryGateway` on every platform, DSN from `config/sentry.local.json`.
  2. **Firebase Crashlytics**: `CrashlyticsGateway` on Android, iOS and macOS (the platforms
     `firebase_crashlytics` supports, checked on pub.dev: 6.1.0); on Windows, Linux and the web
     `SentryGateway` when a DSN is set, else no gateway. The project gets `firebase_core` and
     `firebase_crashlytics`; `flutterfire configure` is the user's step (or the agent's, in chat),
     and the creation's notes say so. Until Firebase is configured the app runs with the log only
     (a failed `Firebase.initializeApp` is logged, not fatal).
  3. **Log only**: no gateway, no Sentry or Firebase dependency; `logs.sqlite` and the queue as
     usual.

  The gateway interface is generic (`ISentryGateway` becomes `ICrashReportGateway`: `reachable`,
  `send`); `CrashlyticsGateway.reachable` is always `true` (Crashlytics keeps and sends its own
  reports offline) and `send` calls `recordError(error, stack, reason: hint, fatal: level ==
  'fatal')` with the cleaned entry and its breadcrumbs as `log` lines. `CrashlyticsGateway` is a
  Flutter plugin call, so it lives in the app's glue (`_core/telemetry/`), not in the pure-Dart
  module; a conditional import picks the gateway per platform, as the old
  `error_util_vm.dart`/`error_util_js.dart` pair did
  (`github.com/dilovar88/avera-web-flutter/tree/main/lib/src/common/utils/error_util`) — but it
  picks the gateway behind the queue, never a direct `recordError` that bypasses cleaning and
  `isExpectedFailure`. Crashlytics collection is off until telemetry sends
  (`setCrashlyticsCollectionEnabled`), and its own `FlutterError.onError` recipe is not used.
  A monorepo's "Add to project…" app skeleton uses the reporter its `packages/telemetry` glue was
  made with (the choice is per project, written where the add can read it — builder's call).
- **Sentry in a new project**: `config/sentry.local.json` in `.gitignore`; the Makefile's `run`
  passes it with `--dart-define-from-file` when the file exists (monorepo `make run APP=` too).
  Sending is on whenever the chosen reporter is configured (the developer who sets it is the
  owner); the rules say how to add a user switch, with the consent rule below. No settings screen
  in the template.
- FAgent itself stays on Sentry.
- **Monorepo creation and "Add to project…"**: creation writes the three packages next to
  `packages/ui` and makes `database` run `build_runner` (the workspace build already covers
  members). A new app added with the skeleton gets `telemetry`, `database` and `api_client` as path
  dependencies, as it gets `ui` today. A monorepo made before this change lacks them: the skeleton
  is not offered there (Empty only, with a hint), like an old `packages/ui` on SDK material today.
- New `pub add` names: `sentry`, `clock`, `archive`, `path` (and `meta` where used) for whoever hosts
  the module; versions resolved fresh, checked on pub.dev before adding (CLAUDE.md
  "Dependencies").
- The integration test that creates a project and runs analyze and every step (one app and
  monorepo) stays green.

## Non-goals

- The shelf server middleware (`errorMiddleware`, `logUnexpectedError`), device-log upload, the
  top-bar "sending" indicator, the server and device rows of cafe_pos's "Журналы ошибок" tab.
- Moving FAgent's own code off `package:flutter/material.dart`.
- `sentry_flutter`, symbolizing obfuscated stacks, a crash dialog.
- Running `flutterfire configure` or creating a Firebase project for the user.
- A shared pub/git package for telemetry (approach C).
- Changing cafe_pos.

## Anti-goals

- FAgent sending anything before the user turned the switch on.
- A secret, an API key or a user name reaching the log on disk, the queue, the archive or Sentry
  because a path bypasses `redactSecrets`.
- A new project that fails `flutter analyze`, a test or a web build.
- Silencing a lint to make the port compile.

## Constraints

- CLAUDE.md and `docs/AI_INSTRUCTIONS.md` with CLAUDE.md's overrides: desktop only, colours from
  `context.colors`, en+ru through gen-l10n, widgets → controller → repository, no IO in widgets,
  every `Stream` method follows the stream rules, `drift` for storage, no silenced lints.
- `control` stays pinned at `685a9bc6ef60c987b99b5526e125813adba54e2a`.
- `logs.sqlite` is its own drift database with its own schema version, not a table of FAgent's
  database.
- New projects target Flutter 3.50 / Dart 3.14 (`kArchitectureMinFlutter`).

## Approaches

- **A. One source in FAgent, the template copies it** — picked. The module lives in FAgent, is
  tested there, and is written into new projects from FAgent's assets. Costs: the module may not
  import FAgent's code (a test checks it).
- **B. Two copies, FAgent and the template.** Simplest on day one; every fix is made twice and the
  copies drift.
- **C. A separate package (git or pub.dev), like `control`.** Fixes reach everyone, but it is a
  public package to maintain and the code leaves the user's project, unlike everything else the
  template writes.

## Decided by the owner

- Everything moves: rules, FAgent, the template.
- Approach A (the owner's answer: the layout above).
- Monorepo: shared infrastructure in `packages/`; one app: in `lib/_core/`.
- Three packages (`telemetry`, `database`, `api_client`), no `core`.
- Turning crash reports on sends only what happens after; earlier errors stay on the machine.
- New projects choose the crash reporter: Sentry, Firebase Crashlytics, or log only.

## My calls (correct me)

- FAgent's crash reports are off by default; the log on disk is always on.
- `ExpectedException` / `RejectedException` sit in `api_client`.
- Monorepo package names unprefixed (`telemetry`, `database`, `api_client`), as `ui` is.
- The template sends whenever a DSN is set, with no switch.
- On the web the template's error pipeline is console only.
- The added API-key patterns in `redactSecrets`.
- The module's own imports are package imports, rewritten on copy (the lint forbids relative ones).
- Pipeline rules are conditional on the project having `ErrorUtil`; generic rules apply everywhere.
- The template's `ApiClient` is unchanged; providers throw `RejectedException`.
- `packages/telemetry` runs `build_runner` too (its own drift database); FAgent closes telemetry in
  its quit path (`AppCloseRepository.shutdown`) as well as in `$disposeApp`.

## Left to the builder

- The exact list of FAgent's expected failures in `isExpectedFailure`.
- How the module's files are listed as assets and mapped to their destinations (one list in
  `project_template.dart`, checked by a test against the folder).
- Whether the three monorepo packages are Flutter or pure Dart packages, as long as their tests run
  in the project's scripts and `pub get` resolves (the rules note that `test` next to
  `build_runner` broke `pub get`; cafe_pos pins `test: 1.32.0`).
- The order of the work: rules, then FAgent, then the template (the template copies FAgent's
  finished module).
