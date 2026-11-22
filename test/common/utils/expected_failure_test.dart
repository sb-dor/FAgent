import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/dart_analysis_server.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/lsp_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/emulator_launcher.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/utils/expected_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expected: what the user or the outside world causes', () {
    final expected = <Object>[
      const FlutterNotFoundException(),
      TimeoutException('slow'),
      const SocketException('x'),
      const DaemonClosedException(method: 'device.getDevices'),
      const LspClosedException('textDocument/hover'),
      const DartAnalysisStartCancelled(),
      const AgentRemovedException(),
      const EmulatorLaunchException(exitCode: 1, output: ''),
    ];
    for (final error in expected) {
      expect(isExpectedFailure(error), isTrue, reason: '${error.runtimeType}');
    }
  });

  test('bugs are not expected', () {
    final bugs = <Object>[
      StateError('x'),
      TypeError(),
      ArgumentError('x'),
      const FormatException('x'),
      const ProcessException('git', <String>[]),
      const FileSystemException('locked'),
      const DaemonRequestException(method: 'm', error: 'e'),
    ];
    for (final error in bugs) {
      expect(isExpectedFailure(error), isFalse, reason: '${error.runtimeType}');
    }
  });

  test('the project packages are FAgent itself', () {
    expect(fagentPackages, {'flutter_code_agent'});
  });
}
