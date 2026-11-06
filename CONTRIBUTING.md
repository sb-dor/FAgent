# Contributing

Thanks for helping. Issues and pull requests are welcome, in English or Russian.

## Bugs and ideas

Open an issue with what you did, what you expected and what happened. For a bug, add the agent
(Claude Code, Codex, Gemini CLI or a custom one), the output of `flutter --version` and, if you can,
a screenshot.

## Code

1. Read [CLAUDE.md](CLAUDE.md) and [docs/AI_INSTRUCTIONS.md](docs/AI_INSTRUCTIONS.md): the app
   follows the same architecture rules it gives to agents.
2. Set up and run:

   ```bash
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter run -d macos
   ```

3. Before a pull request, both must pass:

   ```bash
   flutter analyze
   flutter test
   ```

   Generated files (`*.g.dart`, `*.freezed.dart`, `lib/src/common/localization/generated/`) are not
   committed. Every visible string goes into both `intl_en.arb` and `intl_ru.arb`.

## The built-in rules

The rules in [`assets/knowledge/rules/`](assets/knowledge/rules) are read by agents in users'
projects, so they have to be right:

- Say what to do and why, in plain sentences; leave out what the code already shows.
- Check every claim: against the Flutter SDK, a package's source, pub.dev, or a small program you
  ran. Say so when it was checked by running it.
- A fenced `dart` block whose first line is `// file: name.dart` is compiled by the tests. Check it:

  ```bash
  flutter test test/feature/skills
  FLUTTER_RUN_TEST=1 flutter test test/feature/skills/builtin_knowledge_content_test.dart --plain-name compile
  ```

## The new project template

The files a new project gets are in
[`assets/project_template/architecture/`](assets/project_template/architecture), listed in
`lib/src/feature/project_creation/data/project_template.dart`. A change there is checked by creating
a real project, which needs the network:

```bash
FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/new_project_test.dart
```
