# UI Stage 7 (New project) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этап 7 спеки: мастер «Новый Flutter-проект» — диалог 560 px из меню сайдбара «＋ Проект ▾» с настоящей формой (проверка имени как в `flutter create`, org из настроек, папка, платформы, шаблон, git, «открыть чат») и прогрессом создания на фейковом репозитории до M4 (шаги `flutter create` → `git init` → шаг агента → `flutter analyze` → коммит); диалог можно свернуть, создание продолжается — как в макете `docs/design/6-new-project.html`.

**Architecture:** Новая фича `lib/src/feature/project_creation/` (`models`, `data`, `controller`, `widgets`). Репозиторий `IProjectCreationRepository` проверяет цель (Real: имя и существование папки) и создаёт (Fake до M4: детерминированные шаги, на диск ничего не пишется). Контроллер создания живёт на уровне окна в `WorkspaceConfigWidget`, поэтому закрытый диалог не останавливает создание, а сайдбар показывает чип прогресса.

**Tech Stack:** Flutter (macOS), control, freezed, gen-l10n en/ru, `file_selector` (уже есть). Новых пакетов и таблиц нет.

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` §3.1 (меню «＋ Проект»), §3.9, §3.10 (Flutter SDK не найден), §4 (`project_creation`, модели `NewProjectRequest`/`CreationStep`, «Фейковые репозитории»), §6; макет `docs/design/6-new-project.html`. Отложенное — `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`.

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями `CLAUDE.md`: репозитории `abstract interface` + `Impl({required this._x})`; виджеты не трогают репозитории; Sequential для load/watch, Droppable для мутаций; Stream-методы репозиториев по Pattern 1 (onListen/onCancel), гарантированно закрываются.
- Fake (спека §4): данные детерминированные, задержки через параметр `step`; флаг `isPreview` → `PreviewBadge`; действие, которого ещё нет, показывает SnackBar `comingInMilestone('M4')` и ничего не делает. Фейк не создаёт файлов и проектов и не запускает процессов.
- Диалог: ширина 560 px (`ConstrainedBox(maxWidth: 560)`), высота — по содержимому с прокруткой; при окне 900×600 ничего не переполняется.
- Цвета только `context.colors`, радиусы `AppRadius`, моно — `AppText.mono`, шаг 4 px; Material Icons; у кнопок-иконок `tooltip`; Esc закрывает диалог (спека §2).
- Все строки — `intl_en.arb` и `intl_ru.arb` (русское множественное — one/few/many/other, без `=1`; обращение на «вы»).
- Виджет-тесты не трогают настоящие файлы и процессы: двойник `test/support/memory_project_creation_repository.dart` по умолчанию в `testDependencies`; нативный выбор папки подменяется полем `@visibleForTesting pickFolder` (как `SkillsConfigWidgetState.pickFolder`).
- `flutter analyze` чистый; коммиты заканчиваются `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Папка `<родитель>/<имя>` уже существует — ошибка под «Папкой», «Создать» неактивна; пустая существующая папка — тоже ошибка (как и непустая: `flutter create` в чужую папку не пишем) (Task 1, Task 2).
2. Имя-ключевое слово (`class`), имя зависимости (`flutter`, `meta`), с заглавной, дефисом или цифрой в начале — ошибка с подсказкой исправленного имени, как у `flutter create` (`My-App` → «Попробуйте "my_app"») (Task 1, Task 2).
3. Диалог закрыт (Свернуть / ✕ / Esc) во время создания — создание идёт дальше, в сайдбаре чип «Создаю … 2/5»; клик по чипу или повторный «Новый Flutter-проект…» открывает текущий прогресс, а не новую форму (Task 3).
4. Flutter SDK не найден (`IFlutterSdkRepository.sdkFor(null).path == null`) — внизу формы «Flutter SDK не найден» со ссылкой в Настройки → Flutter, «Создать» неактивна (Task 2).
5. Сняты все платформы — подсказка «Выберите хотя бы одну платформу», «Создать» неактивна (Task 2).

---

