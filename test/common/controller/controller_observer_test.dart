import 'package:control/control.dart';
import 'package:flutter_code_agent/src/common/controller/controller_observer.dart';
import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Controller extends Controller {}

void main() {
  late List<Object> reported;
  late ControllerObserver observer;
  late _Controller controller;

  setUp(() {
    reported = <Object>[];
    observer = ControllerObserver(report: (error, _) => reported.add(error));
    controller = _Controller();
  });

  tearDown(() => controller.dispose());

  test('an expected failure is not reported as a crash', () {
    observer.onError(controller, const ChatBusyException(1), StackTrace.current);
    expect(reported, isEmpty);
  });

  test('a ChatBusyException is an ExpectedException', () {
    expect(const ChatBusyException(1), isA<ExpectedException>());
    expect(const ChatBusyException(1), isA<Exception>());
  });

  test('a bug is reported once', () {
    final bug = StateError('x');
    observer.onError(controller, bug, StackTrace.current);
    expect(reported, [bug]);
  });
}
