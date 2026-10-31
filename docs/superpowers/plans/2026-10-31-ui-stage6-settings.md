# UI Stage 6 (Settings) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этап 6 спеки: все разделы экрана «Настройки» вместо заглушек — Общие, Агенты (Claude Real, Codex/Gemini/свой — Fake до M5), MCP-серверы (хранение Real в drift, схема v6; статус и инструменты — Preview до M3), Разрешения (Real: правила «Всегда в этом проекте» из `.claude/settings.local.json`), Flutter (путь SDK и fvm — Real, версия и `flutter doctor` — Fake до M4), Внешний вид, Горячие клавиши — как в макете `docs/design/5-settings.html`.

**Architecture:** Каждый раздел — виджет своей фичи (`lib/src/feature/<feature>/widgets/*_settings_section.dart`) со своим ConfigWidget и контроллером; `WorkspaceSettingsPage` только выбирает раздел и оборачивает его. Новые фичи: `agents`, `mcp_servers`, `permission_rules`, `flutter_sdk`; их репозитории — в `Dependencies`. Новые поля `AppSettings` (закрытие, плотность ленты, org, шаблон, DevTools) и каталог настроек агента (модели/усилия/режимы последней сессии) хранятся в той же таблице `app_settings` (новый ключ, без миграции).

**Tech Stack:** Flutter (macOS), control, freezed, drift (v5 → v6), gen-l10n en/ru, `file_selector` (уже есть). Новых пакетов нет.

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` §2 (горячие клавиши), §3.8, §3.10, §4 (таблица фич, модели `AgentInfo`/`McpServer`, БД), §6; макет `docs/design/5-settings.html`. Отложенное — `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`.

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями `CLAUDE.md`: репозитории `abstract interface` + `Impl({required this._x})`; виджеты не трогают репозитории (только контроллеры через ConfigWidget/InheritedWidget); Sequential для load/watch, Droppable для мутаций; Stream-методы репозиториев по Pattern 1 (onListen/onCancel), гарантированно закрываются; каждый `Process` завершается или убивается.
- Раскладка (спека §3.8, уже в `WorkspacePageScaffold`): навигация 220 px / рейл 56 px уже `kWideWindowWidth`, колонка max 640 px, отступы 32; карточки в одну колонку, внутри перенос (`Wrap`, `softWrap`), а не обрезка; ничего не переполняется при 900×600.
- Карточки — общие `AppCard` и `KeyValueGrid` (`lib/src/common/widget/app_card.dart`), статусы — `lib/src/common/widget/status.dart`, сегменты — `SegmentedControl`, меню — `AppMenu`/`SelectorChip`.
- Fake-части (спека §4 «Фейковые репозитории»): данные детерминированные, задержки через параметр `step`; у модели флаг `isPreview` → `PreviewBadge`; действие, которого ещё нет, показывает SnackBar `comingInMilestone('<M>')` и ничего не делает.
- Цвета только `context.colors`, радиусы `AppRadius`, моно — `AppText.mono`, шаг 4 px; Material Icons; у кнопок-иконок `tooltip`.
- Все строки — `intl_en.arb` и `intl_ru.arb` (русское множественное — one/few/many/other, без `=1`; обращение на «вы»).
- Новая версия схемы — step-by-step + тест `SchemaVerifier`, как v5 (команды: `dart run drift_dev schema dump lib/src/common/database/database.dart drift_schemas/`, `dart run drift_dev schema steps drift_schemas/ lib/src/common/database/database.steps.dart`, `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`).
- Виджет-тесты не трогают настоящие файлы и процессы (в fake async они зависают): для них — двойники в `test/support/` и параметры по умолчанию в `testDependencies`.
- `flutter analyze` чистый; коммиты заканчиваются `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. `.claude/settings.local.json` проекта битый, без `permissions`, с не-строками в `allow` или с чужими ключами (`hooks`, `env`) — раздел «Разрешения» не падает (битый файл — строка ошибки у этого проекта), а удаление правила сохраняет все остальные ключи файла (Task 7).
2. Импорт `.mcp.json` с занятым именем, `sse`-сервером, записью без `command`/`url` или файлом не-JSON — понятный итог «добавлено N, пропущено M (почему)», ничего не перезаписано (Task 5).
3. Claude: нет Node.js или он старше 22, `npx` не найден, `auth status` висит или печатает не JSON — карточка показывает «не установлен» с подсказкой или «вход не известен», а не вечную загрузку (таймаут) и не исключение (Task 3).
4. Модель/усилие/режим по умолчанию до первой сессии агента (каталог пуст) — меню не пустые кнопки: строка «Откройте чат с агентом, чтобы выбрать» и «Сбросить», если значение уже сохранено; режим `bypassPermissions` в меню режима отсутствует (Task 4).
5. Неверный org (`Com.Example`, `example`, `com..x`) — поле показывает ошибку и не сохраняет; верный сохраняется после ввода без отдельной кнопки (Task 8).

---

### Task 1: Новые поля настроек: закрытие, плотность, org, шаблон, DevTools

**Files:**
- Modify: `lib/src/feature/app_settings/models/app_settings.dart`, `lib/src/feature/app_close/data/app_close_repository.dart`, `lib/src/feature/app_close/controller/app_close_controller.dart`, `lib/src/feature/chat/widgets/chat_feed.dart`, место создания `AppCloseRepositoryImpl` (найти `grep -rn AppCloseRepositoryImpl lib`)
- Test: `test/feature/app_settings/app_settings_test.dart`, `test/feature/app_close/*` (существующий тест контроллера), `test/feature/chat/` (тест ленты, где проверяется отступ)

