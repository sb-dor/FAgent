---
name: generated-files
description: "Never edit generated files; run build_runner after touching annotations."
---

# Generated files

- Never edit `*.freezed.dart`, `*.g.dart`, `*.gen.dart`, `*.generated.dart` or localization output
  under `lib/src/common/localization/generated/`. They are gitignored; regenerate them.
- Run build_runner after touching `@freezed`, a `part '*.freezed.dart'`/`'*.g.dart'`, Drift tables,
  JSON annotations or FlutterGen assets:
  `dart run build_runner build --delete-conflicting-outputs && dart format lib/`
