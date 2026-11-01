import 'package:flutter/widgets.dart';

import 'dependencies.dart';
import 'example_controller.dart';
import 'example_data_controller.dart';
import 'example_repository.dart';

/// Gives the widgets below access to [ExampleConfigWidgetState].
class ExampleConfigInhWidget extends InheritedWidget {
  const ExampleConfigInhWidget({super.key, required this.state, required super.child});

  final ExampleConfigWidgetState state;

  static ExampleConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<ExampleConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'ExampleConfigInhWidget was not found in element tree');
    return (widget! as ExampleConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(ExampleConfigInhWidget oldWidget) => false;
}

/// Creates the feature's controllers in `initState`, disposes them in `dispose` and exposes them
/// through [ExampleConfigInhWidget]. The screen is built by [builder].
class ExampleConfigWidget extends StatefulWidget {
  const ExampleConfigWidget({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<ExampleConfigWidget> createState() => ExampleConfigWidgetState();
}

class ExampleConfigWidgetState extends State<ExampleConfigWidget> {
  late final ExampleController exampleController;
  late final ExampleDataController exampleDataController;

  @override
  void initState() {
    super.initState();
    final dependencies = DependenciesScope.of(context);
    exampleController = ExampleController(
      repository: ExampleRepositoryImpl(service: dependencies.exampleService),
    );
    exampleDataController = ExampleDataController();
    load();
  }

  @override
  void dispose() {
    exampleController.dispose();
    exampleDataController.dispose();
    super.dispose();
  }

  /// The active filter lives in the data controller and is passed on every call.
  void load() => exampleController.load(query: exampleDataController.query);

  @override
  Widget build(BuildContext context) =>
      ExampleConfigInhWidget(state: this, child: widget.builder(context));
}
