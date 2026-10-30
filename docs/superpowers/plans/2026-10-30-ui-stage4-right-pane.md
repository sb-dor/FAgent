# UI Stage 4 (right pane) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этап 4 спеки: правая панель с настоящими вкладками «Изменения» и «План», вкладка «Run» и выбор виджета на фейковых данных, кнопки запуска в шапке, ⌘R/⇧⌘R, «→ Отправить агенту» и секция «Из запуска» в меню `@` — как в макете `docs/design/3-run.html`.

**Architecture:** Чат публикует наружу маленький `ChatHandle` (вид чата и действия над полем ввода) через колбэк `ChatConfigWidget`; рабочая область хранит его в `WorkspaceDataController`, и правая панель строится из него, не трогая контроллеры чата. «Изменения» и «План» — чистые функции над `ChatItem`. Запуск — новая фича `app_run` с интерфейсами репозиториев и `Fake*Impl` (детерминированный сценарий, бейдж «Preview»), один запуск на проект; контроллеры живут в `WorkspaceConfigWidget`.

**Tech Stack:** Flutter (macOS), control, freezed, drift, gen-l10n en/ru.

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` §3.2, §3.6, §4 (таблица `app_run`, `widget_picker`, `changes_pane`, `plan_pane`; правила фейковых репозиториев), макет `docs/design/3-run.html`. Отложенное: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`.

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями `CLAUDE.md`: репозитории `abstract interface` + `Impl({required this._x})`; виджеты не трогают репозитории и `AgentHub`; Sequential для load/watch, Droppable для мутаций; Stream-методы репозиториев гарантированно закрываются.
- Фейки (спека §4): файл `data/fake_<name>_repository.dart`, класс `Fake<Name>RepositoryImpl implements I<Name>Repository`; выбор реализации в `initialize_dependencies.dart`, в `Dependencies` хранится интерфейс; данные детерминированные, задержки как у настоящих операций, без случайности; флаг `isPreview` → `PreviewBadge`; действия, которые ничего не делают, честно говорят `comingInMilestone('M2')` (SnackBar), а не притворяются.
- Запуск принадлежит проекту: все чаты проекта видят один запуск.
- Цвета только `context.colors`, радиусы `AppRadius` (6/10/14), шаг 4 px, моно — `AppText.mono`; Material Icons; новых пакетов нет.
- Правая панель 340–560 px; ничего не переполняется при окне 900×600 с открытыми панелями.
- Все строки — `intl_en.arb` и `intl_ru.arb` (русское множественное — только one/few/many/other, без `=1`); у кнопок-иконок `tooltip`.
- `flutter analyze` чистый; коммиты заканчиваются `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Проект — подпапка git-репозитория: пути из `turn_files` относительны корню git, а не проекту — «Изменения» показывают правильный путь и находят diff этого файла (Task 2).
2. Логи запуска растут бесконечно (часы работы, тысячи строк) — память ограничена, список не тормозит, фильтр и поиск работают (Task 4, Task 5).
3. Смена проекта во время сборки/работы: панель показывает запуск выбранного проекта, события старого не протекают в новый (Task 4).
4. «→ Отправить агенту», когда чат не выбран или агент сейчас работает: ничего не отправляется молча — текст ошибки попадает в черновик поля ввода, а без чата — понятное сообщение (Task 6).
5. Hot reload после хода агента: срабатывает один раз на переход «работает → простаивает», а не на каждую перерисовку, и только при работающем запуске (Task 6).

---

### Task 1: Канал «чат → рабочая область»

**Files:**
- Create: `lib/src/feature/chat/models/chat_handle.dart`
- Modify: `lib/src/feature/chat/widgets/chat_config_widget.dart` (+ параметр `onHandle`), `lib/src/feature/chat/widgets/chat_screen.dart`, `chat_feed.dart`, `chat_item_view.dart`, `tool_call_card.dart` (клик по строке правки), `lib/src/feature/workspace/widgets/controllers/workspace_data_controller.dart`, `workspace_chat_area.dart`
- Test: `test/feature/workspace/workspace_chat_handle_test.dart`

**Interfaces:**
- Produces:
  - `@immutable final class ChatHandle { const ChatHandle({required int sessionId, required ChatView view, required void Function(String text) insertDraft}); }` — `insertDraft` вставляет текст в поле ввода чата (в конец, с пустой строкой-разделителем, если там уже что-то есть) и ставит фокус в поле.
  - `ChatConfigWidget({…, ValueChanged<ChatHandle>? onHandle, ValueChanged<String>? onOpenChange})` — `onHandle` вызывается при каждом новом `ChatView` (после кадра, не во время build); `onOpenChange(path)` — клик по строке правки в ленте (абсолютный путь файла из diff).
  - `WorkspaceDataController`: `ValueListenable<ChatHandle?> get chatHandle`, `void publishChatHandle(ChatHandle handle)` (игнорирует handle не выбранного `sessionId`), сброс в `null` при смене чата; `String? get selectedChangePath`, `void selectChange(String? path)`.
  - `WorkspaceConfigWidgetState.openChange(String path)` — открывает правую панель (если скрыта — `AppSettingsController.update(rightPaneVisible: true)`), вкладку `changes` и `selectChange(path)`; это колбэк `onOpenChange` для `ChatConfigWidget` из `workspace_chat_area.dart`.
- [ ] **Step 1: Write the failing tests**:
  - `'the selected chat publishes its view'`: открыть чат → `dataController.chatHandle.value!.sessionId == chat`; переключить чат → handle нового.
  - `'a handle of another chat is ignored'`.
  - `'insertDraft puts text into the composer and focuses it'` (поле было пустым → текст; было `hi` → `hi\n\n<текст>`).
  - `'clicking an edit row opens its file in Changes'`: в ленте правка `/p/lib/a.dart` → tap → `paneTab == changes`, `selectedChangePath == '/p/lib/a.dart'`, панель видима.
- [ ] **Step 2: Run** `flutter test test/feature/workspace/workspace_chat_handle_test.dart` — FAIL.
- [ ] **Step 3: Implement** модель, колбэки, хранение в контроллере, клик по строке правки (весь заголовок строки — кнопка «Открыть в Изменениях», раскрытие тела — отдельная стрелка).
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Chat publishes a handle to the workspace"`.

