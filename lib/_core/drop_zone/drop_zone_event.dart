import 'package:meta/meta.dart';

/// {@template drop_zone_event}
/// A drag over the app window, as the native drop zone reports it.
///
/// [dx] and [dy] are logical pixels from the top-left corner of the window, the same space as
/// Flutter's global coordinates (the window has a single Flutter view).
///
/// The shape follows PlugFox's drop zone gist (`e94689b8e708c5ab191764506f5da089`): enter, over,
/// leave and drop. Here a drop carries file paths instead of file bytes.
/// {@endtemplate}
@immutable
sealed class DropZoneEvent {
  /// {@macro drop_zone_event}
  const DropZoneEvent({required this.dx, required this.dy});

  /// Parses one event of the `flutter_code_agent/drop_zone` channel:
  /// `{type: enter|over|leave|drop, dx, dy, paths?, failed?}`.
  ///
  /// A missing or malformed position is the origin; a missing `paths` is empty and a missing
  /// `failed` is zero. An unknown or missing `type` gives `null`, and the event is ignored.
  static DropZoneEvent? fromMap(Map<Object?, Object?> map) {
    final dx = _double(map['dx']);
    final dy = _double(map['dy']);
    return switch (map['type']) {
      'enter' => DropZoneEvent$Enter(dx: dx, dy: dy),
      'over' => DropZoneEvent$Over(dx: dx, dy: dy),
      'leave' => DropZoneEvent$Leave(dx: dx, dy: dy),
      'drop' => DropZoneEvent$Drop(
        dx: dx,
        dy: dy,
        paths: <String>[
          if (map['paths'] case final List<Object?> paths)
            for (final path in paths)
              if (path is String && path.isNotEmpty) path,
        ],
        failed: switch (map['failed']) {
          final int failed when failed > 0 => failed,
          _ => 0,
        },
      ),
      _ => null,
    };
  }

  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  /// Logical pixels from the left edge of the window.
  final double dx;

  /// Logical pixels from the top edge of the window.
  final double dy;
}

/// A drag came into the window.
final class DropZoneEvent$Enter extends DropZoneEvent {
  /// A drag came into the window at [dx], [dy].
  const DropZoneEvent$Enter({required super.dx, required super.dy});

  @override
  String toString() => 'DropZoneEvent\$Enter($dx, $dy)';
}

/// A drag moved over the window.
final class DropZoneEvent$Over extends DropZoneEvent {
  /// A drag moved over the window to [dx], [dy].
  const DropZoneEvent$Over({required super.dx, required super.dy});

  @override
  String toString() => 'DropZoneEvent\$Over($dx, $dy)';
}

/// A drag left the window or was cancelled without a drop.
final class DropZoneEvent$Leave extends DropZoneEvent {
  /// A drag left the window, last seen at [dx], [dy].
  const DropZoneEvent$Leave({required super.dx, required super.dy});

  @override
  String toString() => 'DropZoneEvent\$Leave($dx, $dy)';
}

/// Files were dropped on the window. Sent once every promised file has arrived or failed.
final class DropZoneEvent$Drop extends DropZoneEvent {
  /// Files were dropped at [dx], [dy].
  const DropZoneEvent$Drop({
    required super.dx,
    required super.dy,
    this.paths = const <String>[],
    this.failed = 0,
  });

  /// Absolute paths of the dropped files and folders, in drop order. Promised files (Safari,
  /// Photos, Mail) and image data are saved in a temporary folder first.
  final List<String> paths;

  /// How many dropped items could not be received.
  final int failed;

  @override
  String toString() => 'DropZoneEvent\$Drop($dx, $dy, $paths, failed: $failed)';
}
