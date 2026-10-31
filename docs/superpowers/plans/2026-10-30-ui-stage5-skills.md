# UI Stage 5 (Skills and rules) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этап 5 спеки: экран «Скиллы и правила» на настоящем файловом хранилище (встроенные, Мои, Проект), включение глобально с исключениями по проектам (drift `skill_states`, схема v5), редактор `SKILL.md`, добавление (создать, из папки, дублировать, сгенерировать с агентом), а в чате — чип 🧩 N с меню F, секция «Скиллы проекта» в меню `/` и строка «🧩 Скилл …» в ленте — как в макетах `docs/design/4-skills.html` и `2-composer.html` (C, F).

**Architecture:** Новая фича `lib/src/feature/skills/`: модели (`KnowledgeItem` — и скилл, и правило), разбор frontmatter, источник встроенных знаний из ассетов `assets/knowledge/`, `SkillsRepositoryImpl` над файлами + drift. Репозиторий отдаёт одну библиотеку (`SkillLibrary`) для выбранного проекта: сканирует папки по таймеру (опрос, без FSEvents) и пересчитывает при изменении `skill_states`. Экран — свой `SkillsConfigWidget` с контроллерами; чат получает только плоские данные (`ChatSkills`), как `RunMentions` на этапе 4.

**Tech Stack:** Flutter (macOS), control, freezed, drift (v4 → v5), gen-l10n en/ru, `file_selector` (уже есть), `yaml` (новый пакет — для frontmatter).

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` §3.3 (строка скилла), §3.4 (чип 🧩, меню C), §3.7, §4 (таблица `skills`, модели, БД), §6; макеты `docs/design/4-skills.html`, `docs/design/2-composer.html` (C, F). Отложенное: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`.

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями `CLAUDE.md`: репозитории `abstract interface` + `Impl({required this._x})`; виджеты не трогают репозитории; Sequential для load/watch, Droppable для мутаций; Stream-методы репозиториев по Pattern 1 (onListen/onCancel), гарантированно закрываются.
- Формат Anthropic Skills: скилл — папка `<name>/SKILL.md` с frontmatter `name`, `description` (+ необязательные `when_to_use`, `version`) и файлами рядом; имя — `^[a-z0-9][a-z0-9-]{0,63}$`.
- Правило — один файл `<name>.md` с тем же frontmatter (без файлов).
- Источники (спека §4): встроенные — ассеты `assets/knowledge/skills/<name>/…` и `assets/knowledge/rules/<name>.md`, только чтение; Мои — `<Application Support>/skills/` и `<Application Support>/rules/`; Проект — `<project>/.claude/skills/` и `<project>/.claude/rules/`; git — Fake до M3 (только пункт «＋ Добавить источник…» с `PreviewBadge` и SnackBar `comingInMilestone('M3')`, без выдуманных скиллов).
- Доставка скиллов и правил агенту — M3. Сейчас агент сам знает только скиллы Проекта (Claude Code читает `.claude/skills`), поэтому «Попробовать в чате» и `/имя` в меню доступны только для них; остальным — подсказка `M3`.
- Цвета только `context.colors`, радиусы `AppRadius` (6/10/14), шаг 4 px, моно — `AppText.mono`; Material Icons.
- Раскладка экрана: навигация 220 px (56 px рейл при окне уже `kWideWindowWidth`), список 320 px, карточка min 400 px; карточка — `Expanded` с вертикальной прокруткой; при окне 900×600 (рейл 56 + 320 + 400 ≤ 900) ничего не переполняется.
- Все строки — `intl_en.arb` и `intl_ru.arb` (русское множественное — только one/few/many/other, без `=1`); у кнопок-иконок `tooltip`.
- Новая версия схемы — step-by-step + тест `SchemaVerifier`, как v4 (команды: `dart run drift_dev schema dump lib/src/common/database/database.dart drift_schemas/`, `dart run drift_dev schema steps drift_schemas/ lib/src/common/database/database.steps.dart`, `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`).
- `flutter analyze` чистый; коммиты заканчиваются `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Сломанный скилл: `SKILL.md` без frontmatter, с битым YAML, без `name`, или папка без `SKILL.md` — экран не падает: папка без `SKILL.md` пропускается, остальные видны с именем папки и текстом проблемы в карточке (Task 1, Task 2).
2. Агент (или пользователь в Finder) создаёт `.claude/skills/x/SKILL.md`, когда папки `.claude/skills` ещё не было, пока экран открыт — скилл появляется без перезапуска (Task 2: опрос корней, а не watch существующих папок).
3. Имя занято: «Дублировать в Мои» для скилла, у которого в Моих уже есть такое имя, и «Создать» с занятым именем — ничего не перезаписывается (дубль получает `-copy`, `-copy-2`; создание — понятная ошибка) (Task 2, Task 5).
4. Несохранённая правка в редакторе, а пользователь выбирает другой скилл — правка не теряется молча: диалог «Отменить изменения?» (Task 5); сохранение пишет ровно то, что в редакторе.
5. Глобальное включение переключили, когда у скилла уже есть исключения — исключения остаются только там, где значение проекта отличается от глобального (Task 2).

---

### Task 1: Модели, frontmatter и встроенные знания

**Files:**
- Modify: `pubspec.yaml` (зависимость `yaml` — последняя версия с pub.dev, проверить статус; ассеты `assets/knowledge/rules/` и каждая папка встроенного скилла — Flutter не берёт подпапки сам)
- Create: `lib/src/feature/skills/models/knowledge_item.dart`, `lib/src/feature/skills/models/skill_library.dart`, `lib/src/feature/skills/data/frontmatter.dart`, `lib/src/feature/skills/data/builtin_knowledge.dart`
- Create (контент): `assets/knowledge/skills/feature-architecture/SKILL.md` (+ `templates/controller.dart`, `templates/repository.dart`), `assets/knowledge/skills/drift-migration/SKILL.md`, `assets/knowledge/skills/pub-freshness/SKILL.md`, `assets/knowledge/skills/widget-test/SKILL.md`, `assets/knowledge/rules/architecture.md`, `assets/knowledge/rules/package-freshness.md`, `assets/knowledge/rules/localization.md` — по-английски, коротко (10–40 строк), выжимка из `docs/AI_INSTRUCTIONS.md` и `CLAUDE.md`; полная раскладка знаний — M3
- Test: `test/feature/skills/frontmatter_test.dart`, `test/feature/skills/builtin_knowledge_test.dart`

**Interfaces:**
- Produces:
  - `enum KnowledgeKind { skill, rule }`, `enum SkillSource { builtin, user, project, git }`
  - `KnowledgeItem` (freezed): `String id` (`'<kind>:<source>:<name>'`, напр. `skill:builtin:feature-architecture`), `KnowledgeKind kind`, `SkillSource source`, `String name` (имя папки/файла), `String title` (frontmatter `name` или `name`), `String description`, `String? whenToUse`, `String? version`, `String path` (абсолютный путь папки скилла / файла правила; для встроенных — ключ ассета), `List<String> files` (относительные, `SKILL.md` первым; у правил пусто), `bool readOnly`, `String? problem`, `bool enabled` (для наблюдаемого проекта), `bool enabledGlobally`, `Set<int> exceptions` (проекты, где значение ≠ глобальному). Геттер `bool get invocable => kind == KnowledgeKind.skill && source == SkillSource.project`.
  - `SkillLibrary` (freezed): `List<KnowledgeItem> skills`, `List<KnowledgeItem> rules` (каждый список: по источнику в порядке enum, внутри по `name`); `KnowledgeItem? byId(String id)`; `static const empty`.
  - `({Map<String, String> fields, String body})? parseFrontmatter(String text)` — `null`, если текст не начинается с `---\n` и нет закрывающей `---`; бросает `FrontmatterException(String message)` на битом YAML или не-map; значения-не-строки приводятся `toString()`, вложенный `metadata.version` поднимается в `version`, если верхнего `version` нет.
  - `String writeFrontmatter(Map<String, String> fields, String body)` — для шаблона «Создать».
  - `abstract interface class IBuiltinKnowledge { Future<Map<String, String>> load(); }` — ключ: путь относительно `assets/knowledge/` (`skills/feature-architecture/SKILL.md`), значение: текст. `AssetBuiltinKnowledge({required AssetBundle bundle})` — `AssetManifest.loadFromAssetBundle(bundle)`, ключи с префиксом `assets/knowledge/`, кэширует результат.

- [ ] **Step 1: Failing tests** `frontmatter_test.dart`:
  - `'reads name and description'`: `'---\nname: a\ndescription: "Does x: y"\n---\n# A\n'` → `fields == {'name': 'a', 'description': 'Does x: y'}`, `body == '# A\n'`.
  - `'no frontmatter is null'`: `'# Title'` → `null`; `'---\nname: a\n'` (не закрыт) → `null`.
  - `'broken yaml throws'`: `'---\nname: [a\n---\n'` → throws `FrontmatterException`.
  - `'metadata.version is lifted'`: `'---\nname: a\nmetadata:\n  version: 1.3\n---\n'` → `fields['version'] == '1.3'`.
  - `'folded description'`: `'---\nname: a\ndescription: >\n  one\n  two\n---\n'` → `fields['description'] == 'one two'` (значения `trim()`).
  - `'round trip'`: `parseFrontmatter(writeFrontmatter({'name': 'a', 'description': 'x: y'}, 'Body\n'))` даёт те же поля и тело.
- [ ] **Step 2:** `flutter test test/feature/skills/frontmatter_test.dart` — FAIL (нет файла).
- [ ] **Step 3:** модели, `frontmatter.dart` (через `package:yaml` `loadYaml`), `dart run build_runner build --delete-conflicting-outputs`.
- [ ] **Step 4:** тест `builtin_knowledge_test.dart` — `testWidgets('the app ships its built-in skills and rules')`: `AssetBuiltinKnowledge(bundle: rootBundle).load()` содержит ключи `skills/feature-architecture/SKILL.md`, `skills/feature-architecture/templates/controller.dart`, `rules/architecture.md`; у каждого `SKILL.md` и правила `parseFrontmatter` даёт `name`, равное имени папки/файла, и непустой `description`.
- [ ] **Step 5:** ассеты, `pubspec.yaml`, `flutter pub get`; оба теста PASS; `flutter analyze` — No issues.
- [ ] **Step 6: Commit** `git commit -m "skills: models, frontmatter and built-in knowledge"`.

### Task 2: Хранилище: файлы + `skill_states` (схема v5)

**Files:**
- Create: `lib/src/common/database/tables/skill_states_table.dart`, `lib/src/feature/skills/data/skills_repository.dart`
- Modify: `lib/src/common/database/database.dart` (таблица, `schemaVersion => 5`, `from4To5: createTable(schema.skillStates)`), сгенерировать `drift_schemas/drift_schema_v5.json`, `database.steps.dart`, `test/generated_migrations/`
- Test: `test/common/database/migration_test.dart` (+ `v4 → v5`), `test/feature/skills/skills_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 (`KnowledgeItem`, `SkillLibrary`, `parseFrontmatter`, `writeFrontmatter`, `IBuiltinKnowledge`).
- Produces:
  - Таблица `skill_states` (`SkillStateRow`): `id` autoincrement, `skillId` text, `projectId` int nullable (FK `projects.id` ON DELETE CASCADE), `enabled` bool; уникальный ключ `(skillId, projectId)`. Нет строки — включено. SQLite считает `NULL` в уникальном ключе разными, поэтому глобальную строку искать/заменять явно (`projectId IS NULL`), а не `insertOnConflictUpdate`.
  - `abstract interface class ISkillsRepository`:
    - `Stream<SkillLibrary> watch({int? projectId, String? projectRoot})` — первая библиотека сразу, затем при изменении файлов (опрос корней раз в `pollInterval`; сравнение «путь → mtime/size» всех `SKILL.md`, файлов скилла и правил; эмит только при изменении), при изменении `skill_states` и после своих мутаций. Корни, которых нет, просто пусты — и проверяются снова на каждом опросе.
    - `Future<String> read(String id)` — текст `SKILL.md` / правила.
    - `Future<void> write(String id, String text)` — для `readOnly` бросает `ReadOnlyKnowledgeException`.
    - `Future<void> setEnabled(String id, {required bool enabled, int? projectId})` — `projectId == null`: заменить глобальную строку и удалить строки проектов, равные новому глобальному; иначе: если равно глобальному — удалить строку проекта, иначе upsert.
    - `Future<void> clearException(String id, int projectId)` — удалить строку проекта.
    - `Future<String> create(KnowledgeKind kind, String name)` — в Мои: скилл `skills/<name>/SKILL.md`, правило `rules/<name>.md`, текст `writeFrontmatter({'name': name, 'description': ''}, '# <name>\n')`; бросает `InvalidKnowledgeNameException` (имя не по правилу) или `KnowledgeExistsException`; возвращает id.
    - `Future<String> duplicate(String id)` — копия (папка целиком / файл) в Мои; имя `name`, если свободно, иначе `name-copy`, `name-copy-2`, …; в скопированном `SKILL.md` frontmatter `name` меняется на новое имя; возвращает id.
    - `Future<String> importFolder(String path)` — папка с `SKILL.md` копируется в `<user>/skills/<basename>`; без `SKILL.md` — `InvalidKnowledgeException`; занятое имя — как `duplicate` (`-copy`); возвращает id.
  - `SkillsRepositoryImpl({required AppDatabase database, required IBuiltinKnowledge builtin, required String userRoot, Duration pollInterval = const Duration(seconds: 2)})` — `userRoot` содержит `skills/` и `rules/`; проектный корень — `<projectRoot>/.claude/`.
  - Сканирование: подпапка без `SKILL.md` пропускается; `parseFrontmatter` вернул `null`/бросил/нет `description` → элемент с `title = name` и `problem` (текст ошибки или `'No frontmatter'` / `'No description'` — показываются как есть, без локализации: это диагностика файла); `files` — все файлы папки рекурсивно, относительные, `SKILL.md` первым, остальные по алфавиту, скрытые (`.`) пропускаются.

