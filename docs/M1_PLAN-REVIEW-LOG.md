# Plan Review Log: M1 — чат с Claude Code через ACP
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

## Round 1 — Codex

План пока не готов к реализации: есть несколько блокеров, нарушающих собственные критерии M1.

1. **[Блокер] Заявленный auth-flow несовместим с typed API SDK.** `ClientCapabilities` не содержит `auth`, поэтому `auth.terminal: true` нельзя отправить обычным `AcpClientApp.v1`; кроме того, stable `AuthMethod` моделирует только `type: agent` и теряет terminal-specific `args` ([SDK models.dart](/Users/avaz/.pub-cache/hosted/pub.dev/dart_acp_sdk-0.1.1/lib/src/protocol/v1/generated/stable/models.dart:1567), [auth union](/Users/avaz/.pub-cache/hosted/pub.dev/dart_acp_sdk-0.1.1/lib/src/protocol/v1/generated/stable/models.dart:720)).  
   Исправление: объявлять поддерживаемый адаптером `_meta["terminal-auth"]`, читать команду из raw `_meta` либо реализовать custom initialize codec и покрыть initialize реальным контрактным тестом 0.96.0.

2. **[Блокер] «Сырой журнал ACP» фактически не обеспечен.** Stable `SessionUpdateCodec` бросает `FormatException` на неизвестных discriminator, а повторная сериализация typed-модели уже не является исходным JSON ([SDK models.dart](/Users/avaz/.pub-cache/hosted/pub.dev/dart_acp_sdk-0.1.1/lib/src/protocol/v1/generated/stable/models.dart:11155)).  
   Исправление: перехватывать и сохранять raw JSON-RPC params middleware-слоем до typed decode, а неизвестные варианты отображать как диагностические события.

3. **[Блокер] Безопасный permission mode не гарантирован.** Подтверждение `bypassPermissions` предусмотрено только при переключении UI, но новая/загруженная сессия может унаследовать `acceptEdits`, `auto` или `bypassPermissions` из `.claude/settings.json` либо transcript ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:93)).  
   Исправление: до разблокировки composer принудительно установить `default/manual` или запросить и сохранить явное согласие на найденный небезопасный режим.

4. **[Блокер] Проектные hooks обходят `request_permission`.** Сам план признаёт исполнение `.claude/` hooks, но ограничивается предупреждением; SessionStart/другие hooks способны выполнить код до карточки разрешения ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:143)).  
   Исправление: добавить trust-gate на канонический путь до создания ACP-сессии и по умолчанию отключать project/local settings и hooks для недоверенных папок.

5. **[Блокер] Обещание «каждая правка показана как diff» невыполнимо через `tool_call`.** Bash, hooks, formatter, subagent, бинарные и слишком большие файлы могут измениться без diff-события; это также противоречит roadmap с git-страховкой ([M1 plan](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:129), [roadmap](/Users/avaz/StudioProjects/flutter_agent/docs/PLAN.md:163)).  
   Исправление: делать неповреждающий baseline рабочего дерева перед ходом и вычислять фактический post-turn diff/список бинарных изменений либо ослабить критерий готовности.

6. **[Высокий] `npx -y` исполняет скачанный код без закреплённой целостности.** Точная версия фиксирует имя релиза, но не доверенный SHA-512 и не устраняет runtime-install/lifecycle scripts.  
   Исправление: ставить адаптер в app-managed cache по lock manifest с закреплённым integrity hash или поставлять проверенный артефакт вместе с приложением.

7. **[Высокий] Не определена модель конкурентности AgentHub.** Два фоновых чата могут одновременно вызвать lazy start, `ensureLive`, restart или prompt; результат — два процесса, двойной load и маршруты старого поколения соединения.  
   Исправление: добавить global single-flight для start/stop, generation token и отдельную последовательную очередь операций на каждую appSessionId.

