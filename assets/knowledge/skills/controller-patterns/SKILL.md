---
name: controller-patterns
description: "Single responsibility for features and controllers; mutation features (creation, deletion); several controllers in one feature."
when_to_use: "When deciding whether to split a controller or feature, adding a create/edit/delete flow, or coordinating several controllers."
version: "2.0"
---

# Controller patterns

## Single responsibility

Every feature folder and every controller has one domain responsibility. A responsibility is not a
single function; it is a single domain concern.

A controller may have several methods when they serve the same concern. An
`AuthenticationController` with `signIn`, `signOut` and `checkToken` is fine: all three answer "is
this user authenticated?". Splitting them into three features is over-engineering.

Split when two things have genuinely independent UI state machines or no logical connection at the
domain level. Quick replies are three features:

```
example_list/       "provide the reactive list to the UI"
example_creation/   "manage the create/edit form lifecycle (inProgress, completed, error)"
example_deletion/   "manage the delete confirmation lifecycle (inProgress, completed, error)"
```

The creation form and the deletion dialog each need their own `inProgress` / `completed` / `error`.
If they shared one controller, a deletion in progress could overwrite the form's state and break
`PopScope`. The list (watching a stream) has no state overlap with either mutation.

## Mutation features (creation, deletion)

```
feature_name/
├── data/feature_name_repository.dart       (interface + impl)
├── controller/feature_name_controller.dart (freezed states + handle())
└── widgets/
    ├── feature_name_config_widget.dart     (InheritedWidget scope + static factory)
    └── feature_name_dialog_widget.dart     (form / confirmation UI)
```

The controller uses `DroppableControllerHandler`, so duplicate taps are dropped. Templates:
`example_creation_controller.dart`, `example_deletion_controller.dart` and their repository
interfaces in `example_mutation_repositories.dart` (flat folder; adjust imports to the layout):

```dart
class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(const ExampleCreationState.inProgress());
        final result = await _repo.save(title: title, content: content, existing: existing);
        setState(ExampleCreationState.completed(result));
      }, error: (e, st) async => setState(const ExampleCreationState.error()));
}
```

Use `SequentialControllerHandler` for load/watch.

The config widget owns the controller lifecycle and exposes a static factory so callers need one
line:

```dart
class ExampleCreationConfigWidget extends StatefulWidget {
  static Future<void> showCreationDialog(BuildContext context, {Example? existing}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ExampleCreationConfigWidget(
        builder: (_) => ExampleCreationDialogWidget(existing: existing),
      ),
    );
  }
  // ...
}
```

The dialog widget closes itself with `StateConsumer` and blocks dismissal mid-flight with
`PopScope` (`example_deletion_dialog.dart`):

```dart
StateConsumer<ExampleCreationController, ExampleCreationState>(
  controller: _controller,
  listener: (context, controller, oldState, newState) {
    if (newState is ExampleCreation$CompletedState) Navigator.pop(context);
  },
  builder: (context, state, child) => PopScope(
    canPop: state is! ExampleCreation$InProgressState,
    child: AlertDialog(...),
  ),
);
```

The calling site only uses the factory:

```dart
ExampleCreationConfigWidget.showCreationDialog(context);
ExampleCreationConfigWidget.showCreationDialog(context, existing: example);
ExampleDeletionConfigWidget.showDeletionDialog(context, example);
```

## Rules

- Group by domain concern, not by function count.
- Create and update may share one feature when they write the same record. The create-vs-update
  decision belongs in the repository, not the controller or widget.
- Split when UI states are independent: if two operations each show their own
  `inProgress` / `completed` / `error` at once or to different widgets, they need separate
  controllers and features.
- Config widgets own the controller lifecycle: created in `initState`, disposed in `dispose`,
  nowhere else.
- Static factory methods on config widgets keep wiring internal and give callers a one-line API.
- `DroppableControllerHandler` for mutations, `SequentialControllerHandler` for load/watch.
- `PopScope(canPop: state is! ...InProgressState)` on every dialog with an async operation.

## Multiple controllers in one feature

Split a feature's controllers when its async operations either need different concurrency handlers
(`Droppable` vs `Sequential`) or keep independent state that must update simultaneously without one
overwriting the other.

```
call/controller/
├── call_controller.dart
├── call_media_controller.dart
└── call_members_controller.dart
```

Each handles one async concern. `CallMediaController` is `Droppable`, so rapid taps are dropped.
`CallController` is `Sequential`, so join and leave never interleave. One shared controller would
force a single strategy on all three.

### Coordination rule

Controllers in the same feature never import or depend on each other. The widget layer coordinates
them with `addListener` or the `listener` of `StateConsumer`: it reacts to one controller's state
and calls methods on another.

```dart
callController.addListener(() {
  if (callController.state is Call$IdleState) {
    callMembersController.reset();
    callMediaController.reset();
  }
});
```
