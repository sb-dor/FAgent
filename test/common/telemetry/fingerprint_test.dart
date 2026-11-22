import 'package:flutter_code_agent/src/common/telemetry/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

const _packages = {'my_app'};

String _fp(Object error, StackTrace stack) =>
    errorFingerprint(error, stack, projectPackages: _packages);

StackTrace _stack(int line) => StackTrace.fromString(
  '#0      Repo.load (package:my_app/repo.dart:$line:5)\n'
  '#1      main (package:my_app/main.dart:7:3)\n'
  '#2      _rootRun (dart:async/zone.dart:1399:13)\n',
);

void main() {
  test('numbers in the message and line numbers do not change the fingerprint', () {
    final a = _fp(StateError('Order 15 not found'), _stack(10));
    final b = _fp(StateError('Order 9023 not found'), _stack(42));
    expect(a, b);
  });

  test('another type, message or frame gives another fingerprint', () {
    final base = _fp(StateError('Order not found'), _stack(10));
    expect(_fp(ArgumentError('Order not found'), _stack(10)), isNot(base));
    expect(_fp(StateError('Table not found'), _stack(10)), isNot(base));
    final other = StackTrace.fromString('#0 Other.run (package:my_app/other.dart:1:1)');
    expect(_fp(StateError('Order not found'), other), isNot(base));
  });

  test('library frames do not count, only the first 5 project frames go in', () {
    final frames = [for (var i = 0; i < 8; i++) '#$i f$i (package:my_app/f$i.dart:1:1)'];
    final a = _fp(StateError('x'), StackTrace.fromString(frames.join('\n')));
    final tail = [...frames.take(5), '#9 other (package:my_app/other.dart:1:1)'];
    final b = _fp(StateError('x'), StackTrace.fromString(tail.join('\n')));
    expect(a, b);
    final withLib = ['#0 lib (package:drift/a.dart:1:1)', ...frames.take(5)];
    expect(_fp(StateError('x'), StackTrace.fromString(withLib.join('\n'))), a);
  });

  test('uses the given project packages', () {
    StackTrace stack(String foreign, String own) => StackTrace.fromString(
      '#0 a (package:other/$foreign.dart:1:1)\n'
      '#1 b (package:my_app/$own.dart:1:1)\n',
    );

    final base = _fp(StateError('x'), stack('one', 'repo'));

    // Frames of `package:other/` are not the project's: they do not decide the fingerprint.
    expect(_fp(StateError('x'), stack('two', 'repo')), base);
    // Frames of `package:my_app/` decide it.
    expect(_fp(StateError('x'), stack('one', 'other_file')), isNot(base));
    // Another set of packages picks other frames.
    final swapped = errorFingerprint(
      StateError('x'),
      stack('one', 'repo'),
      projectPackages: {'other'},
    );
    expect(swapped, isNot(base));
  });

  String aot({required int pid, required String abs, String offset = '0x1a2b'}) =>
      '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n'
      'pid: $pid, tid: 77, name main\n'
      "build_id: 'abcdef0123'\n"
      'isolate_dso_base: 7f0000, vm_dso_base: 7f0000\n'
      'isolate_instructions: 7f1000, vm_instructions: 7f2000\n'
      'os: android arch: arm64 comp: no sim: no\n'
      '    #00 abs $abs virt 0000000000123456 _kDartIsolateSnapshotInstructions+$offset\n'
      '    #01 abs $abs virt 0000000000123999 _kDartIsolateSnapshotInstructions+0x77aa\n';

  test('AOT stack: other pid and abs give the same fingerprint, other offsets another', () {
    final a = _fp(StateError('x'), StackTrace.fromString(aot(pid: 1, abs: '00007f1111')));
    final b = _fp(StateError('x'), StackTrace.fromString(aot(pid: 999, abs: '00007f9999')));
    final c = _fp(
      StateError('x'),
      StackTrace.fromString(aot(pid: 1, abs: '00007f1111', offset: '0x9999')),
    );
    expect(a, b);
    expect(a, isNot(c));
  });

  test('hex tokens and UUIDs in the message do not multiply the fingerprint', () {
    final a = _fp(
      StateError('no key 3f2a9c1d77be and 123e4567-e89b-12d3-a456-426614174000'),
      _stack(1),
    );
    final b = _fp(
      StateError('no key aa00bb11cc22 and 00000000-0000-0000-0000-000000000001'),
      _stack(1),
    );
    expect(a, b);
  });
}