**Interfaces:**
- Produces (в `app_settings.dart`):
  - `enum FeedDensity { comfortable, compact }`, `enum NewProjectTemplate { architecture, plain, git }`, `enum DevToolsTarget { browser, app }`.
  - Поля `AppSettings` (с `copyWith`, `==`, `hashCode`, `toJson`/`fromJson` как у существующих): `bool askBeforeQuit` (по умолчанию `true`; JSON `askBeforeQuit`), `FeedDensity feedDensity` (`comfortable`), `String projectOrg` (`'com.example'`; при чтении невалидный org → по умолчанию), `NewProjectTemplate projectTemplate` (`architecture`), `DevToolsTarget devToolsTarget` (`browser`). Неизвестное имя enum → значение по умолчанию.
  - `static final RegExp orgPattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');` — им же проверяет поле в Task 8.
  - `IAppCloseRepository.askBeforeQuit() → Future<bool>`; `AppCloseRepositoryImpl` получает `IAppSettingsRepository settings` и читает `(await settings.watch().first).askBeforeQuit`.
- `AppCloseController.requestClose`: при `busyChats > 0 && !await _repository.askBeforeQuit()` — сразу `_quit()`.
- Лента: вертикальный отступ строки `6` для `comfortable`, `2` для `compact` (`chat_feed.dart`, `Padding` элемента); плотность берётся из `AppSettingsConfigInhWidget.of(context).controller` через `ListenableBuilder`.

- [ ] **Step 1: Failing tests** в `app_settings_test.dart`: `'new fields default and round trip'` — `const AppSettings()` даёт `askBeforeQuit == true`, `feedDensity == FeedDensity.comfortable`, `projectOrg == 'com.example'`, `projectTemplate == NewProjectTemplate.architecture`, `devToolsTarget == DevToolsTarget.browser`; `AppSettings.fromJson(s.toJson()) == s` для `s` со всеми непустыми значениями (`compact`, `'dev.avaz'`, `plain`, `app`, `false`); `'bad stored values fall back'` — `fromJson({'feedDensity': 'huge', 'projectOrg': 'Com.Example', 'projectTemplate': 1, 'askBeforeQuit': 'no'})` даёт значения по умолчанию.
- [ ] **Step 2:** в тесте контроллера закрытия: `'quits without asking when askBeforeQuit is off'` — репозиторий-двойник с `busyChats → 2`, `askBeforeQuit → false`; после `requestClose()` вызваны `shutdown` и `quit`, состояние ни разу не `confirming`.
- [ ] **Step 3:** виджет-тест ленты `'compact density tightens the feed'`: с `feedDensity: compact` у `Padding` элемента ленты `vertical == 2`, с `comfortable` — `6`.
- [ ] **Step 4:** `flutter test test/feature/app_settings test/feature/app_close test/feature/chat` — новые тесты FAIL.
- [ ] **Step 5:** реализовать; `dart run build_runner build --delete-conflicting-outputs`, если нужно; тесты PASS; `flutter analyze` — No issues.
- [ ] **Step 6: Commit** `git commit -m "settings: quit, feed density, org, template and DevTools fields"`.

### Task 2: Экран настроек: каркас разделов, Общие, Внешний вид, Горячие клавиши

**Files:**
- Modify: `lib/src/feature/workspace/widgets/workspace_settings_page.dart` (убрать `SectionPlaceholder` у реализованных разделов, `_milestones` — только для ещё не сделанных; к концу этапа заглушек нет), `lib/src/feature/workspace/widgets/workspace_page_scaffold.dart` (параметр `subtitle`)
- Create: `lib/src/feature/app_settings/widgets/general_settings_section.dart`, `lib/src/feature/app_settings/widgets/appearance_settings_section.dart`, `lib/src/feature/app_settings/widgets/settings_row.dart`, `lib/src/feature/workspace/widgets/shortcuts_settings_section.dart`
- Modify: `lib/src/common/localization/intl_en.arb`, `intl_ru.arb`
- Test: `test/feature/workspace/workspace_settings_page_test.dart` (новый)

**Interfaces:**
- Produces:
  - `SettingsRow({required String label, String? hint, required Widget control})` — строка раздела: подпись (и серая подсказка под ней) слева, контрол справа; уже 480 px контрол переносится под подпись. Используют все разделы.
  - `GeneralSettingsSection()` — карточка: «Язык» (`SelectorChip` + `AppMenu`: Системный / English / Русский → `AppSettingsController.update((s) => s.copyWith(locale: …))` или `resetLocale: true`), «При закрытии, пока агенты работают» (`Switch` «Спрашивать» ↔ `askBeforeQuit`). Строку «Агент по умолчанию» добавит Task 4 (слот `agentRow` не нужен — Task 4 правит этот файл).
  - `AppearanceSettingsSection()` — «Тема» (`SegmentedControl`: Системная / Светлая / Тёмная ↔ `themeMode`), «Плотность ленты» (`SegmentedControl`: Обычная / Компактная ↔ `feedDensity`).
  - `ShortcutsSettingsSection()` — список только для чтения из спеки §2: ⌘N новый чат · ⌘K поиск по чатам · ⌘\ сайдбар · ⌘J правая панель · ⌘, настройки · ⌘R hot reload · ⇧⌘R hot restart · ⇧Tab режим разрешений · Esc закрыть меню/страницу; клавиши — моно-чипы (`AppText.mono`, фон `colors.surface`, `AppRadius` 6).
  - Под заголовком каждого раздела — подзаголовок (`bodySmall`, `colors.muted`) из макета: Агенты — «Агенты работают через Agent Client Protocol. Подписка и вход — ваши; приложение только запускает агента.», MCP — «Передаются агенту в каждой сессии. Встроенные выключаются только по проекту.» (+ Task 6 добавляет пометку M3), остальные — без подзаголовка. Подзаголовок — параметр `subtitle` у `WorkspacePageScaffold` (новый, `String?`, показывается под `label` при `fill == false`).

- [ ] **Step 1: Failing tests** `workspace_settings_page_test.dart` (через `testDependencies` и существующий способ открыть экран настроек — см. `test/feature/workspace/workspace_test.dart`):
  - `'general: language menu switches to Russian'`: открыть «Общие», выбрать «Русский» — `AppSettingsController.settings.locale == const Locale('ru')`, заголовок раздела — «Общие».
  - `'general: ask before quit switch'`: переключатель меняет `askBeforeQuit` на `false`.
  - `'appearance: theme and density'`: «Тёмная» → `themeMode == ThemeMode.dark`; «Компактная» → `feedDensity == FeedDensity.compact`.
  - `'shortcuts lists every binding'`: видны `'⌘N'`, `'⌘K'`, `'⌘\\'`, `'⌘J'`, `'⌘,'`, `'⌘R'`, `'⇧⌘R'`, `'⇧Tab'`, `'Esc'`.
  - `'sections fit 900×600 and 1280×800 in en and ru, light and dark'`: для каждого из трёх разделов и каждой комбинации — нет исключений рендера (`tester.takeException() == null`).
