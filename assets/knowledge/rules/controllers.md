---
name: controllers
description: "StateController with freezed states, handler choice and one concern per controller."
---

# Controllers

- Extend `StateController<XState>` and change state through `handle(() async {...}, error: ...)`.
  States are freezed: `initial`, `inProgress`, `error`, `completed`.
- `SequentialControllerHandler` for load/watch and pagination.
  `DroppableControllerHandler` for mutations (create, save, delete).
- One controller, one domain concern. Split when the async parts need different handlers or have
  independent `inProgress`/`error` state.
- Controllers of one feature never import each other. Widgets coordinate them with `addListener`
  or the `listener` of `StateConsumer`.
- A controller keeps no query or filter field. The widget passes the filter on every call.
- Dialogs with an async action: `PopScope(canPop: state is! ...InProgressState)`.
- Skills `controller-patterns`, `paginated-controller`.
