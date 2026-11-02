import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';

/// A widget picker for tests: a pick waits [step] and returns [result] (the booking card by
/// default) unless [cancel] ends it first; [select] returns [selectResult]. Every call is recorded.
class ScriptedWidgetPickerRepository implements IWidgetPickerRepository {
  /// Creates the picker.
  ScriptedWidgetPickerRepository({
    this.step = const Duration(milliseconds: 600),
    this.result = const PickPicked(bookingCard),
    this.selectResult = const PickGone(),
  });

  /// The widget a pick returns unless a test sets [result].
  static const PickedWidget bookingCard = PickedWidget(
    name: 'BookingCard',
    file: 'lib/src/feature/booking/widgets/booking_card.dart',
    line: 42,
    column: 7,
    id: 'inspector-card',
    ancestors: <PickedAncestor>[
      PickedAncestor(
        name: 'BookingList',
        file: 'lib/src/feature/booking/widgets/booking_list.dart',
        line: 20,
        column: 5,
        id: 'inspector-list',
      ),
      PickedAncestor(
        name: 'BookingScreen',
        file: 'lib/src/feature/booking/widgets/booking_screen.dart',
        line: 9,
        column: 12,
        id: 'inspector-screen',
      ),
    ],
  );

  /// How long a pick waits before it returns [result].
  final Duration step;

  /// What a pick returns once [step] passed.
  PickResult result;

  /// What [select] returns.
  PickResult selectResult;

  /// The projects [pick] was called for, in order.
  final List<int> picks = <int>[];

  /// The projects [cancel] was called for, in order.
  final List<int> cancels = <int>[];

  /// The `(project, id)` pairs [select] was called with, in order.
  final List<(int, String)> selects = <(int, String)>[];

  /// Whether [dispose] was called.
  bool disposed = false;

  final Map<int, Completer<PickResult>> _pending = <int, Completer<PickResult>>{};

  /// Whether a pick of [projectId] waits.
  bool isPicking(int projectId) => _pending.containsKey(projectId);

  @override
  Future<PickResult> pick(int projectId) {
    picks.add(projectId);
    _pending.remove(projectId)?.complete(const PickCancelled());
    final completer = Completer<PickResult>();
    _pending[projectId] = completer;
    Timer(step, () {
      if (identical(_pending[projectId], completer)) _pending.remove(projectId);
      if (!completer.isCompleted) completer.complete(result);
    });
    return completer.future;
  }

  @override
  Future<void> cancel(int projectId) async {
    cancels.add(projectId);
    final completer = _pending.remove(projectId);
    if (completer != null && !completer.isCompleted) completer.complete(const PickCancelled());
  }

  @override
  Future<PickResult> select(int projectId, String id) async {
    selects.add((projectId, id));
    return selectResult;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(const PickCancelled());
    }
    _pending.clear();
  }
}