- [ ] **Step 2:** `flutter test test/feature/workspace/workspace_settings_page_test.dart` — FAIL.
- [ ] **Step 3:** реализовать разделы и строки ARB; `flutter pub get`.
- [ ] **Step 4:** тесты PASS, весь `flutter test` зелёный (старые тесты заглушек обновить под новые разделы), `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Settings screen: General, Appearance and Shortcuts sections"`.

### Task 3: Агенты: модель, репозиторий (Claude Real, Codex/Gemini Fake), каталог настроек

**Files:**
- Create: `lib/src/feature/agents/models/agent_info.dart`, `lib/src/feature/agents/data/agents_repository.dart`, `lib/src/feature/agents/data/claude_auth_status.dart`, `lib/src/feature/agents/data/agent_options_catalog.dart`
- Modify: `lib/src/common/acp/agent_hub.dart` (колбэк каталога), `lib/src/feature/initialization/models/dependencies.dart`, `lib/src/feature/initialization/data/initialize_dependencies.dart`, `test/support/test_app.dart`
- Create (тест-двойник): `test/support/memory_agents_repository.dart`
- Test: `test/feature/agents/claude_auth_status_test.dart`, `test/feature/agents/agents_repository_test.dart`, `test/common/acp/` (тест хаба на колбэк — рядом с существующими тестами `AgentHub`)

**Interfaces:**
- Produces:
  - `enum AgentStatus { checking, ready, needsLogin, notInstalled, installing }`.
  - `AgentInfo` (freezed): `String id`, `String name`, `String? version` (Claude — `AgentDefinition.claudeAdapterVersion`), `String? runtime` (Claude — `'Node 22.11'` из `node --version`), `AgentStatus status`, `String? account` (email / организация / источник ключа; `null` — «не сообщается»), `String? problem` и `String? hint` (из `AgentPreflightException`), `List<String> loginMethods` (Claude: `claude-ai-login`, `console-login`), `List<ConfigOption> options` (каталог), `bool isPreview`, `bool canStartChats` (только Claude `true`).
  - `ClaudeAuth? parseClaudeAuthStatus(String stdout)` в `claude_auth_status.dart` — `({bool loggedIn, String? account})`; по полям `claude auth status --json`: `loggedIn` (bool, обязателен — иначе `null`), `email`, `orgName`, `apiKeySource`, `apiProvider`. Вошли, если `loggedIn` или есть `apiKeySource`, или `apiProvider` не `firstParty`; `account` = `email` ?? `orgName` ?? `apiKeySource` ?? `apiProvider`.
  - `abstract interface class IAgentOptionsCatalog { Stream<Map<String, List<Map<String, Object?>>>> watch(); Future<void> save(String agentId, List<Map<String, Object?>> options); }`; `AgentOptionsCatalogImpl({required AppDatabase database})` — строка `app_settings` с ключом `agentOptions`, JSON `{agentId: [option…]}`; `save` пишет только при отличии (глубокое сравнение) и не пишет пустой список.
  - `AgentHub` получает необязательный `void Function(String agentId, List<Map<String, Object?>> options)? onConfigOptions`; в `_open` вешается слушатель на `live.configOptions`, вызывает колбэк при непустом значении. В `initialize_dependencies.dart` колбэк — `catalog.save(...)` (ошибки в `l.w`).
  - `abstract interface class IAgentsRepository`:
    - `Stream<List<AgentInfo>> watchAgents()` — порядок: Claude, Codex, Gemini. Сразу отдаёт последнее известное (вначале Claude в `checking`), затем проверяет Claude и отдаёт снова; при изменении каталога — снова.
    - `Future<void> refresh(String agentId)` — повторная проверка (для Fake — ничего).
    - `Future<AgentLogin> login(String agentId, String methodId)` — Claude: `AgentHub.login`, после `succeeded` — `refresh`; Fake → `AgentPreviewException('M5')`.
    - `Future<void> logout(String agentId)` — Claude: `<npx> <args> --cli auth logout`, затем `refresh`; Fake → `AgentPreviewException('M5')`.
    - `Future<void> install(String agentId)` — всегда `AgentPreviewException('M5')` (Claude ставится через `npx` сам; при `notInstalled` карточка показывает `hint`).
    - `Future<void> openSettings(String agentId)` — Claude: `open -t ~/.claude/settings.json`, если файла нет — `open ~/.claude` (папки нет — `AgentSettingsMissingException`).
  - `AgentsRepositoryImpl({required AgentHub hub, required ShellEnvironment environment, required IAgentOptionsCatalog catalog, ProcessRunner? runProcess, Future<String> Function(AgentDefinition, ShellEnvironment)? preflight, Duration statusTimeout = const Duration(seconds: 30)})`, где `typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments, {Map<String, String>? environment})`; `preflight` по умолчанию — `AgentPreflight.check`. Проверка Claude: preflight (исключение → `notInstalled`, `problem`/`hint`); `node --version` → `runtime`; `<executable> ...AgentDefinition.claude.arguments --cli auth status --json` с `statusTimeout` (таймаут или `null` из парсера → `ready`, `account == null`); `loggedIn == false` → `needsLogin`.
  - Fake Codex: `AgentInfo(id: 'codex', name: 'Codex', status: notInstalled, problem: 'codex-acp · Node 22+', isPreview: true, canStartChats: false)`; Gemini: `AgentInfo(id: 'gemini', name: 'Gemini CLI', version: '0.9.2', status: needsLogin, loginMethods: ['google'], isPreview: true, canStartChats: false)`.
  - `Dependencies.agentsRepository` (`IAgentsRepository`); шаг инициализации «Create agents repository» после «Create agent hub»; каталог создаётся до хаба (хаб получает колбэк).
  - `MemoryAgentsRepository({List<AgentInfo>? agents})` — список в памяти, `login`/`logout` меняют статус Claude, записывает вызовы (`calls`); по умолчанию в `testDependencies`.

