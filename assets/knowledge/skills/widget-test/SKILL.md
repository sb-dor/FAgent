---
name: widget-test
description: "Write a Flutter widget test for a screen or control, with fake controllers and repositories."
when_to_use: "When a widget or screen is added or changed and needs test coverage."
version: "1.0"
---

# Widget test

Test behaviour the user sees, not the widget tree layout.

## Steps

1. Create `test/feature/<feature>/<widget>_test.dart` next to the other tests of the feature.
2. Replace services with in-memory fakes of the repository interfaces (`IFooRepository`), and pass
   them to the real controller. Do not mock the widget itself.
3. Wrap the widget in `MaterialApp` with `Localization.localizationsDelegates` and the app theme,
   so `Localization.of(context)` and `context.colors` work. Give it a desktop-sized window.
4. `await tester.pumpWidget(...)`, interact with `tester.tap` and `tester.enterText`, then
   `await tester.pump()` or `pumpAndSettle()`.
5. Assert on visible text and state: `find.text`, `find.byType`, the fake repository's calls.
6. Cover the empty, loading, error and filled states, and one failing action.

## Rules

- Dispose controllers in `tearDown`; leave no timers or streams open.
- Use `tester.runAsync` for real I/O such as assets or processes.
- Run with `flutter test test/feature/<feature>/`.
