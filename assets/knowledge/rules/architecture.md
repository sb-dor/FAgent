---
name: architecture
description: "Layered feature architecture: models, data, controller, widgets; desktop only."
---

# Architecture

- Code lives in `lib/src/feature/<feature>/` (`models/`, `data/`, `controller/`, `widgets/`) or
  `lib/src/common/`. Nothing but `main.dart` sits directly under `lib/`.
- A repository is an `abstract interface class IFooRepository` plus `FooRepositoryImpl`. It gets
  services (processes, file system, database) through the constructor. No datasource layer.
- Controllers extend `StateController` with freezed states. Use `SequentialControllerHandler` for
  load/watch and `DroppableControllerHandler` for mutations. One controller, one concern.
- Controllers of one feature never import each other; the widget layer coordinates them.
- Config widgets create controllers in `initState` and dispose them in `dispose`.
- Every `Stream`-returning method must guarantee the stream is closed. Every `Process` is killed
  in `dispose`.
- Desktop only: no `widgets/mobile/`, no responsive switches.
- Feature widgets take colors from `context.colors` and radii from `AppRadius`; never `Color(0x…)`
  or `Colors.*`.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`); regenerate them.