- [ ] **Step 1: Failing tests** `claude_auth_status_test.dart`: `'{"loggedIn":true,"email":"a@b.c"}'` → `(loggedIn: true, account: 'a@b.c')`; `'{"loggedIn":false}'` → `loggedIn == false`; `'{"loggedIn":false,"apiKeySource":"ANTHROPIC_API_KEY"}'` → вошли, `account == 'ANTHROPIC_API_KEY'`; `'{"loggedIn":false,"apiProvider":"bedrock"}'` → вошли; `'not json'` и `'{"email":"x"}'` → `null`.
- [ ] **Step 2:** `agents_repository_test.dart` (обычный `test`, двойники `runProcess`/`preflight`, каталог-двойник в памяти; хаб — как в существующих тестах хаба, с фейковым агентом):
  - `'claude is ready with the account'`: preflight → `'/usr/bin/npx'`, `node --version` → `v22.11.0`, status → `{"loggedIn":true,"email":"a@b.c"}`; второй элемент потока — Claude `ready`, `account 'a@b.c'`, `runtime 'Node 22.11'`; первый — `checking`.
  - `'missing node is not installed with a hint'`: preflight бросает `AgentPreflightException('Node.js 22+ …', hint: 'Install …')` → `notInstalled`, `problem`/`hint` заполнены, `auth status` не запускался.
  - `'hanging status ends as ready without account'`: `runProcess` для status не завершается, `statusTimeout: 50 ms` → `ready`, `account == null`.
  - `'logged out claude needs login'`, `'logout runs auth logout then checks again'` (аргументы последнего вызова заканчиваются `['--cli', 'auth', 'logout']`, затем снова `auth status`).
  - `'fake agents refuse actions'`: `login('codex', …)`, `install('gemini')` бросают `AgentPreviewException` с `milestone == 'M5'`.
  - `'catalog options reach the agent'`: каталог отдаёт `{'claude': [{'id': 'model', 'type': 'select', 'currentValue': 'opus', 'options': [{'value': 'opus', 'name': 'Opus'}]}]}` → у Claude `options` содержит `SelectConfigOption` с id `model`.
  - тест хаба `'config options reach onConfigOptions'`: после создания сессии с фейковым агентом колбэк получает `('claude', <непустой список>)`.
- [ ] **Step 3:** `flutter test test/feature/agents test/common/acp` — новые FAIL.
- [ ] **Step 4:** реализовать; `build_runner`; тесты PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "agents: status, login and logout for Claude, preview agents, options catalog"`.

### Task 4: Раздел «Агенты» и агент по умолчанию

**Files:**
- Create: `lib/src/feature/agents/controller/agents_controller.dart`, `lib/src/feature/agents/controller/agent_actions_controller.dart`, `lib/src/feature/agents/widgets/agents_config_widget.dart`, `lib/src/feature/agents/widgets/agents_settings_section.dart`, `lib/src/feature/agents/widgets/agent_card.dart`, `lib/src/feature/agents/widgets/agent_defaults.dart`
- Modify: `lib/src/feature/app_settings/widgets/general_settings_section.dart` (строка «Агент по умолчанию»), `lib/src/feature/workspace/widgets/workspace_settings_page.dart` (разделы `general` и `agents` обёрнуты в `AgentsConfigWidget`), ARB
- Test: `test/feature/agents/agents_settings_section_test.dart`

**Interfaces:**
- Consumes: Task 3 (`IAgentsRepository`, `AgentInfo`, `AgentLogin`), `AppSettingsController.update`, `modelOption`/`effortOption`/`permissionModeOf`/`bypassPermissionMode` из `session_config/models`.
- Produces:
  - `AgentsController` (Sequential): `watch()`; состояние freezed `initial | completed(List<AgentInfo>) | error(Object, List<AgentInfo>)`; геттер `List<AgentInfo> agents`.
  - `AgentActionsController` (Droppable): `login(id, method)`, `logout(id)`, `install(id)`, `openSettings(id)`; состояние хранит `Map<String, List<String>> output` (строки текущего входа агента из `AgentLogin.output`, очищаются при новом входе) и `String? previewMilestone` / `Object? error` последнего действия (виджет показывает SnackBar и сбрасывает).
  - `AgentCard({required AgentInfo agent})` — по макету: лого 32 px (`Icons.auto_awesome` для Claude, `Icons.terminal` Codex, `Icons.diamond_outlined` Gemini), имя, бейдж «по умолчанию» у `defaultAgentId`, строка `version · runtime` моно; статус-пилюля (`checking` — «Проверяем…», `ready` — «● вошли · account» или «● вошли», `needsLogin` — «нужен вход», `notInstalled` — «не установлен», `installing`); действия: `ready` → «Выйти»; `needsLogin` → «Войти» (меню из `loginMethods`: `claude-ai-login` — «Подписка Claude», `console-login` — «Anthropic Console», `google` — «Войти с Google»); `notInstalled` → «Установить» + `problem` и `hint` текстом; `isPreview` → `PreviewBadge`. Вывод текущего входа — моно-блок до 8 последних строк под шапкой. Для `canStartChats`: `KeyValueGrid` «Модель по умолчанию» (`SelectorChip` модель + `SelectorChip` усилие), «Режим по умолчанию» (режимы без `bypassPermissionMode`), «Настройки Claude» — текст «Также читаются ~/.claude/settings.json и .claude/ проекта» + ссылка «открыть» (`openSettings`).
  - `AgentDefaults` — меню значения: выбор пишет `sessionDefaults[agentId][configId] = value` через `AppSettingsController.update`; текущий текст чипа — имя выбранного из каталога, иначе сохранённое значение, иначе «Как у агента»; пустой каталог — пункт-подсказка «Откройте чат с агентом, чтобы выбрать» (неактивный) и «Сбросить» (удаляет ключ), если значение сохранено.
  - Внизу раздела — кнопка «＋ Свой ACP-агент» с `PreviewBadge` → SnackBar `comingInMilestone('M5')`.
  - Строка «Агент по умолчанию» в Общих: `SelectorChip` с агентами `canStartChats`; остальные агенты — неактивные пункты с `PreviewBadge`.

- [ ] **Step 1: Failing tests** `agents_settings_section_test.dart` (`MemoryAgentsRepository`; Claude `ready`, `account 'a@b.c'`, каталог с моделями `opus`/`sonnet`, режимами `default`/`acceptEdits`/`bypassPermissions`):
  - `'shows three agents with their states'`: видны «Claude Code», «Codex», «Gemini CLI», `a@b.c`, «не установлен»/`not installed`, два `PreviewBadge` (Codex, Gemini — в карточках).
  - `'logout and login'`: «Выйти» → `calls` содержит `logout:claude`; затем статус `needsLogin`, «Войти» → «Подписка Claude» → `login:claude:claude-ai-login`, строки вывода двойника видны в карточке.
  - `'default model is stored'`: меню модели → «Sonnet» → `settings.sessionDefaults['claude']!['model'] == 'sonnet'`.
  - `'mode menu has no bypass'`: в меню режима нет пункта `bypassPermissions`.
  - `'empty catalog explains itself'`: каталог пуст, `sessionDefaults` `{'claude': {'model': 'opus'}}` — меню показывает подсказку и «Сбросить»; «Сбросить» удаляет `model`.
  - `'preview actions say the milestone'`: «Установить» у Codex и «＋ Свой ACP-агент» показывают SnackBar с `M5`.
  - `'general offers only agents that can start chats'`: в меню «Агент по умолчанию» Claude активен, Codex/Gemini неактивны.
  - `'fits 900×600 and 1280×800 in en and ru, light and dark'`.
- [ ] **Step 2:** тесты FAIL. **Step 3:** реализовать, ARB, `build_runner`. **Step 4:** тесты PASS, `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Settings: Agents section and the default agent"`.

