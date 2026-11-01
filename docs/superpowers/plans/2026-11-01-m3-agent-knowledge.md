# M3: Flutter knowledge for the agent — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every chat's agent gets the architecture rules, the skills and the app's own tools (run, logs, errors, screenshot) without the user pasting anything.

**Architecture:** Built-in knowledge is rewritten from `docs/AI_INSTRUCTIONS.md` into `assets/knowledge/`. An in-app MCP server (`mcp_dart` Streamable HTTP on `127.0.0.1`, one bearer token per chat) serves skills and run tools. A session-context repository gives `AgentHub` the server list (app server, Dart MCP, the user's servers) and the Claude `_meta` (rules in `systemPrompt.append`, `allowedTools`, `skills`) for `session/new` and `session/load`. Runtime errors come from the VM service `Flutter.Error` stream.

**Tech Stack:** Flutter macOS, control, freezed, drift (schema v7 → v8), gen-l10n en/ru, `mcp_dart` 2.4.3, `vm_service` (locked 15.4.0), `dart_acp_sdk` 0.1.1.

**Spec:** `docs/superpowers/specs/2026-11-01-m3-agent-knowledge-design.md` (it argues from `docs/superpowers/specs/2026-10-28-ui-system-design.md` §3.7, §3.8, §4).

## Global Constraints

- Architecture per `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md`: repositories are `abstract interface class IFoo` + `FooImpl`, services through the constructor; widgets never touch repositories; Stream methods follow "Stream-Returning Methods"; every `Process` is killed in `dispose`.
- Feature widgets take colors only from `context.colors`, radii from `AppRadius`.
- UI copy through arb files en + ru (Russian uses formal «вы»); error text inside MCP tool results and `RunError` titles is English.
- New packages: `mcp_dart: ^2.4.3`; `vm_service` constrained to what the Flutter SDK allows (`flutter pub add vm_service` keeps the locked 15.4.0). Check pub.dev before adding anything else.
- App MCP server name: `flutter_code_agent`; host `127.0.0.1`; port 0; path `/mcp`; tokens 32 bytes from `Random.secure`, base64url; header `Authorization: Bearer <token>`; tokens never logged.
- Server `instructions` < 2048 characters. Built-in rules together ≤ 8 KB (8192 bytes UTF-8).
- Dart MCP command: `<SDK>/bin/dart mcp-server --flutter-sdk <SDK> --disable launch_app,stop_app`, SDK from `flutterExecutableFor` (fvm-aware, M2).
- Claude `_meta` keys: `systemPrompt: {append: <text>}`, `claudeCode: {options: {allowedTools: ['mcp__flutter_code_agent'], skills: [<project skill names>]}}`.
- Rules order: built-in → user ("My") → project → project `AGENTS.md`; the text starts with the line `Later rules override earlier ones.`; `AGENTS.md` is skipped when the project's `CLAUDE.md` has a line `@AGENTS.md`.
- Server list, rules and `skills` are fixed when a session starts; app-served skills and per-chat choices act at once.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `flutter analyze` clean and `flutter test` green after every task; generated files are regenerated, never edited.

## Review Focus

1. A project whose `AGENTS.md` (or a user rule) is huge (200 KB) — the session still starts; each non-built-in rule file is cut at 32 KB with a line `[truncated]`. Test in Task 2.
2. Project A's token used to call `app_status` / `hot_reload` while project B is the one running — tools act only on the token's project and report `No app is running` for A. Test in Task 5.
3. `hot_reload` called while the app is still building or in profile mode — immediate error result (`App is not running` / `Hot reload works only in debug mode`), no hang. Test in Task 5.
4. A chat deleted while the agent still holds its token — the next request gets 401 (token valid only while the session row exists). Test in Task 4.
5. The app server failed to bind, or the project has no Flutter SDK — `session/new` still goes out, without the missing server. Test in Task 6.

---

### Task 1: Built-in knowledge from AI_INSTRUCTIONS.md

**Files:**
- Modify/replace: `assets/knowledge/rules/*.md`, `assets/knowledge/skills/*/SKILL.md` (+ `templates/`)
- Create: `assets/knowledge/rules/controllers.md`, `repositories.md`, `dependencies.md`, `widgets.md`, `generated-files.md`; `assets/knowledge/skills/repository-streams/`, `paginated-controller/`, `controller-patterns/`, `dependency-injection/`
- Modify: `pubspec.yaml` (asset folders for the new skill directories, if listed per folder)
- Test: `test/feature/skills/builtin_knowledge_content_test.dart`, `test/fixtures/knowledge_templates/` (pubspec + `analysis_options.yaml` for the template check)

**Interfaces:**
- Produces: asset keys `rules/<name>.md`, `skills/<name>/SKILL.md`, `skills/<name>/templates/*.dart`; the rule and skill names in spec §1 tables.

- [ ] **Step 1: Write the failing test** `builtin_knowledge_content_test.dart` reading `assets/knowledge/` from disk:
  - `expect(ruleNames, {'architecture','controllers','repositories','dependencies','widgets','localization','package-freshness','generated-files'})`;
  - `expect(skillNames, {'feature-architecture','repository-streams','paginated-controller','controller-patterns','dependency-injection','drift-migration','widget-test','pub-freshness'})`;
  - every file parses with `parseFrontmatter` (from `lib/src/feature/skills/data/frontmatter.dart`) with non-empty `name` and `description`, and `name` equals the folder/file name;
  - `expect(totalRuleBytes, lessThanOrEqualTo(8192))`;
  - no built-in file contains any of `Desktop only`, `No ApiClient`, `flutter_code_agent`.
- [ ] **Step 2: Run** `flutter test test/feature/skills/builtin_knowledge_content_test.dart` — FAIL (missing files).
- [ ] **Step 3: Write the content** from `docs/AI_INSTRUCTIONS.md` by spec §1: rules are terse imperative bullets (the "what"), skills carry the full sections, examples and templates (the "how"). Keep mobile/web parts; drop "AI Identity", "Token Economy" and this repo's overrides. Templates are complete, compilable Dart against `control`, `freezed_annotation` and `flutter`.
- [ ] **Step 4: Add the template check** to the same test: copy `skills/*/templates/*.dart` into `test/fixtures/knowledge_templates/lib/`, run `dart analyze` there (`Process.run`, tag `flutter`, skipped unless `FLUTTER_RUN_TEST=1`), expect exit code 0.
- [ ] **Step 5: Run** the test file, then `flutter test` — existing skills tests that count built-in items are updated to the new names. PASS.
- [ ] **Step 6: Commit** `knowledge: built-in rules and skills from AI_INSTRUCTIONS.md`.

### Task 2: AGENTS.md as a project rule, and the rules prompt

**Files:**
- Modify: `lib/src/feature/skills/data/knowledge_scanner.dart` (project root's `AGENTS.md`)
- Create: `lib/src/feature/session_context/data/rules_prompt.dart`
- Test: `test/feature/skills/knowledge_scanner_test.dart`, `test/feature/session_context/rules_prompt_test.dart`

**Interfaces:**
- Consumes: `KnowledgeItem`, `SkillLibrary`, `ISkillsRepository.read(id, projectRoot:)`.
- Produces:
  - `KnowledgeItem` with `id: 'rule:project:AGENTS'`, `kind: rule`, `source: project`, `name: 'AGENTS'`, `readOnly: true`, `path: <projectRoot>/AGENTS.md`, always `enabled: true` (no per-project switch).
  - `String buildRulesPrompt({required List<RuleText> rules, required List<SkillSummary> skills, String? agentsMd, String? claudeMd})` where `RuleText = ({SkillSource source, String name, String text})` and `SkillSummary = ({String name, String description})`.
  - `const int ruleFileLimit = 32 * 1024;`

- [ ] **Step 1: Write failing tests.**
  - Scanner: a project with `AGENTS.md` yields the item above; without the file, no item; the item ignores `skill_states` rows.
  - `buildRulesPrompt`: output starts with `Later rules override earlier ones.`; rules appear in order builtin → user → project, then a `## AGENTS.md` section; with `claudeMd: 'x\n@AGENTS.md\n'` the AGENTS section is absent; a 200 KB user rule is cut to `ruleFileLimit` bytes followed by `[truncated]` (built-in rules are never cut); skills render as a `## Skills from flutter_code_agent` section with `- name — description` lines, and the section is absent when `skills` is empty.
- [ ] **Step 2: Run** both test files — FAIL.
- [ ] **Step 3: Implement.** Frontmatter is stripped from each rule body before it goes into the prompt; each rule becomes `## <name>` + body.
- [ ] **Step 4: Run** tests, then `flutter test` — PASS. The Rules list shows AGENTS with the project source tag and no switch (widget test in `test/feature/skills/widgets/` for the tile without a switch).
- [ ] **Step 5: Commit** `skills: AGENTS.md as a read-only project rule; rules prompt`.

### Task 3: Skills per chat (menu F) — drift v8

**Files:**
- Create: `lib/src/common/database/tables/chat_skill_states_table.dart`, `lib/src/feature/skills/data/chat_skills_repository.dart`, `lib/src/feature/skills/controller/chat_skills_controller.dart`
- Modify: `lib/src/common/database/database.dart` (schema 8, `from7To8`), `drift_schemas/drift_schema_v8.json` + steps (via `dart run drift_dev make-migrations`), `lib/src/feature/skills/widgets/chat_skills_chip.dart`, `lib/src/feature/initialization/models/dependencies.dart`, `initialize_dependencies.dart`, arb files
- Test: `test/common/database/migration_test.dart` (v7 → v8), `test/feature/skills/chat_skills_repository_test.dart`, `test/feature/skills/widgets/chat_skills_chip_test.dart`

**Interfaces:**
- Produces:
  - table `chat_skill_states(sessionId INTEGER REFERENCES sessions ON DELETE CASCADE, skillId TEXT, enabled BOOL, PRIMARY KEY(sessionId, skillId))`;
  - `abstract interface class IChatSkillsRepository { Stream<Map<String, bool>> watch(int sessionId); Future<Map<String, bool>> current(int sessionId); Future<void> set(int sessionId, String skillId, {required bool enabled, required bool projectEnabled}); }` — a row exists only when `enabled != projectEnabled`; otherwise `set` deletes the row.
  - `List<KnowledgeItem> skillsForChat(SkillLibrary library, Map<String, bool> chatStates)` — project-enabled skills with chat overrides applied.

- [ ] **Step 1: Write failing tests:** migration v7→v8 creates the table and keeps data; repository round trip (set off → row; set back to project value → no row; deleting the session drops rows); `skillsForChat` applies overrides; chip menu lists skills with checkboxes, toggling calls the controller, project skills show the subtitle `Applies when the chat is reopened` (en) / `Применится при повторном открытии чата` (ru); the Skills and rules screen shows under its lists `Rules apply to new and reopened chats` / `Правила применятся к новым и заново открытым чатам`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** table, migration, repository (Pattern 1 stream), controller (`DroppableControllerHandler` for `set`), chip menu.
- [ ] **Step 4: Run** `dart run build_runner build --delete-conflicting-outputs`, then `flutter test` — PASS.
- [ ] **Step 5: Commit** `skills: per-chat skill choice (menu F), schema v8`.

### Task 4: App MCP server core

**Files:**
- Create: `lib/src/common/app_mcp/app_mcp_server.dart`, `lib/src/common/app_mcp/app_mcp_tokens.dart`, `lib/src/common/app_mcp/app_mcp_tool.dart`
- Modify: `pubspec.yaml` (`mcp_dart: ^2.4.3`), `initialize_dependencies.dart` (step "App MCP server"), `dependencies.dart`, `lib/src/feature/app_close/data/app_close_repository.dart` (close after agents, before the database), `lib/src/feature/hub_notices/` (notice when start failed), arb files
- Test: `test/common/app_mcp/app_mcp_server_test.dart`

**Interfaces:**
- Produces:
  - `typedef AppMcpCaller = ({int sessionId, int projectId});`
  - `abstract interface class AppMcpTool { String get name; String get description; Map<String, Object?> get inputSchema; Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments); }`
  - `sealed class AppMcpResult` → `AppMcpText(String text)`, `AppMcpImage(List<int> png, {String? caption})`, `AppMcpError(String message)`.
  - `final class AppMcpTokens { AppMcpTokens({required AppDatabase database}); String issue(int sessionId, int projectId); Future<AppMcpCaller?> resolve(String token); }` — `issue` replaces the session's previous token; `resolve` returns null unless the token is known AND the `sessions` row still exists.
  - `abstract interface class IAppMcpServer { Future<void> start(); Uri? get url; int get toolCount; Object? get startError; Future<void> close(); }`; `AppMcpServerImpl({required AppMcpTokens tokens, required List<AppMcpTool> tools, required String instructions})`.
  - `const String appMcpServerName = 'flutter_code_agent';` and `const String appMcpInstructions` (exact text written here, < 2048 chars, English: what the server is; call `list_skills` when a task may match a skill and `load_skill` before following it; get the DTD URI from `app_status` and connect Dart MCP's `dtd` tool to it; use `hot_reload` after edits when an app is running).
- [ ] **Step 1: Write failing tests** with `mcp_dart`'s HTTP client against a started server: no header → 401; unknown token → 401; token of a deleted session → 401 (Review Focus 4); valid token → `tools/list` returns the registered fake tool; `tools/call` passes the token's `AppMcpCaller` to the tool; `AppMcpError` arrives as `isError: true`; `AppMcpImage` arrives as image content `image/png`; `Host: evil.example` → rejected; `appMcpInstructions.length < 2048`; binding fails (port taken via a stub binder) → `startError` set, `url` null, no throw.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** with `StreamableMcpServer(host: '127.0.0.1', port: 0, path: '/mcp', authenticator: …)`, the factory registering every `AppMcpTool`. The authenticator stores the resolved caller per MCP session id for tool calls.
- [ ] **Step 4: Run** tests, `flutter test` — PASS.
- [ ] **Step 5: Commit** `app_mcp: in-app MCP server with per-chat tokens`.

### Task 5: App MCP tools — skills and run

**Files:**
- Create: `lib/src/feature/app_mcp_tools/data/skill_tools.dart`, `lib/src/feature/app_mcp_tools/data/run_tools.dart`
- Modify: `lib/src/feature/app_run/data/app_run_repository.dart` (`RunState currentRun(int projectId)`, `List<LogEntry> recentLogs(int projectId, {int limit})` — synchronous snapshots), `test/support/scripted_app_run_repository.dart`, `initialize_dependencies.dart` (register tools)
- Test: `test/feature/app_mcp_tools/skill_tools_test.dart`, `test/feature/app_mcp_tools/run_tools_test.dart`

**Interfaces:**
- Consumes: `AppMcpTool`, `AppMcpCaller`, `AppMcpResult` (Task 4); `IChatSkillsRepository`, `skillsForChat` (Task 3); `ISkillsRepository`; `IAppRunRepository`; a `Future<String?> Function(int projectId) projectRoot`.
- Produces: tools `list_skills`, `load_skill`, `read_skill_file`, `app_status`, `app_logs`, `runtime_errors`, `hot_reload`, `hot_restart`, `screenshot` (names and inputs from spec §2). Only built-in and user skills are served (project skills are Claude's own). `const int skillFileLimit = 256 * 1024;`
- [ ] **Step 1: Write failing tests.**
  - `list_skills` lists built-in + user skills on for the chat, not project skills, not ones switched off in the chat.
  - `load_skill('x')` for a chat-off skill → error `Skill x is off for this chat`; unknown → `Skill not found: x`; ok → SKILL.md text plus `Files:` list.
  - `read_skill_file` refuses `../secret`, `/etc/passwd` and a symlink pointing outside (`Path is outside the skill`); a non-UTF-8 file → `Not a text file`; a file over `skillFileLimit` → `File is too large`.
  - `app_status` with no run → `No app is running`; with `RunRunning` → JSON with `device`, `mode`, `vmServiceUri`, `dtdUri`, `devToolsUri`.
  - Review Focus 2: caller of project 1 while project 2 runs → `No app is running`; `hot_reload` never touches project 2.
  - Review Focus 3: `hot_reload` during `RunBuilding` → `App is not running`; in profile → `Hot reload works only in debug mode`; ok → `Reloaded in <ms> ms`.
  - `app_logs(lines: 5, errorsOnly: true)` → the last 5 error entries; `lines` above 1000 is clamped.
  - `runtime_errors` → the run's `RunError`s as text (`RunError` title, place, message, stack excerpt).
  - `screenshot` → `AppMcpImage` with the PNG bytes and the saved path as caption; repository returns null → `Screenshot failed`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the two snapshot methods in `AppRunRepositoryImpl` (from the state it already keeps) and the tools.
- [ ] **Step 4: Run** tests, `flutter test` — PASS.
- [ ] **Step 5: Commit** `app_mcp: skill and run tools`.

### Task 6: Session context — servers and Claude meta in session/new and session/load

**Files:**
- Create: `lib/src/feature/session_context/data/session_context_repository.dart`, `lib/src/feature/session_context/models/session_context.dart`
- Modify: `lib/src/common/acp/agent_definition.dart` (`final bool acceptsClaudeMeta`, true for `claude`), `lib/src/common/acp/agent_hub.dart` (`SessionContextProvider` in the constructor; used in `_create` and `_load`), `initialize_dependencies.dart`
- Test: `test/feature/session_context/session_context_repository_test.dart`, `test/common/acp/agent_hub_test.dart`, `test/integration/agent_knowledge_test.dart` (opt-in)

**Interfaces:**
- Consumes: `IAppMcpServer`, `AppMcpTokens` (Task 4); `buildRulesPrompt`, `RuleText`, `SkillSummary` (Task 2); `IChatSkillsRepository`, `skillsForChat` (Task 3); `IMcpServersRepository`; `ISkillsRepository`; `flutterExecutableFor`; `ShellEnvironment`.
- Produces:
  - `final class SessionContext { const SessionContext({required this.servers, this.meta}); final List<McpServer> servers; final Map<String, Object?>? meta; static const SessionContext empty; }` (ACP `McpServer` from `dart_acp_sdk`).
  - `abstract interface class ISessionContextRepository { Future<SessionContext> forSession({required int sessionId, required AgentDefinition agent}); }` — looks up the project from the `sessions` row.
  - `typedef SessionContextProvider = Future<SessionContext> Function(int sessionId, AgentDefinition agent);` passed as `AgentHub(sessionContext: …)`; default returns `SessionContext.empty`. A provider that throws is logged and treated as empty — the session still starts.
- [ ] **Step 1: Write failing tests.**
  - Servers: app server HTTP entry `url` = server url, header `Authorization: Bearer <issued token>`; Dart MCP stdio entry with the exact command from Global Constraints; enabled user stdio server with `PATH` from the shell env; user server off in the project → absent; built-in `builtin:app` / `builtin:dart` off in the project → absent.
  - Review Focus 5: server `url == null` → no app entry and no skills section in the prompt; `flutterExecutableFor` returns null → no Dart MCP entry; `session/new` still sent.
  - Meta: only when `agent.acceptsClaudeMeta`; `systemPrompt.append` equals `buildRulesPrompt(...)` of enabled rules; `allowedTools == ['mcp__flutter_code_agent']`; `skills` = project skills enabled for project and chat.
  - `AgentHub`: `NewSessionRequest` and `LoadSessionRequest` carry `mcpServers` and `meta` from the provider (fake connector records requests).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** Rules text comes from `ISkillsRepository.read` of every enabled rule (one `watch` snapshot via `.first` with the project root), `AGENTS.md` and `CLAUDE.md` read from the project root.
- [ ] **Step 4: Opt-in integration test** (`FLUTTER_AGENT_TEST=1`, tag `agent`, add the tag to `dart_test.yaml`): real adapter + real app server in a temp project; prompt `Call the list_skills tool of flutter_code_agent and reply with the first skill name.`; expect a `list_skills` tool call, no permission request, and a built-in skill name in the reply. If a permission request arrives, implement the fallback from the spec (`PermissionBroker` auto-answers `allow_once` for `mcp__flutter_code_agent__*`) and keep the test.
- [ ] **Step 5: Run** unit tests, `flutter test`, and the opt-in test once — PASS.
- [ ] **Step 6: Commit** `session_context: app server, Dart MCP, user servers and rules for every session`.

### Task 7: Real MCP status in Settings

**Files:**
- Create: `lib/src/feature/mcp_servers/data/mcp_probe.dart`
- Modify: `lib/src/feature/mcp_servers/models/mcp_server.dart` (`McpStatus.failed`; `isPreview` default false), `mcp_servers_repository.dart` (built-in app entry: `transport: http`, url from `IAppMcpServer`, real `toolCount`; status from probes), `mcp_servers_controller.dart` (probe on open and after add/enable), `mcp_server_row.dart`, `mcp_settings_section.dart` (note `Changes apply to new and reopened chats` / `Изменения применятся к новым и заново открытым чатам`), arb files
- Test: `test/feature/mcp_servers/mcp_probe_test.dart`, `test/feature/mcp_servers/mcp_servers_repository_test.dart`, widget tests of the row

**Interfaces:**
- Produces: `abstract interface class IMcpProbe { Future<McpProbeResult> probe(McpServer server, {Duration timeout = const Duration(seconds: 10)}); }`; `sealed class McpProbeResult` → `McpProbeConnected(int toolCount)`, `McpProbeFailed(String message)`, `McpProbeNeedsAuth()`.
- [ ] **Step 1: Write failing tests:** a scripted stdio MCP server script (`test/support/`) answering `initialize` + `tools/list` with 3 tools → `connected(3)`; a script that never answers → `failed('Timed out')` and its process group is gone (`kill -0` on the group fails); an HTTP stub answering 401 → `needsAuth`; the app entry shows `Running on 127.0.0.1:<port> · N tools`, or the start error.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** with `mcp_dart`'s client (stdio client started in a `GroupedProcess`, HTTP client with the server's headers).
- [ ] **Step 4: Run** tests, `flutter test` — PASS.
- [ ] **Step 5: Commit** `mcp_servers: real status and tool count`.

### Task 8: Skills of every source in the composer

**Files:**
- Modify: `lib/src/feature/prompt_sending/models/slash_commands.dart` (`skillCommands` for all chat skills), `lib/src/feature/chat/widgets/chat_config_widget.dart` (`resourcesFor` adds embedded skill resources), the Skills card's "Try in chat" action (`lib/src/feature/skills/widgets/skill_card.dart`), `test/...`
- Test: `test/feature/prompt_sending/slash_commands_test.dart`, `test/feature/chat/widgets/chat_config_widget_test.dart`

**Interfaces:**
- Consumes: `skillsForChat` (Task 3), `ISkillsRepository.read`.
- Produces: an embedded resource block `{'type': 'resource', 'resource': {'uri': 'skill://<name>/SKILL.md', 'mimeType': 'text/markdown', 'text': <SKILL.md>}}` for a built-in or user skill named by a leading `/<name>` in the prompt; the prompt text sent is the rest after the command (or `Use the <name> skill.` when empty). Project skills keep today's behaviour.
- [ ] **Step 1: Write failing tests:** `/feature-architecture add a todo feature` → text `add a todo feature` + the resource above; a chat-off skill is not in the command list and `/name` stays plain text; "Try in chat" on a built-in skill opens a new chat with the composer prefilled `/<name> `.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** tests, `flutter test` — PASS.
- [ ] **Step 5: Commit** `prompt_sending: /skill and Try in chat for every skill source`.

### Task 9: Runtime errors from the VM service, docs

**Files:**
- Create: `lib/src/feature/app_run/data/flutter_error_listener.dart`
- Modify: `pubspec.yaml` (`vm_service`), `lib/src/feature/app_run/data/app_run_repository.dart` (connect after `app.debugPort`; close on stop and `dispose`), `lib/src/feature/app_run/data/run_output_parser.dart` (`bool structuredErrors` setter: when true, Flutter error blocks (`══╡ EXCEPTION CAUGHT BY …`) are logged as plain lines without a `RunError`), docs: `docs/PLAN.md` (M3 ticks + decisions), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (§3.7, §3.8, §4: "до M3" items are now real), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` (an "M3 follow-ups" section, and remove the M2 follow-up about `Flutter.Error`)
- Test: `test/feature/app_run/flutter_error_listener_test.dart`, `test/feature/app_run/run_output_parser_test.dart`

**Interfaces:**
- Produces: `abstract interface class IFlutterErrorListener { Stream<RunError> errors(); Future<void> close(); }`; `typedef FlutterErrorListenerConnect = Future<IFlutterErrorListener> Function(Uri vmServiceUri);` injected into `AppRunRepositoryImpl` (default uses `vm_service`'s `vmServiceConnectUri`, calls `ext.flutter.inspector.structuredErrors` with `enabled: 'true'` on the main isolate, listens to `EventStreams.kExtension` for `Flutter.Error`).
- Mapping `Flutter.Error` `extensionData` → `RunError(title: <description>, message: <renderedErrorText>, file/line: from the first `creationLocation` or project stack frame)`.
- [ ] **Step 1: Write failing tests:** a scripted `Flutter.Error` event (overflow sample JSON in the test) → one `RunError` with title `A RenderFlex overflowed by 42 pixels on the right.` and the project file/line; with the listener connected, the same overflow text block in stdout gives no second `RunError`; connect throws → parser still produces the error from the text; stop closes the listener.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** tests, `flutter test`, and `FLUTTER_RUN_TEST=1 flutter test test/integration/flutter_run_test.dart` — PASS.
- [ ] **Step 5: Update the docs** listed above.
- [ ] **Step 6: Commit** `app_run: runtime errors from Flutter.Error; M3 docs`.
