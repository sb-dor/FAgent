---
name: widgets
description: "Widget conventions: ListenableBuilder, super.key, file splitting, responsive screens."
---

# Widgets

- Observe a `ChangeNotifier` with `ListenableBuilder`, not `ValueListenableBuilder`.
- Use `const Foo({super.key})`. `StatefulWidget` for roots and anything owning controllers,
  focus, scroll or animation; `StatelessWidget` for small presentational widgets.
- Keep screen files short: split cards, rows, filters into files in the same folder. No `part`.
- UI-only state (filters, selection) lives in a `ChangeNotifier` data controller in
  `widgets/controllers/`.
- Where the project has desktop and mobile UIs, pick them with `context.screenSizeMaybeWhen`
  from `widgets/desktop/` and `widgets/mobile/`; add tablet only for a real tablet UI.
- Show an error with a retry button that calls the controller again.