### Task 1: Модели, проверка имени и цели, фейковое создание

**Files:**
- Create: `lib/src/feature/project_creation/models/new_project_request.dart`, `lib/src/feature/project_creation/models/creation_step.dart`, `lib/src/feature/project_creation/models/package_name.dart`, `lib/src/feature/project_creation/data/project_creation_repository.dart` (интерфейс + `ProjectCreationRepositoryImpl`)
- Modify: `lib/src/feature/initialization/models/dependencies.dart`, `lib/src/feature/initialization/data/initialize_dependencies.dart`, `test/support/test_app.dart`
- Create (двойник): `test/support/memory_project_creation_repository.dart`
- Test: `test/feature/project_creation/package_name_test.dart`, `test/feature/project_creation/project_creation_repository_test.dart`

**Interfaces:**
- Produces:
  - `enum FlutterPlatform { ios, android, macos, web, windows, linux }`; по умолчанию выбраны `ios`, `android`, `macos` (макет).
  - `NewProjectRequest` (freezed): `String name`, `String org`, `String parent` (папка, в которой создаётся `<parent>/<name>`), `Set<FlutterPlatform> platforms`, `NewProjectTemplate template` (enum из `app_settings`, этап 6), `bool gitInit`, `bool openChat`; геттер `String get path => p.join(parent, name)`.
  - `enum CreationStepKind { flutterCreate, gitInit, agentSetup, analyze, firstCommit }`, `enum CreationStepStatus { pending, running, done, failed }`.
  - `CreationStep` (freezed): `CreationStepKind kind`, `CreationStepStatus status`, `List<String> output` (строки моно под шагом), `Duration? took`.
  - `List<CreationStepKind> creationStepsFor(NewProjectRequest request)` — порядок спеки; `gitInit` и `firstCommit` только при `request.gitInit`; `agentSetup` только при `template == NewProjectTemplate.architecture`.
  - В `package_name.dart` (перенос правил `flutter_tools/lib/src/commands/create_base.dart`): `PackageNameProblem? checkPackageName(String name)` — `enum PackageNameProblem { empty, invalid, keyword, dependency }`: пусто → `empty`; не совпадает целиком с `^[a-z_][a-z0-9_]*$` → `invalid`; в наборе ключевых слов `flutter create` → `keyword`; в `{'collection', 'flutter', 'flutter_test', 'meta'}` → `dependency`. Ключевые слова — ровно список `_keywords` из `create_base.dart` (`abstract`, `as`, `assert`, `async`, `await`, `break`, `case`, `catch`, `class`, `const`, `continue`, `covariant`, `default`, `deferred`, `do`, `dynamic`, `else`, `enum`, `export`, `extends`, `extension`, `external`, `factory`, `false`, `final`, `finally`, `for`, `function`, `get`, `hide`, `if`, `implements`, `import`, `in`, `inout`, `interface`, `is`, `late`, `library`, `mixin`, `native`, `new`, `null`, `of`, `on`, `operator`, `out`, `part`, `patch`, `required`, `rethrow`, `return`, `set`, `show`, `source`, `static`, `super`, `switch`, `sync`, `this`, `throw`, `true`, `try`, `typedef`, `var`, `void`, `while`, `with`, `yield`). `String? suggestPackageName(String name)` — как `potentialValidPackageName` там же: нижний регистр, `-` и пробелы → `_`, ведущая цифра → `_` впереди, остальные недопустимые символы убираются; результат проходит `checkPackageName` или `null`.
  - `enum TargetProblem { exists, parentMissing }`.
  - `abstract interface class IProjectCreationRepository`:
    - `bool get isPreview` — `true` до M4.
    - `Future<String> defaultParent()` — папка родителя последнего открытого проекта (`projects.lastOpenedAt` по убыванию), если она есть на диске; иначе `~/StudioProjects`, если есть; иначе домашняя папка (`HOME`).
    - `Future<TargetProblem?> checkTarget(String parent, String name)` — Real: `parent` нет → `parentMissing`; `<parent>/<name>` есть (файл или папка, пустая тоже) → `exists`; иначе `null`.
    - `Stream<List<CreationStep>> create(NewProjectRequest request)` — снимок всех шагов при каждом изменении; Pattern 1; завершается после последнего шага. Fake: шаги из `creationStepsFor` по очереди, каждый `pending → running → done`, у каждого `took` — фиксированные значения (`flutterCreate` 6 с, остальные 1–3 с — выбрать и записать константами); между изменениями ждёт `step`; вывод: `flutterCreate` — `'Creating project <name>...'`, `'Wrote 130 files.'`; `agentSetup` — четыре строки из макета (`✎ lib/src/common/localization/intl_en.arb`, `✎ lib/src/feature/initialization/…`, `⌁ flutter pub add control drift freezed_annotation…`, `⌁ dart run build_runner build`) по одной на `step`; `analyze` — `'No issues found!'`. Отмена подписки останавливает таймеры.
  - `ProjectCreationRepositoryImpl({required AppDatabase database, Duration step = const Duration(milliseconds: 700), String? home})` — `home` по умолчанию `Platform.environment['HOME']`; `Dependencies.projectCreationRepository`; шаг инициализации «Create project creation repository».
  - `MemoryProjectCreationRepository({String parent = '/Users/test/StudioProjects', Set<String> existing = const {}, Duration step = Duration.zero})` — `checkTarget` по `existing` (полные пути), `create` — те же шаги через `creationStepsFor`, без IO; записывает запросы в `requests`. По умолчанию в `testDependencies` (параметр `IProjectCreationRepository? projectCreationRepository`).