8. **[Высокий] Состояния сессии недостаточны.** Нет `starting`, `loading`, `cancelling`, `authenticating`, `disposed`, поэтому prompt/config/close могут пересечься с load или cancel.  
   Исправление: задать явный state machine с допустимыми переходами и сериализовать prompt/load/config/cancel в рамках сессии.

9. **[Высокий] Ключ PermissionBroker не уникален для запроса.** Один tool call может запросить разрешение повторно, а несколько ожидающих запросов делают `sessionId + toolCallId` коллизионным; cancel и поздний клик также гоняются за одним Completer.  
   Исправление: ключевать по JSON-RPC requestId, хранить множество запросов на toolCall и завершать/удалять каждый idempotently ровно один раз.

10. **[Высокий] Permission request не имеет места в журнале.** Схема перечисляет только `permission_response`, поэтому `PermissionItem` нельзя восстановить после перезапуска ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:63)).  
    Исправление: сохранять отдельные `permission_request` и `permission_resolution` с requestId/toolCallId, а незавершённые запросы после restart помечать `stale/cancelled`.

11. **[Высокий] Автоповтор последнего prompt после login может повторить побочные эффекты.** `authRequired` не доказывает, что до ошибки не было tool calls или файловых правок ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:95)).  
    Исправление: после проверки auth восстановить сессию и показывать явную кнопку «Повторить», никогда не отправляя prompt автоматически.

12. **[Высокий] `seq` не защищён от гонок.** Обычный индекс `(sessionId, seq)` допускает дубликаты, а события prompt, permission и stream будут записываться конкурентно.  
    Исправление: сделать composite `UNIQUE(sessionId, seq)` и выдавать seq одним сериализованным writer/transaction на сессию.

13. **[Высокий] Live stream и drift watch будут дублировать события.** Живое событие сначала добавляется в UI, затем та же запись приходит из watch, но план не задаёт identity или reconciliation ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:77)).  
    Исправление: присваивать стабильный eventId до публикации и дедуплицировать overlay либо публиковать в UI только через единый durable event store.

14. **[Высокий] Склейка чанков по одному `kind` неверна.** ACP прямо определяет `messageId` как границу сообщений ([SDK models.dart](/Users/avaz/.pub-cache/hosted/pub.dev/dart_acp_sdk-0.1.1/lib/src/protocol/v1/generated/stable/models.dart:2378)); соседние ответы одного kind могут быть ошибочно объединены.  
    Исправление: группировать по `(sessionId, messageId, kind, parent/subagent)` и принудительно flush на completion, cancel, error, process exit и dispose.

15. **[Высокий] Миграция 1→2 недоопределена.** Добавление non-null `isFlutter` в существующую таблицу требует default/backfill, а SQLite cascade не работает без `PRAGMA foreign_keys=ON` ([текущая БД](/Users/avaz/StudioProjects/flutter_agent/lib/src/common/database/database.dart:11)).  
    Исправление: добавить `isFlutter` с безопасным default, выполнить app-level backfill, включить foreign keys в `beforeOpen` и сохранить schema snapshots для migration test.

16. **[Высокий] Recovery через строку «не найдена» опасен.** Transient/auth/protocol error может быть ошибочно принят за потерю контекста; также не указано атомарное сохранение нового `acpSessionId`.  
    Исправление: классифицировать ошибку по code/data конкретного адаптера и создавать новую сессию только при доказанном not-found, атомарно обновляя ID и system event.

17. **[Высокий] Завершение процессов не гарантирует уборку дерева.** Cancel — notification без подтверждения, немедленное закрытие stdin может её обогнать, а SIGKILL только `npx` способен оставить Claude и login-процессы; при отсутствии running-сессий dispose вообще не указан.  
    Исправление: всегда закрывать Hub при выходе, ждать отправки cancel и prompt grace period, запускать через process-tree supervisor и завершать всю группу, включая auth subprocess.

