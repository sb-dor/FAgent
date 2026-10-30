# UI Stage 3 (chat and composer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Этап 3 спеки: лента в новом оформлении, поле ввода с чипами агента/модели/режима и меню «/», новая карточка разрешения — как в макете `docs/design/2-composer.html`.

**Architecture:** Модель ленты (`ChatTranscript`, `ChatItem`) расширяется минимально (длительность размышлений, команды агента в `ChatView`); группировка и подсветка — чистые функции в `chat/models/`. Чипы поля ввода строятся из `configOptions` агента в `session_config/widgets/`, меню — через `showAppMenu`. Модель/режим по умолчанию для новых чатов хранятся в `AppSettings` и применяются в `AgentHub` сразу после `session/new`, до отправки первого промпта.

**Tech Stack:** Flutter (macOS), control, freezed, drift, gen-l10n en/ru, file_selector (уже в зависимостях).

**Spec:** `docs/superpowers/specs/2026-10-28-ui-system-design.md` §3.3–3.5 (макет `docs/design/2-composer.html`). Предыдущий план: `docs/superpowers/plans/2026-10-28-ui-foundation.md`; отложенное: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md`.

**Что из §3.3–3.5 переносится и почему** (Task 7 записывает это в спеку):
- чип «🧩 N» и меню F, строка «🧩 Скилл X» в ленте — этап 5 (нет хранилища скиллов);
- секция «Из запуска» в меню «@» (виджет, ошибка, скриншот) и клик по правке → diff в правой панели — этап 4 (Run и вкладка «Изменения»);
- смена агента в чате — M5 (сейчас есть только Claude; чип агента показывает его, другие — недоступны).

## Global Constraints

- Архитектура — `docs/AI_INSTRUCTIONS.md` с отличиями `CLAUDE.md`: репозитории `abstract interface` + `Impl({required this._x})`; виджеты не трогают репозитории и `AgentHub`; Sequential для load/watch, Droppable для мутаций.
- Цвета только `context.colors`, радиусы только `AppRadius` (6/10/14), шаг 4 px, моноширинный текст — `AppText.mono`; Material Icons; новых пакетов нет.
- Лента ≤ 720 px по центру (сейчас 860 — исправить); поле ввода — та же колонка, радиус 14.
- Все строки — `intl_en.arb` и `intl_ru.arb`; у кнопок-иконок `tooltip`.
- Режим `bypassPermissions` никогда не включается без диалога подтверждения: ни из «по умолчанию», ни по ⇧Tab.
- `flutter analyze` чистый; коммиты заканчиваются `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Текущая модель агента отсутствует в списке вариантов (Claude отдаёт `currentValue: 'opusplan'`, которого нет в `options`) — чип показывает её как есть, в меню ничего не отмечено, выбор другой модели работает (Task 3).
2. Сохранённая модель «по умолчанию» больше не предлагается агентом или значение битое — её молча пропускают, чат создаётся и промпт уходит (Task 2).
3. `availableCommands` огромный (сотни команд, ~38 КБ) или с битыми записями — меню «/» фильтрует без задержек, битые записи пропускаются, не падает (Task 4).
4. Ждёт разрешение, а в поле ввода набран черновик: ↵ не одобряет действие, а Esc не отклоняет — клавиши разрешения работают только при пустом поле (Task 6).
5. ⇧Tab перебирает режимы и никогда не попадает на `bypassPermissions` (Task 3).

---

### Task 1: AppMenu: поиск, интерактивный подвал, мелкие исправления

**Files:**
- Modify: `lib/src/common/widget/app_menu.dart`
- Test: `test/common/widget/app_menu_test.dart`

**Interfaces:**
- Produces:
  - `showAppMenu<T>({…, bool searchable = false, String? searchHint, Widget Function(BuildContext context, void Function(T? value) close)? footerBuilder})` — `footer` заменяется на `footerBuilder` (обновить вызовы); `close(value)` закрывает меню с результатом.
  - При `searchable` над секциями — поле поиска в фокусе; фильтр по `title` и `subtitle` без учёта регистра (Dart `toLowerCase().contains`); пустые после фильтра секции скрываются; ↑/↓/↵ работают из поля.