- [ ] **Step 1: Failing migration test** `'v4 → v5 adds skill_states and keeps settings'`: в v4 вставить строку `app_settings` (`key 'app'`), мигрировать до 5 через `verifier.migrateAndValidate`, строка на месте, `skill_states` пуст.
- [ ] **Step 2:** таблица, v5, генерация схем (команды из Global Constraints); тест PASS.
- [ ] **Step 3: Failing tests** `skills_repository_test.dart` (временная папка `Directory.systemTemp.createTempSync`, in-memory БД, `pollInterval: Duration(milliseconds: 20)`, встроенные — `_MapKnowledge` с `skills/a/SKILL.md` и `rules/r.md`):
  - `'lists built-in, user and project items in source order'`: создать `<user>/skills/b/SKILL.md`, `<project>/.claude/skills/c/SKILL.md`, `<project>/.claude/rules/p.md` → `skills.map((s) => s.id) == ['skill:builtin:a', 'skill:user:b', 'skill:project:c']`, `rules.map(id) == ['rule:builtin:r', 'rule:project:p']`; `skill:builtin:a.readOnly`, остальные нет.
  - `'a folder without SKILL.md is skipped, a broken one shows its problem'`: `<user>/skills/empty/` и `<user>/skills/bad/SKILL.md` = `'no frontmatter'` → нет `empty`; у `bad` `title == 'bad'`, `problem != null`.
  - `'a skill created on disk while watching appears'`: watch с `projectRoot`, у которого нет `.claude`; затем создать `.claude/skills/new/SKILL.md` → библиотека с `skill:project:new` приходит в течение 1 с.
  - `'enabled by default; a project exception'`: `setEnabled(id, enabled: false, projectId: 1)` → для проекта 1 `enabled == false`, `enabledGlobally == true`, `exceptions == {1}`; для проекта 2 `enabled == true`.
  - `'flipping global drops exceptions that now match'`: исключение `false` для проекта 1, затем `setEnabled(id, enabled: false)` → `enabledGlobally == false`, `exceptions == {}`; затем `setEnabled(id, enabled: true, projectId: 2)` → `exceptions == {2}`.
  - `'clearException'` → строка проекта удалена, `exceptions` пуст.
  - `'write to built-in throws, write to user saves'`.
  - `'create rejects bad and taken names'`: `create(skill, 'Bad Name')` → `InvalidKnowledgeNameException`; `create(skill, 'b')` при существующем `b` → `KnowledgeExistsException`, файл `b/SKILL.md` не изменился.
  - `'duplicate picks a free name and renames frontmatter'`: `duplicate('skill:builtin:a')` дважды → ids `skill:user:a`, затем `skill:user:a-copy`; в копии `parseFrontmatter(...).fields['name'] == 'a-copy'`; файлы скилла скопированы.
  - `'importFolder copies a skill and refuses a folder without SKILL.md'`.
  - `'the stream closes on cancel'`: после `cancel()` таймер опроса остановлен (нет утечки — тест завершается без висящих таймеров; `drift` cleanup как в `disposeTestApp`).