18. **[Средний] Ошибка первого запуска может никогда не появиться.** Есть timeout shell-env, но нет timeout/cancel для `npx`, initialize, new/load и проверки Node ≥22.  
    Исправление: выполнить preflight `node --version`/`npx --version` и добавить отдельные cancellable deadlines для spawn, initialize и session setup.

19. **[Средний] Логи создают утечку и риск заполнения диска.** Кольцо ограничивает только stderr в памяти, тогда как `CLAUDE_AGENT_LOGS` создаёт append-only `agent.log`; строки stderr и показанный auth output тоже не ограничены и не редактируются.  
    Исправление: ввести ротацию по размеру, предел длины строки/события, ANSI sanitization и редактирование токенов, auth URL и секретных env values.

20. **[Средний] `configOptions` ошибочно сведены к dropdown.** ACP v1 SDK поддерживает как `select`, так и `boolean`, а неизвестные будущие варианты сейчас не имеют fallback.  
    Исправление: рендерить tagged union `select|boolean|unknown`, объявить соответствующие client capabilities и обновлять состояние только полным ответом агента.

21. **[Средний] Архитектурная граница и закрытие stream не зафиксированы.** Фичи напрямую упоминают AgentHub, хотя правила требуют repository-обёртки процессов/drift, а у LiveSession event stream нет явного close path ([CLAUDE.md](/Users/avaz/StudioProjects/flutter_agent/CLAUDE.md:17), [stream rule](/Users/avaz/StudioProjects/flutter_agent/docs/AI_INSTRUCTIONS.md:530)).  
    Исправление: определить repository interfaces между controllers и AgentHub/DB и закрывать все session controllers/subscriptions в `LiveSession.dispose` и `AgentHub.dispose`.

22. **[Средний] `@file` не задаёт безопасную семантику пути.** `git ls-files` без NUL ломается на переводах строк, fallback может пройти по symlink наружу, а ручной `file://` некорректно кодирует пробелы и Unicode.  
    Исправление: использовать `git ls-files -z`, `Uri.file`, `followLinks:false` и realpath-проверку, что каждый ресурс остаётся внутри доверенного project root.

23. **[Средний] Набор тестов не проверяет основные аварийные пути.** In-memory fake не ловит двойной spawn, зависший child, malformed/unknown NDJSON, stderr backpressure, process-tree cleanup и несовместимый terminal auth.  
    Исправление: добавить реальный child-process fixture и тесты гонок start/load/cancel, нескольких permissions, dedupe live/DB, flush-on-crash и initialize contract адаптера 0.96.0.

VERDICT: REVISE
### Claude's response

Принято (план переписан, ревизия 2):
- 1 — `_meta: {"terminal-auth": true}` (проверено: в `ClientCapabilities` SDK нет `auth`, но есть `meta`); команды входа берутся из `AgentDefinition`; контрактный тест `initialize`.
- 2 — `RawMessageTap` перед typed-декодером, журнал пишет сырой JSON, неизвестные варианты → `UnknownItem` (проверено: `SessionUpdateCodec` разбирает жёстким switch).
- 3 — частично: `bypassPermissions` из настроек блокирует поле ввода до подтверждения; `acceptEdits`/`auto` — плашка. Принудительно ставить `default` не стали: это осознанный выбор пользователя в его настройках Claude.
- 4 — частично: диалог доверия к папке до первой ACP-сессии (`projects.trustedAt`). Отключать project-настройки для недоверенных папок не стали — без доверия сессия просто не создаётся.
- 5 — критерий ослаблен до «diff для правок инструментами агента» + фича `turn_files` (git status до/после хода).
- 7, 8 — single-flight старта, поколения процесса, очередь операций на сессию, таблица состояний.
- 9, 10 — ключ разрешения = JSON-RPC id; события `permission_request`/`permission_resolution`, незавершённые → `stale`.
- 11 — повтор промпта после входа только по кнопке.
- 12 — `UNIQUE(sessionId, seq)`, единственный писатель на сессию.
- 13 — `SessionEventStore` как единственный путь к UI, drift watch для ленты не используется.
- 14 — склейка чанков по `(messageId, kind)`, flush на конце хода/отмене/ошибке/падении/dispose.
- 15 — default + backfill для `isFlutter`, `PRAGMA foreign_keys = ON`, снимки схем + `SchemaVerifier`.
- 16 — любая ошибка load → карточка с выбором; новая сессия только по кнопке, атомарно.
- 17 — группа процессов + kill группы, ожидание cancel, dispose всегда при выходе, процесс входа тоже.
- 18 — preflight node/npx, дедлайны spawn/initialize/new/load.
- 19 — частично: `CLAUDE_AGENT_LOGS` не задаётся по умолчанию, лимит длины строки, вырезание ANSI.
- 20 — config options как `select|boolean|unknown`.
- 21 — репозитории между фичами и `AgentHub`/drift; закрытие потоков в dispose.
- 22 — `git ls-files -z`, `followLinks: false`, проверка realpath, `Uri.file`.
- 23 — тесты с реальным дочерним процессом и гонками; контрактный тест адаптера по тегу.

