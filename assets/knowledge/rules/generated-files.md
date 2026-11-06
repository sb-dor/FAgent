---
name: generated-files
description: "Never edit generated files; run build_runner after touching annotations; build.yaml decides where each generator runs."
---

# Generated files

- Never edit `*.freezed.dart`, `*.g.dart`, `*.gen.dart`, `*.generated.dart` or localization output
  under `lib/src/_core/localization/generated/`. They are gitignored; regenerate them.
- Run build_runner after touching `@freezed`, a `part '*.freezed.dart'`/`'*.g.dart'`, Drift tables,
  JSON annotations or FlutterGen assets:
  `dart run build_runner build --delete-conflicting-outputs && dart format lib/`
- A generator runs only where `build.yaml` lets it. A file that uses it somewhere else gets no
  generated part, so its `part` directive fails to resolve: add the folder to `build.yaml`. See
  "build.yaml".

## build.yaml

`build.yaml` at the project root tells build_runner which files to read and where each generator
runs. Limiting a generator to the files that use it keeps every build fast, since a builder
otherwise reads every file of `lib/` and `test/`. New projects start with:

```yaml
targets:
  $default:
    sources:
      - $package$
      - pubspec.yaml
      - lib/**
      - test/**
    builders:
      freezed:
        generate_for:
          - lib/src/**/controller/*.dart
```

- freezed is for the states of the controllers (see "One recipe for states" in
  `docs/rules/controllers.md`), so it runs only in `controller/` folders. Checked: with this file,
  a `@freezed` class in `lib/src/home/controller/` got its `.freezed.dart`, and one in
  `lib/src/home/models/` got none, with no warning from build_runner.
- Another generator gets its own entry when the project adds it, limited the same way:

```yaml
      drift_dev:
        generate_for:
          include:
            - lib/src/_core/database/**
        options:
          databases:
            app_database: lib/src/_core/database/database.dart
          data_class_to_companions: true
          mutable_classes: false
```

- Configure only builders the project depends on: an entry for a package that is not installed
  only adds a warning to every build.

## Repository statistics

Generated and vendored files that are committed (a compiled `web/drift_worker.js`, a bundled
JavaScript or WebAssembly library) count in GitHub's language bar and show up in pull request
diffs. Mark them in `.gitattributes`:

```
web/drift_worker.js linguist-generated
web/vendor/** linguist-vendored
```

`linguist-generated` leaves the file out of the language statistics and collapses its diff in
pull requests; `linguist-vendored` is for third-party code and leaves it out of the statistics.
Generated Dart files need no entry: they are gitignored.