### Task 5: MCP-серверы: хранение (схема v6), встроенные, импорт `.mcp.json`

**Files:**
- Create: `lib/src/common/database/tables/mcp_servers_table.dart` (две таблицы), `lib/src/feature/mcp_servers/models/mcp_server.dart`, `lib/src/feature/mcp_servers/data/mcp_servers_repository.dart`, `lib/src/feature/mcp_servers/data/mcp_json.dart`
- Modify: `lib/src/common/database/database.dart` (`schemaVersion => 6`, `from5To6`), сгенерировать `drift_schemas/drift_schema_v6.json`, `database.steps.dart`, `test/generated_migrations/`; `dependencies.dart`, `initialize_dependencies.dart`, `test/support/test_app.dart`
- Test: `test/common/database/migration_test.dart` (+ `v5 → v6`), `test/feature/mcp_servers/mcp_json_test.dart`, `test/feature/mcp_servers/mcp_servers_repository_test.dart`

**Interfaces:**
- Produces:
  - Таблица `mcp_servers` (`McpServerRow`): `id` int autoincrement, `name` text unique, `transport` text (`stdio` | `http`), `config` text JSON (`{"command", "args", "env"}` или `{"url", "headers"}`), `enabled` bool (по умолчанию `true`), `createdAt` dateTime. Колонки `projectId` из спеки нет: «только в проекте» заменено выключением по проектам (ниже) — решение этапа, записать в спеку в Task 9.
  - Таблица `mcp_server_states` (`McpServerStateRow`): `id` autoincrement, `serverKey` text (`builtin:app`, `builtin:dart`, `user:<id>`), `projectId` int NOT NULL (FK `projects.id` ON DELETE CASCADE), `enabled` bool; уникальный ключ `(serverKey, projectId)`. Строка есть только там, где сервер выключен в проекте.
  - `enum McpTransport { stdio, http }`, `enum McpStatus { ready, needsAuth, unknown }`.
  - `McpServer` (freezed): `String id`, `String name`, `McpTransport transport`, `String? command`, `List<String> args`, `Map<String, String> env`, `String? url`, `Map<String, String> headers`, `bool builtin`, `bool enabled`, `Set<int> disabledIn`, `McpStatus status`, `int? toolCount`, `String? summary`, `bool isPreview`. Встроенные (всегда первые, `enabled: true`, `isPreview: true`, `status: ready`): `builtin:app` — `name 'flutter_code_agent'`, `stdio`, `summary 'skills, rules, run, screenshot'`, `toolCount 9`; `builtin:dart` — `name 'Dart MCP'`, `command 'dart'`, `args ['mcp-server']`, `summary 'hot reload, analysis, pub.dev'`, `toolCount 18`. Свои: `status: unknown`, `toolCount: null`, `isPreview: true`.
  - `McpJsonEntries parseMcpJson(String text)` → `({List<McpServerDraft> servers, List<(String name, String reason)> skipped})`; `McpServerDraft` (freezed): `name`, `transport`, `command`, `args`, `env`, `url`, `headers`. Формат: `{"mcpServers": {"<name>": {"command", "args"?, "env"?} | {"type": "http", "url", "headers"?}}}`; `url` без `type` — тоже `http`; `type: "sse"` → пропуск `'sse is not supported'`; ни `command`, ни `url` → пропуск `'no command or url'`; не JSON / нет `mcpServers` → `McpJsonException`. Причины пропуска — английские коды для диагностики, UI показывает число и имена.
  - `abstract interface class IMcpServersRepository`:
    - `Stream<List<McpServer>> watchServers()` — встроенные + свои по `createdAt`; обновляется при изменении обеих таблиц.
    - `Future<McpServer> add(McpServerDraft draft)` — имя `^[A-Za-z0-9_.-]{1,64}$`, не `flutter_code_agent`/`Dart MCP`/`dart`, уникально (без учёта регистра) → иначе `InvalidMcpServerException(reason)` (`invalidName`, `duplicateName`, `missingCommand`, `invalidUrl` — `http`/`https` с хостом).
    - `Future<void> remove(String id)` — встроенный → `ArgumentError`.
    - `Future<void> setEnabled(String id, {required bool enabled, int? projectId})` — `projectId == null`: только для своих (встроенный → `ArgumentError`), меняет `enabled`; с проектом: `false` — вставить строку состояния, `true` — удалить.
    - `Future<({List<String> added, List<(String name, String reason)> skipped})> importMcpJson(String path)` — читает файл, `parseMcpJson`, добавляет каждый через `add`; занятое имя → пропуск `'name is taken'`, ошибка `add` → пропуск с её причиной; ничего не перезаписывает.
  - `McpServersRepositoryImpl({required AppDatabase database})`; `Dependencies.mcpServersRepository`.
  - Доставка серверов агенту (`mcpServers` в `session/new`) — M3, сейчас не подключается.

