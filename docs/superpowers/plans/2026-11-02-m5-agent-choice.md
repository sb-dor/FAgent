# M5 Agent Choice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex, Gemini CLI and user-defined ACP agents become real agents next to Claude: real status, sign-in from the app, a default agent, a per-chat agent choice, and the M3 knowledge delivered to each through its own channel.

**Architecture:** An agent is data (`AgentDefinition`: built-ins in code, custom ones in drift). `AgentHub` follows a changing list of definitions. A generic ACP probe (preflight + `initialize`) plus a small per-built-in sign-in check gives each agent's status; browser sign-ins go through ACP `authenticate`. `SessionContextRepository` builds servers and rules per agent from its `rulesChannel` and the capabilities its `initialize` reported.

**Tech Stack:** Flutter macOS, control, freezed, drift (schema v8 → v9), gen-l10n (en/ru), `dart_acp_sdk` 0.1.1, `GroupedProcess`, `ShellEnvironment`.

**Spec:** `docs/superpowers/specs/2026-11-02-m5-agent-choice-design.md` (Russian). Read it first; it is the authority.

## Global Constraints

- All code follows `CLAUDE.md` and `docs/AI_INSTRUCTIONS.md` (repo overrides win). `common/` never imports `feature/`. Feature widgets take colors only from `context.colors`, radii from `AppRadius`.
- Every user-facing string is in both `intl_en.arb` and `intl_ru.arb`; regenerate with `flutter pub get`; never edit generated files.
- Built-in agent commands, verbatim: Claude `npx -y @agentclientprotocol/claude-agent-acp@0.96.0` (unchanged, Node 22); Codex `npx -y @agentclientprotocol/codex-acp@2.5.0` (Node 20); Gemini `npx -y @google/gemini-cli@0.66.0 --acp` (Node 22).
- Rules channels: Claude `claudeMeta`, Codex `systemPrompt`, Gemini `firstMessage`, custom default `firstMessage`.
- Key variables: Codex `api-key` → `CODEX_API_KEY`, `OPENAI_API_KEY`; Gemini `gemini-api-key` → `GEMINI_API_KEY`. No API key is ever typed into or stored by the app.
- Codex sign-in status: the `_auth/status_update` notification `{authStatus: {kind, label, …}}` pushed after `initialize`; `kind` is one of `none` (label "Not logged in"), `account`, `api_key`, `external`, `gateway`; signed in = any kind but `none`. The client must advertise `_meta: {authStatus: {}}` in its capabilities (verified 2026-11-02 against codex-acp 2.5.0).
- Gemini sign-in: `~/.gemini/oauth_creds.json` exists or `GEMINI_API_KEY` is set. Codex fallback: `~/.codex/auth.json` exists or a key variable is set.
- Codex `systemPrompt` shape: `{"mode": "append", "content": [{"type": "text", "text": <rules>}]}` as a top-level param of `session/new` and `session/load`.
- First-message rules resource: `{"type": "resource", "resource": {"uri": "flutter-agent://rules", "mimeType": "text/markdown", "text": <rules>}}`, inserted at index 1 of the first prompt of a new ACP session only.
- Probe time limit 60 s; Codex auth-status wait after `initialize` 3 s.
- Opt-in real-agent tests: `FLUTTER_AGENT_TEST=1`, tag `agent`.
- Drift: schema v9 adds `custom_agents`; dump/steps/generated-migrations exactly as the M3 plan did (`drift_schemas/`, `database.steps.dart`, `test/generated_migrations/`).
- After every task: `flutter analyze` → No issues found; `flutter test` → all pass. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A custom agent edited while one of its chats is mid-turn — the turn must finish; the process restarts only when no chat of that agent is busy (Task 2 test).
2. A chat whose agent was removed — opening it shows "This agent was removed", never a `StateError` (Task 2 test).
3. The default agent points at a removed or unavailable agent — "＋ Chat" starts a Claude chat, nothing throws (Task 6 test).
4. The first-message rules resource must not appear as user text in the transcript, and Retry must still send the user's text first (Task 5 test).
5. The agent of a new chat is switched after the hub already opened its `LiveSession` — the first prompt goes to the new agent (Task 6 test).

---

### Task 1: Agent definitions and custom agents storage