- [ ] **Step 1: Failing tests** `package_name_test.dart`: `'avera_booking'` → `null`; `''` → `empty`; `'My-App'`, `'1app'`, `'app.name'`, `'привет'` → `invalid`; `'class'`, `'yield'` → `keyword`; `'flutter'`, `'meta'` → `dependency`; `suggestPackageName('My-App') == 'my_app'`, `suggestPackageName('1app') == '_1app'`, `suggestPackageName('Hello World') == 'hello_world'`, `suggestPackageName('---') == null`.
- [ ] **Step 2:** `project_creation_repository_test.dart` (обычный `test`, временная папка, `NativeDatabase.memory()`):
  - `'checkTarget'`: свободное имя → `null`; существующая папка (пустая) → `exists`; существующий файл → `exists`; нет родителя → `parentMissing`.
  - `'defaultParent prefers the last opened project'`: два проекта в БД (пути во временной папке), родитель более позднего; без проектов и без `~/StudioProjects` (`home` — временная папка) → `home`; с `<home>/StudioProjects` → она.
  - `'create runs the steps in order'` (`step: Duration.zero`): архитектура + git → виды `[flutterCreate, gitInit, agentSetup, analyze, firstCommit]`, последний снимок — все `done`, у `agentSetup` 4 строки вывода; поток закрывается; на диске в родителе ничего не появилось.
  - `'plain template without git skips steps'`: `[flutterCreate, analyze]`.
  - `'cancel stops the run'`: отмена подписки после первого снимка — больше снимков нет (`step: 10 ms`, ждать 100 ms).
- [ ] **Step 3:** `flutter test test/feature/project_creation` — FAIL. **Step 4:** реализовать, `build_runner`; PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "project_creation: package names, target checks and preview creation"`.

### Task 2: Диалог: форма

**Files:**
- Create: `lib/src/feature/project_creation/controller/project_creation_controller.dart`, `lib/src/feature/project_creation/widgets/new_project_dialog.dart`, `lib/src/feature/project_creation/widgets/new_project_form.dart`, `lib/src/feature/project_creation/widgets/platform_chips.dart`
- Modify: `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (контроллер создания, `openNewProject()`, `pickFolder`), `lib/src/feature/workspace/widgets/workspace_sidebar.dart` (пункт `_AddProjectAction.newFlutter` → `openNewProject()`; «Клонировать из git…» остаётся SnackBar M4), ARB
- Test: `test/feature/project_creation/new_project_form_test.dart`