- [ ] **Step 1: Failing migration test** `'v5 → v6 adds mcp tables and keeps skill states'`: в v5 вставить проект и строку `skill_states`, мигрировать до 6, строка на месте, `mcp_servers` и `mcp_server_states` пусты.
- [ ] **Step 2:** `mcp_json_test.dart`: stdio с `args`/`env`; `{"url": "https://mcp.figma.com/mcp"}` → `http`; `sse` и пустая запись — в `skipped` с причинами; `'[]'` и `'{}'` → `McpJsonException`.
- [ ] **Step 3:** `mcp_servers_repository_test.dart` (`NativeDatabase.memory()`):
  - `'built-ins come first'`: пустая БД → два встроенных в порядке `builtin:app`, `builtin:dart`.
  - `'add, disable in a project, remove'`: `add` stdio `figma-local` → в потоке; `setEnabled('user:1', enabled: false, projectId: p)` → `disabledIn == {p}`; `remove` → исчез, строки состояния удалены.
  - `'built-ins only switch per project'`: `setEnabled('builtin:dart', enabled: false)` → `ArgumentError`; с `projectId` → `disabledIn == {p}`; `remove('builtin:app')` → `ArgumentError`.
  - `'names are checked'`: `'Figma'` после `'figma'` → `duplicateName`; `'dart'` → `invalidName`; `'a b'` → `invalidName`; http `'ftp://x'` → `invalidUrl`.
  - `'import skips taken names and keeps existing ones'`: временный `.mcp.json` с `figma` (занято) и `linear` → `added == ['linear']`, `skipped` содержит `('figma', 'name is taken')`, конфиг старого `figma` не изменился.
  - `'deleting a project drops its states'`: удаление проекта → `disabledIn` пуст (каскад).
- [ ] **Step 4:** таблицы, v6, генерация схем; тесты FAIL → реализовать → PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "mcp_servers: storage (schema v6), built-ins and .mcp.json import"`.

### Task 6: Раздел «MCP-серверы»

**Files:**
- Create: `lib/src/feature/mcp_servers/controller/mcp_servers_controller.dart`, `lib/src/feature/mcp_servers/controller/mcp_server_actions_controller.dart`, `lib/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart`, `lib/src/feature/mcp_servers/widgets/mcp_settings_section.dart`, `lib/src/feature/mcp_servers/widgets/mcp_server_row.dart`, `lib/src/feature/mcp_servers/widgets/add_mcp_server_dialog.dart`
- Modify: `workspace_settings_page.dart` (раздел `mcp` в `McpServersConfigWidget`), ARB
- Test: `test/feature/mcp_servers/mcp_settings_section_test.dart`

**Interfaces:**
- Consumes: Task 5 (`IMcpServersRepository`, `McpServer`, `McpServerDraft`, `InvalidMcpServerException`), список проектов — `WorkspaceConfigInhWidget.of(context).projectsController`.
- Produces:
  - `McpServersController` (Sequential, `watch()`), `McpServerActionsController` (Droppable: `add(draft)`, `remove(id)`, `setEnabled(id, {enabled, projectId})`, `importMcpJson(path)`; состояние — последний итог/ошибка для SnackBar или диалога).
  - `McpServerRow({required McpServer server})` — по макету: точка статуса (`ready` — `colors.ok`, `needsAuth` — `colors.warn`, `unknown` — `colors.muted`), имя, тег «встроенный», строка `command args` или `url` моно + `summary` + «N инструментов» (русское множественное), `PreviewBadge` при `isPreview`; справа: у своих `Switch` (глобальный `enabled`), у всех кнопка-иконка «Проекты» (`Icons.folder_off_outlined`, tooltip «Выключить в проектах») → `AppMenu` с проектами и галочками (галочка = включён в проекте), у своих «Удалить» (`Icons.delete_outline`, с подтверждением). Строка `needsAuth` — кнопка «Войти» → SnackBar `comingInMilestone('M3')`.
  - Подзаголовок раздела (Task 2) дополнен строкой «Статус и инструменты появятся в M3; агенту серверы передаются с M3.».
  - Внизу: «＋ stdio (команда)», «＋ HTTP (URL)» → `AddMcpServerDialog(transport)`; «Импорт из .mcp.json» → `file_selector` `openFile(acceptedTypeGroups: [XTypeGroup(label: 'JSON', extensions: ['json'])])` → итог SnackBar «Добавлено: N. Пропущено: M (имена)».
  - `AddMcpServerDialog({required McpTransport transport})` — поля: имя; stdio — команда, аргументы (одна строка, разбиение по пробелам с кавычками `"…"`), переменные (`KEY=VALUE` по строкам); http — URL, заголовки (`Name: value` по строкам). Ошибки `InvalidMcpServerException` показываются под соответствующим полем, диалог не закрывается.

- [ ] **Step 1: Failing tests** `mcp_settings_section_test.dart` (настоящий `McpServersRepositoryImpl` на in-memory БД из `testDependencies`):
  - `'shows built-ins with tool counts'`: видны `flutter_code_agent`, `Dart MCP`, «9 инструментов»/`9 tools`, «18 …», `PreviewBadge`.
  - `'adds a stdio server'`: «＋ stdio» → имя `figma-local`, команда `npx`, аргументы `-y "@figma/mcp" --stdio` → сохранено с `args == ['-y', '@figma/mcp', '--stdio']`; строка видна.
  - `'duplicate name stays in the dialog'`: второй `figma-local` → текст ошибки под полем имени, диалог открыт.
  - `'built-in switches off per project only'`: у `Dart MCP` нет `Switch`; меню «Проекты» → снять галочку у проекта → `disabledIn` содержит его id.
  - `'remove asks first'`: «Удалить» → «Отмена» — сервер на месте; «Удалить» — исчез.
  - `'fits 900×600 and 1280×800 in en and ru, light and dark'` (с одним своим сервером с длинным URL — перенос, без переполнения).
- [ ] **Step 2:** FAIL. **Step 3:** реализовать, ARB. **Step 4:** PASS, `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Settings: MCP servers section"`.

