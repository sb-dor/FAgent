import 'package:flutter_code_agent/src/common/telemetry/log_zone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

// ignore: experimental_member_use
const _quiet = LogOptions(output: LogOutput.ignore, handlePrint: true);

void main() {
  test('logZone: an unhandled error of async code goes to onError', () async {
    final errors = <Object>[];
    logZone(() async {
      Future<void>.delayed(Duration.zero, () => throw StateError('in the zone'));
    }, onError: (error, stack) => errors.add(error));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(errors.single, isA<StateError>());
  });

  test('logZone: print in the zone goes to the log', () async {
    final logged = <String>[];
    final sub = l.listen((m) => logged.add(m.message.toString()));
    addTearDown(sub.cancel);

    logZone(
      () async {
        // ignore: avoid_print
        print('line from the zone');
      },
      onError: (_, _) {},
      options: _quiet,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(logged, contains('line from the zone'));
  });
}
