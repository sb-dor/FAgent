# UI Foundation (design system + window shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этапы 1–2 спеки: дизайн-система (токены, тема, общие виджеты) и новый каркас окна (шапка, сайдбар чатов по проектам, правая панель с вкладками, экраны Скиллы/Настройки, поиск ⌘K, горячие клавиши, сохранённые настройки).

**Architecture:** Токены — `ThemeExtension<AppColors>` + `ColorScheme` из них; общие виджеты в `lib/src/common/widget/`. Каркас остаётся в фиче `workspace`: экран окна выбирается состоянием `WorkspaceDataController.view`, без роутера. Настройки окна (тема, язык, видимость и ширина панелей) — новая фича `app_settings` на drift (схема v4) с config-widget над `MaterialApp`.

**Tech Stack:** Flutter (macOS), control (`StateController`, Sequential/Droppable), freezed, drift (step-by-step миграции, `SchemaVerifier`), window_manager (`DragToMoveArea`), gen-l10n en/ru.

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` (макеты: `docs/design/1-window.html`, `5-settings.html`). Этапы 3–7 спеки — отдельные планы после этого.

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями из `CLAUDE.md` (desktop only, без роутера, репозитории получают сервисы через конструктор, `required this._x`).
- Токены — ровно значения из таблицы спеки §1 (светлая/тёмная), `muted` светлой темы `#626A75`.
- Шрифт кода — JetBrains Mono (OFL) из `assets/fonts/`; новые pub-пакеты не добавляем; иконки — Material Icons.
- Радиусы 6 / 10 / 14, шаг сетки 4 px.
- Окно: по умолчанию 1280×800, минимум 900×600. Сайдбар 236 px; правая панель 340–560 px (по умолчанию 380); лента ≤ 720 px; колонка экранов Скиллы/Настройки ≤ 640 px; навигация экрана 220 px, при окне уже 1100 px — 56 px.
- Уже 1100 px правая панель по умолчанию закрыта.
- Все строки — `intl_en.arb` и `intl_ru.arb`; у кнопок-иконок `tooltip`.
- Генерация: `dart run build_runner build --delete-conflicting-outputs`; `flutter analyze` чистый; хук форматирует `.dart`.
- Коммиты заканчиваются строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Минимальное окно 900×600 с открытыми сайдбаром и правой панелью — ничего не переполняется (Task 5).
2. Повреждённый или старый JSON настроек (не JSON, нет полей, неизвестное значение темы) — подставляются значения по умолчанию, приложение стартует (Task 4).
3. Поиск ⌘K со строкой `%`, `_`, `'` ищет буквально, а не как шаблон (Task 7).
4. Очень длинные названия проектов и чатов, сотня чатов — многоточие и прокрутка, без переполнений (Task 6).
5. Esc при открытом меню закрывает только меню, а не экран Настроек; горячие клавиши работают, когда фокус в поле ввода (Task 2, Task 5).

---

### Task 1: Токены, тема и моноширинный шрифт

**Files:**
- Create: `lib/src/common/design/app_colors.dart`, `lib/src/common/design/app_theme.dart`, `lib/src/common/design/app_text.dart`
- Create: `assets/fonts/JetBrainsMono-Regular.ttf`, `assets/fonts/JetBrainsMono-Medium.ttf`, `assets/fonts/OFL.txt`
- Modify: `pubspec.yaml` (секция `flutter: fonts:`), `lib/src/feature/initialization/widget/app.dart` (убрать `_theme`, взять `AppTheme`)
- Test: `test/common/design/app_theme_test.dart`

