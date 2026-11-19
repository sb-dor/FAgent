import 'dart:ui';

import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error_kind.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_error_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupGeneratedLocalization(const Locale('en'));
  final ru = lookupGeneratedLocalization(const Locale('ru'));

  test('a known kind is shown in the language of the app', () {
    const error = RunError(kind: RunErrorKind.buildFailed, title: 'Build failed', message: '');
    expect(runErrorTitle(en, error), 'Build failed');
    expect(runErrorTitle(ru, error), isNot('Build failed'));
  });

  test('every kind but other has its own text in both languages', () {
    for (final kind in RunErrorKind.values.where((kind) => kind != RunErrorKind.other)) {
      final error = RunError(kind: kind, title: 'x', message: '');
      expect(runErrorTitle(en, error), isNot('x'), reason: '$kind');
      expect(runErrorTitle(ru, error), isNot('x'), reason: '$kind');
    }
  });

  test('other keeps the title it came with', () {
    const error = RunError(kind: RunErrorKind.other, title: 'Rendering library', message: '');
    expect(runErrorTitle(en, error), 'Rendering library');
    expect(runErrorTitle(ru, error), 'Rendering library');
  });
}
