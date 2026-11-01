# M3: Flutter-знания для агента

Веха M3 из `docs/PLAN.md`. Готово, когда: в чистом проекте агент без подсказок делает фичу по
архитектуре из `docs/AI_INSTRUCTIONS.md` и перед добавлением пакета проверяет его версию.

## Цель и рамки

Агент в чате получает правила, скиллы и инструменты приложения сам, без копирования текста
пользователем. Вместе с M3 закрываются отложенные «до M3» пункты UI-спеки
(`2026-10-28-ui-system-design.md` §3.7, §3.8, §4): свои MCP-серверы уходят агенту и показывают
настоящий статус, скиллы всех источников доступны агенту, меню F выбирает скиллы на чат, runtime-ошибки
берутся из VM service.

Вне рамок: выбор виджета (M6), другие агенты (M5: у Codex/Gemini свои механизмы правил; stdio-мост к
серверу приложения — там же, если агенту не хватит HTTP), git-источники скиллов, DevTools в окне.

## Установленные факты (проверены перед спекой)

- Адаптер Claude `@agentclientprotocol/claude-agent-acp@0.96.0` отвечает на `initialize`
  `mcpCapabilities: {http: true, sse: true}`; stdio поддерживается всегда.
- Claude Code обрезает `instructions` MCP-сервера до 2048 символов — правила туда не помещаются.
- `session/new` и `session/load` принимают `_meta.systemPrompt.append` (дописывается к системному
  промпту `claude_code`) и `_meta.claudeCode.options` — среди ключей `allowedTools` и `skills`
  (`string[]`: показывать модели только эти нативные скиллы). Изменение этих ключей при
  `session/load` пересоздаёт процесс сессии в адаптере — то есть они фиксируются на старт сессии.
- `dart mcp-server` (Dart 3.13) не принимает адрес DTD: агент подключается своим инструментом `dtd`
  (`connect` + `uri`). Флаги: `--flutter-sdk`, `--dart-sdk`, `--disable <tools>`.
- `mcp_dart` 2.4.3 (pub.dev, 2026-10-14, 160 баллов) — сервер Streamable HTTP
  (`StreamableMcpServer`: `host`, `port`, `path`, `authenticator(HttpRequest)`, фабрика сервера на
  MCP-сессию), защита от DNS rebinding, клиент. `dart_mcp` (labs.dart.dev) — только stdio-канал.
- `vm_service` уже в `pubspec.lock` (транзитивно); последняя версия 15.4.0.

## 1. Знания (`assets/knowledge/`)

`docs/AI_INSTRUCTIONS.md` остаётся первоисточником; его содержание вручную разносится по встроенным
правилам и скиллам и заменяет нынешний тонкий набор. Текст платформенно-нейтральный: мобильные и
веб-части (`screenSizeMaybeWhen`, `widgets/mobile/`, навигация) сохраняются; переопределения этого
репозитория (только десктоп, нет `ApiClient`, нет аутентификации) и разделы «AI Identity», «Token
Economy» не переносятся.

**Правила** (всегда включены, уходят в системный промпт; вместе ≤ 8 КБ):

| Файл `rules/` | Содержание |
|---|---|
| `architecture.md` | раскладка `lib/src/common` + `lib/src/feature/<f>/{models,data,controller,widgets}`, имена файлов, нет datasource-слоя |
| `controllers.md` | `StateController` + freezed-состояния, Sequential/Droppable, одна забота на контроллер, контроллеры не импортируют друг друга |
| `repositories.md` | `abstract interface` + `Impl`, сервисы через конструктор, краткие правила Stream-методов |
| `dependencies.md` | `Dependencies` и scope, config-виджеты создают и освобождают контроллеры, доступ через inherited widgets |
| `widgets.md` | `ListenableBuilder`, современный синтаксис конструкторов, когда `screenSizeMaybeWhen` |
| `localization.md`, `package-freshness.md`, `generated-files.md` | нынешние правила, уточнённые |

**Скиллы** (полный текст, агент грузит по надобности):

| Папка `skills/` | Содержание |
|---|---|
| `feature-architecture` | раздел «Feature Conventions» целиком, пример, шаблоны в `templates/` |
| `repository-streams` | «Stream-Returning Methods» целиком |
| `paginated-controller` | правила, шаблон, геттеры состояния, вызов `paginate` из виджета |
| `controller-patterns` | SRP, несколько контроллеров в фиче |
| `dependency-injection` | глобальный и фичевый DI, scope, интерфейсы |
| `drift-migration`, `widget-test`, `pub-freshness` | нынешние |

