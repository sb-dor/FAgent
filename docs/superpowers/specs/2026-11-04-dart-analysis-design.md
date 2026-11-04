# Анализ Dart в виде «Код»: автодополнение и ошибки

Ветка `dart-analysis` (от `main`). Следующий шаг вида «Код»
(`docs/superpowers/specs/2026-11-04-code-view-design.md`): редактор начинает понимать Dart через
Dart analysis server по LSP. В этой вехе — автодополнение со сниппетами и подчёркивание ошибок;
hover-документация, переход к определению и форматирование — следующая.

## Установленные факты (2026-11-04)

- `dart language-server` (Dart SDK внутри Flutter пользователя) запускает analysis server по LSP:
  stdin/stdout, сообщения с заголовком `Content-Length`. Сервер сам содержит сниппеты Flutter
  `stful`, `stless`, `stanim` (проверено в `analysis_server.dart.snapshot`) и шлёт статус анализа
  уведомлением `$/analyzerStatus` (`isAnalyzing`).
- Пакеты на pub.dev не подходят: `lsp_client` 0.1.2 (2024-06, заброшен), `analysis_server_lib`
  0.2.5 (2023, старый не-LSP протокол). Клиент пишем свой.
- В приложении уже есть `GroupedProcess` (`common/process/`, своя группа процессов, надёжно
  убивается) и `ShellEnvironment` (`PATH` из login shell) — по ним запускаются `flutter daemon` и
  агенты.
- `re_editor` 0.10.0:
  - `CodeAutocomplete(viewBuilder, promptsBuilder, child)` — всплывающий список у каретки со своими
    клавишами; `CodeAutocompletePromptsBuilder.build(context, codeLine, selection)` **синхронный**.
  - `CodeLineEditingController(codeLines:, options:, spanBuilder:)` — `CodeLineSpanBuilder`
    (`context, index, codeLine, textSpan, style`) меняет отрисовку строки (подчёркивания).
  - `MouseTrackerAnnotationTextSpan(onEnterWithRect, onExitWithRect)` — наведение на кусок строки
    (сообщение ошибки).

## 1. Что видит пользователь

- **Автодополнение (только `.dart`):**
  - список открывается сам после буквы или `.`, сужается при наборе; ⌃Space открывает где угодно;
    ↑↓ — выбор, Enter или Tab — вставить, Esc — закрыть;
  - строка: значок вида (класс, метод, поле, переменная, ключевое слово, сниппет), подпись
    (`StatefulWidget`, `setState`) и справа тип или сигнатура приглушённым;
  - `int`, `String`, классы проекта и пакетов, члены после `.`, именованные параметры;
  - выбор класса из ещё не импортированного пакета добавляет `import` (дополнительные правки
    сервера);
  - сниппеты сервера (`stful`, `stless`, `stanim`, `main`, `for` …): вставка с подстановками,
    каретка на первой; Tab / ⇧Tab — следующая / предыдущая; одинаковые подстановки меняются вместе
    (имя виджета и его `State`); Esc или уход каретки за сниппет — конец режима.
- **Ошибки и предупреждения:**
  - волнистое подчёркивание диапазона сервера: ошибка — `danger`, предупреждение — `warn`,
    подсказка — `muted`;
  - наведение на подчёркнутое — всплывающая подсказка: сообщение и код (`undefined_identifier`);
  - вкладка: «ⓧ 2 ⚠ 1» рядом с именем; в проводнике файл с ошибками — цветом `danger`.
- **Несохранённый текст в счёт:** сервер видит текст редактора, а не диска; ошибки обновляются
  через 300 мс после остановки набора.
- **Подвал редактора:** «Анализ…» пока сервер запускается или анализирует; «Анализ Dart
  недоступен» с **Перезапустить**, если `dart` не найден или сервер упал. Редактор работает и без
  анализа.

## 2. Устройство

- `lib/src/common/dart_analysis/` — без импорта `feature/`:
  - `LspConnection` — кадры `Content-Length`, JSON-RPC: `request(method, params) → Future`
    (тайм-аут 10 с, `LspRequestException`), `notify(method, params)`, `Stream<LspNotification>`
    уведомлений, ответы на запросы сервера (`workspace/configuration` → пусто,
    `client/registerCapability` → ok), `close()`;
  - `DartAnalysisServer.start({required String root, required ShellEnvironment environment})` —
    `dart language-server --protocol=lsp --client-id=flutter_code_agent` в `GroupedProcess`,
    `initialize` (rootUri и workspaceFolders = проект; completion: `snippetSupport`,
    `resolveSupport` для `additionalTextEdits`, `documentationFormat` markdown; `publishDiagnostics`)
    и `initialized`; `dispose()` — `shutdown` + `exit`, затем kill группы через 2 с.