- [ ] **Step 4:** `flutter test test/feature/skills/skills_repository_test.dart` — FAIL.
- [ ] **Step 5:** реализовать `SkillsRepositoryImpl` (весь ввод-вывод асинхронный: `Directory.list`, `File.stat`; скан одного корня — отдельная функция).
- [ ] **Step 6:** тесты Task 2 PASS; `flutter test test/common/database`; `flutter analyze`.
- [ ] **Step 7: Commit** `git commit -m "skills: file storage and per-project enablement (schema v5)"`.

### Task 3: Контроллеры и зависимости

**Files:**
- Create: `lib/src/feature/skills/controller/skill_library_controller.dart`, `lib/src/feature/skills/controller/skill_actions_controller.dart`, `lib/src/feature/skills/controller/skill_text_controller.dart`
- Modify: `lib/src/feature/initialization/models/dependencies.dart` (`late final ISkillsRepository skillsRepository`), `initialize_dependencies.dart` (шаг `'Create skills repository'`: `SkillsRepositoryImpl(database, builtin: AssetBuiltinKnowledge(bundle: rootBundle), userRoot: (await getApplicationSupportDirectory()).path)`), `test/support/test_app.dart` (`testDependencies({…, ISkillsRepository? skillsRepository})`; по умолчанию — репозиторий на временной папке, встроенные из `_MapKnowledge` с одним скиллом и одним правилом, `pollInterval` 20 мс)
- Test: `test/feature/skills/skill_controllers_test.dart`

