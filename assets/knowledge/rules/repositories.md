---
name: repositories
description: "Repository interface plus Impl, services through the constructor, safe Stream-returning methods."
---

# Repositories

- `abstract interface class IFooRepository` plus `final class FooRepositoryImpl implements ...`.
  Services (API client, database, file system, processes) come through the constructor.
- App-global scope values (selected store, organisation) are read by the repository, not passed
  through widgets and controllers. Only per-screen filters and ids travel through `load(...)`.
- A `Stream`-returning method must always close its stream: `onListen`/`onCancel`, or an `async`
  wrapper with `close()` in `finally`. For one value use `Stream.value`/`Stream.fromFuture`. A
  `StreamController` without a guaranteed `close()` is a bug.
- Create-vs-update is decided in the repository, not in the controller or widget.
- Skill `repository-streams`.
