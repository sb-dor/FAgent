import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';

/// Lets the user point at a widget in the running app.
abstract interface class IWidgetPickerRepository {
  /// Turns the select mode on in the app of [projectId], waits without a limit for the user to tap
  /// a widget there and returns it. The select mode is off again when it returns, whatever the
  /// result.
  Future<PickResult> pick(int projectId);

  /// Ends a pick of [projectId] that waits for a tap as [PickCancelled]; returns once it ended. Does
  /// nothing when none waits.
  Future<void> cancel(int projectId);

  /// The widget with inspector id [id] from the chain of the last pick of [projectId] (or of a
  /// [select] after it), read again with its own chain and screenshot. [PickGone] when the id is
  /// no longer valid: a new pick, a hot restart or the end of the run released it.
  Future<PickResult> select(int projectId, String id);

  /// Ends every pick (turning the select mode off) and closes every connection to an app.
  Future<void> dispose();
}

/// How a [IWidgetPickerRepository.pick] or [IWidgetPickerRepository.select] ended.
@immutable
sealed class PickResult {
  const PickResult();
}

/// The user picked [widget].
final class PickPicked extends PickResult {
  /// Creates the result.
  const PickPicked(this.widget);

  /// The widget that was picked.
  final PickedWidget widget;

  @override
  bool operator ==(Object other) => other is PickPicked && other.widget == widget;

  @override
  int get hashCode => Object.hash(PickPicked, widget);

  @override
  String toString() => 'PickPicked($widget)';
}

/// Nothing was picked: the user cancelled or left the select mode, or the run ended or restarted.
final class PickCancelled extends PickResult {
  /// Creates the result.
  const PickCancelled();

  @override
  bool operator ==(Object other) => other is PickCancelled;

  @override
  int get hashCode => (PickCancelled).hashCode;

  @override
  String toString() => 'PickCancelled';
}

/// The tap hit only widgets of Flutter or packages, none of the project's own.
final class PickNoProjectWidget extends PickResult {
  /// Creates the result.
  const PickNoProjectWidget();

  @override
  bool operator ==(Object other) => other is PickNoProjectWidget;

  @override
  int get hashCode => (PickNoProjectWidget).hashCode;

  @override
  String toString() => 'PickNoProjectWidget';
}

/// The widget to select is gone: its id was released by a new pick, a hot restart or a stop.
final class PickGone extends PickResult {
  /// Creates the result.
  const PickGone();

  @override
  bool operator ==(Object other) => other is PickGone;

  @override
  int get hashCode => (PickGone).hashCode;

  @override
  String toString() => 'PickGone';
}

/// Why a pick could not be made.
enum PickFailure {
  /// The app has no isolate with the widget inspector.
  inspectorUnavailable,

  /// The app is not running, not in debug or has no VM service yet.
  notDebug,

  /// The VM service of the app could not be reached or went away.
  connectionLost,

  /// The inspector, or the picker itself, failed a call; [PickFailed.detail] says how.
  inspectorError,
}

/// The pick could not be made, for the reason [kind].
final class PickFailed extends PickResult {
  /// Creates the result.
  const PickFailed(this.kind, {this.detail});

  /// Why the pick failed.
  final PickFailure kind;

  /// The error behind a [PickFailure.inspectorError], as the app or the picker reported it (the card
  /// shows it shortened to three lines); `null` for the other kinds.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is PickFailed && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(PickFailed, kind, detail);

  @override
  String toString() => 'PickFailed(${kind.name}${detail == null ? '' : ', $detail'})';
}