**Files:**
- Modify: `lib/src/common/acp/agent_definition.dart`
- Create: `lib/src/common/database/tables/custom_agents_table.dart`; modify `database.dart` (v9, step `from8To9`), regenerate `database.steps.dart`, `drift_schemas/drift_schema_v9.json`, `test/generated_migrations/`
- Create: `lib/src/feature/agents/models/custom_agent_draft.dart`, `lib/src/feature/agents/data/custom_agents_repository.dart`
- Modify: every use of `acceptsClaudeMeta` (`session_context_repository.dart`, tests, `test/support/fake_agent_binary.dart`)
- Test: `test/common/acp/agent_definition_test.dart`, `test/feature/agents/custom_agents_repository_test.dart`, the migration test

**Interfaces:**
- Produces (in `common/acp/agent_definition.dart`):
  - `enum RulesChannel { claudeMeta, systemPrompt, firstMessage }`, `enum AgentSource { builtin, custom }`.
  - `AgentDefinition` fields added: `RulesChannel rulesChannel` (default `firstMessage`), `Map<String, List<String>> keyVariables` (default empty), `AgentSource source` (default `builtin`); `acceptsClaudeMeta` removed (callers use `rulesChannel == RulesChannel.claudeMeta`). Value equality (`==`/`hashCode`) over all fields, so the hub can tell an edited definition.
  - `static const AgentDefinition codex`, `static const AgentDefinition gemini` with the Global Constraints values; `static const String codexAdapterVersion = '2.5.0'`, `geminiCliVersion = '0.66.0'`; `static const List<AgentDefinition> builtins = [claude, codex, gemini]`.
- Produces (feature `agents`):
  - `@freezed CustomAgentDraft({required String name, required String executable, List<String> arguments, Map<String,String> environment, RulesChannel rulesChannel = RulesChannel.firstMessage})`.
  - `abstract interface class ICustomAgentsRepository { Stream<List<AgentDefinition>> watch(); Future<String> add(CustomAgentDraft draft); Future<void> update(String id, CustomAgentDraft draft); Future<void> remove(String id); }` — ids `custom:<row id>`, `source: custom`, `displayName: name`. `CustomAgentsRepositoryImpl({required AppDatabase database})`.
  - Table `custom_agents`: `id` int autoIncrement, `name` text, `executable` text, `arguments` text (JSON list), `environment` text (JSON map), `rulesChannel` text (enum name), `createdAt`.

- [ ] **Step 1: Write the failing tests:** `builtins are claude, codex, gemini with the pinned commands` (exact `executable`/`arguments`/`minimumNodeMajor`/`rulesChannel`/`keyVariables`); `definitions with the same fields are equal`; repository: `add then watch emits custom:1 with the draft's fields`, `update changes the definition`, `remove drops it`, `bad JSON in a row is skipped with a warning`; migration `v8 → v9 creates custom_agents`.
- [ ] **Step 2: Run** `flutter test test/common/acp/agent_definition_test.dart test/feature/agents/custom_agents_repository_test.dart` — FAIL.
- [ ] **Step 3: Implement**; `dart run build_runner build`; dump schema v9 and regenerate steps and test migrations.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(agents): built-in Codex and Gemini definitions, custom agents table`.

### Task 2: The hub follows a changing agent list; ACP authenticate and logout

**Files:**
- Modify: `lib/src/common/acp/agent_hub.dart`, `lib/src/common/acp/agent_connection.dart`
- Modify: `lib/src/feature/initialization/data/initialize_dependencies.dart` (build the custom agents repository before the hub; feed `[...AgentDefinition.builtins, ...custom]` into the hub)
- Modify: `test/support/fake_agent.dart` (authMethods `browser-login` and `api-key`; an `authenticate` handler that succeeds unless `FAKE_AGENT_AUTH_FAIL=1`, and hangs if `FAKE_AGENT_AUTH_HANG=1`; a `logout` handler; after `authenticate` succeeds, `auth` prompts no longer throw `-32000`)
- Test: `test/common/acp/agent_hub_agents_test.dart`, `test/common/acp/agent_hub_auth_test.dart`

**Interfaces:**
- Consumes: `AgentDefinition` equality and `builtins` (Task 1).
- Produces:
  - `void AgentHub.setAgents(List<AgentDefinition> definitions)` — new id → new slot; equal definition → nothing; changed → slot's definition replaced, its connection closed now if no chat of that agent is busy, else as soon as the last busy chat of it becomes idle (reason `Agent settings changed`); missing id → slot removed, connection closed (reason `Agent removed`), its live chats get `SessionProblem` text `This agent was removed`. The constructor keeps `agents:` as the initial list.
  - Opening a chat whose `agentId` has no slot no longer throws: the `LiveSession` opens in `error` with problem `This agent was removed` and no retry.
  - `Future<void> AgentHub.authenticate(String agentId, String methodId, {CancellationToken? cancel})` — starts the slot's connection if needed, sends ACP `authenticate` (typed `AuthenticateRequest`), no timeout; on success retries that agent's `needsAuth` chats exactly as the existing `login` success path does (factor the shared part out); on cancel closes the slot's connection (reason `Sign-in cancelled`); errors propagate.
  - `Future<void> AgentHub.logout(String agentId)` — ACP `logout` (typed `LogoutRequest`), then closes the slot's connection.
  - `Map<String, Object?>? AgentHub.initializeResultOf(String agentId)` — the raw `initialize` result of the slot's live connection, `null` when none.
  - `AgentConnection` client capabilities `_meta` gains `'authStatus': {}` (keeps `'terminal-auth': true`).

- [ ] **Step 1: Write the failing tests** (fake agent): `setAgents adds a slot that can run a chat`; `edit while a turn runs restarts only after the turn` (start a `hang` turn, `setAgents` with changed env, assert same process until the turn is cancelled/finished, then a new process); `remove closes the process and marks its chats removed`; `opening a chat of an unknown agent gives the removed problem, not a StateError`; `authenticate succeeds and retries needsAuth chats`; `authenticate failure propagates and leaves needsAuth`; `cancelled authenticate closes the connection`; `logout sends logout and closes`; `initializeResultOf returns agentCapabilities after a chat started`.
- [ ] **Step 2: Run** the two test files — FAIL.
- [ ] **Step 3: Implement**; wire `initialize_dependencies.dart` (listen to the custom agents stream and call `setAgents`; cancel on dispose).
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(acp): dynamic agent list, ACP authenticate and logout`.

