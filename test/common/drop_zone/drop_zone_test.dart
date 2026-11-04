import 'dart:async';

import 'package:flutter_code_agent/src/common/drop_zone/drop_zone.dart';
import 'package:flutter_code_agent/src/common/drop_zone/drop_zone_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropZoneEvent.fromMap', () {
    test('enter, over and leave carry the position', () {
      expect(
        DropZoneEvent.fromMap(<Object?, Object?>{'type': 'enter', 'dx': 10.5, 'dy': 20}),
        isA<DropZoneEvent$Enter>().having((e) => e.dx, 'dx', 10.5).having((e) => e.dy, 'dy', 20),
      );
      expect(
        DropZoneEvent.fromMap(<Object?, Object?>{'type': 'over', 'dx': 1, 'dy': 2.25}),
        isA<DropZoneEvent$Over>().having((e) => e.dx, 'dx', 1).having((e) => e.dy, 'dy', 2.25),
      );
      expect(
        DropZoneEvent.fromMap(<Object?, Object?>{'type': 'leave', 'dx': 3, 'dy': 4}),
        isA<DropZoneEvent$Leave>().having((e) => e.dx, 'dx', 3).having((e) => e.dy, 'dy', 4),
      );
    });

    test('drop carries the paths in order and the failed count', () {
      final event = DropZoneEvent.fromMap(<Object?, Object?>{
        'type': 'drop',
        'dx': 5,
        'dy': 6,
        'paths': <Object?>['/b/second.txt', '/a/first.png'],
        'failed': 2,
      });

      expect(
        event,
        isA<DropZoneEvent$Drop>()
            .having((e) => e.dx, 'dx', 5)
            .having((e) => e.dy, 'dy', 6)
            .having((e) => e.paths, 'paths', <String>['/b/second.txt', '/a/first.png'])
            .having((e) => e.failed, 'failed', 2),
      );
    });

    test('a drop without paths or failed has none and zero', () {
      final event = DropZoneEvent.fromMap(<Object?, Object?>{'type': 'drop', 'dx': 0, 'dy': 0});

      expect(
        event,
        isA<DropZoneEvent$Drop>()
            .having((e) => e.paths, 'paths', isEmpty)
            .having((e) => e.failed, 'failed', 0),
      );
    });

    test('empty and non-string paths are skipped', () {
      final event = DropZoneEvent.fromMap(<Object?, Object?>{
        'type': 'drop',
        'dx': 0,
        'dy': 0,
        'paths': <Object?>['', 7, null, '/ok'],
      });

      expect((event! as DropZoneEvent$Drop).paths, <String>['/ok']);
    });

    test('a missing or malformed position is the origin', () {
      final event = DropZoneEvent.fromMap(<Object?, Object?>{'type': 'over', 'dy': 'x'});

      expect(
        event,
        isA<DropZoneEvent$Over>().having((e) => e.dx, 'dx', 0).having((e) => e.dy, 'dy', 0),
      );
    });

    test('an unknown or missing type is ignored', () {
      expect(DropZoneEvent.fromMap(<Object?, Object?>{'type': 'hover', 'dx': 1, 'dy': 1}), isNull);
      expect(DropZoneEvent.fromMap(<Object?, Object?>{'dx': 1, 'dy': 1}), isNull);
    });
  });

  test('DropZone.fromStream passes the events through to several listeners', () async {
    final controller = StreamController<DropZoneEvent>.broadcast();
    addTearDown(controller.close);
    final zone = DropZone.fromStream(controller.stream);
    final first = <DropZoneEvent>[];
    final second = <DropZoneEvent>[];
    final a = zone.listen(first.add);
    final b = zone.listen(second.add);
    addTearDown(a.cancel);
    addTearDown(b.cancel);

    controller
      ..add(const DropZoneEvent$Enter(dx: 1, dy: 2))
      ..add(const DropZoneEvent$Drop(dx: 1, dy: 2, paths: <String>['/x']));
    await Future<void>.delayed(Duration.zero);

    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(first.last, isA<DropZoneEvent$Drop>());
  });
}
