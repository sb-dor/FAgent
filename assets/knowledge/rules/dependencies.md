---
name: dependencies
description: "Global Dependencies with DependenciesScope; config widgets own and dispose feature controllers."
---

# Dependencies

- App-wide services live in `Dependencies` and are read with `DependenciesScope.of(context)`.
  Add a new service as a step of the app's initialization.
- A feature config widget creates its controllers in `initState`, builds repositories from
  `DependenciesScope`, disposes controllers in `dispose` and exposes itself through
  `XConfigInhWidget.of(context)` (`updateShouldNotify` returns `false`).
- Widgets get controllers from that scope, never from a repository.
- Code against `IFooRepository` interfaces; give dependencies to constructors, never create them
  inside a controller.
- Skill `dependency-injection`.
