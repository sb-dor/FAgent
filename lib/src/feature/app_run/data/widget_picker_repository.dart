import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';

/// Lets the user point at a widget in the running app.
abstract interface class IWidgetPickerRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// Turns the picker on in the app of [projectId] and returns the widget the user picked, or
  /// `null` when nothing was picked.
  Future<PickedWidget?> pick(int projectId);
}