- Отложенное из `ui-foundation-followups.md` (Task 2 там), исправить здесь: выбранный пункт прокручивается в видимую область при открытии; пустой `sections` (или все секции без пунктов) у `SelectorChip` ведёт себя как `sections: null`; тень меню — от токена (`context.colors.text.withValues(alpha: 0.12)`), без `Color(0x…)`.

- [ ] **Step 1: Write the failing tests**:
  - `'a searchable menu filters items as you type'`: пункты `Opus 5.5`, `Sonnet 5.5`, `Haiku 5.5`; ввод `son` → виден только `Sonnet 5.5`; ↵ → выбран `'sonnet'`.
  - `'search ignores case and hides empty sections'`: две секции, запрос `HAI` → видна одна секция.
  - `'the footer closes the menu with a value'`: `footerBuilder` с кнопкой, вызывающей `close('x')` → результат `'x'`.
  - `'the selected item is scrolled into view'`: 40 пунктов, выбран 35-й, высота вида 400 → `find.text('Item 35')` попадает в видимую область (`tester.getRect` внутри окна).
  - `'a chip with empty sections acts like a plain chip'`: `sections: const []` → tap вызывает `onPressed`, меню не открывается.
- [ ] **Step 2: Run** `flutter test test/common/widget/app_menu_test.dart` — FAIL.
- [ ] **Step 3: Implement** поиск, `footerBuilder`, прокрутку при открытии, пустые секции, тень.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze` — No issues.
- [ ] **Step 5: Commit** `git commit -m "AppMenu: search, interactive footer, scroll to selection"`.

### Task 2: Модель и режим по умолчанию для новых чатов

**Files:**
- Modify: `lib/src/feature/app_settings/models/app_settings.dart` (+ поле), `lib/src/common/acp/agent_hub.dart` (`_create`), `lib/src/feature/initialization/data/initialize_dependencies.dart` (передать источник), `lib/src/feature/workspace/widgets/workspace_config_widget.dart` (`createChat` берёт `settings.defaultAgentId` вместо `'claude'`)
- Test: `test/feature/app_settings/app_settings_test.dart`, `test/common/acp/agent_hub_test.dart`

**Interfaces:**
- Produces:
  - `AppSettings.sessionDefaults: Map<String, Map<String, String>>` (agentId → configId → value), по умолчанию пусто; JSON-ключ `'sessionDefaults'`; `fromJson` пропускает не-строковые ключи/значения и **никогда не хранит** `mode: 'bypassPermissions'` (выбрасывает при чтении и в `copyWith`/`update`).
  - `AgentHub({…, Future<Map<String, String>> Function(String agentId)? sessionDefaults})`; в `_create` после `session/new`: для каждого `(configId, value)` из `sessionDefaults(agentId)`, если опция с этим id есть, `value` входит в её варианты, отличается от `currentValue` и это не `mode == bypassPermissions`, — `setSessionConfigOption` (тот же поток, до перехода в `idle`), `configOptions` обновляются из ответа. Ошибка чтения или установки — `l.w`, создание чата не падает.
  - В `initialize_dependencies.dart`: `sessionDefaults: (agentId) async => (await AppSettingsRepositoryImpl(database: d.database).watch().first).sessionDefaults[agentId] ?? const {}`.
- [ ] **Step 1: Write the failing tests**:
  - `'session defaults round-trip and never keep bypass'`: `fromJson({'sessionDefaults': {'claude': {'model': 'sonnet', 'mode': 'bypassPermissions'}, 'x': 5}})` → `{'claude': {'model': 'sonnet'}}`.
  - Хаб (фейковый агент, у него есть `mode`): `'a new chat starts in the default mode'` — `sessionDefaults: (_) async => {'mode': 'acceptEdits'}` → после `prompt(chat, 'echo hi')` `configOptions` `mode` == `acceptEdits` и ответ `hi` получен.
  - `'a bypass or unknown default is ignored'` — `{'mode': 'bypassPermissions'}` и `{'mode': 'nope', 'model': 'x'}` → режим `default`, промпт ушёл.
  - `'a failing defaults source does not block the chat'` — источник бросает → промпт ушёл.
  - `'⌘N uses the default agent'` (workspace-тест) — `defaultAgentId` из настроек попадает в `sessions.agentId` нового чата.
- [ ] **Step 2: Run** `flutter test test/feature/app_settings test/common/acp/agent_hub_test.dart` — FAIL.
- [ ] **Step 3: Implement** поле, применение в `_create`, проводку источника, `createChat`.
- [ ] **Step 4: Run** тесты и `flutter test test/feature/workspace` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Default model and mode for new chats"`.