**Interfaces:**
- Produces:
  - `final class AppColors extends ThemeExtension<AppColors>` с полями `bg, surface, surfaceAlt, border, text, muted, accent, accentSoft, ok, okSoft, warn, warnSoft, danger, dangerSoft` (все `Color`), `static const AppColors light`, `static const AppColors dark`, `copyWith`, `lerp`.
  - `extension AppThemeContext on BuildContext { AppColors get colors; }` (в `app_colors.dart`).
  - `abstract final class AppTheme { static ThemeData light(); static ThemeData dark(); }` — `useMaterial3`, `ColorScheme` из токенов (`primary=accent`, `surface=bg`, `surfaceContainerLow=surface`, `outlineVariant=border`, `error=danger`, `onSurfaceVariant=muted`), `extensions: [AppColors.x]`, `textTheme`: bodyMedium 13/20, bodySmall 12/16, titleSmall 15 w600, titleLarge 20 w600; `switchTheme` (дорожка `accent`, выкл. — `border`), `dividerTheme` (`border`, 1 px), `tooltipTheme` — отдельный `AppSwitch` не нужен.
  - `abstract final class AppText { static const String monoFamily = 'JetBrainsMono'; static TextStyle mono(BuildContext context, {double size = 12}); }` — высота строки 18/12.
  - `abstract final class AppRadius { static const double small = 6, medium = 10, large = 14; }` (в `app_theme.dart`).

- [ ] **Step 1: Write the failing test** `test/common/design/app_theme_test.dart`:
  - `contrast(Color a, Color b)` — WCAG-отношение (функция в тесте).
  - `'text is readable in both themes'`: для `AppColors.light` и `.dark`: `contrast(text, bg) >= 4.5`, `contrast(muted, bg) >= 4.5`, `contrast(muted, surface) >= 4.5`, `contrast(Colors.white, accent) >= 4.5` для светлой.
  - `'themes carry the tokens'`: `AppTheme.light().extension<AppColors>() == AppColors.light`, `AppTheme.dark().colorScheme.primary == AppColors.dark.accent`, `AppTheme.light().colorScheme.brightness == Brightness.light`.
  - `'lerp halfway mixes colors'`: `AppColors.light.lerp(AppColors.dark, .5).bg == Color.lerp(light.bg, dark.bg, .5)`.
- [ ] **Step 2: Run** `flutter test test/common/design/app_theme_test.dart` — Expected: FAIL (нет `AppColors`).
- [ ] **Step 3: Implement** токены (значения из спеки §1), `AppTheme`, `AppText`, `AppRadius`. Скачать JetBrains Mono 2.304 (`https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip`) в каталог scratchpad, положить `fonts/ttf/JetBrainsMono-Regular.ttf` (weight 400), `JetBrainsMono-Medium.ttf` (500) и `OFL.txt` в `assets/fonts/`; объявить family `JetBrainsMono` в `pubspec.yaml`. В `app.dart` — `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`.
- [ ] **Step 4: Run** `flutter test test/common/design/app_theme_test.dart` — Expected: PASS. Затем `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git add lib/src/common/design assets/fonts pubspec.yaml lib/src/feature/initialization/widget/app.dart test/common/design && git commit -m "Design tokens, themes and JetBrains Mono"`.

### Task 2: SelectorChip и AppMenu

**Files:**
- Create: `lib/src/common/widget/app_menu.dart`, `lib/src/common/widget/selector_chip.dart`
- Test: `test/common/widget/app_menu_test.dart`

**Interfaces:**
- Consumes: `context.colors`, `AppRadius`, `AppText` (Task 1).
- Produces:
  - `@immutable final class AppMenuItem<T> { const AppMenuItem({required T value, required String title, String? subtitle, IconData? icon, bool selected = false, bool enabled = true, String? shortcut, AppTone tone = AppTone.neutral}); }`
  - `@immutable final class AppMenuSection<T> { const AppMenuSection({String? title, required List<AppMenuItem<T>> items}); }`
  - `enum AppTone { neutral, warn, danger }` (в `selector_chip.dart`).
  - `Future<T?> showAppMenu<T>({required BuildContext context, required Rect anchor, required List<AppMenuSection<T>> sections, double width = 320, Widget? footer})` — всплывающее меню (`OverlayEntry`/`showDialog` с `barrierColor: transparent`), позиционируется под `anchor`, если не влезает — над ним; клавиши ↑/↓ двигают выделение по `enabled` пунктам, ↵ выбирает, Esc закрывает с `null`; клик вне — `null`.
  - `class SelectorChip<T> extends StatelessWidget { const SelectorChip({required String label, IconData? icon, AppTone tone = AppTone.neutral, String? tooltip, List<AppMenuSection<T>>? sections, ValueChanged<T>? onSelected, VoidCallback? onPressed}); }` — пилюля 28 px, радиус 8, ▾ при наличии `sections`; tone: `warn` → фон `warnSoft`/текст `warn`, `danger` → `dangerSoft`/`danger`.

