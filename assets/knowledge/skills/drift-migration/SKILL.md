---
name: drift-migration
description: "Change the local Drift schema safely: new table or column, schema version bump and step-by-step migration."
when_to_use: "When a task needs a new local table, a new column or any other Drift schema change."
version: "1.0"
---

# Drift migration

Only add a local table when the feature really needs persistence. Never edit `*.g.dart` by hand.

## Steps

1. Put the table class in `lib/src/common/database/tables/<name>_table.dart`.
2. Add the table to `@DriftDatabase(tables: [...])` in `lib/src/common/database/database.dart`.
3. Bump `schemaVersion` by one.
4. Dump the new schema and regenerate the step helper:
   `dart run drift_dev schema dump lib/src/common/database/database.dart drift_schemas/` then
   `dart run drift_dev schema steps drift_schemas/ lib/src/common/database/database.steps.dart`.
5. Add the new step to the `stepByStep(...)` call in `migration`, for example
   `from1To2: (migrator, schema) async => migrator.create(schema.exampleTable)`.
6. Run `dart run build_runner build --delete-conflicting-outputs`.
7. Cover the upgrade with a migration test that opens the old schema and checks the data survives.

## Checks

- `onCreate` still calls `createAll()`; `onUpgrade` uses the generated `stepByStep`.
- A column added to an existing table has a default or is nullable.
- Repositories get the database through the constructor; widgets never touch it.