### Task 2: Вкладка «Изменения» с настоящими данными

**Files:**
- Modify: `lib/src/feature/turn_files/data/git_turn_files_observer.dart` (в payload `turn_files` добавить `'root'` — абсолютный корень git), `lib/src/feature/chat/models/chat_item.dart` (`TurnFilesItem.root: String?`), `chat_transcript.dart`
- Create: `lib/src/feature/changes_pane/models/changed_file.dart`, `lib/src/feature/changes_pane/widgets/changes_tab.dart`, `changes_file_list.dart`
- Modify: `lib/src/feature/workspace/widgets/workspace_right_pane.dart` (вкладка `changes` и её счётчик)
- Modify: arb (`changesEmpty`, `changedByCommand`, `openFile`, `changesCount(count)` если нужен)
- Test: `test/feature/changes_pane/changed_file_test.dart`, `test/feature/changes_pane/changes_tab_test.dart`, `test/feature/turn_files/git_turn_files_observer_test.dart`

**Interfaces:**
- Consumes: `ChatHandle.view.items`, `selectedChangePath` (Task 1); `DiffLinesCache`, `DiffView(lines:)`, `LineDiff` (есть).
- Produces:
  - `@immutable final class ChangedFile { const ChangedFile({required String path, required String status, required List<ToolDiffContent> diffs}); }` — `path` абсолютный; `status`: `added|modified|deleted|renamed|clean` (как в `TurnFilesCard`) или `edited` (есть только diff агента); `diffs` — все diff-ы этого файла по порядку.
  - `List<ChangedFile> collectChanges(List<ChatItem> items, {required String projectRoot})` — объединяет `TurnFilesItem` (путь = `root ?? projectRoot` + относительный путь; последний статус побеждает) и diff-ы `ToolCallItem`; файлы со статусом `clean` в итоге убираются; порядок — по последнему изменению, новые сверху.
  - Вкладка: список файлов (имя моно, папка относительно проекта — `muted`, статус, `+N −M` по сумме diff-ов), по клику — diff-ы файла (`DiffView` с кешированными строками); файл без diff-ов — текст `changedByCommand` и кнопка `openFile` (через новый `IProjectsRepository.openPath(String path)` → `Process.run('open', [path])`, контроллер — простой метод как `reveal`); пусто — `EmptyState(changesEmpty)`. Счётчик вкладки — число файлов.
