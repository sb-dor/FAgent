import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';

/// Always "picks" the same widget until the inspector is wired in.
final class FakeWidgetPickerRepositoryImpl implements IWidgetPickerRepository {
  /// Creates the repository; [step] is the time the "pick" takes.
  FakeWidgetPickerRepositoryImpl({this.step = const Duration(milliseconds: 600)});

  /// The time one operation takes.
  final Duration step;

  @override
  bool get isPreview => true;

  @override
  Future<PickedWidget?> pick(int projectId) async {
    await Future<void>.delayed(step);
    return const PickedWidget(
      name: 'BookingCard',
      file: 'lib/src/feature/booking/widgets/booking_card.dart',
      line: 42,
      ancestors: <String>['Row', 'Padding', 'BookingCard', 'ListView', 'BookingScreen'],
    );
  }
}