### Task 3: The agent probe

**Files:**
- Create: `lib/src/feature/agents/data/agent_probe.dart`, `lib/src/feature/agents/models/agent_probe_result.dart`
- Test: `test/feature/agents/agent_probe_test.dart`

**Interfaces:**
- Consumes: `AgentConnection.start` and its `initializeResult` / `incoming` (Task 2's `authStatus` capability), `AgentPreflight.check`.
- Produces:
  - `@freezed AgentProbeResult({String? version, List<AcpAuthMethod> authMethods, bool mcpHttp, bool mcpSse, bool loadSession, bool systemPrompt, bool canLogout, AcpAuthStatus? authStatus, String? failure, String? notInstalledHint, bool notInstalled})` with `@freezed AcpAuthMethod({required String id, required String name, String? description, String? apiKeyProvider})` and `@freezed AcpAuthStatus({required String kind, required String label})`.
  - `abstract interface class IAgentProbe { Future<AgentProbeResult> probe(AgentDefinition agent); Future<void> dispose(); }`; `AgentProbeImpl({required ShellEnvironment environment, Duration timeout = const Duration(seconds: 60), Duration authStatusWait = const Duration(seconds: 3), connect})` — `connect` defaults to `AgentConnection.start` (tests pass the fake agent). Preflight failure → `notInstalled: true` with the exception's hint; start/initialize failure or timeout → `failure` (one line: `command not found: <exe>` for a missing executable, `no ACP answer to initialize` for a timeout or a non-JSON answer, else the first stderr line); success → fields from `initializeResult` (`agentInfo.version`, `authMethods[*]` with `_meta['api-key'].provider`, `agentCapabilities.mcpCapabilities.http/sse`, `.loadSession`, `.sessionCapabilities.systemPrompt != null`, `.auth.logout != null`); then waits up to `authStatusWait` for a `_auth/status_update` frame on `incoming` and keeps its `authStatus`; always closes the connection. `dispose` closes probes in flight.

- [ ] **Step 1: Write the failing tests:** `ready agent reports version, methods and capabilities` (fake agent: its declared values); `auth status notification is read` (fake agent env `FAKE_AGENT_AUTH_STATUS=account:ChatGPT Plus` makes it push `_auth/status_update` — add that to the fake); `missing executable is a failure "command not found: …"`; `old Node is not installed with the hint`; `silent agent times out as "no ACP answer to initialize"` (a script that never answers, short timeout); `the probe process is gone afterwards`; `dispose closes a probe in flight`.
- [ ] **Step 2: Run** `flutter test test/feature/agents/agent_probe_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the test, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(agents): ACP probe for agent status`.

### Task 4: The agents repository, Settings and the chat sign-in banner for every agent

**Files:**
- Modify: `lib/src/feature/agents/models/agent_info.dart`, `data/agents_repository.dart`, `controller/agent_actions_controller.dart`, `widgets/agent_card.dart`, `widgets/agents_settings_section.dart`, `widgets/agents_config_widget.dart`
- Create: `lib/src/feature/agents/widgets/custom_agent_dialog.dart`
- Modify: `lib/src/feature/app_settings/widgets/general_settings_section.dart` (default agent picker), `lib/src/feature/chat/widgets/chat_problem_banner.dart`, `lib/src/feature/chat/data/chat_repository.dart` (`loginMethods` from the agents repository), `lib/src/feature/initialization/data/initialize_dependencies.dart`, `lib/src/feature/app_close/data/app_close_repository.dart` (dispose the probe)
- Modify: both arb files; `test/support/memory_agents_repository.dart`
- Test: `test/feature/agents/agents_repository_test.dart`, `agents_settings_section_test.dart`, `custom_agent_dialog_test.dart`, `test/feature/chat/chat_problem_banner_test.dart`

**Interfaces:**
- Consumes: `AgentDefinition.builtins`, `ICustomAgentsRepository` (Task 1); `AgentHub.authenticate/logout/login` (Task 2); `IAgentProbe` (Task 3).
- Produces:
  - `AgentStatus` gains `failed`. `AgentInfo` replaces `loginMethods: List<String>` with `List<AgentLoginMethod> methods` and adds `AgentSource source`, `bool canSignOut`; `isPreview` removed. `@freezed AgentLoginMethod({required String id, required String name, required AgentLoginKind kind, List<String> keyVariables, bool keyPresent})`, `enum AgentLoginKind { terminal, browser, apiKey, unsupported }` — Claude's methods are `terminal` (from `loginArguments`); for others a method with `apiKeyProvider` or a `keyVariables` entry is `apiKey`; `vertex-ai` and `gateway` are `unsupported`; the rest `browser`.
  - `IAgentsRepository`: `install` and the preview agents removed; `login(agentId, methodId)` — `terminal` → `hub.login` (as now), `browser`/`apiKey` → `hub.authenticate`; `Future<void> cancelLogin(String agentId)`; `logout` — Claude as now, others `hub.logout` when `canSignOut`; `refresh(agentId)` probes any agent; `Future<void> addCustom(CustomAgentDraft)`, `updateCustom(String id, CustomAgentDraft)`, `removeCustom(String id)` delegate to `ICustomAgentsRepository`; `openSettings` stays Claude-only.
  - Status per agent: preflight/probe as Task 3; Claude sign-in as today; Codex — `authStatus.kind != 'none'` (account = `label`), without a push the fallback files/variables; Gemini — the files/variable; custom — `ready` with `hint` "sign-in is checked on the first chat". Checked once at startup in the background and on `refresh`; Settings → Agents calls `refresh` for every agent when it opens.
  - Settings card: methods by kind — `browser` → a sign-in button (with the running dialog and Cancel → `cancelLogin`); `apiKey` with `keyPresent: false` → text naming the variables and "restart the app to pick up the key", with `keyPresent: true` → "Use API key"; `unsupported` → "Set this up in the agent's own settings"; `failed` shows the one-line reason; custom cards have Edit and Remove (Remove asks when a chat of it is busy). "Add ACP agent" opens `CustomAgentDialog` (name, command, arguments one per line, `KEY=value` lines, rules channel).
  - Default agent picker: enabled for every agent except `notInstalled` and `failed`.
  - `ChatProblemBanner`: needs-auth buttons come from the agent's `methods` with their localized names (the method's `name` for non-Claude); an `apiKey` method without its variable shows the variable hint instead of a button.

