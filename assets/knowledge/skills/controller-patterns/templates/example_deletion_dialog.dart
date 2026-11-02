import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'example_deletion_controller.dart';

/// Confirmation dialog. It closes itself on completion and cannot be dismissed mid-flight.
class ExampleDeletionDialog extends StatelessWidget {
  const ExampleDeletionDialog({
    super.key,
    required this.controller,
    required this.exampleId,
    this.onSuccessfullyDelete,
  });

  final ExampleDeletionController controller;
  final int exampleId;

  /// Called before the dialog closes, so the parent screen can reload.
  final VoidCallback? onSuccessfullyDelete;

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ExampleDeletionController, ExampleDeletionState>(
      controller: controller,
      listener: (context, controller, oldState, newState) {
        if (newState is ExampleDeletion$CompletedState) {
          onSuccessfullyDelete?.call();
          Navigator.pop(context);
        }
      },
      builder: (context, state, child) => PopScope(
        canPop: state is! ExampleDeletion$InProgressState,
        // Texts are literal only to keep the template self-contained: use `Localization.of`.
        child: AlertDialog(
          title: const Text('Delete'),
          content: const Text('Delete this item?'),
          actions: [
            TextButton(
              onPressed: state is ExampleDeletion$InProgressState
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: state is ExampleDeletion$InProgressState
                  ? null
                  : () => controller.delete(exampleId),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
