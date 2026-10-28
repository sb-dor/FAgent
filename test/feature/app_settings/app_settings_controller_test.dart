import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// A repository whose write echoes arrive late and out of order, like a slow database stream.
final class _SlowEchoRepository implements IAppSettingsRepository {
  _SlowEchoRepository(this._stored);

  AppSettings _stored;
  final StreamController<AppSettings> _controller = StreamController<AppSettings>.broadcast();
  final List<AppSettings> written = <AppSettings>[];

  /// Emits an older value after the write that follows it.
  final List<AppSettings> staleEchoes = <AppSettings>[];

  @override
  Stream<AppSettings> watch() async* {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    yield _stored;
    yield* _controller.stream;
  }

  @override
  Future<void> update(AppSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _stored = settings;
    written.add(settings);
    // The echo of an earlier write lands now, after this (newer) write.
    if (written.length > 1) _controller.add(written[written.length - 2]);
    _controller.add(settings);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'condition was not met in time');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('an update before the first load keeps the stored fields it did not change', () async {
    final dependencies = testDependencies();
    addTearDown(dependencies.database.close);
    final repository = AppSettingsRepositoryImpl(database: dependencies.database);
    await repository.update(const AppSettings(themeMode: ThemeMode.dark, locale: Locale('ru')));
    final controller = AppSettingsController(repository: repository);
    addTearDown(controller.dispose);

    controller
      ..watch()
      ..update((current) => current.copyWith(rightPaneWidth: 400));

    await until(() => controller.settings.rightPaneWidth == 400);
    final stored = await repository.watch().first;
    expect(stored.themeMode, ThemeMode.dark);
    expect(stored.locale, const Locale('ru'));
    expect(stored.rightPaneWidth, 400);
    expect(controller.settings, stored);
  });

  test('update works even if watch() was never called', () async {
    final dependencies = testDependencies();
    addTearDown(dependencies.database.close);
    final repository = AppSettingsRepositoryImpl(database: dependencies.database);
    await repository.update(const AppSettings(themeMode: ThemeMode.dark));
    final controller = AppSettingsController(repository: repository);
    addTearDown(controller.dispose);

    controller.update((current) => current.copyWith(sidebarVisible: false));

    await until(() => !controller.settings.sidebarVisible);
    expect((await repository.watch().first).themeMode, ThemeMode.dark);
  });

  test('three quick updates are all persisted and in state', () async {
    final dependencies = testDependencies();
    addTearDown(dependencies.database.close);
    final repository = AppSettingsRepositoryImpl(database: dependencies.database);
    final controller = AppSettingsController(repository: repository)..watch();
    addTearDown(controller.dispose);
    await until(() => controller.state is AppSettings$CompletedState);

    controller
      ..update((current) => current.copyWith(rightPaneWidth: 400))
      ..update((current) => current.copyWith(sidebarVisible: false))
      ..update((current) => current.copyWith(themeMode: ThemeMode.dark));

    await until(() => controller.settings.themeMode == ThemeMode.dark);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    const expected = AppSettings(
      themeMode: ThemeMode.dark,
      sidebarVisible: false,
      rightPaneWidth: 400,
    );
    expect(controller.settings, expected);
    expect(await repository.watch().first, expected);
  });

  test('a late echo of an earlier write does not undo a later one', () async {
    final repository = _SlowEchoRepository(const AppSettings(locale: Locale('ru')));
    final controller = AppSettingsController(repository: repository)..watch();
    addTearDown(controller.dispose);

    controller
      ..update((current) => current.copyWith(rightPaneWidth: 400))
      ..update((current) => current.copyWith(sidebarVisible: false))
      ..update((current) => current.copyWith(themeMode: ThemeMode.dark));
    await until(() => repository.written.length == 3);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    const expected = AppSettings(
      themeMode: ThemeMode.dark,
      locale: Locale('ru'),
      sidebarVisible: false,
      rightPaneWidth: 400,
    );
    expect(repository.written.last, expected);
    expect(controller.settings, expected);
  });

  test('a failed write rolls the next change back to the last stored settings', () async {
    final repository = _FailingOnceRepository();
    final controller = AppSettingsController(repository: repository)..watch();
    addTearDown(controller.dispose);

    controller.update((current) => current.copyWith(themeMode: ThemeMode.dark));
    await until(() => controller.state is AppSettings$ErrorState);
    expect(controller.settings, const AppSettings());

    controller.update((current) => current.copyWith(sidebarVisible: false));
    await until(() => repository.written.isNotEmpty);
    expect(repository.written.single, const AppSettings(sidebarVisible: false));
  });
}

final class _FailingOnceRepository implements IAppSettingsRepository {
  final List<AppSettings> written = <AppSettings>[];
  bool _failed = false;

  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(const AppSettings());

  @override
  Future<void> update(AppSettings settings) async {
    if (!_failed) {
      _failed = true;
      throw StateError('disk full');
    }
    written.add(settings);
  }
}