- [ ] **Step 1: Write the failing tests**:
  - `'turn files carry the git root'` (наблюдатель: в payload есть `root`).
  - `'changes merge turn files and agent diffs'`: turn_files `lib/a.dart` modified + правка агента `/p/lib/a.dart` → один файл, статус `modified`, 1 diff.
  - `'a project inside a git repo resolves paths against the git root'`: root `/repo`, project `/repo/app`, путь `app/lib/a.dart` → `/repo/app/lib/a.dart` (Review Focus 1).
  - `'a file reverted later is not listed'` (`clean` последним).
  - `'old journals without root fall back to the project root'`.
  - Виджет: `'picking a file shows its diff'`; `'a file changed by a command offers to open it'`; `'the tab badge counts files'`; 900×600 без переполнения.
- [ ] **Step 2: Run** `flutter test test/feature/changes_pane test/feature/turn_files` — FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Changes tab: files changed in the chat with their diffs"`.

### Task 3: Вкладка «План»

**Files:**
- Create: `lib/src/feature/plan_pane/widgets/plan_tab.dart`
- Modify: `workspace_right_pane.dart`, arb (`planEmpty`, `planProgress(done, total)`)
- Test: `test/feature/plan_pane/plan_tab_test.dart`

**Interfaces:**
- Consumes: `ChatHandle.view.items` (Task 1), `PlanItem{entries: List<PlanEntry{content, status}>}`.
- Produces: `PlanTab({required List<ChatItem> items})` — последний `PlanItem` чата: строка прогресса `planProgress(done, total)`, пункты с иконкой по статусу (`completed` — `ok`, `in_progress` — `accent` + индикатор, иначе — `muted`), длинный текст переносится; без плана — `EmptyState(planEmpty)`.
- [ ] **Step 1: Write the failing tests**: `'the latest plan is shown with progress'` (два PlanItem — показан второй, `2/3`); `'without a plan the tab explains it'`; `'long entries wrap without overflow at 340 px'`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Plan tab"`.

### Task 4: Фича `app_run`: модели, фейковые репозитории, контроллеры

**Files:**
- Create: `lib/src/feature/app_run/models/{device.dart, run_state.dart, log_entry.dart, run_error.dart, picked_widget.dart}`, `data/{devices_repository.dart, app_run_repository.dart, widget_picker_repository.dart}` (интерфейсы), `data/{fake_devices_repository.dart, fake_app_run_repository.dart, fake_widget_picker_repository.dart}`, `controller/{devices_controller.dart, run_controller.dart, run_actions_controller.dart}`
- Modify: `lib/src/feature/initialization/models/dependencies.dart`, `initialize_dependencies.dart` (фейки), `lib/src/feature/app_settings/models/app_settings.dart` (`reloadAfterTurn: bool`, по умолчанию `false`)
- Test: `test/feature/app_run/fake_app_run_test.dart`, `test/feature/app_run/run_controller_test.dart`