- [ ] **Step 1: Write the failing tests** `test/common/widget/app_menu_test.dart` (обёртка `testApp` из `test/support/test_app.dart`):
  - `'a chip opens its menu and returns the picked value'`: tap по `SelectorChip(label: 'Opus', sections: [...'opus','sonnet'])` → видно `'Sonnet'`; tap → `onSelected` получил `'sonnet'`, меню закрыто.
  - `'arrows and Enter pick, disabled items are skipped'`: пункты `a`, `b(enabled:false)`, `c`; ↓, ↓, ↵ → выбран `'c'`.
  - `'Escape closes only the menu'`: в `Focus`-обёртке с `CallbackShortcuts(Esc → pageClosed = true)`; открыть меню, Esc → меню закрыто, `pageClosed == false`.
  - `'danger tone paints the chip red'`: `tester.widget<DecoratedBox>(…)` цвет фона `AppColors.light.dangerSoft`.
- [ ] **Step 2: Run** `flutter test test/common/widget/app_menu_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** `showAppMenu`, `AppMenuItem`, `AppMenuSection`, `AppTone`, `SelectorChip` по интерфейсам выше. Esc обрабатывается фокус-узлом меню и не всплывает (`KeyEventResult.handled`).
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "SelectorChip and AppMenu"` (файлы задачи).

### Task 3: Карточки, статусы и мелкие общие виджеты

**Files:**
- Create: `lib/src/common/widget/app_card.dart` (`AppCard`, `KeyValueGrid`), `lib/src/common/widget/status.dart` (`StatusDot`, `StatusPill`), `lib/src/common/widget/segmented_control.dart`, `lib/src/common/widget/preview_badge.dart`, `lib/src/common/widget/pane_tabs.dart`, `lib/src/common/widget/empty_state.dart`
- Modify: `lib/src/common/localization/intl_en.arb`, `intl_ru.arb` (`preview`: «Preview» / «Preview»; `comingInMilestone(milestone)`: «Coming in {milestone}» / «Появится в {milestone}»)
- Test: `test/common/widget/common_widgets_test.dart`

**Interfaces:**
- Consumes: Task 1, `AppTone` (Task 2).
- Produces:
  - `class AppCard extends StatelessWidget { const AppCard({Widget? leading, required Widget title, Widget? subtitle, List<Widget> trailing = const [], Widget? body}); }` — рамка `border`, радиус 10, отступы 14/16; шапка — `Wrap`-строка: при нехватке места `trailing` переносится вниз.
  - `class KeyValueGrid extends StatelessWidget { const KeyValueGrid({required List<(String, Widget)> rows}); }` — подпись 120–170 px (`muted`, 12), значение `Expanded`, перенос.
  - `class StatusDot extends StatelessWidget { const StatusDot({required AppStatusTone tone}); }`, `enum AppStatusTone { none, active, warn, danger, ok }` — 7 px; `active`→`accent`, `warn`→`warn`, `danger`→`danger`, `ok`→`ok`, `none`→прозрачный.
  - `class StatusPill extends StatelessWidget { const StatusPill({required String label, required AppStatusTone tone}); }`
  - `class SegmentedControl<T> extends StatelessWidget { const SegmentedControl({required List<(T, String)> segments, required T selected, required ValueChanged<T> onChanged}); }`
  - `class PreviewBadge extends StatelessWidget { const PreviewBadge(); }`
  - `class PaneTabs<T> extends StatelessWidget { const PaneTabs({required List<PaneTab<T>> tabs, required T selected, required ValueChanged<T> onSelected}); }`, `final class PaneTab<T> { const PaneTab({required T id, required String label, int? count, int? errors}); }` — `errors > 0` рисует красный бейдж.
  - `class EmptyState extends StatelessWidget { const EmptyState({required IconData icon, required String title, String? message, String? actionLabel, VoidCallback? onAction, Widget? badge}); }`
