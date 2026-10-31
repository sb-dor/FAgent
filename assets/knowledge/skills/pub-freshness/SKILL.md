---
name: pub-freshness
description: "Pick current, maintained pub.dev packages before adding a dependency."
when_to_use: "Before adding or upgrading any package in pubspec.yaml."
version: "1.0"
---

# Pub freshness

Do not add a package from memory: versions and maintenance status change.

## Steps

1. Look the package up with the Dart MCP `pub_dev_search`, or open
   `https://pub.dev/api/packages/<name>`.
2. Read `latest.version`, the SDK constraint and `isDiscontinued`.
3. Skip the package when it is discontinued, unmaintained for years, or needs a newer SDK than
   the project has. Prefer a maintained alternative.
4. Add it with `flutter pub add <name>` (not by editing a guessed version) and commit the
   resulting `pubspec.lock` change.
5. Run `flutter pub get`, `flutter analyze` and the tests.

## Notes

- Code generators (`build_runner`, `freezed`, `drift_dev`) go to `dev_dependencies`.
- A package pinned to a git commit stays pinned; say in a comment why.
- Mention the version you chose and why in the pull request.
