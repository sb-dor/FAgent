---
name: widgets
description: "Widget conventions, and how to write a widget test for a screen or control with fakes."
---

# Widgets

## Rules

- Observe a `ChangeNotifier` with `ListenableBuilder`, not `ValueListenableBuilder`.
- Use `const Foo({super.key})`. `StatefulWidget` for roots and anything owning controllers,
  focus, scroll or animation; `StatelessWidget` for small presentational widgets.
- Keep screen files short: split cards, rows, filters into files in the same folder. No `part`.
- UI-only state (filters, selection) lives in a `ChangeNotifier` data controller in
  `widgets/controllers/`.
- Where the project has desktop and mobile UIs, pick them with `context.screenSizeMaybeWhen`
  from `widgets/desktop/` and `widgets/mobile/`; add tablet only for a real tablet UI.
- Show an error with a retry button that calls the controller again.

## Widget test

Test behaviour the user sees, not the widget tree layout.

### Steps

1. Create `test/feature/<feature>/<widget>_test.dart` next to the other tests of the feature.
2. Replace services with in-memory fakes of the repository interfaces (`IFooRepository`), and pass
   them to the real controller. Do not mock the widget itself.
3. Wrap the widget in `MaterialApp` with `Localization.localizationsDelegates` and the app theme,
   so `Localization.of(context)` and the theme extensions work. Set the test window size
   (`tester.view.physicalSize`) to the screen size the widget targets, and reset it in `addTearDown`.
4. `await tester.pumpWidget(...)`, interact with `tester.tap` and `tester.enterText`, then
   `await tester.pump()` or `pumpAndSettle()`.
5. Assert on visible text and state: `find.text`, `find.byType`, the fake repository's calls.
6. Cover the empty, loading, error and filled states, and one failing action.

### Rules

- Dispose controllers in `tearDown`; leave no timers or streams open.
- Use `tester.runAsync` for real I/O such as assets or processes.
- Run with `flutter test test/feature/<feature>/`.