**Interfaces:**
- Consumes: Task 2 `ISkillsRepository`.
- Produces:
  - `SkillLibraryController({required ISkillsRepository repository})` — Sequential; `void watch({int? projectId, String? projectRoot})` (повторный вызов с теми же аргументами ничего не делает; с другими — отменяет прошлую подписку); состояние `SkillLibraryState` (freezed): `idle`, `loading({int? projectId})`, `loaded({required SkillLibrary library, int? projectId})`, `failed({required Object error, int? projectId})`; геттер `SkillLibrary get library` (последняя загруженная или `SkillLibrary.empty`).
  - `SkillActionsController({required ISkillsRepository repository})` — Droppable; `setEnabled(String id, {required bool enabled, int? projectId})`, `clearException(String id, int projectId)`, `save(String id, String text)`, `create(KnowledgeKind kind, String name)`, `duplicate(String id)`, `importFolder(String path)`; состояние `SkillActionsState`: `idle`, `processing`, `completed({String? id})` (id нового элемента для create/duplicate/importFolder), `failed({required Object error})`.
  - `SkillTextController({required ISkillsRepository repository})` — Sequential; `load(String id)`; состояние `SkillTextState`: `idle`, `loading(id)`, `loaded(id, text)`, `failed(id, error)`.

- [ ] **Step 1: Failing tests** (`FakeSkillsRepository` в тесте — простая реализация интерфейса со `StreamController`):
  - `'watch emits loaded for the project and switches projects'`: `watch(projectId: 1, projectRoot: '/a')` → `loaded(projectId: 1)`; `watch(projectId: 2, …)` → старая подписка отменена (`fake.cancels == 1`), состояние `loaded(projectId: 2)`.
  - `'a failing stream ends in failed and keeps the last library'`.
  - `'create completes with the new id'`, `'a taken name fails with KnowledgeExistsException'`.
  - `'text load'`.