**Interfaces:**
- Consumes: Task 1 (всё из Produces), `AppSettings.projectOrg`, `.projectTemplate`, `AppSettings.orgPattern` (этап 6), `IFlutterSdkRepository.sdkFor(null)` (этап 6, `Dependencies.flutterSdkRepository`), `WorkspaceDataController.openView(WorkspaceView.settings, section: 'flutter')`.
- Produces:
  - `ProjectCreationController` (Droppable — одно создание за раз): состояние freezed `idle | running(NewProjectRequest request, List<CreationStep> steps) | completed(NewProjectRequest request, List<CreationStep> steps) | failed(NewProjectRequest request, List<CreationStep> steps, Object error)`; `start(NewProjectRequest)` (из `idle` и только из него), `reset()` (из `completed`/`failed` в `idle`); `dispose` отменяет подписку. Для формы: `Future<String> defaultParent()`, `Future<TargetProblem?> checkTarget(String parent, String name)` — прямые обёртки репозитория (без состояния).
  - `WorkspaceConfigWidgetState`: `late final ProjectCreationController projectCreation`; `@visibleForTesting Future<String?> Function(String confirmButtonText) pickFolder` (по умолчанию `getDirectoryPath`); `void openNewProject()` — показывает `NewProjectDialog` (`showDialog`, `barrierDismissible: false`); если диалог уже открыт — ничего.
  - `NewProjectDialog()` — заголовок «Новый Flutter-проект» и ✕ (tooltip «Закрыть»); при `idle` — `NewProjectForm`, иначе — прогресс (Task 3; в этой задаче — временный `Text` с числом готовых шагов, Task 3 заменяет).
  - `NewProjectForm` — по макету, сверху вниз:
    - «Имя пакета» (`TextField`, моно; подсказка «snake_case, проверяется как в flutter create»); ошибка — по `checkPackageName`: `invalid` → «Только строчные латинские буквы, цифры и _, не с цифры» + «Попробуйте "<suggest>"», если есть; `keyword` → «Это зарезервированное слово Dart»; `dependency` → «Совпадает с зависимостью Flutter»; `empty` — без текста ошибки (кнопка неактивна). Ошибка показывается после первого ввода, не на пустой форме.
    - «Organization» — `TextField`, по умолчанию `projectOrg`; подсказка «из Настроек → Flutter»; неверный (`orgPattern`) → «Например, com.example»; настройки не меняет.
    - «Папка» — `<parent>/<name>` моно (пока имени нет — `<parent>/`) + `CompactButton` «Выбрать…» → `pickFolder` → новый `parent`; ошибка `exists` → «Папка уже существует», `parentMissing` → «Папки нет». `checkTarget` вызывается при изменении имени или папки, последний ответ побеждает (устаревший ответ отбрасывается).
    - «Платформы» — `PlatformChips` (6 чипов-переключателей, выбранный — `colors.accentSoft` + галочка); ни одной → «Выберите хотя бы одну платформу».
    - «Шаблон» — три карточки-радио: «Моя архитектура» («flutter create, затем агент раскладывает lib/src/common + feature, control, drift, gen-l10n en/ru — по включённым скиллам и правилам»), «Чистый flutter create» («как из терминала, без агента»), «Из git-шаблона…» («свой стартовый репозиторий») с `PreviewBadge` — выбор показывает SnackBar `comingInMilestone('M4')` и не меняет выбор; по умолчанию — `projectTemplate` из настроек (если там `git` — `architecture`).
    - Флажки «git init + первый коммит» и «Открыть чат после создания» (оба включены).
    - Низ: слева `Flutter <version>` моно (+ `· fvm`, если `fvmVersion != null`) и `PreviewBadge`, если `sdk.isPreview`; если `sdk.path == null` — «Flutter SDK не найден» (`colors.danger`) и ссылка «Настройки → Flutter» (закрывает диалог и открывает раздел). Справа «Отмена» (закрывает) и «Создать» (`FilledButton`; активна, только когда имя, org, папка и платформы без ошибок, проверка цели завершена и SDK найден) → `projectCreation.start(request)`.
    - Esc закрывает диалог; ↵ в поле имени — как «Создать», если она активна.