Отклонено:
- 6 — собственная установка адаптера с integrity hash: пользователь явно выбрал `npx` с закреплённой версией; доверие то же, что у установки Claude Code через npm. Вернёмся к M7 (релиз).
- 19 (редактирование токенов) — вывод входа и stderr показываются только локально пользователю, никуда не уходят.
- 4 (отключение project settings) — заменено диалогом доверия.

## Round 2 — Codex

Ревизия 2 существенно лучше. Достаточно закрыты пункты 1, 4, 7, 9–12, 15, 18, 20–23. Риски из пункта 6 и редактирование локальных логов явно приняты как trade-off. Однако остаются материальные проблемы.

1. **[Блокер, прежний #5] `turn_files` всё ещё не находит все изменённые файлы.** Разница двух `git status` пропустит файл, который был ` M` или `??` до хода и остался в том же состоянии после изменения содержимого ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:137)).  
   Исправление: сохранять baseline-хэши путей, уже присутствующих в исходном status, и сравнивать их содержимое после хода; добавить тесты для pre-dirty, untracked и rename.

2. **[Блокер, новое] Очередь операций несовместима с немедленным cancel.** Если `prompt` занимает последовательную очередь до ответа конца хода, поставленный «в начало» `cancel` всё равно не сможет начаться ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:65)).  
   Исправление: вынести cancel в отдельный control lane и не удерживать session mutex во время ожидания ответа на уже отправленный prompt.

3. **[Блокер, прежний #8] State machine содержит неверные переходы.** После `authRequired` во время `loading`/`creating` переход `needsAuth → idle` объявляет живой сессию, которая ещё не была загружена или создана; одновременно обещан restart по следующему prompt, но перехода `error → starting` нет ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:72)).  
   Исправление: хранить прерванную setup-операцию, после входа повторять `load/new`, добавить `error → starting`, а `idle` устанавливать только после успешного setup.

4. **[Высокий, новое] Аутентификация ошибочно моделируется как операция сессии.** Credentials и auth-процесс принадлежат общему процессу агента, поэтому две сессии могут параллельно запустить login и получить несогласованные состояния ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:64)).  
   Исправление: сделать auth agent-scoped single-flight и после него переоценивать все `needsAuth`-сессии.