- [ ] **Step 2:** FAIL; **Step 3:** реализация + `build_runner`; **Step 4:** PASS, весь `flutter test` зелёный (новый `testDependencies` не ломает старые тесты), `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "skills: controllers and dependencies"`.

### Task 4: Экран — навигация, список, проект

**Files:**
- Create: `lib/src/feature/skills/widgets/skills_config_widget.dart` (config widget + `SkillsConfigInhWidget`: `SkillLibraryController`, `SkillActionsController`, `SkillTextController`, выбранный проект экрана, раздел/источник/поиск/выбранный id в `SkillsViewController with ChangeNotifier`), `skills_navigation.dart`, `skills_list.dart`, `skill_list_tile.dart`, `skills_project_selector.dart`, `source_tag.dart`
- Modify: `lib/src/feature/workspace/widgets/workspace_page_scaffold.dart` (+ `List<Widget> actions = const []` в шапку справа; `Widget? navigationFooter` под разделами; `Map<String, String> sectionBadges = const {}` — число справа от раздела; `bool fill = false` — `child` занимает всё справа от навигации без колонки 640 и заголовка), `lib/src/feature/workspace/widgets/workspace_skills_page.dart` (строит `SkillsConfigWidget` → экран), `lib/src/feature/workspace/widgets/controllers/workspace_data_controller.dart` (`openSkills({String? itemId, int? projectId})`: открыть экран на элементе; хранит `skillsTarget` — `({String? itemId, int? projectId})?`, экран забирает его `takeSkillsTarget()`), `intl_en.arb`, `intl_ru.arb`
- Test: `test/feature/skills/skills_page_test.dart`