- [ ] **Step 1: Write the failing tests:** repository — `codex signed in from the auth status push`, `codex falls back to auth.json`, `gemini needs sign-in without creds or key`, `gemini signed in with GEMINI_API_KEY`, `custom agent is ready with the first-chat hint`, `browser login goes to authenticate`, `terminal login goes to hub.login`, `logout of codex calls hub.logout`, `vertex-ai is unsupported`, `add/update/remove custom delegate`; widgets — the card for each kind, the dialog's validation (name and command required, `KEY=value` parsing), Remove confirmation with a busy chat, the default picker's enabled set, the banner's methods for a Codex chat.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; remove `previewCodexAgent`, `previewGeminiAgent`, `AgentPreviewException` uses, `showCustomAgentComingSoon` and the Preview badges; update arb keys (add what the cards and dialog need; drop keys left unused; grep to confirm).
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(agents): real Codex, Gemini and custom agents in Settings`.

### Task 5: Knowledge for each agent

**Files:**
- Modify: `lib/src/common/acp/session_context.dart`, `lib/src/common/acp/agent_hub.dart`, `lib/src/common/acp/agent_connection.dart`, `lib/src/feature/session_context/data/session_context_repository.dart`, `lib/src/feature/chat/models/chat_transcript.dart`
- Test: `test/feature/session_context/session_context_repository_test.dart`, `test/common/acp/agent_hub_context_test.dart`, `test/feature/chat/chat_transcript_test.dart`

**Interfaces:**
- Consumes: `RulesChannel` (Task 1), `initializeResultOf` (Task 2).
- Produces:
  - `SessionContext({required servers, meta, String? systemPrompt, String? firstMessageRules, List<String> skippedServers})`; `SessionContextProvider` becomes `Future<SessionContext> Function(int sessionId, AgentDefinition agent, Map<String, Object?> initializeResult)`.
  - Repository: servers — HTTP servers only when `mcpCapabilities.http == true`, SSE servers only when `.sse == true` (today `McpTransport` has only `stdio`/`http`, so only the HTTP check bites; names of dropped servers go to `skippedServers`), stdio always. Rules text: `buildRulesPrompt` with `agentReadsProjectRules: rulesChannel == claudeMeta`, and `agentsMd` omitted when the agent is Codex (`agent.id == AgentDefinition.codex.id`). `claudeMeta` → today's `meta`; `systemPrompt` → `systemPrompt` set, no meta; `firstMessage` → `firstMessageRules` set, no meta.
  - Hub: `session/new` and `session/load` carry `systemPrompt` (Global Constraints shape) when set — send them through a hand-built `AcpMethodDescriptor` for `session/new` / `session/load` with a pass-through JSON codec on `AgentConnection` (`Future<Map<String,Object?>> AgentConnection.requestRaw(String method, Map<String,Object?> params)`). **If the SDK refuses a custom descriptor for a standard method name**, fall back: Codex uses the `firstMessage` channel, record it in the report, and keep `requestRaw` out. A new ACP session's first prompt gets the rules resource at index 1 of `live.lastPrompt` (only when `firstMessageRules != null` and the session was just created, never after `session/load`); `retryPrompt` keeps working (text first). `skippedServers` → one `HubNotice` per chat start.
  - Auto-allow for non-Claude agents in `_onPermission`: when `slot.definition.rulesChannel != claudeMeta` and the request's `toolCall.title` or raw `toolCall` JSON contains `flutter_code_agent`, answer with the first `allow_once`/`allow_always` option at once (no prompt in the chat, still journaled as `permissionRequest` + its resolution). Task 7 checks the real titles.
  - Transcript: a prompt's `flutter-agent://rules` resource is not shown in the user message.