5. **[Высокий, прежний #17] Process supervision остаётся открытым исследованием, а не реализуемым решением.** У `detachedWithStdio` отсутствует `exitCode`, и план не определяет гарантированный вызов `killpg`; это противоречит надёжному обнаружению завершения и уборке дерева ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:43), [Dart API](/Users/avaz/development/flutter/bin/cache/dart-sdk/lib/io/process.dart:264)).  
   Исправление: до реализации выбрать и описать конкретный supervisor, сохраняющий stdio и exit status и предоставляющий проверенный `setpgid/killpg`, включая orphan-тест на macOS.

6. **[Высокий, прежние #2/#14] «Сырой журнал» конфликтует со склейкой чанков.** Нельзя одновременно хранить каждый исходный JSON-RPC frame без изменений и объединять несколько frames в одну строку `payload` ([raw transport](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:38), [schema](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:103)).  
   Исправление: сохранять каждый raw frame отдельным immutable event, а склейку выполнять только в `ChatTranscript.fold`, либо завести отдельную materialized-таблицу.

7. **[Высокий, прежний #3] Критерий безопасности всё ещё противоречит выбранной модели.** Цель обещает карточку для каждого опасного действия, но `acceptEdits`/`auto` разрешают действия без карточки, а hooks запускаются после общего trust-диалога ([цель](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:9), [режимы](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:113)).  
   Исправление: либо требовать явного согласия на все немануальные режимы, либо честно заменить критерий на «после доверия папке и согласно выбранному permission mode».

8. **[Высокий, новое] Не определены lifetime и уникальность `SessionEventStore`.** «Одна на открытую сессию» не гарантирует singleton при двух подписчиках и допускает dispose после переключения UI, хотя агент продолжает работать в фоне ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:92)).  
   Исправление: владеть store в app-scoped repository/AgentHub map по `sessionId`; UI только подписывается, а store живёт до завершения live-сессии или shutdown.

9. **[Высокий, новое] Нет crash-consistency между журналом и ACP.** Не указано, что пользовательский prompt успешно сохранён до отправки; падение между send и async insert оставит агенту контекст, которого нет в локальной истории.  
   Исправление: коммитить prompt до `session/prompt`, публиковать события после успешной записи и явно обрабатывать отказ drift без отправки запроса.

10. **[Средний, прежний #16] Recovery после `session/load` фактически предлагает только потерю контекста.** Для transient/auth ошибки есть кнопка новой сессии, но нет безопасного Retry, а состояние `error` не имеет выхода ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:83)).  
    Исправление: добавить «Повторить load» с сохранением старого `acpSessionId`, а destructive reset оставить отдельным подтверждённым действием.

11. **[Средний, прежний #19] Ограничение stderr может быть фиктивным, а auth output остаётся неограниченным.** Обычный `LineSplitter` накопит сколь угодно длинную строку до перевода строки; stdout/stderr login-процесса также не имеют кольца или byte limit ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:45), [auth](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:145)).  
    Исправление: использовать byte-bounded incremental splitter и ограниченные кольцевые буферы для всех subprocess streams.

VERDICT: REVISE
### Claude's response

Принято (ревизия 3):
- 1 — `turn_files`: статус + `git hash-object` для путей, грязных до хода; изменённым считается и путь со сменившимся хэшем; тесты на pre-dirty/untracked/rename/delete/binary.
- 2 — две полосы операций: mutex только на отправку запроса, ожидание конца хода вне mutex; cancel и ответы на разрешения — управляющая полоса без очереди.
- 3 — машина состояний: `setupFailed` с запомненной операцией, `idle` только после успешной настройки, `error → starting`, после входа повторяется прерванная настройка.
- 4 — `AgentAuth` single-flight на агента, после входа переоцениваются все сессии в `needsAuth`.
- 5 — конкретный способ: `Process.start` в обычном режиме (есть `exitCode`) + `ProcessTreeKiller` через рекурсивный `pgrep -P`, двойной обход, orphan-тест с фейковым агентом, порождающим потомка.
- 6 — каждый сырой frame — отдельная строка; склейка только в `ChatTranscript.fold`.
- 7 — цель переписана честно: разрешения «в соответствии с выбранным режимом» после доверия папке.
- 8 — `SessionEventStore` — один на `sessionId`, владелец — app-scoped репозиторий; жизненный цикл описан.
- 10 — `setupFailed` → «Повторить» с тем же `acpSessionId`; сброс контекста — отдельное подтверждённое действие.
- 11 — `BoundedLineSplitter` (обрезка при чтении) и кольцо для всех дочерних процессов, включая вход.

Частично:
- 9 — `prompt`, `permission_resolution`, `system` пишутся в drift до отправки/публикации, отказ drift → запрос не уходит. Вывод агента публикуется сразу и пишется пачками раз в 200 мс: публикация-после-записи для каждого чанка добавила бы задержку потоку. Потеря ≤ 200 мс вывода при аварии самого приложения допустима — контекст агента восстановит `session/load`.

## Round 3 — Codex

Revision 3 закрыла замечания 2–4, 6–8 и 10 второго раунда. Замечание 9 получило приемлемый явно описанный trade-off. Пункты 1, 5 и 11 закрыты не полностью, плюс появились новые гонки.

1. **[Блокер, регрессия из #11] Ограничение stdout ломает ACP transport.** По плану stdout агента проходит через `BoundedLineSplitter` с лимитом 2000 символов, но именно stdout содержит исходные NDJSON frames, которые должны без изменений попасть в `RawMessageTap`; нормальный tool result легко длиннее 2000 символов ([transport](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:40), [лимит](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:51)).  
   Исправление: передавать stdout агента без изменений в `RawMessageTap`/`ndJsonStream`, ограничивая только agent stderr и stdout/stderr auth-процесса.

2. **[Блокер, прежний #1] Baseline `turn_files` всё ещё гоняется с агентом.** В risks сказано, что хэширование выполняется в фоне и «не блокирует ход»; агент может изменить файл раньше вычисления исходного хэша, и изменение исчезнет из результата ([алгоритм](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:163), [risk](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:225)). Кроме того, `git hash-object --stdin-paths` принимает LF-разделённые имена и не имеет `-z`, поэтому ломается на допустимом имени с переводом строки.  
   Исправление: вычислять хэши точных путей из NUL-status средствами Dart или безопасными argv и обязательно завершать baseline до отправки `session/prompt`, блокируя только ход, но не UI.

3. **[Высокий, развитие #9] Пакетная запись нарушает причинный порядок событий.** Raw `permission_request` получает `seq` в памяти и ждёт batch до 200 мс, затем `permission_resolution` с большим `seq` коммитится немедленно; при падении сохранится ответ без запроса ([порядок](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:114)). Это также противоречит утверждению, что `seq` выдаётся внутри транзакции ([schema](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:128)).  
   Исправление: использовать одну ordered write queue и перед durable-событием сначала коммитить все предыдущие `seq`; `permission_request` должен быть durable до разблокировки ответа пользователя.

4. **[Высокий, прежний #5] `pgrep -P` не является надёжным process supervisor.** После закрытия stdin корневой процесс может завершиться, потомки переподчинятся `launchd`, и повторный обход уже их не найдёт; между snapshot и signal возможен также PID reuse с убийством чужого процесса ([остановка](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:45), [признанный риск](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:220)). Один orphan-тест эту структурную гонку не устраняет.  
   Исправление: запускать адаптер через небольшой macOS supervisor/process-group helper с проверенным `setpgid`/`killpg`, stdio и exit status.

5. **[Высокий, новое] Пользовательский Stop может зависнуть навсегда.** Переход `cancelling → idle` зависит только от ответа `prompt`; для игнорирующего cancel или зависшего агента нет deadline либо следующего действия ([state machine](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:91)).  
   Исправление: после cancel-timeout показывать «Принудительно остановить агента», предупреждать о затронутых фоновых чатах и завершать общий процесс с переводом его сессий в `error`.

6. **[Средний, новое] Инварианты state machine защищены только `assert`.** Assertions отключены в release-сборке, поэтому переходы вне таблицы не будут надёжно отклоняться ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:81)).  
   Исправление: проверять переходы runtime guard с `StateError`/controlled session error, оставив `assert` лишь дополнительной диагностикой.

7. **[Средний, новое] Close guard не видит часть работающих процессов.** Диалог учитывает только `running/awaitingPermission/cancelling`, но молча оборвёт `starting`, `loading`, `creating` и активный `AgentAuth` ([app_close](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:178)).  
   Исправление: считать все non-terminal состояния и `AgentAuth.isRunning`, а `dispose` выполнять только после подтверждённого закрытия.

VERDICT: REVISE
### Claude's response

Принято (ревизия 4):
- 1 — регрессия признана: stdout агента идёт без изменений в `RawMessageTap`/`ndJsonStream`; `BoundedLineSplitter` только для stderr агента и вывода процесса входа.
- 2 — снимок «до» для `turn_files` завершается до отправки `session/prompt` (ход ждёт, UI нет); хэши — SHA-256 в Dart по путям из NUL-вывода, без `git hash-object --stdin-paths`; тест на имя с переводом строки.
- 3 — одна упорядоченная очередь записи на сессию; durable-событие сначала сбрасывает всё до себя в той же транзакции; кнопки разрешения активны только после записи `permission_request`.
- 5 — `cancelling` без ответа 15 с → кнопка «Принудительно остановить агента» с предупреждением о фоновых чатах.
- 6 — проверка переходов в рантайме (`StateError` + системное событие), `assert` только в debug.
- 7 — диалог закрытия учитывает все нетерминальные состояния и `AgentAuth.isRunning`; `dispose` после подтверждения.

Частично / отклонено:
- 4 — нативный supervisor с `setpgid`/`killpg` в M1 не делаем. Основной путь остановки — штатный выход адаптера по EOF stdin (он сам закрывает сессии). Запасной путь усилен: снимок дерева снимается до закрытия stdin, пока корень жив (потомки, переподчинённые `launchd`, остаются в снимке), сигналы — только PID с совпавшим временем старта (защита от переиспользования PID). Остаточный риск — процесс, родившийся после снимка; если orphan-тест или ручная проверка его покажут, helper станет отдельной задачей. Нативный код в Xcode-проекте ради теоретической гонки на редком пути — непропорциональная цена для M1.

## Round 4 — Codex

Revision 4 корректно закрыла замечания 1–3 и 5–7 третьего раунда. Обоснование частичного отклонения пункта 4 устраняет PID reuse для уже найденных процессов, но не основную дыру snapshot-подхода.

1. **[Высокий, прежний #4] Snapshot не видит потомков, daemonized до его снятия.** Запущенный агентом `dev-server &` может переподчиниться `launchd` ещё во время хода; `pgrep -P` при закрытии его уже не найдёт. Кроме того, заявлен штатный выход по EOF, но последовательность отправляет SIGTERM сразу после закрытия stdin, без отдельного EOF grace period ([cleanup](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:47), [shutdown](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:67)).  
   Исправление: использовать process-group helper либо сделать тест с заранее reparented-потомком обязательным implementation gate; после EOF сначала ждать `exitCode`, и только затем запускать fallback.

2. **[Высокий, новое] Ошибка записи `permission_request` оставит агента ждать бесконечно.** Это входящий JSON-RPC request, поэтому формулировка «запрос не отправляется» неприменима: агент его уже отправил и ожидает response ([durable queue](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:127)).  
   Исправление: при отказе drift отвечать на request `cancelled` либо JSON-RPC internal error ровно один раз, завершать pending broker entry и переводить ход в контролируемую ошибку.

3. **[Высокий, новое] `RawMessageTap` всё ещё может стать неограниченным буфером.** Он расположен до `ndJsonStream` и должен сам найти границу строки, тогда как план объявляет frames «сколь угодно длинными»; SDK на самом деле ограничивает NDJSON строку 16 MiB ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:41), [SDK limit](/Users/avaz/.pub-cache/hosted/pub.dev/dart_acp_sdk-0.1.1/lib/src/transport/ndjson_stream.dart:28)).  
   Исправление: помещать tap после bounded NDJSON framing, но до typed decode, либо применять к tap тот же `maximumLineBytes` и завершать connection диагностической ошибкой при превышении.

4. **[Средний, новое] SHA-256 baseline не определён для symlink и специальных файлов.** Обычное чтение Dart последует по symlink — возможно наружу проекта — а FIFO может навсегда заблокировать подготовку хода; изменение самого symlink также можно пропустить ([turn_files](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:176)).  
   Исправление: использовать `lstat/followLinks:false`: хэшировать содержимое только regular files, для symlink — текст target, а для directory/FIFO/device/deleted — типизированный sentinel без открытия.

5. **[Средний, новое] Правило выдачи `seq` описано противоречиво.** Очередь выдаёт `seq` при постановке события, но схема всё ещё утверждает, что он выдаётся внутри поздней batch-транзакции ([queue](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:123), [schema](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:141)).  
   Исправление: зафиксировать выдачу `seq` в синхронной критической секции enqueue, а транзакцию использовать только для строго упорядоченной вставки и durable barriers.

VERDICT: REVISE
### Claude's response

Принято (ревизия 5):
- 1 — после закрытия stdin ждём `exitCode` до 5 с (штатный выход по EOF), только потом SIGTERM/SIGKILL. Тест с фоновым процессом, переподчинённым `launchd` во время хода, — обязательный gate этапа 2; его провал включает нативный helper с `setpgid`/`killpg` в M1 (выбран предложенный вариант «implementation gate»).
- 2 — отказ записи входящего `permission_request` → агенту ровно один раз `cancelled`, брокер очищен, ход → контролируемая ошибка с системным событием.
- 3 — `RawMessageTap` стоит после нарезки `ndJsonStream` (лимит 16 МБ SDK, превышение закрывает соединение с диагностикой) и до typed-декодера; своего буфера нет.
- 4 — отпечатки по `lstat` без перехода по ссылкам: regular file — SHA-256, symlink — текст цели, каталог/FIFO/устройство/удалённый — метка без открытия; тесты на symlink наружу и FIFO.
- 5 — `seq` выдаётся синхронно при постановке в очередь; транзакции только упорядоченно вставляют и служат барьерами.

## Round 5 — Codex

Revision 5 закрыла все пять замечаний round 4:

- Process cleanup теперь имеет EOF grace period и обязательный early gate; провал автоматически включает process-group helper в M1 ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:50)).
- Ошибка сохранения входящего permission request обрабатывается fail-closed без зависшего агента ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:134)).
- `RawMessageTap` расположен после ограниченного NDJSON framing и не имеет собственного буфера ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:41)).
- `turn_files` корректно различает regular files, symlinks и специальные объекты без следования наружу проекта ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:187)).
- Выдача и сохранение `seq` теперь описаны непротиворечиво ([план](/Users/avaz/StudioProjects/flutter_agent/docs/M1_PLAN.md:130)).

Новых материальных блокеров не нашёл. Две неблокирующие детали реализации:

- После `ndJsonStream` сохраняется семантически исходный JSON-объект, но не исходное текстовое представление с пробелами и порядком ключей; термин «сырой JSON» не должен подразумевать byte-for-byte audit log.
- Если drift недоступен, системную ошибку о несохранённом permission request придётся показать через transient UI error channel, поскольку durable `system` event в ту же неисправную БД записать невозможно.

План достаточно конкретен, проверяем и безопасен для начала реализации.

VERDICT: APPROVED
### Claude's response

Обе неблокирующие заметки внесены в план: уточнено, что «сырой» = семантически исходный JSON-объект (не побайтовая копия), и что ошибка записи `permission_request` показывается через временный канал ошибок UI.

## Resolution

APPROVED в раунде 5 из 5. План ждёт подписи пользователя; код не писался.