- [ ] **Step 1: Write the failing tests**:
  - `'an AppCard wraps its actions on a narrow width'`: `SizedBox(width: 320)` с длинным заголовком и тремя кнопками в `trailing` — `tester.takeException()` равно `null`.
  - `'KeyValueGrid keeps labels within 120–170 px'`: при ширине 640 `tester.getSize(find.text('Модель по умолчанию')).width <= 170`; при 300 — без исключений.
  - `'PaneTabs shows an error badge and reports the picked tab'`: вкладка Run с `errors: 2` → виден `'2'`; tap «Изменения» → `onSelected('changes')`.
  - `'EmptyState runs its action'`.
  - `'StatusDot maps tones to tokens'`: цвет `active` == `AppColors.light.accent`.
- [ ] **Step 2: Run** `flutter test test/common/widget/common_widgets_test.dart` — FAIL.
- [ ] **Step 3: Implement** виджеты и строки локализации.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Common cards, status, tabs and empty state widgets"`.

### Task 4: Фича `app_settings` и схема v4

**Files:**
- Create: `lib/src/common/database/tables/app_settings_table.dart`
- Modify: `lib/src/common/database/database.dart` (таблица, `schemaVersion => 4`, `from3To4`), сгенерировать `drift_schemas/drift_schema_v4.json`, `lib/src/common/database/database.steps.dart`, `test/generated_migrations/` (команды как для v3: `dart run drift_dev schema dump …`, `schema steps …`, `schema generate …`)
- Create: `lib/src/feature/app_settings/models/app_settings.dart`, `data/app_settings_repository.dart`, `controller/app_settings_controller.dart`, `widgets/app_settings_config_widget.dart`
- Modify: `lib/src/feature/initialization/widget/app.dart` (`themeMode`, `locale` из настроек), `lib/main.dart` — `dependencies.inject(child: const AppSettingsConfigWidget(child: App()))`
- Modify: спека §4 «База данных»: v4 — только `app_settings`; `skill_states` и `mcp_servers` добавят планы этапов 5 и 6
- Test: `test/feature/app_settings/app_settings_test.dart`, `test/common/database/migration_test.dart` (+ v3 → v4)

**Interfaces:**
- Produces:
  - Таблица `app_settings`: `key TEXT PRIMARY KEY`, `value TEXT` (JSON), `updatedAt DATETIME default now`.
  - `@immutable final class AppSettings { const AppSettings({ThemeMode themeMode = ThemeMode.system, Locale? locale, bool sidebarVisible = true, bool? rightPaneVisible, double rightPaneWidth = 380, String defaultAgentId = 'claude'}); Map<String, Object?> toJson(); factory AppSettings.fromJson(Object? json); AppSettings copyWith(...); }` — `rightPaneVisible == null` значит «по ширине окна»; `fromJson` никогда не бросает: не-Map, отсутствующие поля, неизвестная тема/язык → значения по умолчанию; ширина зажимается в 340–560. Ручная сериализация (без json_serializable).
  - `abstract interface class IAppSettingsRepository { Stream<AppSettings> watch(); Future<void> update(AppSettings settings); }`; `final class AppSettingsRepositoryImpl({required this._database})` — одна строка с ключом `'app'`; `watch` — drift `watchSingleOrNull` → `AppSettings.fromJson(jsonDecode)` (ошибка декодирования → `const AppSettings()`).
  - `AppSettingsState` (freezed: `initial`, `inProgress`, `error({Object? error, required AppSettings settings})`, `completed({required AppSettings settings})`); `final class AppSettingsController extends StateController<AppSettingsState> with SequentialControllerHandler` — `void watch()`, `void update(AppSettings Function(AppSettings current) change)`, геттер `AppSettings get settings` (из любого состояния, иначе `const AppSettings()`). Комментарий: Sequential и для изменений — нельзя терять запись ширины панели.
  - `AppSettingsConfigWidget` + `AppSettingsConfigInhWidget.of(context) → AppSettingsConfigWidgetState` с полем `controller`.