### Task 3: Поле ввода с чипами (меню A и B), ⇧Tab, «＋»

**Files:**
- Create: `lib/src/feature/session_config/widgets/composer_toolbar.dart` (чипы), `lib/src/feature/session_config/models/config_roles.dart` (поиск ролей опций)
- Modify: `lib/src/feature/prompt_sending/widgets/prompt_composer.dart` (ряд инструментов, ⇧Tab, новый плейсхолдер), `lib/src/feature/chat/widgets/chat_screen.dart` (убрать `SessionConfigBar`, передать тулбар), `lib/src/feature/chat/widgets/chat_config_widget.dart` (`attachFile`, `cycleMode`, `saveAsDefaults`), `lib/src/feature/session_config/controller/session_config_controller.dart` (сохранение умолчаний через новый метод репозитория)
- Delete: `lib/src/feature/session_config/widgets/session_config_bar.dart` (её логика — в тулбаре; тесты перенести)
- Modify: arb (`promptHint`: «Ask the agent… @ file · / skill or command» / «Спроси агента… @ файл · / скилл или команда»; `attach`, `agentLabel`, `modelLabel`, `effortLabel`, `modeLabel`, `makeDefaultForNewChats`, `availableAfterStart`, `attachOutsideProject`)
- Test: `test/feature/session_config/composer_toolbar_test.dart`, `test/feature/prompt_sending/prompt_composer_test.dart`

**Interfaces:**
- Consumes: `showAppMenu(searchable, footerBuilder)` (Task 1), `SelectorChip`, `AppTone`, `SegmentedControl`; `AppSettings.sessionDefaults` (Task 2).
- Produces:
  - `config_roles.dart`: `SelectConfigOption? modelOption(List<ConfigOption>)` (id `model` или category `model`), `SelectConfigOption? effortOption(…)` (id `effort` или category `thought_level`), `permissionModeOf` уже есть; `List<String> cycleModes(SelectConfigOption mode)` — варианты без `bypassPermissions` в исходном порядке.
  - `PromptComposer({…, List<Widget> toolbar = const [], VoidCallback? onCycleMode})` — под текстом ряд `toolbar` слева и кнопка отправки/стоп справа; ⇧Tab в поле → `onCycleMode`.
  - `ComposerToolbar({required String agentName, required bool agentLocked, required List<ConfigOption> options, required bool enabled, required void Function(String configId, Object value) onChanged, required VoidCallback onAttach, required VoidCallback onMakeDefault})`:
    - «＋» (tooltip `attach`) → `onAttach`;
    - чип агента — меню: агент чата ✓; Codex и Gemini — `enabled: false`, подпись `comingInMilestone('M5')`;
    - чип модели — `searchable` меню моделей; в подвале `SegmentedControl` усилия (если есть `effortOption`) и `CheckboxListTile` `makeDefaultForNewChats` → `onMakeDefault`; надпись чипа — `currentName` модели (если значения нет в вариантах — сырое значение);
    - чип режима — меню B (иконка, название, подпись варианта), тон `warn` для `acceptEdits`/`auto`, `danger` для `bypassPermissions`; выбор bypass — тот же диалог подтверждения, что был в `SessionConfigBar`;
    - остальные `select`/`boolean`/неизвестные опции — как в прежнем `SessionConfigBar`;
    - нет `options` (агент ещё не стартовал) — чипы модели и режима недоступны с tooltip `availableAfterStart`.
  - `ChatConfigWidgetState.cycleMode()` — следующий из `cycleModes` после текущего (по кругу) через `setConfig`; `attachFile()` — `openFile(initialDirectory: project.path)`, файл внутри проекта (через `fileMentionController.insideProject`) → вставка `@<relative> ` в позицию курсора, иначе SnackBar `attachOutsideProject`; `makeDefault()` — пишет в `AppSettings.sessionDefaults[agentId]` текущие `model`, `effort`, `mode` (без bypass) через новый `ISessionConfigRepository.saveDefaults(String agentId, Map<String, String> values)`. Реализация: `SessionConfigRepositoryImpl({required this._hub, required this._settings})`, где `_settings` — `IAppSettingsRepository`; читает текущие настройки `watch().first`, заменяет `sessionDefaults[agentId]`, пишет `update(...)` (контроллер настроек примет это как внешнее изменение). Контроллер — Droppable-метод `SessionConfigController.saveDefaults(String agentId, Map<String, String> values)`.