**Interfaces:**
- Produces (модели — freezed или `@immutable` с `==`):
  - `Device{id, name, platform: DevicePlatform{ios, android, macos, web, windows, linux}, kind: DeviceKind{running, available}, detail}`.
  - `sealed RunState`: `RunIdle`, `RunBuilding{progress: double (0–1), label}`, `RunRunning{device: Device, startedAt: DateTime, lastReload: Duration?}`, `RunFailed{error: RunError}`, `RunStopped`.
  - `LogEntry{seq: int, time: DateTime, level: LogLevel{info, warning, error}, text, error: RunError?, sentToAgent: bool}`.
  - `RunError{title, message, location: String? ('booking_card.dart:42:12'), file: String?, line: int?, stack: String?}`; `String RunError.forAgent()` — текст для агента (заголовок, сообщение, место, первые 20 строк стека в блоке кода).
  - `PickedWidget{name, file, line, ancestors: List<String>}`.
  - `IDevicesRepository{ bool get isPreview; Stream<List<Device>> watchDevices(); }`.
  - `IAppRunRepository{ bool get isPreview; Stream<RunState> watchRun(int projectId); Stream<LogEntry> logs(int projectId); Future<void> start(int projectId, {required String deviceId, required BuildMode mode, required String target}); Future<void> stop(int projectId); Future<Duration> hotReload(int projectId); Future<void> hotRestart(int projectId); }`, `enum BuildMode { debug, profile, release }`.
  - `IWidgetPickerRepository{ bool get isPreview; Future<PickedWidget?> pick(int projectId); }`.
  - Фейк запуска: сценарий на проект — `start` → `RunBuilding` с шагами (0.2 «Resolving dependencies», 0.6 «Xcode build», 1.0) → `RunRunning`; логи: запуск, `flutter: Booking loaded 12 rooms`; первый `hotReload` → лог `Reloaded 3 of 812 libraries in 180ms.` и через шаг — ошибка `A RenderFlex overflowed by 24 pixels on the right.` с `location: 'booking_card.dart:42:12'`, `file: 'lib/src/feature/booking/widgets/booking_card.dart'`, `line: 42`; `stop` → `RunStopped`. Конструктор `FakeAppRunRepositoryImpl({Duration step = const Duration(milliseconds: 600)})` — тесты передают маленький шаг.
  - Фейк устройств: запущенные `iPhone 16 Pro` (ios, sim), `macOS`, `Chrome`; доступные `Pixel 9 API 35`, `iPad Air (M3)`.
  - Фейк выбора виджета: через шаг возвращает `PickedWidget(name: 'BookingCard', file: 'lib/src/feature/booking/widgets/booking_card.dart', line: 42, ancestors: ['Row','Padding','BookingCard','ListView','BookingScreen'])`.
  - `DevicesController` (Sequential watch) → `DevicesState.completed(devices)`.
  - `RunController({required IAppRunRepository repository})` (Sequential): `void watch(int projectId)` — подписка на `watchRun` и `logs` выбранного проекта; при смене проекта старые подписки отменяются, логи очищаются; состояние `RunViewState{projectId, run: RunState, logs: List<LogEntry> (последние 2000), errorCount, selectedDeviceId, mode, target}`; `void select({String? deviceId, BuildMode? mode})`; `void markSent(int seq)`.
  - `RunActionsController` (Droppable): `start(projectId, …)`, `stop`, `hotReload`, `hotRestart`, `pickWidget` → `RunActions$CompletedState(picked: PickedWidget?)`.
- [ ] **Step 1: Write the failing tests** (с `step: Duration(milliseconds: 1)`):
  - `'start builds, then runs, then reload reports an overflow'` — последовательность состояний и логов, ошибка с `line == 42`.
  - `'stop ends the run'`.
  - `'logs keep only the newest 2000 entries'` (фейк, выдающий 2500 строк → в состоянии 2000, `errorCount` считает только оставшиеся) — Review Focus 2.
  - `'switching projects drops the old run and logs'` — запуск в проекте 1, `watch(2)`, событие проекта 1 после этого не попадает в состояние (Review Focus 3).
  - `'the agent text of an error has the place and a stack excerpt'` (`forAgent`).
  - `'reloadAfterTurn round-trips and defaults to false'`.
