# Flutter Code Agent

Open-source desktop app for Flutter development with AI coding agents. Pick an agent (Claude Code,
Codex, Gemini CLI — anything that speaks the [Agent Client Protocol](https://agentclientprotocol.com)),
open a Flutter project, chat, run the app with hot reload and point at widgets — in one window. The
agent gets Flutter knowledge (architecture rules, skills, the Dart MCP server) automatically.

**Status:** early development. The window shell is in place; agent chat comes next. See
[docs/PLAN.md](docs/PLAN.md) for the roadmap.

## Requirements

- Flutter 3.47+ (Dart 3.13+)
- macOS (Linux and Windows builds are planned)

## Development

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d macos
```

Architecture and coding rules: [CLAUDE.md](CLAUDE.md) and
[docs/AI_INSTRUCTIONS.md](docs/AI_INSTRUCTIONS.md).

## License

[MIT](LICENSE)