- [ ] **Step 1: Write the failing tests**:
  - `'the model chip shows a value the agent does not list'`: `currentValue: 'opusplan'` → чип `opusplan`; меню без галочек; выбор `Sonnet 5.5` → `onChanged('model', 'sonnet')`.
  - `'effort is picked in the model menu footer'` → `onChanged('effort', 'high')`.
  - `'the mode chip is coloured by risk'`: `acceptEdits` → фон `warnSoft`; `bypassPermissions` → `dangerSoft`.
  - `'choosing bypass still asks first'` (перенос из старого теста бара: Cancel → ничего, Allow → `onChanged('mode', 'bypassPermissions')`).
  - `'⇧Tab cycles modes and skips bypass'` (`cycleModes` юнит + виджет: из `auto` следующий — `default`).
  - `'without options the model and mode chips are disabled'`.
  - `'make default saves model, effort and mode but not bypass'` (контроллер/репозиторий с фейковым хранилищем).
  - `'the composer keeps Enter to send and Shift+Enter for a new line'` — существующие тесты композера проходят с тулбаром.
- [ ] **Step 2: Run** `flutter test test/feature/session_config test/feature/prompt_sending` — FAIL.
- [ ] **Step 3: Implement** роли опций, тулбар, изменения композера и экрана чата, `attachFile`/`cycleMode`/`makeDefault`; удалить `session_config_bar.dart`.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Composer toolbar: agent, model, effort and mode chips"`.

### Task 4: Меню «/» — команды приложения и агента

**Files:**
- Create: `lib/src/feature/prompt_sending/models/slash_command.dart`
- Modify: `lib/src/feature/chat/models/chat_view.dart` (+ `commands`), `lib/src/feature/chat/controller/chat_controller.dart` (слушать `session.availableCommands`), `lib/src/feature/prompt_sending/widgets/prompt_composer.dart` (подсказки «/»)
- Modify: arb (`slashSectionApp`, `slashSectionAgent`, `commandRun`, `commandReload`, `commandRestart`, `commandScreenshot` — подписи)
- Test: `test/feature/prompt_sending/slash_command_test.dart`, `test/feature/prompt_sending/prompt_composer_test.dart`

**Interfaces:**
- Produces:
  - `@immutable final class SlashCommand { const SlashCommand({required String name, String? description, required SlashSource source, bool enabled = true, String? hint}); }`, `enum SlashSource { app, agent }`.
  - `List<SlashCommand> agentCommands(List<Map<String, Object?>> raw)` — из ACP `availableCommands` (`name` строка без пробелов, `description` строка или null); битые записи пропускаются; дубликаты по имени — первый.
  - `const appCommands` — `run`, `reload`, `restart`, `screenshot`, все `enabled: false`, `hint: comingInMilestone('M2')` (подставляется в виджете).
  - `List<SlashCommand> searchCommands(List<SlashCommand> all, String query, {int limit = 12})` — префикс имени, затем вхождение в имя, затем в описание; без учёта регистра.
  - `ChatView.commands: List<SlashCommand>` (только агентские; приложение добавляет свои в виджете).
  - Композер: «/» в начале текста (позиция 0) открывает список с секциями «Приложение» / «Агент» (тот же стиль, что подсказки `@`); ↑/↓, ↵/Tab вставляет `/<name> ` вместо набранного, Esc закрывает; недоступные пункты видны с подсказкой, не вставляются.