- [ ] **Step 2: Run** `flutter test test/feature/app_run test/feature/app_settings` — FAIL.
- [ ] **Step 3: Implement** модели, интерфейсы, фейки, контроллеры, регистрацию фейков в `Dependencies`.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "app_run: models, fake run, devices and widget picker"`.

### Task 5: Вкладка «Run»

**Files:**
- Create: `lib/src/feature/app_run/widgets/{run_tab.dart, run_header.dart, run_logs.dart, run_error_block.dart, picked_widget_card.dart}`
- Modify: `workspace_right_pane.dart` (вкладка `run`, бейдж ошибок `errors: errorCount`), `workspace_config_widget.dart` (владеет `DevicesController`, `RunController`, `RunActionsController`; `RunController.watch` при смене выбранного проекта), arb (`runStart`, `runStop`, `hotReload`, `hotRestart`, `pickWidget`, `screenshot`, `devTools`, `runArguments`, `runningFor(duration)`, `lastReload(ms)`, `reloadAfterTurn`, `logsAll`, `logsErrors`, `logsSent`, `logsSearch`, `logsClear`, `sendToAgent`, `openFile`, `details`, `devicesRunning`, `devicesAvailable`, `pickWidgetHint`, `addToMessage`, `runIdle`)
- Test: `test/feature/app_run/run_tab_test.dart`

**Interfaces:**
- Consumes: Task 4 контроллеры и модели; `SelectorChip`, `showAppMenu`, `SegmentedControl`, `PreviewBadge`, `StatusPill` (есть).
- Produces: `RunTab` по макету 3-run.html:
  - шапка: чип устройства (меню: «Запущены» / «Можно запустить», внизу `runArguments` — `enabled: false` с `comingInMilestone('M2')`), чип режима (debug/profile/release), моно-чип `main.dart`; `PreviewBadge`, если `isPreview`;
  - кнопки с tooltip: ▶ `runStart` / ■ `runStop`, ⚡ `hotReload`, ⟳ `hotRestart`, 🎯 `pickWidget`, 📷 `screenshot` и ↗ `devTools` — обе SnackBar `comingInMilestone('M2')`;
  - строка состояния: зелёная точка + `runningFor` + `lastReload` / прогресс сборки (`LinearProgressIndicator` + label) / `runIdle`;
  - переключатель `reloadAfterTurn` (пишет в `AppSettings`);
  - логи: `SegmentedControl` Все / Ошибки N / Агенту, поиск (без учёта регистра), очистка; ленивый список (`ListView.builder`), моно; ошибка — блок `RunErrorBlock` (`dangerSoft`) с кнопками `sendToAgent`, `openFile`, `details` (раскрывает стек);
  - после 🎯 — `PickedWidgetCard` (имя, `file:line` моно, цепочка предков) с `addToMessage` и `openFile`.
  - Пустое состояние без проекта — `EmptyState`.
- Колбэки наружу: `onSendError(RunError)`, `onAddWidget(PickedWidget)`, `onOpenFile(String path, int? line)` (реализация — Task 6).
- [ ] **Step 1: Write the failing tests** (фейк с маленьким шагом):
  - `'run builds then shows the running state'` (прогресс → `runningFor`).
  - `'reload produces an error block and a badge'` (бейдж вкладки `1`).
  - `'the errors filter and search narrow the logs'`.
  - `'devices menu shows running and available devices; arguments say M2'`.
  - `'screenshot and DevTools say they come in M2'`.
  - `'picking a widget shows its card'`.
  - `'2000 log lines scroll without jank and without overflow at 900×600'` (ленивый список: построено меньше 100 строк) — Review Focus 2.
- [ ] **Step 2: Run** `flutter test test/feature/app_run` — FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Run tab on the fake run"`.

### Task 6: Шапка, горячие клавиши, связь запуска с чатом

