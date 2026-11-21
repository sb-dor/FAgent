# Monorepo projects: create them, add members, run their apps — design

## Why

Some projects grow into several apps and shared packages. cafe_pos
(`/Users/avaz/StudioProjects/cafe_pos`) is the model: a pure pub workspace at the root, apps in
`apps/` (`desktop`, `mobile`, `server`, `license_generator`), shared code in `packages/` (`core`,
`api_client`, `design_system`, …), and repo-wide `scripts/`, `Makefile`, `config/` and
`docs/rules`. The owner wants FAgent to create such a project from the start, and to add apps and
packages to it with a FAgent action, not by hand or through the agent, so every member comes out the
same way. A small project stays a single app in `lib/`.

FAgent cannot run cafe_pos today: the Run tab runs `flutter run` only in the project root, and a
`launch.json` configuration whose `cwd` is a subfolder is rejected as `LaunchCwdOutsideProject`
(`lib/src/feature/app_run/data/launch_config_reader.dart`). A monorepo FAgent creates would have
the same problem, so Run is part of this work.

## Goals

1. **Structure in the New project dialog.** With type "App", a new row "Structure": "One app"
   (today's layout, unchanged) or "Monorepo".
2. **Monorepo creation.** The root is a pure workspace: `pubspec.yaml` named `<name>_workspace`
   with `workspace: [apps/*, packages/*]`, no `lib/`. The first app goes to `apps/<app>` with the
   "My architecture" skeleton, laid out exactly like a one-app project (`lib/main.dart`,
   `lib/_core/`, `lib/initialization/`, `lib/home/`, no `src`). `packages/ui` sits next to it and
   keeps the package layout (`lib/ui.dart`, `lib/src/`). Repo-wide files are at the root:
   `scripts/`, `Makefile`, `analysis_options.yaml`, `CHANGELOG.md`, `docs/rules`, `AGENTS.md`,
   `CLAUDE.md`.
3. **"Add to project…"** in the project's menu in the sidebar, only for monorepo projects. Four
   kinds:

   | Kind | Folder | Created by |
   |---|---|---|
   | Flutter app | `apps/<folder>` | `flutter create`, then the skeleton (or empty, the template choice as today) |
   | Dart app (server, console) | `apps/<folder>` | `dart create -t console` |
   | Flutter package | `packages/<folder>` | `flutter create -t package` |
   | Dart package | `packages/<folder>` | `dart create -t package` |

   The new member is a workspace member at once (`resolution: workspace`), the repo-wide scripts
   pick it up without being edited, the project passes `analyze`, and the new files are committed.
4. **Run picks the app** in a monorepo: an "App" chip next to the device lists the Flutter apps
   of `apps/`; the choice is kept per project. `flutter run`, its target and its
   `--dart-define-from-file` paths work in that app's folder. A `launch.json` configuration with a
   `cwd` inside the project runs in that folder. One-app projects see no change.
5. **Rules.** `assets/knowledge/rules/architecture.md` "Project structure" gains a third tree, "A
   monorepo": what goes into `apps/` and `packages/`, apps laid out as an app (no `src`), packages
   as a package (`lib/src/`), and that new members come from "Add to project".

## Non-goals

- Turning a one-app project into a monorepo (moving `lib/` into `apps/`).
- "Add to project" for one-app projects.
- Plugins, FFI packages and modules as members.
- Running two apps of one project at once (one run per project stays; the app MCP tools keep
  addressing "the run of this chat's project").
- Running Dart apps (`apps/server`) from the Run tab: `flutter run` cannot; they run from the
  `Makefile` or a terminal.
- Removing or renaming members.
- melos or any other monorepo tool: Dart's pub workspace is enough, cafe_pos proves it.

## Anti-goals

- "Add to project" never commits changes that are not its own: it stages only the new member's
  folder and `pubspec.lock`, never `git add -A`.
- "Add to project" never edits the repo's scripts or `Makefile`: they find members themselves.
- A one-app project is created exactly as today, byte for byte.

## Constraints

- `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md` of this repo: controllers, repositories over
  processes, `Stream` rules, every `Process` killed in `dispose`, colours from `context.colors`,
  en + ru strings through gen-l10n.
- The creation pipeline's guarantees stay: steps shown with their output, "Stop" kills the process
  and marks the step failed, quitting the app kills it and adds nothing.
- Workspace members are resolved together with the root (a workspace accepts members with
  different lower bounds); pub workspaces with globs (`apps/*`) need the SDK cafe_pos uses
  (`^3.14.0`) or newer, which FAgent's Flutter already has.
- Known and out of scope: on Flutter 3.50 the skeleton's Analyze step fails on the
  `material.dart` deprecation infos (same on `main` today). A monorepo inherits it.

## Approaches

- **A. One member builder for every case (chosen).** Creation gets one operation, "create member of
  kind K in folder F": `flutter create` / `dart create`, the skeleton for a Flutter app, then join
  the workspace. A monorepo is root files + member "Flutter app" `apps/<app>` + `packages/ui`; "Add
  to project" is the same operation followed by `pub get`, `analyze` and a commit, in the same
  dialog opened in "add" mode. The monorepo's scripts iterate over `apps/*` and `packages/*`, so
  adding a member edits nothing. Cost: today's creation code is taken apart into reusable pieces.
- **B. A separate monorepo template, cafe_pos-style.** A ready `project_template/monorepo/` whose
  scripts list members explicitly, and "Add to project" as separate code that also appends lines to
  `test.bash`, `generate.bash` and `Makefile`. Closer to cafe_pos, smaller change today; but two
  creation paths drift apart, and editing script text breaks when the user changed the scripts.
- (Dropped) **C. melos.** An extra dependency in every new project for what pub workspaces do.

The owner chose **A**.

## Design

### Model

- `ProjectStructure { single, monorepo }` on `NewProjectRequest` (`@Default(single)`), meaningful
  only for `FlutterProjectType.app`. A monorepo request also carries `appFolder` (the first app's
  folder, default `app`) and `appPackage` (its package name, default `<name>_<folder>`, editable;
  the skeleton's `{{package}}` is this name). `packages/ui` keeps the package name `ui`.
  *(Builder's call, confirmed in review: the same default as "Add to project".)*
- Monorepo with the "Empty" template is allowed: the root files and a plain `flutter create` in
  `apps/<folder>`, no `packages/ui`, no skeleton steps. The monorepo scripts run `build_runner`
  only when some member depends on it, and `gen-l10n` only in members with `l10n.yaml`, so they
  work without the skeleton. *(Builder's call.)*
- The root's SDK constraint is `^<major>.<minor>.0` of the Dart in the SDK the form shows. Glob
  workspaces (`apps/*`) need a minimum Dart; the builder confirms that version (cafe_pos runs on
  `^3.14.0`). With an older SDK the "Monorepo" chip is disabled with a hint naming the needed
  version. *(Builder's call.)*
- `MemberKind { flutterApp, dartApp, flutterPackage, dartPackage }` with its folder (`apps` or
  `packages`) and whether it gets platforms (only `flutterApp`).
- `NewMemberRequest { projectId, projectPath, kind, folder, packageName, org, platforms,
  template }`. `packageName` defaults to `<project>_<folder>` where `<project>` is the workspace
  name without `_workspace` (cafe_pos → `cafe_desktop` would need the user to type `cafe`; the
  default is a suggestion, the field is editable and validated as a package name).
- `isMonorepo(projectRoot)`: the root `pubspec.yaml` has a `workspace:` key and the root has no
  `lib/` folder. This recognises cafe_pos and every monorepo FAgent creates, and not a one-app
  project (it has `workspace: [packages/ui]` but also `lib/`).

### Creation pipeline

The pipeline stays a list of `CreationStep`s run in order by the same runner (progress, output,
Stop, cancel on quit). New step kinds are added; a one-app request produces today's list unchanged.

Monorepo request, steps in order:
1. `workspace`: create the folder, write the root files: `pubspec.yaml` (`<name>_workspace`,
   `publish_to: none`, the SDK constraint, `workspace: [apps/*, packages/*]`, dev dependencies the
   repo-wide scripts need), `analysis_options.yaml` (today's strict one, which members inherit),
   `scripts/*.bash` (monorepo variants below), `Makefile` (monorepo variant), `CHANGELOG.md`,
   `.gitignore`.
2. `gitInit`.
3. `member` (Flutter app `apps/<appFolder>`): the member builder below, with the skeleton.
4. `member` (`packages/ui`): written from the template, as today. It keeps the template's own SDK
   constraint (`^3.10.4`): on the root's (Dart 3.14 and newer) its `popup.dart` trips
   `prefer_initializing_formals`.
5. `skeleton` tail: `pub get` at the root, `build_runner build --workspace`, `dart fix --apply
   --code=directives_ordering`.
6. `analyze` at the root (covers every member), `rules` (into the root), `firstCommit`.

The member builder, for a member of kind K in folder F with package name N:
- Flutter app / Flutter package: `flutter create --template app|package --org … --project-name N
  [--platforms …] --no-pub <root>/<apps|packages>/F`. Dart app / Dart package: `dart create -t
  console|package --no-pub <path>` and then fix the package name to N.
- Edit the member's `pubspec.yaml`: add `resolution: workspace`, set its SDK constraint to the
  root's (every member FAgent creates with `flutter create` / `dart create`; `packages/ui` keeps
  its template's, see step 4).
- Flutter app with the "My architecture" template: write the app part of the skeleton into the
  member folder, `flutter pub add` the skeleton's packages there, with `ui@{path: ../../packages/ui}`
  instead of `packages/ui`.

The template's file list is split by where a file goes, so both structures share it:
- **repo files** (`Makefile`, `scripts/`, `CHANGELOG.md`, `analysis_options.yaml`,
  `tool/dart/rename_project.dart`): at the root of a one-app project; a monorepo uses its own
  variants of `Makefile` and `scripts/` and leaves out `rename_project.dart`;
- **app files** (`lib/`, `test/`, `l10n.yaml`, `build.yaml`): at the root of a one-app project,
  in `apps/<folder>` of a monorepo;
- **`packages/ui`**: in `packages/ui` in both.

The `packages/ui` shader: today the app's `pubspec.yaml` lists `packages/ui/shaders/shimmer.frag`
as its own asset path. From `apps/<folder>` that path would need `..`, which Flutter does not allow
in assets. In a monorepo the shader is declared in `packages/ui/pubspec.yaml` (`shaders:
[shaders/shimmer.frag]`), and its asset key is still `packages/ui/shaders/shimmer.frag`, the key
the shimmer loads. The builder confirms this with a real `flutter run` (or `flutter build macos`)
of a created monorepo before relying on it.

### Monorepo scripts and Makefile

- `scripts/test.bash`: for every `apps/*/` and `packages/*/` with a `pubspec.yaml`: `flutter test
  --no-pub` in members whose `pubspec.yaml` depends on `flutter`, `dart test` in the others; skip
  members without `test/`. Fails on the first failure (`set -euo pipefail`).
- `scripts/generate.bash`: `flutter pub get` at the root; `flutter gen-l10n` in every member with an
  `l10n.yaml`; `dart run build_runner build --workspace --delete-conflicting-outputs`; `dart
  format` of the members' `lib` and `test`.
- `scripts/analyze.bash`: `flutter analyze --no-pub` at the root. `scripts/format.bash`: every
  member's `lib` and `test`, generated files skipped as today.
- `Makefile`: today's targets (`all`, `ci`, `get`, `generate`, `format`, `analyze`, `test`, …)
  calling the scripts, and `make run APP=<folder> [ENV=…]` (`cd apps/$(APP) && flutter run`,
  `config/$(ENV).json` from the root passed as `../../config/$(ENV).json` when it exists).
  Release builds take `APP` too.

### "Add to project"

- Entry: the project's menu in the sidebar (`workspace_sidebar.dart`, `_ProjectAction`) gains "Add
  to project…" when `isMonorepo` holds for that project — in any monorepo, also one FAgent did
  not create, such as cafe_pos. *(Owner's choice.)*
- In a monorepo FAgent did not create:
  - the "My architecture" template is offered for a Flutter app only when `packages/ui` exists;
    otherwise the template row shows only "Empty", with a hint saying why;
  - the add never edits the repository's scripts. When a script under `scripts/` names members by
    path (it mentions `apps/` or `packages/` with a folder name, not a glob or a loop) and so would
    miss the new member, the last line of the progress screen says so: "scripts/test.bash lists
    members by name: add apps/<folder> to it". The builder picks the exact check; a false "lists by
    name" only adds a harmless line.
- Dialog: the New project dialog in "add" mode. It shows the kind (four chips, as the type row
  today), the folder, the package name; for a Flutter app also the org, platforms and template
  (My architecture / empty). No parent folder, git or chat switches. The folder is checked like
  today's target (exists → error); the package name must be valid and not used by another member.
- Steps: `member` (the builder above), `pub get` at the root, `build_runner build --workspace`
  only when the skeleton was written, `commit`: only when the project is a git repository,
  staging `<apps|packages>/<folder>` and `pubspec.lock`, message `Add <kind> <folder>`; then
  `analyze` of the new member's folder. The commit comes before analyze on purpose: on Flutter
  3.50 every skeleton fails analyze on the `material.dart` deprecation infos, and a failed check
  must not leave the member uncommitted. A failed analyze shows its output; nothing is undone.
  *(Builder's call.)*
- Rollback: the workspace takes every folder under `apps/*` and `packages/*`, so a half-made
  member would break `pub get` for the whole repository. When a step before `commit` fails, is
  stopped, or the app quits, the add deletes the new member's folder and restores the
  `pubspec.lock` it saved before the first step; the failed step's output stays on screen with a
  line saying the folder was removed. *(Builder's call.)*
- After success the progress screen offers "Close"; nothing else is selected or opened.

### Run in a monorepo

- Run arguments (flavor, defines, extra flags) are kept per app: `RunConfigsTable` gains
  `appFolder` (project-relative, `apps/desktop`; `''` for the root) in its key, one row per project
  and app, and a separate per-project value for the selected app. Switching from `desktop` to
  `mobile` never carries `desktop`'s defines over. Drift migration: existing rows get `''`.
  *(Builder's call.)*
- The Run tab, for a monorepo project, lists the apps: members under `apps/` whose `pubspec.yaml`
  depends on `flutter` and that have `lib/main.dart`. An "App" chip shows the selected one; the
  first app is selected when none is stored or the stored one is gone.
  ```
  Run   [desktop ▾]  [macOS ▾]  [debug ▾]   ▶
  ```
- `flutter run` runs with `workingDirectory: <root>/<appFolder>`; the target, flavor and
  defines are relative to that folder, as they would be with `cd apps/x && flutter run`.
- `launch.json` stays at `<root>/.vscode/launch.json`. In every project, a configuration's `cwd`
  inside the project becomes the folder it runs in; a `cwd` outside the project stays unsupported.
  This also lets one-app and plugin projects run `cwd: example`, which is rejected today; nothing
  else changes for them. *(Builder's call: relaxing a rejection cannot break a project that ran.)*
- In a monorepo, a configuration with a `cwd` fixes the app: selecting it shows its app in the chip
  and locks the chip; a configuration without a `cwd` (or with the root) runs in the app the chip
  selects. "Default" keeps the chip free. *(Builder's call.)*
- Screenshots stay in the project root's `.dart_tool/flutter_code_agent/screenshots`; picked
  widgets' files stay relative to the project root (`apps/desktop/lib/...`), which is what the
  agent, working in the root, needs.
- One-app projects: no chip, `appFolder` stays `''` (the project root), behaviour unchanged.

### Rules

`architecture.md`, "Project structure", gains:

```
A monorepo (a pub workspace with several apps):

pubspec.yaml              # <name>_workspace: workspace: [apps/*, packages/*], no lib/
apps/
├── desktop/              # an app: lib/main.dart, lib/_core/, lib/<feature>/, no src
└── server/               # a Dart app
packages/
├── ui/                   # a package: lib/ui.dart and lib/src/
└── core/
scripts/, Makefile        # run for every member
docs/rules/               # one set for the whole repository
```

with the rule that new members are added through FAgent's "Add to project" (or, outside FAgent, by
the same layout), and the Rules bullet about `lib/src` extended to name `apps/` and `packages/`.

### Strings

New en + ru keys: the Structure row and its two hints, the first app's folder field, "Add to
project…", the add dialog's title, the four kinds and their hints, the package name field and its
errors, the new step titles (`workspace`, `member`, `commit`), the Run "App" chip and its empty
state ("No Flutter app in apps/").

## Testing

- Unit tests with the fake process runner the creation tests use: the step list of each request
  (one-app unchanged, monorepo, each of the four add kinds); the exact arguments of every command
  and their working directories; the edited `pubspec.yaml` of a member; commit staging only the new
  member.
- `isMonorepo` on cafe_pos-like and one-app fixtures; the Run app list; `launch.json` with `cwd:
  apps/x`; the stored app folder and its fallback.
- Widget tests: the Structure row appears only for type App; the add dialog shows the right fields
  per kind; the menu item exists only for monorepos; the Run chip only for monorepos.
- Opt-in real toolchain test (`FLUTTER_RUN_TEST=1`, tag `flutter`): create a monorepo, add one
  member of each kind, then `scripts/test.bash` and `flutter analyze` pass (apart from the known
  3.50 deprecation infos) and the shimmer shader resolves.

## Left to the builder

- Names of the new classes, steps and files, within the rules above.
- The exact text of the monorepo scripts and `Makefile`, within the behaviour above.
- How the dialog's "add" mode is factored (one form with a mode, or two forms sharing the fields).
- The drift schema version bump and migration code.