**Порядок и приоритет.** Текст правил собирается: встроенные → «Мои» → проектные → `AGENTS.md` проекта,
с первой строкой «Later rules override earlier ones». В этом репозитории `CLAUDE.md` (Claude читает его
сам) по-прежнему побеждает. `AGENTS.md` пропускается, если `CLAUDE.md` проекта содержит строку
`@AGENTS.md`. `AGENTS.md` показывается в «Скиллы и правила → Правила» как проектное правило только для
чтения (источник «Проект», без переключателя по проекту — выключается удалением или правкой файла).

## 2. Сервер приложения и контекст сессии

### Сервер (`lib/src/common/app_mcp/`)

- Шаг инициализации `AppMcpServer`: `mcp_dart` `StreamableMcpServer` на `127.0.0.1`, порт 0
  (случайный), путь `/mcp`, проверка `Host` (DNS rebinding) включена. Имя сервера для агента —
  `flutter_code_agent`.
- Токены: на каждую ACP-сессию чата — случайные 32 байта (`Random.secure`, base64url), передаются в
  `Authorization: Bearer …` (`HttpHeader` ACP). Реестр `token → (chatId, projectId)` живёт в памяти;
  токен отзывается при закрытии/удалении чата и при выходе. Запрос без действительного токена — 401.
  Токены не пишутся в логи.
- Не удалось запустить сервер — приложение работает, сессии стартуют без него, уведомление хаба
  «Flutter tools are unavailable» (en/ru через arb).
- Выход (⌘Q): `AppCloseRepositoryImpl.shutdown` закрывает сервер после агентов, до базы.
- Имена `flutter_code_agent` и `dart` зарезервированы: свой сервер с таким именем не добавляется
  (`McpServerProblem.reservedName`).

### Инструменты

Текст ошибок в результатах — английский (`isError: true`).

| Инструмент | Что делает |
|---|---|
| `list_skills` | скиллы, включённые для этого чата, которые подаёт приложение: имя, описание, источник |
| `load_skill(name)` | `SKILL.md` и список файлов скилла; выключенный для чата — ошибка «off for this chat» |
| `read_skill_file(name, path)` | файл скилла; путь вне папки скилла (`..`, абсолютный, симлинк наружу) — отказ |
| `app_status` | устройство, режим, состояние запуска, URI VM service / DTD / DevTools |
| `app_logs(lines = 200, errorsOnly = false)` | последние строки лога вкладки Run (≤ 1000) |
| `runtime_errors` | структурированные ошибки текущего запуска (§3) |
| `hot_reload`, `hot_restart` | через `IAppRunRepository` — видны во вкладке Run; ошибка, если нет запуска или не debug |
| `screenshot` | PNG как image-контент плюс путь файла (тот же `screenshot()` M2) |

`instructions` сервера (< 2048 символов, тест проверяет): при задаче, похожей на скилл, —
`list_skills`/`load_skill`; адрес DTD — из `app_status`, затем `dtd connect` Dart MCP.

### Контекст сессии

`ISessionContextRepository.forSession({chatId, projectId}) → Future<SessionContext>`,
`SessionContext {List<McpServer> servers, Map<String, Object?> meta}`. `AgentHub` получает его через
конструктор и использует в `_create` и `_load` вместо `const <McpServer>[]`.

Серверы:
1. Сервер приложения — `McpServerMcpServerHttp` с токеном чата.
2. Dart MCP — stdio: `<SDK>/bin/dart mcp-server --flutter-sdk <SDK> --disable launch_app,stop_app`.
   SDK — тот же поиск, что в M2 (`flutterExecutableFor`, с fvm). `launch_app`/`stop_app` выключены,
   чтобы все запуски принадлежали вкладке Run; hot reload Dart MCP работает на нашем запуске через DTD.
   Нет SDK — сервера нет, в настройках статус «SDK not found».
3. Свои серверы, включённые для проекта (глобально и `mcp_server_states`); `env` stdio-серверов
   дополняется `PATH` из `shell_env`.

Встроенный сервер, выключенный в проекте, в список не попадает (без сервера приложения пропадают и его
скиллы из промпта).