**Files:**
- Modify: `lib/src/feature/workspace/widgets/workspace_title_bar.dart` (чип устройства, ▶/■, ⚡), `workspace_shortcuts.dart` (⌘R → hot reload, ⇧⌘R → hot restart, только при работающем запуске), `workspace_config_widget.dart` (`sendErrorToAgent`, `addWidgetToMessage`, `openRunFile`, перезагрузка после хода), `lib/src/feature/prompt_sending/widgets/prompt_composer.dart` + `mention_suggestions.dart` (секция «Из запуска»), `lib/src/feature/chat/widgets/chat_config_widget.dart` (передать в композер источники «из запуска»)
- Modify: arb (`fromRun`, `selectedWidget`, `lastError`, `noChatForError`)
- Test: `test/feature/app_run/run_chat_link_test.dart`, `test/feature/prompt_sending/prompt_composer_test.dart`

**Interfaces:**
- Consumes: `ChatHandle.insertDraft` и `view.status` (Task 1), Task 4–5.
- Produces:
  - `sendErrorToAgent(RunError e)`: есть выбранный чат → `insertDraft(e.forAgent())` + `RunController.markSent(seq)` (фильтр «Агенту»); нет чата → SnackBar `noChatForError`. Никогда не отправляет сам (Review Focus 4).
  - `addWidgetToMessage(PickedWidget w)` → `insertDraft('@widget ${w.name} (${w.file}:${w.line})')`.
  - `openRunFile(path, line)` → `IProjectsRepository.openPath` (Task 2) с путём относительно проекта.
  - Перезагрузка после хода: слушатель `chatHandle`; на переходе статуса `running → idle` выбранного чата, если `settings.reloadAfterTurn` и запуск в `RunRunning` — один `hotReload` (Review Focus 5).
  - Меню `@`: новая секция «Из запуска» (`fromRun`) над файлами, когда есть данные: `selectedWidget` (последний `PickedWidget`) и `lastError` (последняя ошибка); выбор вставляет тот же текст, что `addWidgetToMessage` / краткое `@error <title> (<location>)`; скриншот — пункт недоступен с `comingInMilestone('M2')`. Композер получает `runContext: ({PickedWidget? widget, RunError? error})?` через `ChatConfigWidget`.
  - Шапка: справа перед переключателем панели — чип устройства (то же меню, что во вкладке), ▶/■ и ⚡ с tooltip; без проекта — скрыты.
- [ ] **Step 1: Write the failing tests**:
  - `'send to agent puts the error into the composer draft'` (текст с `booking_card.dart:42`, лог помечен «Агенту»).
  - `'without a chat, send to agent explains why'`.
  - `'reload after a turn fires once per finished turn'` — статус чата running → idle → (перерисовки) → idle: `hotReload` вызван 1 раз; при выключенном переключателе — 0; при остановленном запуске — 0.
  - `'⌘R reloads and ⇧⌘R restarts the running app'`; при неработающем — ничего.
  - `'the @ menu offers the picked widget and the last error'`; `'screenshot in @ says M2'`.
  - `'the title bar run button starts the selected device'`.
- [ ] **Step 2: Run** `flutter test test/feature/app_run test/feature/prompt_sending test/feature/workspace` — FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Run controls in the title bar, shortcuts, send to agent and @ from run"`.

### Task 7: Проверка этапа

**Files:**
- Modify: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` (убрать устаревшую строку про подсказки ↵/Esc на не последних карточках — уже исправлено; добавить «Stage 4 follow-ups» из ревью этапа)
- Modify: спека §3.6 — отметить, что «Агенту» в логах — это ошибки, отправленные в черновик, и что DevTools/скриншот/аргументы запуска ждут M2

- [ ] **Step 1: Run** `flutter pub get` — без ICU-предупреждений; `flutter analyze` — No issues; `flutter test` — All tests passed; `flutter build macos --debug` — `✓ Built`.
- [ ] **Step 2:** запуск `flutter run -d macos` — только если пользователь не держит свой экземпляр; иначе прямо написать в отчёте, что проверка запуска пропущена и визуальной проверки не было.
- [ ] **Step 3: Commit** `git commit -m "Stage 4 wrap-up: follow-ups and spec notes"`.
