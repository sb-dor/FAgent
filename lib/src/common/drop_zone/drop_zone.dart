import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone_event.dart';

/// {@template drop_zone}
/// Drags of files over the app window, as a broadcast [Stream] of [DropZoneEvent]s.
///
/// One per app (in `Dependencies`): every drop target listens to it and checks whether the
/// event's position falls inside itself. Show a hint on [DropZoneEvent$Enter] and
/// [DropZoneEvent$Over] inside the target, hide it on [DropZoneEvent$Leave] and
/// [DropZoneEvent$Drop].
///
/// After PlugFox's drop zone gist (`e94689b8e708c5ab191764506f5da089`), whose stream works only in
/// the browser; on macOS the events come from the app's own native view
/// (`macos/Runner/DropZone.swift`).
/// {@endtemplate}
extension type DropZone._(Stream<DropZoneEvent> _events) implements Stream<DropZoneEvent> {
  /// {@macro drop_zone}
  ///
  /// The events of the native drop view over the `flutter_code_agent/drop_zone` channel. Events
  /// the app does not know are skipped.
  factory DropZone.platform() => DropZone._(
    _channel
        .receiveBroadcastStream()
        .expand(
          (event) => <DropZoneEvent>[
            if (event case final Map<Object?, Object?> map) ?DropZoneEvent.fromMap(map),
          ],
        )
        .asBroadcastStream(),
  );

  /// {@macro drop_zone}
  ///
  /// The given [events], for tests. A single-subscription stream is made broadcast.
  factory DropZone.fromStream(Stream<DropZoneEvent> events) =>
      DropZone._(events.isBroadcast ? events : events.asBroadcastStream());

  static const EventChannel _channel = EventChannel('flutter_code_agent/drop_zone');
}
