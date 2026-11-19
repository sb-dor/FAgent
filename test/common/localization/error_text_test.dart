import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/localization/error_text.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lcl = lookupGeneratedLocalization(const Locale('en'));

  test('a file error names the path and the OS reason', () {
    final text = errorText(
      lcl,
      const FileSystemException('Cannot open', '/p/a.txt', OSError('Permission denied', 13)),
    );
    expect(text, contains('/p/a.txt'));
    expect(text, contains('Permission denied'));
    expect(text, isNot(contains('FileSystemException')));
  });

  test('a process that cannot start names the command', () {
    expect(errorText(lcl, const ProcessException('npx', <String>[])), contains('npx'));
  });

  test('a failed flutter doctor shows what it printed', () {
    expect(errorText(lcl, const FlutterDoctorFailedException(1, 'no git')), contains('no git'));
  });

  test('a timeout has its own sentence', () {
    expect(errorText(lcl, TimeoutException('x')), lcl.errorTimeout);
  });

  test('Flutter not found, a busy chat and a busy project have their own sentences', () {
    expect(errorText(lcl, const FlutterNotFoundException()), lcl.errorFlutterNotFound);
    expect(errorText(lcl, const ChatBusyException(1)), lcl.errorChatBusy);
    expect(errorText(lcl, const ProjectBusyException(1)), lcl.errorProjectBusy);
  });

  test('an unknown error is its toString in debug', () {
    expect(errorText(lcl, StateError('boom'), debug: true), contains('boom'));
  });

  test('an unknown error is a generic sentence in release', () {
    expect(errorText(lcl, StateError('boom'), debug: false), lcl.errorUnknown);
  });

  test('Russian has every key', () {
    final ru = lookupGeneratedLocalization(const Locale('ru'));
    final errors = <Object>[
      const FileSystemException('Cannot open', '/p/a.txt', OSError('Permission denied', 13)),
      const ProcessException('npx', <String>[]),
      TimeoutException('x'),
      const FlutterDoctorFailedException(1, 'x'),
      const FlutterNotFoundException(),
      const ChatBusyException(1),
      const ProjectBusyException(1),
      StateError('boom'),
    ];
    for (final error in errors) {
      final text = errorText(ru, error, debug: false);
      expect(text, isNotEmpty);
      // A file error is "path: reason" in every language, so only its text must exist.
      if (error is! FileSystemException) expect(text, isNot(errorText(lcl, error, debug: false)));
    }
  });
}