### Task 7: Разрешения: правила «Всегда в этом проекте»

**Files:**
- Create: `lib/src/feature/permission_rules/data/permission_rules_repository.dart`, `lib/src/feature/permission_rules/controller/permission_rules_controller.dart`, `lib/src/feature/permission_rules/widgets/permission_rules_config_widget.dart`, `lib/src/feature/permission_rules/widgets/permissions_settings_section.dart`
- Modify: `dependencies.dart`, `initialize_dependencies.dart`, `test/support/test_app.dart`, `workspace_settings_page.dart`, ARB
- Create (двойник): `test/support/memory_permission_rules_repository.dart`
- Test: `test/feature/permission_rules/permission_rules_repository_test.dart`, `test/feature/permission_rules/permissions_settings_section_test.dart`

**Interfaces:**
- Produces:
  - Источник: «Всегда в этом проекте» адаптер Claude пишет в `<project>/.claude/settings.local.json` → `permissions.allow` (строки вида `Bash(npm test:*)`, `WebFetch(domain:pub.dev)`, `mcp__dart__hot_reload`). Общий `.claude/settings.json` проекта не показывается и не меняется.
  - `abstract interface class IPermissionRulesRepository`:
    - `Future<List<String>> rules(String projectRoot)` — нет файла / нет `permissions` / нет `allow` → `[]`; не-строки в `allow` пропускаются; не JSON или корень не объект → `PermissionRulesUnreadableException(path)`.
    - `Future<void> remove(String projectRoot, String rule)` — перечитать файл, удалить все равные `rule` из `permissions.allow`, остальное (другие ключи, `deny`, `ask`, порядок ключей) сохранить; записать `JsonEncoder.withIndent('  ')` + `'\n'` через временный файл и `rename`; файла нет или правила уже нет — ничего не делать.
  - `PermissionRulesRepositoryImpl()` (без зависимостей); `Dependencies.permissionRulesRepository`.
  - `PermissionRulesController` (Sequential): `load(List<Project> projects)`; состояние freezed `initial | inProgress | completed(Map<int, ProjectRules>)`, где `ProjectRules` (freezed) — `rules(List<String>)` | `unreadable(String path)`; `remove(Project project, String rule)` — затем перезагрузка этого проекта.
  - `PermissionsSettingsSection()` — загрузка при открытии раздела и кнопка «Обновить»; по карточке на проект с правилами (имя проекта, путь моно): строки правил моно + кнопка-иконка «Удалить» (tooltip «Удалить правило»); `unreadable` — строка ошибки «Не удалось прочитать …settings.local.json»; проекты без правил — одна общая строка внизу «Без сохранённых правил: N проектов»; нет проектов вовсе — `EmptyState`. Удаление без подтверждения (правило можно снова дать в чате).
  - `MemoryPermissionRulesRepository({Map<String, List<String>> rules, Set<String> unreadable})` — в `testDependencies`.

- [ ] **Step 1: Failing tests** `permission_rules_repository_test.dart` (временная папка):
  - `'reads allow rules'`: файл `{"permissions":{"allow":["Bash(npm test:*)", 3, "WebFetch(domain:pub.dev)"],"deny":["Bash(rm:*)"]},"env":{"A":"1"}}` → `['Bash(npm test:*)', 'WebFetch(domain:pub.dev)']`.
  - `'no file is empty'`; `'broken file is unreadable'` (`'{'` → `PermissionRulesUnreadableException`).
  - `'remove keeps everything else'`: после `remove(root, 'Bash(npm test:*)')` файл декодируется в `{"permissions":{"allow":[3,"WebFetch(domain:pub.dev)"],"deny":["Bash(rm:*)"]},"env":{"A":"1"}}`, оканчивается `'\n'`, во временной папке нет лишних файлов.
- [ ] **Step 2:** `permissions_settings_section_test.dart` (двойник; два проекта — с двумя правилами и без): видны правила и «Без сохранённых правил: 1 …»; «Удалить» у правила → двойник получил `remove`, правило исчезло; `unreadable` проект показывает строку ошибки; `'fits 900×600 and 1280×800 in en and ru, light and dark'`.
- [ ] **Step 3:** FAIL → реализовать, ARB, `build_runner` → PASS; `flutter analyze` — No issues.
- [ ] **Step 4: Commit** `git commit -m "Settings: Permissions section from the project's local Claude settings"`.

### Task 8: Flutter: SDK, fvm, doctor, новый проект, DevTools

**Files:**
- Create: `lib/src/feature/flutter_sdk/models/flutter_sdk.dart`, `lib/src/feature/flutter_sdk/data/flutter_sdk_repository.dart` (интерфейс), `lib/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart`, `lib/src/feature/flutter_sdk/controller/flutter_sdk_controller.dart`, `lib/src/feature/flutter_sdk/widgets/flutter_sdk_config_widget.dart`, `lib/src/feature/flutter_sdk/widgets/flutter_settings_section.dart`
- Modify: `dependencies.dart`, `initialize_dependencies.dart`, `test/support/test_app.dart`, `workspace_settings_page.dart`, ARB
- Test: `test/feature/flutter_sdk/fake_flutter_sdk_repository_test.dart`, `test/feature/flutter_sdk/flutter_settings_section_test.dart`

