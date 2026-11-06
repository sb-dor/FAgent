---
name: package-freshness
description: "Check a package's latest version and status on pub.dev before adding or upgrading it."
---

# Package freshness

## Rules

- Before adding a package, check its latest version and status on pub.dev (Dart MCP
  `pub_dev_search` or `https://pub.dev/api/packages/<name>`).
- Never add a discontinued or long-unmaintained package; choose a maintained alternative.
- Add dependencies with `flutter pub add`, not a version typed from memory.
- Generators (`build_runner`, `freezed`, `drift_dev`) go to `dev_dependencies`.
- A dependency pinned to a git commit stays pinned until the reason for the pin is gone.
- A package with a build hook (`hook/build.dart`) runs code on every build: read the hook before
  adding it. See "Notes".

## Pub freshness

Do not add a package from memory: versions and maintenance status change.

### Steps

1. Look the package up with the Dart MCP `pub_dev_search`, or open
   `https://pub.dev/api/packages/<name>`.
2. Read `latest.version`, the SDK constraint and `isDiscontinued`.
3. Skip the package when it is discontinued, unmaintained for years, or needs a newer SDK than
   the project has. Prefer a maintained alternative.
4. Add it with `flutter pub add <name>` (not by editing a guessed version) and commit the
   resulting `pubspec.lock` change.
5. Run `flutter pub get`, `flutter analyze` and the tests.

### Notes

- Code generators (`build_runner`, `freezed`, `drift_dev`) go to `dev_dependencies`.
- A package pinned to a git commit stays pinned; say in a comment why.
- Mention the version you chose and why in the pull request.
- A package with a build hook (`hook/build.dart`, for native code) runs that code whenever the app
  is built. Read it before adding the package and check three things. Does it download binaries
  during the build (then an offline or locked-down CI fails)? Does an option make it build from
  source, needing a toolchain on every build machine? Does the web need manual steps? `pixer`
  0.0.13 does all three: its hook downloads a prebuilt library and checks its hash; a custom
  `formats:` list under `hooks: user_defines:` in `pubspec.yaml` builds it from source with Rust;
  and on the web `pixer.wasm` must be copied into `web/` and `await Pixer.initialize()` called.
