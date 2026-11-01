---
name: architecture
description: "Project layout and layers: lib/src/common, lib/src/feature/<feature>/{models,data,controller,widgets}."
---

# Architecture

- `lib/main.dart` is the entry; everything else is in `lib/src/`: `common/` (shared code) and
  `feature/<feature>/` (one folder per feature). Never put feature code directly under `lib/src/`.
  Existing folders stay as they are.
- A feature has `models/`, `data/` (repository), `controller/`, `widgets/`. Name files
  `<feature>_<role>.dart`.
- Dependencies point one way: widgets -> controller -> repository. A widget never touches a
  repository.
- No datasource layer: a repository does the request and the conversion itself.
- A detail screen loaded by id, a create/update form and a delete action are each their own
  feature (`x_detail`, `x_creation`, `x_deletion`).
- Models are immutable. Parse API JSON in a converter, not in widgets.
- A control used by two or more features goes to `lib/src/common/widget/`.
- No Provider, Riverpod, MobX, GetX or BLoC for widget state.
- Skill `feature-architecture` has the full layouts and templates.