**Interfaces:**
- Consumes: Task 1 (`projectOrg`, `projectTemplate`, `devToolsTarget`, `AppSettings.orgPattern`), `WorkspaceConfigInhWidget.of(context).selectedProject` и `.createChat({int? projectId, String? draft})`.
- Produces:
  - `FlutterSdk` (freezed): `String? path`, `String? version`, `String? channel`, `String? fvmVersion`, `bool isPreview`. `enum DoctorStatus { ok, warning, error }`; `DoctorCheck` (freezed): `String title`, `DoctorStatus status`, `String? detail`.
  - `abstract interface class IFlutterSdkRepository { Future<FlutterSdk> sdkFor(String? projectPath); Future<List<DoctorCheck>> doctor(); }`.
  - `FakeFlutterSdkRepositoryImpl({required String? Function(String name) which, Duration step = const Duration(milliseconds: 300)})`: `path` — Real `which('flutter')`; `fvmVersion` — Real: `<projectPath>/.fvmrc` (JSON, ключ `flutter`), иначе `<projectPath>/.fvm/fvm_config.json` (ключ `flutterSdkVersion`), битый файл → `null`; `version '3.27.1'`, `channel 'stable'`, `isPreview: true`; `doctor()` после `step`: Flutter ✓ «Channel stable, 3.27.1», Android toolchain ⚠ «cmdline-tools component is missing», Xcode ✓, Chrome ✓, Connected device ✓ «2 available», Network resources ✓. В инициализации `which: shellEnvironment.which`.
  - `Dependencies.flutterSdkRepository`.
  - `FlutterSdkController` (Sequential): `load(String? projectPath)`, `runDoctor()`; состояние: `FlutterSdk? sdk`, `List<DoctorCheck>? checks`, `bool doctorRunning`, `Object? error`.
  - `FlutterSettingsSection()`:
    - карточка SDK: «Путь» (моно; `null` — «Flutter SDK не найден» + подсказка «Установите Flutter или добавьте его в PATH», спека §3.10), «Версия» `version · channel` + `PreviewBadge`, «Проект» (если выбран проект): `fvmVersion` → «fvm: 3.24.0», иначе «Системный SDK»;
    - карточка doctor: кнопка «Запустить flutter doctor» (`PreviewBadge`, M4); список проверок со значками статуса; у `warning`/`error` — «Исправить с агентом» → `createChat(projectId: selectedProject.id, draft: localization.doctorFixDraft(title, detail))` (черновик на языке интерфейса: «flutter doctor сообщает: {title} — {detail}. Помогите исправить.»); нет выбранного проекта — кнопка неактивна с tooltip «Откройте проект, чтобы начать чат»;
    - карточка «Новый проект»: «Org» — `TextField`, сохраняет при каждом валидном значении (`orgPattern`), неверное — `errorText` «Например, com.example», не сохраняется; «Шаблон» — `SegmentedControl` Моя архитектура / flutter create / Из git; сегмент `git` помечен `PreviewBadge` рядом с контролом, выбор показывает SnackBar `comingInMilestone('M4')` и значение не меняет;
    - карточка «DevTools»: `SegmentedControl` «В браузере» / «В приложении» (`app` — SnackBar `comingInMilestone('M2')`, не сохраняется).

- [ ] **Step 1: Failing tests** `fake_flutter_sdk_repository_test.dart` (временная папка): `.fvmrc` `{"flutter":"3.24.0"}` → `fvmVersion '3.24.0'`; только `.fvm/fvm_config.json` `{"flutterSdkVersion":"3.22.1"}` → `'3.22.1'`; битый `.fvmrc` → `null`; `which` → `null` → `path == null`; `doctor()` — 6 проверок, вторая `warning`.
- [ ] **Step 2:** `flutter_settings_section_test.dart` (`step: Duration.zero`, `which` → `'/opt/flutter/bin/flutter'`, выбран проект):
  - `'shows the sdk and the project fvm'`.
  - `'doctor fix starts a chat with a draft'`: «Запустить flutter doctor» → «Исправить с агентом» у Android toolchain → создан черновик чата проекта, текст содержит `cmdline-tools component is missing` (проверить так же, как `test/feature/workspace/workspace_new_chat_draft_test.dart`).
  - `'org is validated'`: ввод `Com.Example` → текст ошибки, `projectOrg` не изменился; `dev.avaz` → `projectOrg == 'dev.avaz'`.
  - `'git template and in-app DevTools are previews'`: SnackBar с `M4` / `M2`, значения не изменились.
  - `'missing sdk explains itself'`: `which` → `null` → «Flutter SDK не найден».
  - `'fits 900×600 and 1280×800 in en and ru, light and dark'`.
- [ ] **Step 3:** FAIL → реализовать, ARB, `build_runner` → PASS; `flutter analyze` — No issues.
- [ ] **Step 4: Commit** `git commit -m "Settings: Flutter section (SDK, fvm, doctor preview, new project defaults)"`.

### Task 9: Итог этапа: без заглушек, спека и отложенное

**Files:**
- Modify: `lib/src/feature/workspace/widgets/workspace_settings_page.dart` (`_milestones` и `SectionPlaceholder` для настроек удалены; `SectionPlaceholder` в `workspace_page_scaffold.dart` удалить, если больше не используется), `docs/superpowers/specs/2026-10-28-ui-system-design.md` (раздел «Решения этапа 6» после §3.8: каталог настроек агента в `app_settings` под ключом `agentOptions`; `mcp_servers` без `projectId` + `mcp_server_states`; разрешения читаются из `.claude/settings.local.json`; доставка MCP агенту — M3; новые поля `AppSettings`), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` (раздел «Stage 6 follow-ups»: что отложено и почему), `docs/PLAN.md` — только если там есть пункты, которые этот этап закрывает (сверить с кодом)
- Test: весь набор

- [ ] **Step 1:** `grep -rn "SectionPlaceholder\|_milestones" lib` — использований для настроек нет.
- [ ] **Step 2:** обновить спеку и follow-ups.
- [ ] **Step 3:** `flutter analyze` — No issues; `flutter test` — All tests passed; `flutter build macos --debug` — успешно.
- [ ] **Step 4: Commit** `git commit -m "Stage 6 wrap-up: spec notes and follow-ups"`.