- [ ] **Step 1: Write the failing tests:** context — the rules table of the spec (Claude meta without `.claude/rules`; Codex `systemPrompt` with `.claude/rules` and without `AGENTS.md`; Gemini `firstMessageRules` with both); `http servers dropped for an agent without mcp http` with `skippedServers`; hub (fake agent with `FAKE_AGENT_REQUESTS_FILE`) — `systemPrompt reaches session/new and session/load raw`, `rules resource only in the first prompt of a new session`, `no rules resource after session/load`, `retry after a first-prompt failure sends text first`, `app tool permission is auto-allowed for a non-Claude agent` (fake agent `permission` script with a `flutter_code_agent` title), `other permissions still ask`; transcript — `rules resource hidden from the user message`.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; update the provider wiring in `initialize_dependencies.dart`.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(session_context): rules and tools for every agent`.

### Task 6: Choosing the agent per chat and the default agent

**Files:**
- Modify: `lib/src/feature/sessions/data/sessions_repository.dart` (+ its controller), `lib/src/common/acp/agent_hub.dart` (`forget`), `lib/src/feature/session_config/widgets/composer_toolbar.dart`, `lib/src/feature/chat/widgets/chat_screen.dart`, `lib/src/feature/workspace/widgets/workspace_chat_tile.dart`, `workspace_sidebar_footer.dart` (`agentDisplayName`), `workspace_config_widget.dart` (`createChat` default fallback)
- Modify: both arb files
- Test: `test/feature/sessions/sessions_repository_test.dart`, `test/feature/session_config/composer_toolbar_test.dart`, `test/feature/workspace/workspace_chat_tile_test.dart`, a workspace test for the default fallback

**Interfaces:**
- Consumes: `AgentInfo` list from the agents controller (Task 4), `AgentHub.setAgents` semantics (Task 2).
- Produces:
  - `Future<void> ISessionsRepository.setAgent(int sessionId, String agentId)` — throws `StateError` when the row's `acpSessionId != null`; else updates `agentId` and calls `AgentHub.forget(sessionId)`.
  - `Future<void> AgentHub.forget(int sessionId)` — drops a cached `LiveSession` that has no ACP session and is idle/cold (no-op otherwise), so the next open reads the new `agentId`.
  - `ComposerToolbar` gains `List<AgentInfo> agents`, `String agentId`, `ValueChanged<String>? onAgentSelected`; the chip lists every agent: `ready`/`needsLogin` selectable, `notInstalled`/`failed` disabled with the reason as subtitle; locked after the first message with the tooltip "The agent can't be changed after the first message". Model/effort/mode chips follow the selected agent's options and defaults.
  - `String agentDisplayName(String id, List<AgentInfo> agents)` — the agent's name, else the id.
  - `WorkspaceChatTile` shows a small agent label when `session.agentId != 'claude'`.
  - `createChat` uses `defaultAgentId` when that agent is known and not `notInstalled`/`failed`, else `claude`; the agent card of an unavailable default says new chats use Claude.

- [ ] **Step 1: Write the failing tests:** `setAgent changes a new chat's agent`; `setAgent refuses after the first message`; `switching agent after the hub opened the chat sends the first prompt to the new agent` (two fake-agent definitions with different `FAKE_AGENT_REQUESTS_FILE`s); chip — entries, disabled reasons, locked tooltip, selection calls `onAgentSelected`; tile — label for a Codex chat, none for Claude; workspace — `default pointing at a removed agent starts a Claude chat`.
- [ ] **Step 2: Run** the test files — FAIL.
- [ ] **Step 3: Implement**; remove the hard-coded `['Codex', 'Gemini CLI']` "Coming in M5" items.
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `feat(chat): choose the agent per chat, default agent fallback`.