- [ ] **Step 1: Write the failing tests**:
  - `'missing or broken settings fall back to defaults'`: `AppSettings.fromJson(null)`, `fromJson('oops')`, `fromJson({'themeMode': 'neon', 'rightPaneWidth': 9000})` → `themeMode == ThemeMode.system`, `rightPaneWidth == 560`.
  - `'settings round-trip through JSON'`: `AppSettings(themeMode: ThemeMode.dark, locale: Locale('ru'), sidebarVisible: false, rightPaneVisible: true, rightPaneWidth: 420)` → `fromJson(toJson())` равен исходному.
  - `'the repository stores one row and emits updates'` (drift in-memory): `watch()` первым отдаёт `const AppSettings()`; после `update(dark)` — `themeMode == ThemeMode.dark`; строк в таблице — 1.
  - `'a row with invalid JSON reads as defaults'`: вставить `value: '{'` → `watch().first` == `const AppSettings()`.
  - `'dark mode applies to the app'` (виджет): `AppSettingsConfigWidget` + `App`-подобный `MaterialApp` с `themeMode` из контроллера; `update(dark)` → `Theme.of(context).brightness == Brightness.dark`.
  - В `migration_test.dart`: `'v3 → v4 matches the v4 schema and keeps chats'` — как тест v2 → v3.