**Interfaces:**
- Consumes: Task 3 контроллеры; `WorkspaceConfigWidgetState` (проекты: `projectsController`, выбранный проект `dataController.projectId`); `SelectorChip`, `AppMenu`, `PreviewBadge`, `EmptyState`.
- Produces: `SkillsConfigInhWidget.of(context)` → состояние с полями `library`, `actions`, `text`, `view` (`SkillsViewController`: `KnowledgeKind kind`, `SkillSource? source` (фильтр; `null` — все), `String query`, `String? selectedId`, `int? projectId`, методы `select(id)`, `setKind`, `setSource`, `setQuery`, `setProject`); `WorkspaceDataController.openSkills`.
- Раскладка (макет 4): шапка — «Проект: <имя> ▾» (`SelectorChip` со списком проектов; без проектов — скрыт, переключатели — глобальные); навигация — разделы «Скиллы N», «Правила N», заголовок «Источники», пункты «Встроенные N», «Мои N», «Проект (.claude/skills) N» (только при выбранном проекте), «＋ Добавить источник…» с `PreviewBadge` → SnackBar `comingInMilestone('M3')`; список 320 px — поиск (по `title`, `name`, `description`, без учёта регистра), строки: название моно, `SourceTag` (встроенный/мой/проект), описание в 2 строки, `Switch` (`enabled` для проекта экрана, вызывает `actions.setEnabled(id, enabled:, projectId: view.projectId)`); пустой список — `EmptyState`; справа — место под карточку (Task 5; пока `EmptyState` «Выберите скилл»).
- Проект экрана по умолчанию — выбранный в окне; `openSkills(projectId:)` перекрывает.

- [ ] **Step 1: Failing widget tests** (`useDesktopView`, `testApp(..., withSettings: true)`, `testDependencies` со своим репозиторием на временной папке; en):
  - `'shows skills by source with counts'`: навигация содержит «Skills 3», «Built-in 1», «Mine 1», «Project (.claude/skills) 1»; список — 3 строки в порядке источников.
  - `'source filter and search'`: тап «Mine» → 1 строка; ввод `zzz` → `EmptyState`.
  - `'the switch writes for the screen project'`: тап `Switch` строки → у элемента `enabled == false` для проекта экрана (проверка через repository.watch), глобально включён.
  - `'rules section lists rules'`.
  - `'add source says M3'`: тап «＋ Add source…» → SnackBar с `comingInMilestone('M3')`.
  - `'no overflow at 900×600 in en and ru, light and dark'` — без исключений рендера.
- [ ] **Step 2:** FAIL; **Step 3:** реализация (строки l10n: `skillsSources`, `skillsSourceBuiltin`, `skillsSourceUser`, `skillsSourceProject`, `skillsAddSource`, `skillsSearch`, `skillsProject` («Project: {name}»), `skillsNothingFound`, `skillsPickOne`, `skillTagBuiltin`, `skillTagUser`, `skillTagProject`); **Step 4:** PASS; старые тесты Settings (`WorkspacePageScaffold`) зелёные; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Skills screen: navigation, list and project selector"`.

### Task 5: Карточка скилла и «＋ Добавить»