- [ ] **Step 1: Failing tests** `new_project_form_test.dart` (`MemoryProjectCreationRepository(existing: {'/Users/test/StudioProjects/taken'})`, `FakeFlutterSdkRepositoryImpl(which: …, step: Duration.zero)`; открыть через меню сайдбара «＋ Проект ▾» → «Новый Flutter-проект…»):
  - `'opens from the sidebar with defaults'`: видны «Новый Flutter-проект», org `com.example` (или сохранённый в настройках `dev.avaz`), папка `/Users/test/StudioProjects/`, выбраны iOS/Android/macOS, «Моя архитектура», оба флажка; «Создать» неактивна (имени нет).
  - `'name errors like flutter create'`: `My-App` → текст ошибки и «Попробуйте "my_app"», «Создать» неактивна; `class` → «зарезервированное слово»; `flutter` → «зависимостью Flutter»; `avera_booking` → ошибок нет, «Создать» активна.
  - `'existing folder blocks creation'`: `taken` → «Папка уже существует», «Создать» неактивна.
  - `'picked folder becomes the parent'`: `pickFolder` возвращает `/tmp/elsewhere` → видно `/tmp/elsewhere/avera_booking`.
  - `'no platform blocks creation'`: снять iOS, Android, macOS → подсказка, «Создать» неактивна.
  - `'missing sdk links to settings'`: `which` → `null` → «Flutter SDK не найден»; тап «Настройки → Flutter» → диалог закрыт, открыт раздел Flutter настроек.
  - `'git template is a preview'`: тап «Из git-шаблона…» → SnackBar с `M4`, выбрана по-прежнему «Моя архитектура».
  - `'create starts with the request'`: заполнить `avera_booking`, снять macOS, выбрать «Чистый flutter create», снять git → «Создать» → `requests.single` = `name 'avera_booking'`, `platforms {ios, android}`, `template plain`, `gitInit false`, `parent '/Users/test/StudioProjects'`.
  - `'clone stays a preview'`: «Клонировать из git…» → SnackBar с `M4`.
  - `'fits 900×600 and 1280×800 in en and ru, light and dark'` (форма с ошибкой имени и длинным путём папки).
- [ ] **Step 2:** FAIL. **Step 3:** реализовать, ARB, `build_runner`. **Step 4:** PASS, весь `flutter test` зелёный, `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "New project: the form"`.

### Task 3: Прогресс, сворачивание и чип в сайдбаре

**Files:**
- Create: `lib/src/feature/project_creation/widgets/creation_progress.dart`, `lib/src/feature/project_creation/widgets/creation_chip.dart`
- Modify: `lib/src/feature/project_creation/widgets/new_project_dialog.dart` (прогресс вместо временного текста), `lib/src/feature/workspace/widgets/workspace_sidebar.dart` (чип над списком проектов, под кнопкой «＋ Проект»), ARB
- Test: `test/feature/project_creation/creation_progress_test.dart`