### Task 7: Real-agent checks and the milestone docs

**Files:**
- Create: `test/integration/agents_test.dart` (tag `agent`, skips unless `FLUTTER_AGENT_TEST=1`)
- Modify (only if the run shows it): `lib/src/common/acp/agent_hub.dart` auto-allow predicate
- Modify: `docs/PLAN.md` (M5 ticks, «Решения M5» from the spec's last section), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (§3.4 agent chip, the stage-6 «Preview до M5» bullet, §4 `agents` row), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` ("## M5 follow-ups"; remove the M3 item "gate the app's HTTP entry on `mcpCapabilities.http`", done in Task 5)

**Interfaces:**
- Consumes: everything above, with the real app MCP server and session context (as `test/integration/agent_knowledge_test.dart` builds them).

- [ ] **Step 1: Write the opt-in test:** `codex probe is ready and signed in` (real `AgentProbeImpl` on `AgentDefinition.codex`: version `2.5.0`, `authStatus.kind != 'none'`, `systemPrompt` true, `mcpHttp` true); `codex calls list_skills` (a real hub chat in a temp project with the real session context; prompt "Call the list_skills tool of flutter_code_agent and reply with the number of skills."; assert a `list_skills` call reached the app server and the turn ended; record every `permissionRequest` event's `toolCall` JSON in the test output); `gemini probe reports its methods` (`oauth-personal`, `gemini-api-key`, `vertex-ai`, `gateway`; `mcpHttp` and `mcpSse` true).
- [ ] **Step 2: Run** `FLUTTER_AGENT_TEST=1 flutter test --tags agent test/integration/agents_test.dart` (needs network and the signed-in Codex). If Codex asked permission for `list_skills` and the recorded `toolCall` does not match the Task 5 predicate, adjust the predicate to what Codex sends (server name in `title`, `rawInput` or `_meta`), add a unit test with that exact JSON, and re-run. If nothing distinguishes the app's tools, keep asking and record it under M5 follow-ups.
- [ ] **Step 3: Update the docs.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze` — pass, clean.
- [ ] **Step 5: Commit** `test(agents): real Codex and Gemini checks; docs: M5`.
