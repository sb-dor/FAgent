import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rule(String name) => File('assets/knowledge/rules/$name.md').readAsStringSync();

Iterable<String> _dartBlocks(String markdown) =>
    RegExp(r'```dart\n(.*?)```', dotAll: true).allMatches(markdown).map((match) => match.group(1)!);

void main() {
  test('controllers.md has the handle recipe', () {
    final controllers = _rule('controllers');
    expect(controllers, contains('error: (error, stackTrace) async =>'));
    expect(controllers, contains('done: () async =>'));
    expect(controllers, contains('### Where the error goes'));
    expect(controllers, contains('#### Typed `on` with `rethrow`'));
    expect(controllers, contains('### An action of two steps'));
    expect(controllers, contains('### Reporting an error'));
  });

  test('no controller example catches everything', () {
    for (final name in ['controllers', 'architecture']) {
      for (final block in _dartBlocks(_rule(name)).where((block) => block.contains('handle('))) {
        expect(block, isNot(contains('on Object catch')), reason: '$name.md: $block');
        expect(block, isNot(contains('} finally {')), reason: '$name.md: $block');
      }
    }
  });

  test('no cafe specifics', () {
    // `PIN` is only checked in the files that never talk about PINs as a general topic.
    const pinFree = {'controllers', 'repositories', 'architecture'};
    const files = {...pinFree, 'security', 'configuration', 'dependencies', 'widgets', 'testing'};
    for (final name in files) {
      final text = _rule(name);
      for (final word in [
        'CAFEPOS',
        'deviceGuard',
        'venue',
        'заведени',
        if (pinFree.contains(name)) 'PIN',
      ]) {
        expect(text, isNot(contains(word)), reason: '$name.md contains $word');
      }
    }
  });

  test('repositories.md reports with ErrorUtil', () {
    expect(_rule('repositories'), contains('**Report with `ErrorUtil`, nothing else.**'));
  });

  test('security.md has Crash reports', () {
    final security = _rule('security');
    expect(security, contains('## Crash reports'));
    for (final word in [
      'sendDefaultPii',
      'redactSecrets',
      'HiddenDetailsError',
      'Firebase Crashlytics',
      'recorded before',
    ]) {
      expect(security, contains(word));
    }
  });

  test('security.md treats every ExpectedException as expected', () {
    final security = _rule('security');
    expect(security, isNot(contains('a `RejectedException` with a known code')));
    final start = security.indexOf('### Expected errors');
    final section = security.substring(start, security.indexOf('### Storing tokens'));
    expect(section, contains('error is ExpectedException'));
    expect(section, contains('ExpectedException() => true'));
    expect(section, contains('TimeoutException'));
    expect(section, contains(r'APIClientException$Network'));
    expect(section, contains(r'APIClientException$Authorization'));
  });

  test('dependencies.md does not log errors with developer.log', () {
    expect(_rule('dependencies'), isNot(contains('developer.log(')));
  });

  test('configuration.md has the DSN', () {
    final configuration = _rule('configuration');
    expect(configuration, contains('### The Sentry DSN'));
    for (final word in [
      'config/sentry.local.json',
      '--dart-define-from-file',
      'SENTRY_DSN',
      'com.apple.security.network.client',
    ]) {
      expect(configuration, contains(word));
    }
  });

  test('dependencies.md has the error log step', () {
    final dependencies = _rule('dependencies');
    expect(dependencies, contains('### The error log and the reporter'));
    expect(dependencies, contains('catchExceptions'));
    expect(dependencies, contains('STARTUP ERROR'));
  });

  test('widgets.md names the five places', () {
    final widgets = _rule('widgets');
    for (final word in ['LoadErrorView', 'RefreshFailedNotice', 'errorText']) {
      expect(widgets, contains(word));
    }
  });
}