- [ ] **Step 1: Write the failing tests**:
  - `'agent commands are parsed and broken entries skipped'`: `[{'name':'compact','description':'Compact'}, {'name': 5}, {'description':'x'}, {'name':'compact'}, {'name':'init'}]` → `compact`, `init`.
  - `'search ranks name prefix, then name, then description'`.
  - `'a large command list filters quickly'`: 600 команд → `searchCommands(..., 'rev')` возвращает ≤ 12 и тест укладывается в обычное время (без таймеров — просто проверка результата).
  - `'typing / at the start suggests commands and Enter inserts one'` → текст `/compact `.
  - `'a / in the middle of text is not a command'`.
  - `'app commands are shown but not inserted'`: выбор `/run` → текст не меняется, видна подпись M2.
- [ ] **Step 2: Run** `flutter test test/feature/prompt_sending` — FAIL.
- [ ] **Step 3: Implement** модель, парсинг, поиск, `ChatView.commands`, подсказки в композере.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Slash menu: app and agent commands"`.

### Task 5: Лента в новом оформлении

**Files:**
- Create: `lib/src/feature/chat/models/feed_grouping.dart`, `lib/src/feature/chat/models/mention_spans.dart`
- Modify: `lib/src/feature/chat/models/chat_item.dart` (`AgentThoughtItem.duration`), `chat_transcript.dart` (длительность из `createdAt` первого и последнего куска), `widgets/chat_feed.dart` (колонка 720, группы), `widgets/chat_item_view.dart`, `widgets/tool_call_card.dart`
- Modify: arb (`thinkingFor(seconds)`: «Thinking · {seconds} s» / «Размышления · {seconds} с»; `readFiles(count)` plural: «Read {count} files» / «Прочитал {count} файл(а/ов)» по формам ru)
- Test: `test/feature/chat/feed_grouping_test.dart`, `test/feature/chat/chat_transcript_test.dart`, `test/feature/chat/chat_item_view_test.dart`

**Interfaces:**
- Produces:
  - `sealed class FeedEntry`; `final class SingleEntry(ChatItem item)`; `final class ReadGroupEntry(List<ToolCallItem> calls)`; `List<FeedEntry> groupFeed(List<ChatItem> items)` — 2+ подряд идущих `ToolCallItem` с `kind == 'read'` и статусом не `failed` → одна группа; остальное как есть.
  - `AgentThoughtItem({…, Duration? duration})` — время между первым и последним куском этого `messageId`; `null`, если кусок один.
  - `List<InlineSpan> mentionSpans(String text, List<String> resourceUris, {required TextStyle pill})` — `@<path>` подсвечивается плашкой, если какой-то URI заканчивается на `/<path>`; остальной текст — обычные `TextSpan`.
  - Строка инструмента: иконка, заголовок, моно-путь первой `locations`, для правок счётчик `+N −M` (сумма `LineDiff.stats(LineDiff.compute(old, new))` по diff-ам, `lib/src/common/utils/line_diff.dart`, цвета `ok`/`danger`), статус; раскрытие — как сейчас. Группа чтения — строка «Прочитал N файлов», раскрывается списком путей.
  - Размышления — свёрнутая строка `thinkingFor(сек)` (или `thinking`, если длительности нет).
  - Сообщение пользователя — текст с `mentionSpans`; строки `@файл` под текстом больше не рисуются.
- [ ] **Step 1: Write the failing tests**:
  - `'consecutive reads collapse into one group'` (3 read + edit + 1 read → group(3), edit, single read).
  - `'a failed read is not grouped'`.
  - `'thought duration comes from the chunk times'` (события с `createdAt` 0 с и 12 с → 12 с; один кусок → null).
  - `'mentions in a user message become pills'` (текст `fix @lib/a.dart now`, URI `file:///p/lib/a.dart` → три span, средний с фоном `accentSoft`).
  - `'an edit row shows added and removed lines'` (`+2 −1`).
  - `'the feed column is at most 720 px'` (при окне 1280).
  - Существующие тесты `chat_transcript_test.dart` проходят.
- [ ] **Step 2: Run** `flutter test test/feature/chat` — FAIL.
- [ ] **Step 3: Implement** модели и виджеты.
- [ ] **Step 4: Run** тесты — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Feed: compact tool rows, read groups, thinking time, mention pills"`.

### Task 6: Карточка разрешения и клавиши ↵ / Esc

