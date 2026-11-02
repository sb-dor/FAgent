import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'example.dart';
import 'example_repository.dart';

part 'example_controller.freezed.dart';

@freezed
sealed class ExampleState with _$ExampleState {
  const factory ExampleState.initial() = Example$InitialState;

  const factory ExampleState.inProgress() = Example$InProgressState;

  const factory ExampleState.error({Object? error}) = Example$ErrorState;

  const factory ExampleState.completed(List<Example> examples) = Example$CompletedState;
}

/// Loads the examples. One controller, one domain concern; load and watch use
/// [SequentialControllerHandler] so calls never interleave.
final class ExampleController extends StateController<ExampleState>
    with SequentialControllerHandler {
  ExampleController({required this._repository, super.initialState = const ExampleState.initial()});

  final IExampleRepository _repository;

  /// The filter arrives as an argument on every call; the controller keeps no query field.
  void load({String query = ''}) => handle(() async {
    setState(const ExampleState.inProgress());
    final examples = await _repository.examples(query: query);
    setState(ExampleState.completed(examples));
  }, error: (error, stackTrace) async => setState(ExampleState.error(error: error)));
}
