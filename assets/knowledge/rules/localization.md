---
name: localization
description: "All visible text is localized; add every key to every .arb file."
---

# Localization

- Every user-facing string uses `Localization.of(context).key`. No hardcoded text in widgets
  (temporary debug text excepted).
- Add each new key to every `.arb` file, e.g. `lib/src/common/localization/intl_en.arb` and
  `intl_ru.arb`. Reuse an existing key first.
- Regenerate the strings with the project's localization tool; never edit files under
  `lib/src/common/localization/generated/`.
- Use ICU placeholders and plurals in the `.arb` text, not string concatenation.