- [ ] **Step 2: Run** `flutter test test/feature/app_settings test/common/database` — FAIL.
- [ ] **Step 3: Implement** таблицу, миграцию (`from3To4: m.createTable(schema.appSettings)`), модель, репозиторий, контроллер, config-widget; подключить в `App` (`themeMode`, `locale`) и обернуть приложение.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "App settings stored in drift (schema v4)"`.

### Task 5: Каркас окна: шапка, экраны, панели, горячие клавиши

**Files:**
- Modify: `lib/src/feature/workspace/widgets/controllers/workspace_data_controller.dart` (экран окна)
- Create: `lib/src/feature/workspace/widgets/app_title_bar.dart`, `workspace_right_pane.dart`, `workspace_page_scaffold.dart`, `workspace_skills_page.dart`, `workspace_settings_page.dart`, `workspace_shortcuts.dart`
- Modify: `lib/src/feature/workspace/widgets/workspace_widget.dart` (новая раскладка), `workspace_config_widget.dart` (доступ к `AppSettingsController`)
- Delete: `lib/src/feature/workspace/widgets/workspace_run_panel.dart` (нижняя панель уходит во вкладку Run)
- Modify: arb (`toggleSidebar`, `toggleRightPane`, `backToChat`, `skills`, `settings`, `paneChanges`, `paneRun`, `panePlan`, `settingsGeneral`, `settingsAgents`, `settingsMcp`, `settingsPermissions`, `settingsFlutter`, `settingsAppearance`, `settingsShortcuts`, `skillsAndRules`, `rules`)
- Test: `test/feature/workspace/workspace_shell_test.dart`

**Interfaces:**
- Consumes: `AppSettingsController.settings/update` (Task 4), `PaneTabs`, `EmptyState`, `PreviewBadge` (Task 3), `context.colors` (Task 1).
- Produces:
  - `enum WorkspaceView { chat, skills, settings }`; `enum RightPaneTab { changes, run, plan }`; в `WorkspaceDataController`: `WorkspaceView get view`, `void openView(WorkspaceView view, {String? section})`, `String? get section`, `void backToChat()`, `RightPaneTab get paneTab`, `void selectPaneTab(RightPaneTab tab)`.
  - `class AppTitleBar extends StatelessWidget { const AppTitleBar({required Widget title, List<Widget> leading = const [], List<Widget> trailing = const []}); }` — высота 38 (`kWindowTitleBarHeight`), фон `surface`, нижняя граница `border`, отступ 78 px слева под светофор macOS, вся шапка — `DragToMoveArea`.
  - `class WorkspacePageScaffold extends StatelessWidget { const WorkspacePageScaffold({required String title, required List<(String id, IconData icon, String label)> sections, required String selected, required ValueChanged<String> onSelect, required Widget child}); }` — шапка «← Чат» + заголовок, навигация 220 px (уже 1100 px окна — 56 px, только иконки с tooltip), контент по центру `maxWidth: 640`, отступы 32, прокрутка.
  - `WorkspaceSkillsPage`, `WorkspaceSettingsPage` — разделы из спеки §3.7/3.8; содержимое каждого раздела пока `EmptyState(badge: PreviewBadge(), message: comingInMilestone(...))` (этапы 5 и 6 его заменят).
  - `WorkspaceRightPane` — `PaneTabs` (Изменения / Run / План), содержимое вкладок — `EmptyState` (этап 4 заменит); левый край — ручка перетаскивания ширины 4 px, курсор `resizeColumn`, ширина зажата 340–560 и пишется в настройки по окончании перетаскивания.
  - `WorkspaceShortcuts` — `CallbackShortcuts` над экраном: ⌘\ `sidebarVisible`, ⌘J `rightPaneVisible`, ⌘, `openView(settings)`, Esc → `backToChat()` только если `view != chat`.
  - Видимость правой панели: `settings.rightPaneVisible ?? (windowWidth >= 1100)`; ⌘J пишет явное значение.
  - Кнопки устройства/▶ Run/⚡ в шапке, ⌘R и ⇧⌘R появятся в плане этапа 4 (Run), ⇧Tab — в плане этапа 3 (поле ввода).
- [ ] **Step 1: Write the failing tests** `workspace_shell_test.dart` (через `testApp` + `useDesktopView`/размер окна):
  - `'1280×800 shows sidebar, chat and the right pane'`: найдены `WorkspaceSidebar`, `WorkspaceRightPane`; ширина сайдбара 236.
  - `'900×600 fits with every panel open'`: окно 900×600, `rightPaneVisible: true` в настройках → `tester.takeException()` равно `null`.
  - `'below 1100 px the right pane starts closed'`: окно 1000×700, настройки по умолчанию → `WorkspaceRightPane` не найден.
  - `'⌘\\ and ⌘J toggle the panels and are saved'`: сочетания → панели скрыты, `controller.settings.sidebarVisible == false`, `rightPaneVisible == false`; работает и при фокусе в `TextField`.
  - `'dragging the pane edge clamps 340–560'`: drag на −500 → ширина 560; на +500 → 340; в настройках то же значение.
  - `'⌘, opens Settings and Esc returns to the same chat'`; `'Esc with a menu open keeps Settings open'` (открыть `showAppMenu` на странице, Esc → меню закрыто, `view == settings`).
  - `'the settings page narrows its navigation under 1100 px'`: при 1000×700 у навигации ширина 56.
- [ ] **Step 2: Run** `flutter test test/feature/workspace/workspace_shell_test.dart` — FAIL.
- [ ] **Step 3: Implement** состояние экрана в `WorkspaceDataController`, `AppTitleBar` (слева: переключатель сайдбара; заголовок: название чата · проект; справа: переключатель панели), раскладку `WorkspaceWidget`, страницы, правую панель, `WorkspaceShortcuts`; удалить `workspace_run_panel.dart`.
- [ ] **Step 4: Run** новые тесты и `flutter test test/feature/workspace` — PASS (обновить `workspace_test.dart` под новые подписи); `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Window shell: title bar, right pane, Skills and Settings screens, shortcuts"`.

