import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'example_mutation_repositories.dart';

part 'example_deletion_controller.freezed.dart';

@freezed
sealed class ExampleDeletionState with _$ExampleDeletionState {
  const factory ExampleDeletionState.initial() = ExampleDeletion$InitialState;

  const factory ExampleDeletionState.inProgress() = ExampleDeletion$InProgressState;

  const factory ExampleDeletionState.error({Object? error}) = ExampleDeletion$ErrorState;

  const factory ExampleDeletionState.completed() = ExampleDeletion$CompletedState;
}

/// Deletes one example. Its state is independent of the creation form, so it is its own
/// controller (and feature).
final class ExampleDeletionController extends StateController<ExampleDeletionState>
    with DroppableControllerHandler {
  ExampleDeletionController({
    required this._repository,
    super.initialState = const ExampleDeletionState.initial(),
  });

  final IExampleDeletionRepository _repository;

  void delete(int id) => handle(() async {
    setState(const ExampleDeletionState.inProgress());
    await _repository.delete(id);
    setState(const ExampleDeletionState.completed());
  }, error: (error, stackTrace) async => setState(ExampleDeletionState.error(error: error)));
}