`meta` (только для агента Claude; флаг в `AgentDefinition`):
- `systemPrompt.append` — правила (порядок из §1), затем список скиллов приложения «name — description»;
- `claudeCode.options.allowedTools` — `['mcp__flutter_code_agent']`: инструменты приложения не
  спрашивают разрешения. Dart MCP и свои серверы спрашивают как обычно. Если адаптер не применит ключ
  (проверяет интеграционный тест), запасной путь — `PermissionBroker` сам отвечает «allow once» на
  запросы инструментов `mcp__flutter_code_agent__*`;
- `claudeCode.options.skills` — имена проектных скиллов (`.claude/skills`), включённых для проекта и
  чата: Claude читает их сам, ключ прячет выключенные.

Когда применяется: список серверов, правила и `skills` фиксируются на старте сессии — изменения доходят
до новых и заново открытых чатов (экраны «Скиллы и правила» и «MCP-серверы» пишут это под списком).
Скиллы приложения и выбор на чат действуют сразу через `list_skills`/`load_skill`.

### Статус своих серверов

`McpProbe` (клиент `mcp_dart`): `initialize` + `tools/list`, затем закрыть. Результат:
`connected(toolCount)` / `failed(message)` / `needsAuth` (HTTP 401). stdio — в своей группе процессов
(`GroupedProcess`), таймаут 10 с, группа убивается целиком. Проба — при открытии «Настройки → MCP» и
после добавления/включения сервера; результат в памяти. Встроенные: сервер приложения — «Running on
127.0.0.1:<port> · N tools» или ошибка запуска; Dart MCP — та же проба.

## 3. Интерфейс и runtime-ошибки

### Скиллы всех источников

- «Попробовать в чате» и `/имя` для встроенных и «Моих» скиллов: поле ввода отправляет текст после
  команды и `SKILL.md` как embedded resource (`skill://<name>/SKILL.md`, `text/markdown`). Проектные
  скиллы — как сейчас (Claude знает их сам).
- `/имя` в списке команд — для всех включённых скиллов чата.

### Меню F (скиллы на чат)

- Меню «Скиллы» в поле ввода: включённые для проекта скиллы с флажком на чат. Снятый флажок — скилл
  выключен только в этом чате.
- Хранение — drift `chat_skill_states` (`sessionId`, `skillId`, `enabled`; строка есть только при
  отличии от проекта), схема v8.
- Скиллы приложения применяются сразу; проектные — с новой/заново открытой сессией (подпись в меню).

### Runtime-ошибки из VM service

- `AppRunRepositoryImpl` после `app.debugPort` подключается к VM service (`vm_service`), включает
  `ext.flutter.inspector.structuredErrors` и слушает `Extension`-события `Flutter.Error`.
- Событие → `RunError` (заголовок из `description`, текст `renderedErrorText`, файл и строка из
  `creationLocation`/первого кадра проекта) — тот же «Отправить агенту», та же карточка.
- Пока VM service подключён, блоки Flutter-ошибок из текста вывода не дублируются: парсер сохраняет
  ошибки компиляции, сборки и unhandled exceptions. Нет подключения (release, сбой) — работает
  нынешний разбор текста.
- Соединение закрывается со стопом запуска и в `dispose`.

## Ошибки и края

- Скилл удалён между `list_skills` и `load_skill` — ошибка «Skill not found: <name>».
- Два чата одного проекта — разные токены; инструменты запуска действуют на запуск проекта.
- Сессия, открытая до старта приложения, видит запуск: `app_status` читает текущее состояние.
- Свой stdio-сервер не запускается у агента — это видит агент; статус в настройках показывает пробу.

## Тестирование

- Знания: frontmatter каждого файла; правила вместе ≤ 8 КБ; во встроенных нет переопределений этого
  репо (`Desktop only`, «нет ApiClient»); шаблоны `templates/*.dart` проходят `dart analyze` в
  фикстуре.
- Сервер: 401 без токена и с отозванным; путь вне скилла — отказ; каждый инструмент на
  `ScriptedAppRunRepository` и скриптованных скиллах; `instructions` < 2048.
- Контекст сессии: порядок правил, пропуск `AGENTS.md` при `@AGENTS.md`, список серверов по
  переключателям проекта, `allowedTools` и `skills` в `meta`, `AgentHub` передаёт контекст в
  `session/new` и `session/load`.
- `McpProbe`: connected / failed / needsAuth / таймаут убивает группу.
- VM service: скриптованные события `Flutter.Error` → `RunError`; без подключения — разбор текста.
- Opt-in интеграция (`FLUTTER_AGENT_TEST=1`, тег `agent`): настоящий адаптер + сервер приложения,
  агент вызывает `list_skills` без запроса разрешения.