**Interfaces:**
- Consumes: Task 1 (`CreationStep`, `CreationStepKind`, `CreationStepStatus`, `isPreview`), Task 2 (`ProjectCreationController` и его состояния, `openNewProject()`).
- Produces:
  - `CreationProgress` — заголовок «Создаю <name>» (`running`) / «<name>: готово (Preview)» (`completed`) / «Не удалось создать <name>» (`failed`); список шагов: значок (`pending` ○ `colors.muted`, `running` — маленький `CircularProgressIndicator`, `done` ✓ `colors.ok`, `failed` ✕ `colors.danger`), подпись по `kind` (`flutterCreate` «flutter create», `gitInit` «git init», `agentSetup` «Агент раскладывает архитектуру · Claude Code», `analyze` «flutter analyze», `firstCommit` «Первый коммит»), `took` справа («6 с»); строки `output` — моно, `colors.muted`, под шагом, не больше 6 последних.
  - Пояснение под шагами (макет): «Шаг агента — это обычный чат «Новый проект» в сайдбаре: разрешения, diff и ошибки работают как везде. Окно можно закрыть — создание продолжится.» Если `isPreview` — вместо него `PreviewBadge` и «Это предпросмотр: файлы не создаются, настоящее создание появится в M4.»
  - Кнопки: `running` — «Открыть чат агента» (Preview: SnackBar `comingInMilestone('M4')`) и «Свернуть» (закрывает диалог); `completed`/`failed` — «Готово» (закрывает диалог и `reset()`).
  - `CreationChip` в сайдбаре — виден при `running`/`completed`/`failed`: «Создаю <name> · N/M» (N — готовые шаги) или «<name>: готово» / «… ошибка»; тап → `openNewProject()` (диалог открывается на прогрессе); у `completed`/`failed` кнопка-иконка ✕ (tooltip «Скрыть») → `reset()`.
  - `openNewProject()` при `running`/`completed`/`failed` открывает прогресс, а не новую форму (так уже следует из `NewProjectDialog`: форма только при `idle`).

- [ ] **Step 1: Failing tests** `creation_progress_test.dart` (`MemoryProjectCreationRepository(step: Duration(milliseconds: 100))`, форма заполнена `avera_booking`, архитектура, git):
  - `'shows steps as they run'`: после «Создать» — «Создаю avera_booking», первый шаг `running`; `pump(...)` до конца — все ✓, заголовок «avera_booking: готово (Preview)», строки вывода агента видны, пояснение про M4.
  - `'minimize keeps it running'`: «Свернуть» → диалога нет, чип «Создаю avera_booking · 0/5» (или текущее N/5); дождаться шагов — N растёт; тап по чипу → диалог с прогрессом, а не форма.
  - `'menu reopens the running creation'`: при `running` «＋ Проект ▾» → «Новый Flutter-проект…» → прогресс, `requests.length == 1`.
  - `'done resets to a fresh form'`: после завершения «Готово» → чипа нет; снова «Новый Flutter-проект…» → пустая форма.
  - `'chip can be dismissed after completion'`: свернуть, дождаться конца, ✕ на чипе → чипа нет, состояние `idle`.
  - `'open agent chat is a preview'`: SnackBar с `M4`.
  - `'plain template shows two steps'`: «Чистый flutter create» без git → два шага, чип «… · N/2».
  - `'fits 900×600 and 1280×800 in en and ru, light and dark'` (прогресс в середине и в конце; сайдбар с чипом и длинным именем проекта).
- [ ] **Step 2:** FAIL. **Step 3:** реализовать, ARB. **Step 4:** PASS, весь `flutter test` зелёный, `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "New project: progress, minimize and the sidebar chip"`.

### Task 4: Итог этапа

**Files:**
- Modify: `docs/superpowers/specs/2026-10-28-ui-system-design.md` («Решения этапа 7:» после §3.9: правила имени — из `flutter_tools` `create_base.dart`; цель — новая папка `<родитель>/<имя>`, существующая (даже пустая) запрещена; родитель по умолчанию — родитель последнего открытого проекта / `~/StudioProjects` / домашняя; создание — снимки `Stream<List<CreationStep>>`; контроллер на уровне окна, чип в сайдбаре; фейк ничего не пишет и не создаёт чат — «Открыть чат агента» и шаг агента — M4), `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` («## Stage 7 follow-ups»), `docs/PLAN.md` (только если пункт M4 «Форма: имя, org, платформы, папка» теперь выполнен — форма есть, но создание фейковое: отметить не галочкой, а пометкой «форма — UI этап 7»)
- Test: весь набор

- [ ] **Step 1:** обновить спеку, follow-ups и `PLAN.md`, сверив каждое утверждение с кодом.
- [ ] **Step 2:** `flutter analyze` — No issues; `flutter test` — All tests passed (дважды); `flutter build macos --debug` — успешно.
- [ ] **Step 3: Commit** `git commit -m "Stage 7 wrap-up: spec notes and follow-ups"`.
