import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'example_config_widget.dart';
import 'example_controller.dart';

/// The screen. It reads controllers from the config widget and never touches a repository.
class ExampleWidget extends StatefulWidget {
  const ExampleWidget({super.key});

  @override
  State<ExampleWidget> createState() => _ExampleWidgetState();
}

class _ExampleWidgetState extends State<ExampleWidget> {
  late final _scope = ExampleConfigInhWidget.of(context);
  late final _controller = _scope.exampleController;
  late final _dataController = _scope.exampleDataController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // A ChangeNotifier is observed with ListenableBuilder, not ValueListenableBuilder.
        // Visible text below is literal only to keep the template self-contained: in a project it
        // comes from `Localization.of(context)`.
        ListenableBuilder(
          listenable: _dataController,
          builder: (context, child) => TextField(
            onSubmitted: (value) {
              _dataController.setQuery(value);
              _scope.load();
            },
          ),
        ),
        Expanded(
          child: StateConsumer<ExampleController, ExampleState>(
            controller: _controller,
            builder: (context, state, child) => switch (state) {
              Example$InitialState() ||
              Example$InProgressState() => const Center(child: CircularProgressIndicator()),
              Example$ErrorState() => TextButton(
                onPressed: _scope.load,
                child: const Text('Try again'),
              ),
              Example$CompletedState(:final examples) => ListView.builder(
                itemCount: examples.length,
                itemBuilder: (context, index) => ListTile(title: Text(examples[index].name)),
              ),
            },
          ),
        ),
      ],
    );
  }
}
