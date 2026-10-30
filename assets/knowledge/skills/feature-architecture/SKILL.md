---
name: feature-architecture
description: "Scaffold or extend a feature with the project's layers: models, data (repository), controller, widgets."
when_to_use: "When adding a new feature folder or a new screen, controller or repository."
version: "1.0"
---

# Feature architecture

Every feature lives in its own folder `lib/src/feature/<feature>/`. Never put feature code
directly under `lib/src/`.

```
<feature>/
├── models/       immutable entities (freezed or @immutable)
├── data/         <feature>_repository.dart: interface + Impl
├── controller/   <feature>_controller.dart: freezed states + handle()
└── widgets/      <feature>_config_widget.dart + screens
```

## Steps

1. **Models.** Immutable. Optional fields in `copyWith` use `ValueGetter<T?>?`.
2. **Repository.** `abstract interface class IFooRepository` plus `FooRepositoryImpl({required this._x})`.
   Services (database, file system, processes) come through the constructor. No separate datasource.
   A method that returns a `Stream` must always close it; a `Process` must be killed in `dispose`.
3. **Controller.** `StateController<FooState>` with freezed states (`initial`, `inProgress`,
   `error`, `completed`). Use `SequentialControllerHandler` for load/watch and
   `DroppableControllerHandler` for mutations. One controller, one domain concern.
4. **Widgets.** A config widget creates controllers in `initState`, disposes them in `dispose` and
   exposes them through an `InheritedWidget`. Desktop only: plain widgets, no `widgets/mobile/`.
5. **Wire up.** Add app-wide services as steps in `initialize_dependencies.dart`.
6. **Test.** Controller and repository get unit tests with a fake repository or service.

Starting points: `templates/controller.dart` and `templates/repository.dart`.