- Фича `code_view`:
  - `IDartAnalysisRepository` на проект — `open(path, text)`, `change(path, text)` (версия растёт
    сама), `close(path)`, `complete(path, line, character) → List<DartCompletion>`,
    `resolve(DartCompletion) → DartCompletion`, `Stream<DartFileDiagnostics> diagnostics`,
    `Stream<DartAnalysisStatus> status` (`starting`, `ready`, `analyzing`,
    `unavailable(reason)`), `restart()`, `dispose()`; поток по правилам «Stream-Returning
    Methods». Сервер запускается при первом открытом `.dart` файле проекта в «Коде» и живёт с
    `CodeWorkspace`; выход из приложения его гасит (реестр «Кода» закрывается в `shutdown`).
  - Модели: `DartCompletion` (label, kind, detail, filterText, sortText, вставка — текст или
    сниппет, диапазон замены, `additionalTextEdits`, данные для resolve), `DartDiagnostic`
    (диапазон, severity, сообщение, код).
  - `CodeDocument` знает `diagnostics`; `spanBuilder` контроллера рисует подчёркивания и
    подсказки из них. Синхронизация: `didOpen` при открытии вкладки, `didChange` полным текстом
    через 300 мс после правки и сразу перед запросом дополнения, `didClose` при закрытии.
  - `DartCompletionController` на вкладку: при правке буквой или `.` (и по ⌃Space) отправляет
    запрос для каретки; устаревший ответ (текст уже другой) отбрасывается. `CodeAutocomplete`
    берёт подсказки из последнего ответа; пришедший ответ обновляет открытый список. Выбор:
    замена диапазона, вставка сниппета, затем `additionalTextEdits` снизу вверх.
  - `SnippetSession` — разбор `$1`, `${1:имя}`, `${1|a,b|}` (первый вариант), `$0`; позиции
    подстановок сдвигаются при правках; одинаковые индексы зеркалятся.
- Риск: `CodeAutocomplete` синхронный, ответ LSP — нет. Первая задача плана проверяет
  «кэш + обновление списка при ответе»; если не выходит — свой список у каретки (позиция каретки
  из `CodeEditor`) с той же клавиатурой.

## Ошибки и края

| Случай | Поведение |
| --- | --- |
| `dart` не найден | «Анализ Dart недоступен», редактор без дополнения и ошибок |
| Сервер упал / не ответил на `initialize` за 30 с | То же, **Перезапустить** |
| Не-Dart файл | Ни дополнения, ни подчёркиваний |
| Проект не Dart (нет `pubspec.yaml`) | Сервер всё равно запускается (одиночные `.dart` анализируются) |
| Ответ дополнения пришёл после новой правки | Отбрасывается, уходит новый запрос |
| Пустой ответ | Список не открывается |
| Закрытие вкладки | `didClose`, её ошибки убираются из вкладки и проводника |
| Удаление проекта / выход | Сервер получает `shutdown`/`exit`, группа процессов убивается |
| Внешняя правка файла (агент) | Чистая вкладка перечитывается → `didChange` с новым текстом |

## Тестирование

- `LspConnection`: кадры (несколько сообщений в одном чанке, сообщение по частям, кириллица в
  `Content-Length` байтах), запрос-ответ, ошибка, тайм-аут, уведомления, запрос сервера, закрытие.
- Сервер и репозиторий — на поддельном LSP-сервере (Dart-скрипт в `test/support`, отвечает
  сценарием): `initialize`, `didOpen`/`didChange` с версиями, `complete`, `diagnostics`,
  `$/analyzerStatus`, падение → `unavailable`, `restart`, `dispose` убивает процесс.
- Сниппеты: разбор, Tab/⇧Tab, зеркала, `$0`, выход из режима; применение правки дополнения и
  `additionalTextEdits` (импорт сверху сдвигает строки).
- Виджеты: список открывается после буквы и `.`, сужается, Enter/Tab/Esc, ⌃Space; `stful` даёт
  виджет и каретку на имени; подчёркивания нужных цветов и подсказка; счётчик на вкладке;
  проводник; подвал «Анализ…» и «недоступен» с **Перезапустить**; 900×600 ru/en, светлая/тёмная.
- Настоящий `dart language-server` — opt-in тест (`DART_LSP_TEST=1`): `stful` в пустом файле и
  ошибка в `void main() { x; }`.

## Решения

- Свой LSP-клиент в `common/dart_analysis/` вместо пакетов; процесс — `GroupedProcess`.
- Один сервер на проект, пока открыт его «Код»; сниппеты — серверные, своих шаблонов нет.
- Список — `CodeAutocomplete` из `re_editor` с асинхронным кэшем; запасной путь — свой список.

## Не в этой вехе

Hover-документация, переход к определению (⌘-клик), форматирование при сохранении, quick fixes
(лампочка), переименование, панель «Проблемы» со списком всех ошибок проекта, анализ не-Dart
файлов.