**Files:**
- Create: `lib/src/feature/skills/widgets/skill_card.dart`, `skill_scope.dart` (включение и исключения), `skill_editor.dart`, `skills_add_menu.dart`
- Modify: `skills_list.dart` (кнопка «＋ Добавить ▾» над списком), `skills_config_widget.dart` (действия экрана: `importFromFolder()` через `file_selector.getDirectoryPath`, `generateWithAgent()`, `tryInChat(KnowledgeItem)`, `confirmDiscard()`), `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (`createChat({int? projectId, String? draft})`: черновик вставляется, когда новый чат опубликует `ChatHandle`), `intl_en.arb`, `intl_ru.arb`
- Test: `test/feature/skills/skill_card_test.dart`, `test/feature/workspace/workspace_new_chat_draft_test.dart`

**Interfaces:**
- Consumes: Task 4 `SkillsConfigInhWidget`; Task 3 `SkillTextController`, `SkillActionsController`; `WorkspaceConfigWidgetState.createChat`, `dataController.chatHandle` / `ChatHandle.insertDraft`, `backToChat`.
- Produces: `WorkspaceConfigWidgetState.createChat({int? projectId, String? draft})` (без `draft` — как раньше).
- Карточка (min 400 px, прокрутка): заголовок — `title` моно, `SourceTag`, `· v<version>`; действия: «Дублировать в Мои» (только `readOnly`; после — выбрать новый id), «Попробовать в чате» (только `invocable`; иначе выключена с tooltip `comingInMilestone('M3')`; действие — к чату и `insertDraft('/<name> ')`; без чата — SnackBar `noChatForSkill`); для `readOnly` — строка «Встроенные только для чтения — чтобы изменить, продублируй»; `problem` — плашка `dangerSoft` с текстом; блоки «Описание», «Когда применять» (если есть), «Включён» (`Switch` «Все проекты» = `enabledGlobally`; чипы исключений `<проект> ✕` → `clearException`; «＋ исключение» — меню проектов без исключения → `setEnabled(id, enabled: !enabledGlobally, projectId:)`; у Проектных — только переключатель для проекта экрана), «Файлы» (`files` через « · »), редактор (`TextField` моно, многострочный, `readOnly` для встроенных; «Сохранить» активна при отличии от загруженного текста → `actions.save`; после сохранения загруженный текст = сохранённый).
- Смена выбранного элемента с несохранённой правкой → диалог `discardChangesTitle` («Отменить изменения?») с «Отменить изменения» / «Остаться».
- «＋ Добавить ▾» (`AppMenu`): «Создать» (диалог имени: подсказка правила имени, ошибки `InvalidKnowledgeNameException` / `KnowledgeExistsException` под полем; создаёт в разделе экрана — скилл или правило; выбирает новый), «Из папки…» (только для скиллов), «Из git-репозитория…» (`PreviewBadge`, SnackBar `comingInMilestone('M3')`), «Сгенерировать с агентом» (без проекта экрана — выключено; иначе `createChat(projectId: view.projectId, draft: localization.skillGeneratePrompt)`, где текст — по-английски для агента независимо от языка UI: `'Write a Claude Code skill for this project in .claude/skills/<name>/SKILL.md (frontmatter: name, description). The skill should: '`).

- [ ] **Step 1: Failing tests** `skill_card_test.dart`:
  - `'built-in card is read-only and duplicates into Mine'`: выбрать встроенный → поле редактора `readOnly`, есть «Duplicate to Mine»; тап → выбран `skill:user:<name>`, в списке 2 строки с этим именем (теги built-in и mine).
  - `'editing and saving a user skill'`: ввести текст → «Save» активна → тап → файл на диске равен тексту, «Save» неактивна.
  - `'switching away from unsaved edits asks'`: правка → тап другой строки → диалог; «Stay» — выбор прежний, текст на месте; снова → «Discard changes» — выбран новый.
  - `'exceptions'`: «＋ exception» → проект → чип с именем проекта; ✕ → чипа нет.
  - `'try in chat is only for project skills'`: у встроенного кнопка выключена; у проектного — тап → экран чата, в черновике `/c `.
  - `'create validates the name'`: «＋ Add» → «Create» → `Bad Name` → текст ошибки, диалог открыт; `ok-name` → выбран `skill:user:ok-name`.
  - `'a skill with a problem shows it'`.
  - `'from git says M3'`.
- [ ] **Step 2:** `workspace_new_chat_draft_test.dart` — `'createChat with a draft puts it into the new chat'`: создать проект в тестовой БД, `createChat(projectId:, draft: 'hello')` → после создания чата у его поля ввода текст `hello`; без `draft` поле пустое. FAIL.
- [ ] **Step 3:** реализация (строки l10n: `skillDuplicate`, `skillTryInChat`, `skillReadOnlyNote`, `skillDescription`, `skillWhenToUse`, `skillEnabled`, `skillAllProjects`, `skillAddException`, `skillFiles`, `skillSave`, `skillsAdd`, `skillsAddCreate`, `skillsAddFolder`, `skillsAddGit`, `skillsAddGenerate`, `skillNameHint`, `skillNameInvalid`, `skillNameTaken`, `discardChangesTitle`, `discardChanges`, `stay`, `noChatForSkill`, `skillGeneratePrompt`); **Step 4:** PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Skills screen: card, editor, scope and adding skills"`.

### Task 6: Скиллы в чате