### Task 6: Сайдбар: чаты по проектам

**Files:**
- Modify: `lib/src/feature/sessions/data/sessions_repository.dart` (+ `watchAllSessions`), `controller/sessions_controller.dart` (+ `watchAll`, состояние со всеми чатами)
- Modify: `lib/src/feature/projects/data/projects_repository.dart` (+ `remove`), `controller/projects_controller.dart` (+ `remove`)
- Modify: `lib/src/feature/workspace/widgets/workspace_sidebar.dart`; Create: `workspace_project_group.dart`, `workspace_sidebar_footer.dart`; Delete: `workspace_projects_list.dart` (группы его заменяют); переписать `workspace_chats_list.dart` в строку чата `workspace_chat_tile.dart`
- Modify: `workspace_config_widget.dart` (`createChat` — в проекте выбранного чата, иначе в выбранном проекте; `revealProject`, `removeProject`)
- Modify: arb (`newChat` с хоткеем, `search`, `addProject`, `openFolder`, `newFlutterProject`, `cloneFromGit`, `showInFinder`, `projectSettings`, `removeProject`, `removeProjectConfirm(name)`: «Remove {name}? Its chats are deleted; files on disk stay.» / «Убрать {name}? Его чаты удалятся, файлы на диске останутся.»)
- Test: `test/feature/workspace/workspace_sidebar_test.dart`

**Interfaces:**
- Consumes: `StatusDot`/`AppStatusTone` (Task 3), `showAppMenu` (Task 2), `WorkspaceDataController.openView` (Task 5).
- Produces:
  - `ISessionsRepository.watchAllSessions() → Stream<List<ChatSession>>` — все чаты, `updatedAt` по убыванию; `SessionsController.watchAll()`; состояние `Sessions$CompletedState` получает список всех чатов (поле `projectId` убрать; потребители фильтруют сами).
  - `IProjectsRepository.remove(int projectId) → Future<void>` (каскад удаляет чаты и события).
  - `AppStatusTone statusTone(SessionStatus status)` в `workspace_chat_tile.dart`: `running/starting/loading/creating/cancelling → active`, `awaitingPermission → warn`, `error/setupFailed/needsAuth → danger`, иначе `none`.
  - Группа проекта: заголовок (имя, ▸/▾ сворачивание в памяти, ⋯ меню: Показать в Finder (`open -R <path>` через `Process.run('open', ['-R', path])` в `ProjectsRepositoryImpl.reveal`), Настройки проекта (`openView(skills)`), Убрать… с диалогом подтверждения); строки чатов с многоточием; «Новый чат» в группе при наведении.
  - Верх: «Новый чат ⌘N», «Поиск ⌘K» (открывает Task 7); «＋ Проект ▾» → Открыть папку… (как сейчас) / Новый Flutter-проект… и Клонировать из git… — снекбар `comingInMilestone('M4')`.
  - Низ (`WorkspaceSidebarFooter`): «Скиллы», «Настройки» → `openView`, строка агента по умолчанию (имя агента из `AppSettings.defaultAgentId`).
  - ⌘N в `WorkspaceShortcuts` → `createChat()`.
- [ ] **Step 1: Write the failing tests**:
  - `'chats are grouped under their projects'`: два проекта, по два чата → под заголовком `avera-hotel` его чаты, порядок по `updatedAt`.
  - `'a long title ends with an ellipsis'` и `'a hundred chats scroll without overflow'` (900×600, `takeException() == null`, последний чат достижим `scrollUntilVisible`).
  - `'collapsing a project hides its chats'`.
  - `'status tones follow the session status'` (юнит на `statusTone`, все значения `SessionStatus`).
  - `'removing a project asks first and deletes its chats'`: ⋯ → Убрать → Отмена → проект остался; ещё раз → Убрать → проекта и его чатов нет в drift.
  - `'⌘N creates a chat in the selected chat's project'`.
