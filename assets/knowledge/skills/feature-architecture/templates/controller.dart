import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'example_controller.freezed.dart';

@freezed
sealed class ExampleState with _$ExampleState {
  const factory ExampleState.initial() = Example$InitialState;

  const factory ExampleState.inProgress() = Example$InProgressState;

  const factory ExampleState.error({Object? error}) = Example$ErrorState;

  const factory ExampleState.completed(List<Example> examples) = Example$CompletedState;
}

/// Loads the examples. One controller, one domain concern.
final class ExampleController extends StateController<ExampleState>
    with SequentialControllerHandler {
  ExampleController({
    required IExampleRepository repository,
    super.initialState = const ExampleState.initial(),
  }) : _repository = repository;

  final IExampleRepository _repository;

  void load() => handle(() async {
    setState(const ExampleState.inProgress());
    final examples = await _repository.examples();
    setState(ExampleState.completed(examples));
  }, error: (error, stackTrace) async => setState(ExampleState.error(error: error)));
}