**Files:**
- Create: `lib/src/feature/skills/models/chat_skills.dart`, `lib/src/feature/skills/widgets/chat_skills_chip.dart` (чип 🧩 N + меню F), `lib/src/feature/chat/models/skill_call.dart`
- Modify: `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (окно держит свой `SkillLibraryController`, следящий за выбранным проектом окна, и отдаёт `ChatSkills`), `workspace_chat_area.dart` → `ChatConfigWidget(chatSkills:)` → `chat_screen.dart` → `PromptComposer(chatSkills:)` (путь как у `runContext`), `lib/src/feature/session_config/widgets/composer_toolbar.dart` (чип после режима), `lib/src/feature/prompt_sending/models/slash_command.dart` (`SlashSource.skill`), `lib/src/feature/prompt_sending/widgets/command_suggestions.dart` (секция «Скиллы проекта» первой), `prompt_composer.dart` (если файл вырастет за ~400 строк — вынести сбор команд в `prompt_sending/models/slash_commands.dart`), `lib/src/feature/chat/widgets/tool_call_card.dart` (строка скилла), `intl_en.arb`, `intl_ru.arb`
- Test: `test/feature/skills/chat_skills_test.dart`, `test/feature/chat/skill_call_test.dart`

**Interfaces:**
- Consumes: Task 3 `SkillLibraryController`; Task 4 `WorkspaceDataController.openSkills`.
- Produces:
  - `ChatSkills` (`@immutable`, `==`/`hashCode` по полям — композитор не перестраивается без изменений): `String? projectName`, `List<ChatSkill> skills`; `ChatSkill{String id, String name, String description, SkillSource source, bool enabled, bool invocable}`; `static const empty`.
  - `String? skillNameOf(ToolCallItem item)` — имя из заголовка адаптера `Load skill: <name>` (`claude-agent-acp`, `SkillReporter`); иначе `null`.
- Чип: `🧩 N` (N — включённые скиллы проекта чата; `Icons.extension_outlined`), tooltip `chatSkillsTooltip`; меню F: заголовок «Включены для <проект>», строки включённых (имя моно + описание), затем выключенные приглушённо; низ — «Открыть библиотеку скиллов →» (`openSkills(projectId:)`) и пояснение `chatSkillsNote` с `PreviewBadge`: выбор скиллов для одного чата и доставка агенту — M3 (строки меню не переключаются).
- Меню `/`: секция `SlashSource.skill` («Скиллы проекта») первой — включённые скиллы проекта; `enabled = invocable`, иначе `hint: 'M3'`.
- Лента: `ToolCallItem` с `skillNameOf != null` — компактная строка «🧩 Скилл <b>name</b>» вместо обычной строки инструмента; клик — `openSkills(itemId:)` по первому скиллу с таким `name` (проект, затем Мои, затем встроенные), если найден; иначе не кликабельна.

- [ ] **Step 1: Failing tests** `skill_call_test.dart`: `skillNameOf(ToolCallItem(0, toolCallId: 't', title: 'Load skill: drift-migration', kind: 'other')) == 'drift-migration'`; `'Load skill'` → `null`; `'Read file'` → `null`; виджет-тест строки ленты: текст `drift-migration`, иконка `Icons.extension_outlined`.
- [ ] **Step 2:** `chat_skills_test.dart` (рабочая область с проектом, чатом и скиллами на временной папке):
  - `'the chip counts enabled skills of the chat project'`: 3 скилла, один выключен для проекта → чип `3`→`2` после выключения.
  - `'menu F lists enabled first and opens the library'`: тап чипа → «Enabled for <project>»; тап «Open the skill library →» → экран Скиллов, проект экрана — проект чата.
  - `'slash menu shows project skills first; only project skills can be inserted'`: ввести `/` → первая секция «Project skills»; строка встроенного приглушена с `M3`; Enter на проектном → в поле `/c `.
  - `'a skill line in the feed opens the skill'`.
  - `'composer does not rebuild when the library is unchanged'`: `ChatSkills` равны при повторной эмиссии того же содержимого (юнит на `==`).
- [ ] **Step 3:** FAIL; **Step 4:** реализация (строки: `chatSkillsTooltip`, `chatSkillsEnabledFor`, `chatSkillsOpenLibrary`, `chatSkillsNote`, `slashSectionSkills`, `skillUsed`); **Step 5:** PASS; `flutter test test/feature/prompt_sending test/feature/chat`; `flutter analyze`.
- [ ] **Step 6: Commit** `git commit -m "Skills in the chat: chip, / menu and the skill line"`.

### Task 7: Проверка этапа

**Files:**
- Modify: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` («Stage 5 follow-ups» из реестра ревью), спека §3.7 и §4 — отметить решения этапа: одна модель `KnowledgeItem` вместо `Skill`/`Rule`, один поток `watch` вместо `watchSkills`/`watchRules`, git-источники без фейковых данных, меню F без выбора на чат до M3, опрос папок раз в 2 с; `docs/PLAN.md` — отметить сделанные пункты M1 (`[x]`), уже влитые в `main`.
- [ ] **Step 1: Run** `flutter pub get` — без предупреждений; `flutter analyze` — No issues; `flutter test` — All tests passed; `flutter build macos --debug` — `✓ Built`.
- [ ] **Step 2:** `flutter run -d macos` — только если у пользователя не запущен свой экземпляр (`pgrep -f flutter_code_agent.app`); иначе прямо написать в отчёте, что запуск пропущен. Визуальной проверки нет — так и написать.
- [ ] **Step 3: Commit** `git commit -m "Stage 5 wrap-up: follow-ups and spec notes"`.