- [ ] **Step 2: Run** `flutter test test/feature/workspace/workspace_sidebar_test.dart` — FAIL.
- [ ] **Step 3: Implement** репозиторные методы, контроллеры, виджеты сайдбара.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Sidebar: chats grouped by project"`.

### Task 7: Поиск по чатам ⌘K

**Files:**
- Create: `lib/src/feature/chat_search/models/chat_search_result.dart`, `data/chat_search_repository.dart`, `controller/chat_search_controller.dart`, `widgets/chat_search_dialog.dart`
- Modify: `workspace_shortcuts.dart` (⌘K), `workspace_sidebar.dart` (строка «Поиск»), arb (`searchChats`, `noSearchResults`)
- Test: `test/feature/chat_search/chat_search_test.dart`

**Interfaces:**
- Produces:
  - `@immutable final class ChatSearchResult { const ChatSearchResult({required int sessionId, required int projectId, required String title, required String projectName, required DateTime updatedAt}); }`
  - `abstract interface class IChatSearchRepository { Future<List<ChatSearchResult>> search(String query, {int limit = 20}); }`; `ChatSearchRepositoryImpl({required this._database})` — join `sessions`/`projects`, без учёта регистра, `LIKE ? ESCAPE '\'` с экранированием `\`, `%`, `_`; пустой запрос → последние 20 чатов.
  - `ChatSearchController` (Droppable не подходит — новый запрос важнее старого; Sequential с отбрасыванием устаревших ответов по счётчику запроса), состояния `initial / inProgress / completed({required String query, required List<ChatSearchResult> results}) / error`.
  - `Future<ChatSearchResult?> showChatSearch(BuildContext context)` — диалог 560 px: поле, результаты (название, проект, дата), ↑/↓/↵, Esc; выбор → `selectProject` + `selectSession`.
- [ ] **Step 1: Write the failing tests**:
  - `'search matches titles regardless of case'`: «Экран бронирования» находится по `бронир` и `БРОНИР`.
  - `'wildcards are searched literally'`: чаты `100% done`, `100 done`, `a_b`, `ab` → `'%'` находит только первый, `'_'` — только `a_b`, `"'"` не бросает.
  - `'an empty query lists recent chats'`.
  - `'⌘K opens search and Enter opens the chat'`: виджет-тест, ввод, ↓, ↵ → `dataController.sessionId` равен найденному.
- [ ] **Step 2: Run** `flutter test test/feature/chat_search` — FAIL.
- [ ] **Step 3: Implement** модель, репозиторий, контроллер, диалог, хоткей.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "Chat search (⌘K)"`.

### Task 8: Финальная проверка фундамента

**Files:**
- Modify: `CLAUDE.md` (строка в «Architecture rules»: дизайн-токены — `lib/src/common/design/`, общие виджеты — `lib/src/common/widget/`, цвета только через `context.colors`, без хардкода `Color(0x…)` в фичах)
- Modify: существующие виджеты фич, которые красят хардкодом (`grep -rn "Color(0x\|Colors\." lib/src/feature`) — перевести на `context.colors`
- Test: весь набор

- [ ] **Step 1: Run** `grep -rn "Color(0x" lib/src/feature` — Expected после правок: пусто.
- [ ] **Step 2: Run** `flutter analyze` — No issues; `flutter test` — All tests passed.
- [ ] **Step 3: Run** `flutter build macos --debug` — `✓ Built`.
- [ ] **Step 4: Run** приложение (`flutter run -d macos`), пройти: светлая/тёмная тема (через настройки системы), 1280×800 и минимальное окно, ⌘\ ⌘J ⌘, ⌘K ⌘N Esc; записать найденное в отчёт этапа. Если нет доступа к окну — сказать об этом пользователю, а не утверждать.
- [ ] **Step 5: Commit** `git commit -m "Use design tokens across features"`.
