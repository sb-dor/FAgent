---
name: package-freshness
description: "Check a package's latest version and status on pub.dev before adding it."
---

# Package freshness

- Before adding a package, check its latest version and status on pub.dev (Dart MCP
  `pub_dev_search` or `https://pub.dev/api/packages/<name>`).
- Never add a discontinued or long-unmaintained package; choose a maintained alternative.
- Add dependencies with `flutter pub add`, not a version typed from memory.
- Generators (`build_runner`, `freezed`, `drift_dev`) go to `dev_dependencies`.
- A dependency pinned to a git commit stays pinned until the reason for the pin is gone.
- Skill `pub-freshness`.
