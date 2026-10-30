# flutter_code_agent

Open-source Flutter Desktop app (macOS first): a Claude Code Desktop–style workspace for Flutter
development. It drives existing coding agents (Claude Code, Codex, Gemini CLI, …) over the Agent
Client Protocol (ACP) and gives them Flutter knowledge through its own MCP server plus the Dart MCP
server. Roadmap and decisions: `docs/PLAN.md`.

## Architecture rules

All code follows @docs/AI_INSTRUCTIONS.md. That file is shared with other projects; for this repo
these overrides win:

- Desktop only. No `widgets/mobile/`, no `screenSizeMaybeWhen`, no `MobileWebNavigator`, no
  `DesktopController` modules — plain widgets inside `lib/src/feature/workspace/` until navigation
  is actually needed.
- No authentication or permissions: skip `AuthenticationInProgressListener` and `*_permissions.dart`.
- No `ApiClient`. Repositories wrap processes (ACP agents, `flutter`), the file system and drift.
  They receive those services through the constructor, same as `ApiClient` in the instructions.
- Localization uses Flutter's built-in `gen-l10n` (`l10n.yaml`), not `intl_utils` (discontinued).
  `Localization.of(context).key` works as described; `flutter pub get` regenerates the strings.
- Dependencies live in `lib/src/feature/initialization/` (`Dependencies`, `DependenciesScope`,
  `initialize_dependencies.dart`). Add new app-wide services as initialization steps there.
- Agent processes and their streams are long-lived: every `Stream`-returning repository method must
  follow the "Stream-Returning Methods" rules, and every `Process` must be killed in `dispose`.
- Design tokens live in `lib/src/common/design/`, shared widgets in `lib/src/common/widget/`. Feature
  widgets take colors only from `context.colors` (no `Color(0x…)`, `Colors.*` or `colorScheme.*`) and
  radii from `AppRadius`.

## Commands

```bash
flutter pub get                                             # also regenerates localization
dart run build_runner build --delete-conflicting-outputs    # freezed, drift
flutter analyze
flutter test
flutter run -d macos
```

Generated files (`*.g.dart`, `*.freezed.dart`, `lib/src/common/localization/generated/`) are
gitignored — regenerate, never edit.

## Hooks

`.claude/settings.json` formats every edited `.dart` file and runs `flutter analyze` when you stop
with uncommitted Dart changes. If the Stop hook reports issues, fix them; do not silence lints.

## Dependencies

Before adding a package, check its latest version and status on pub.dev (Dart MCP `pub_dev_search`,
or `https://pub.dev/api/packages/<name>`). Do not add discontinued packages. `control` is pinned to a
git commit because the pub.dev release lacks `handle(..., error:)`.

## Platform notes

- macOS App Sandbox is off (`macos/Runner/*.entitlements`): the app must spawn agents and `flutter`.
- GUI apps on macOS do not inherit the shell `PATH`; resolve it from the login shell before
  spawning processes (planned `lib/src/common/shell_env/`).