**Files:**
- Modify: `lib/src/feature/permission_request/widgets/permission_card.dart`, `lib/src/feature/chat/models/chat_view.dart` (+ `pendingPermission`), `lib/src/feature/chat/widgets/chat_screen.dart`, `lib/src/feature/prompt_sending/widgets/prompt_composer.dart` (+ `onAcceptPending`, `onRejectPending`), `lib/src/feature/chat/widgets/chat_config_widget.dart` (`rejectAndSay`)
- Modify: arb (`permissionRunCommand` «Run this command?» / «Выполнить команду?», `permissionApplyEdits` «Apply these edits?» / «Применить правки?», `permissionRejectAndSay` «Reject and say…» / «Отклонить и сказать…»)
- Test: `test/feature/permission_request/permission_card_test.dart`, `test/feature/prompt_sending/prompt_composer_test.dart`

**Interfaces:**
- Produces:
  - `ChatView.pendingPermission: PermissionItem?` — последний `PermissionItem` в состоянии `pending`.
  - `PermissionCard({required PermissionItem item, required ValueChanged<String> onAnswer, VoidCallback? onRejectAndSay})`: заголовок — `permissionRunCommand`, если есть `command`; `permissionApplyEdits`, если есть diff; иначе `item.title`. Тело: команда (`AppText.mono` на `surfaceAlt`) или diff. Кнопки: первый `allow_once` — `FilledButton` с подсказкой «↵»; `allow_always` — `OutlinedButton` (название от агента); первый `reject_once` — `OutlinedButton` с подсказкой «Esc»; остальные варианты — `TextButton`; последней — `TextButton` `permissionRejectAndSay` (если передан колбэк).
  - `PromptComposer({…, VoidCallback? onAcceptPending, VoidCallback? onRejectPending})`: при **пустом** поле ↵ → `onAcceptPending`, Esc → `onRejectPending` (если не открыты подсказки); при непустом поле поведение прежнее.
  - `ChatConfigWidgetState.rejectAndSay(PermissionItem item)` — отвечает первым `reject_once` и ставит фокус в поле ввода.
- [ ] **Step 1: Write the failing tests**:
  - `'a command request asks to run the command'` (заголовок, моноблок, порядок и типы кнопок).
  - `'an edit request asks to apply the edits'`.
  - `'reject and say declines and focuses the composer'`.
  - `'with an empty composer Enter allows and Escape rejects'`.
  - `'with a draft in the composer Enter and Escape do not answer'` (Review Focus 4).
- [ ] **Step 2: Run** `flutter test test/feature/permission_request test/feature/prompt_sending` — FAIL.
- [ ] **Step 3: Implement** карточку, `pendingPermission`, клавиши, `rejectAndSay`.
- [ ] **Step 4: Run** `flutter test test/feature` — PASS; `flutter analyze`.
- [ ] **Step 5: Commit** `git commit -m "Permission card: titles by request type, keyboard answers"`.

### Task 7: Проверка этапа, спека и мелочи

**Files:**
- Modify: `lib/src/common/localization/intl_ru.arb` (`quitWhileBusyBody`: убрать перекрывающий вариант — оставить `one`/`few`/`many`/`other` по правилам ru, а «1 чате» дать формой `one`; предупреждение ICU при сборке должно исчезнуть)
- Modify: `docs/superpowers/specs/2026-10-28-ui-system-design.md` (§3.3–3.4: перенос «🧩 N»/меню F/строки скилла на этап 5, секции «Из запуска» и diff в панели на этап 4, смены агента на M5 — как в шапке этого плана)
- Modify: `docs/superpowers/plans/2026-10-28-ui-foundation-followups.md` (убрать пункты, закрытые Task 1 и Task 2)

- [ ] **Step 1: Run** `flutter pub get` — в выводе нет `ICU Syntax Warning`.
- [ ] **Step 2: Run** `flutter analyze` — No issues; `flutter test` — All tests passed; `flutter build macos --debug` — `✓ Built`.
- [ ] **Step 3: Run** `flutter run -d macos`, дождаться `Create agent hub` без исключений, остановить (`q`). Визуальную проверку — только если есть доступ к окну; иначе прямо написать, что она не сделана.
- [ ] **Step 4: Commit** `git commit -m "Stage 3 wrap-up: ru plural, spec and follow-ups"`.
