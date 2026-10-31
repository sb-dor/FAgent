---
name: localization
description: "All visible text goes through gen-l10n; add every key to both .arb files."
---

# Localization

- Every user-facing string uses `Localization.of(context).key`. No hardcoded English or Russian
  text in widgets.
- Add each new key to both `lib/src/common/localization/intl_en.arb` and `intl_ru.arb`.
- Reuse an existing key before adding a new one.
- `flutter pub get` regenerates the strings. Never edit files under
  `lib/src/common/localization/generated/`.
- Use ICU placeholders and plurals in the `.arb` text instead of concatenating strings in code.
