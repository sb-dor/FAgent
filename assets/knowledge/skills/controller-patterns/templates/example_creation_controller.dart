import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'example.dart';
import 'example_mutation_repositories.dart';

part 'example_creation_controller.freezed.dart';

@freezed
sealed class ExampleCreationState with _$ExampleCreationState {
  const factory ExampleCreationState.initial() = ExampleCreation$InitialState;

  const factory ExampleCreationState.inProgress() = ExampleCreation$InProgressState;

  const factory ExampleCreationState.error({Object? error}) = ExampleCreation$ErrorState;

  const factory ExampleCreationState.completed(Example example) = ExampleCreation$CompletedState;
}

/// Saves the create/edit form. A mutation: [DroppableControllerHandler] drops a second tap while
/// the first save is running.
final class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  ExampleCreationController({
    required this._repository,
    super.initialState = const ExampleCreationState.initial(),
  });

  final IExampleCreationRepository _repository;

  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(const ExampleCreationState.inProgress());
        final result = await _repository.save(title: title, content: content, existing: existing);
        setState(ExampleCreationState.completed(result));
      }, error: (error, stackTrace) async => setState(ExampleCreationState.error(error: error)));
}
