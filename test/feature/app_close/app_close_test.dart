import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:flutter_code_agent/src/feature/app_close/widgets/app_close_guard.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final class _FakeAppCloseRepository implements IAppCloseRepository {
  _FakeAppCloseRepository({this.busy = 0, this.ask = true, this.unsaved = 0});

  int busy;
  bool ask;

  /// Unsaved files in the Code view.
  int unsaved;

  /// Whether saving them works.
  bool saves = true;

  /// What saving throws, if anything.
  Error? saveError;
  final StreamController<void> requests = StreamController<void>.broadcast();
  final List<String> calls = <String>[];
  Completer<void>? shutdownGate;

  void close() => requests.add(null);

  @override
  Stream<void> closeRequests() => requests.stream;

  @override
  Future<int> busyChats() async => busy;

  @override
  Future<bool> askBeforeQuit() async => ask;

  @override
  int unsavedFiles() => unsaved;

  @override
  Future<bool> saveAllFiles() async {
    calls.add('saveAllFiles');
    if (saveError case final error?) throw error;
    if (saves) unsaved = 0;
    return saves;
  }

  @override
  Future<void> shutdown() async {
    calls.add('shutdown');
    await shutdownGate?.future;
  }

  @override
  Future<void> quit() async => calls.add('quit');

  @override
  Future<void> cancelQuit() async => calls.add('cancelQuit');
}

void main() {
  late Dependencies dependencies;

  Future<_FakeAppCloseRepository> pumpGuard(
    WidgetTester tester, {
    int busy = 0,
    bool ask = true,
    int unsaved = 0,
    Locale locale = const Locale('en'),
  }) async {
    useDesktopView(tester);
    final repository = _FakeAppCloseRepository(busy: busy, ask: ask, unsaved: unsaved);
    dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(
        AppCloseGuard(repository: repository, child: const Text('workspace')),
        dependencies: dependencies,
        locale: locale,
      ),
    );
    await tester.pump();
    return repository;
  }

  group('unsaved files', () {
    Future<void> close(WidgetTester tester, _FakeAppCloseRepository repository) async {
      repository.close();
      await tester.pump();
      await tester.pump();
    }

    Future<void> answer(WidgetTester tester, String button) async {
      await tester.tap(find.text(button));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('quitting asks even with askBeforeQuit off', (tester) async {
      final repository = await pumpGuard(tester, unsaved: 2, ask: false);

      await close(tester, repository);

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('2 files have unsaved changes.'), findsOneWidget);
      expect(repository.calls, isEmpty);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Save all saves and quits', (tester) async {
      final repository = await pumpGuard(tester, unsaved: 1);
      await close(tester, repository);

      await answer(tester, 'Save all');

      expect(repository.calls, <String>['saveAllFiles', 'shutdown', 'quit']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets("Don't save quits", (tester) async {
      final repository = await pumpGuard(tester, unsaved: 1);
      await close(tester, repository);

      await answer(tester, "Don't save");

      expect(repository.calls, <String>['shutdown', 'quit']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Cancel stays', (tester) async {
      final repository = await pumpGuard(tester, unsaved: 1);
      await close(tester, repository);

      await answer(tester, 'Cancel');

      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.calls, <String>['cancelQuit']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a failed save stays open and says so', (tester) async {
      final repository = await pumpGuard(tester, unsaved: 1)
        ..saves = false;
      await close(tester, repository);

      await answer(tester, 'Save all');

      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(repository.calls, <String>['saveAllFiles']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('M4: an unexpected error while saving stays open and can quit later', (
      tester,
    ) async {
      final repository = await pumpGuard(tester, unsaved: 1)
        ..saveError = StateError('chmod missing');
      await close(tester, repository);

      await answer(tester, 'Save all');
      expect(find.textContaining('could not be saved'), findsOneWidget);

      await answer(tester, "Don't save");
      expect(repository.calls, <String>['saveAllFiles', 'shutdown', 'quit']);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('after Save all, working agents still ask', (tester) async {
      final repository = await pumpGuard(tester, unsaved: 1, busy: 2);
      await close(tester, repository);

      await answer(tester, 'Save all');

      expect(find.textContaining('Agents are still working in 2 chats.'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('closing an idle app quits without asking', (tester) async {
    final repository = await pumpGuard(tester);

    repository.close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.calls, <String>['shutdown', 'quit']);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('quits without asking when askBeforeQuit is off', (tester) async {
    final repository = await pumpGuard(tester, busy: 2, ask: false);

    repository.close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.calls, <String>['shutdown', 'quit']);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('closing while agents work asks, and Cancel keeps the app open', (tester) async {
    final repository = await pumpGuard(tester, busy: 2);

    repository.close();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Agents are still working in 2 chats.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.calls, <String>['cancelQuit']);

    repository.close();
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('Quit stops the agents behind a barrier, then quits', (tester) async {
    final repository = await pumpGuard(tester, busy: 1)
      ..shutdownGate = Completer<void>()
      ..close();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('An agent is still working in 1 chat.'), findsOneWidget);
    await tester.tap(find.text('Quit'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Stopping agents…'), findsOneWidget);
    expect(repository.calls, <String>['shutdown']);
    repository.close();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);

    repository.shutdownGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(repository.calls, <String>['shutdown', 'quit']);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the Russian text for 21 chats is neutral: no "an agent works in one chat"', (
    tester,
  ) async {
    final repository = await pumpGuard(tester, busy: 21, locale: const Locale('ru'));

    repository.close();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Ещё идёт работа в 21 чате.'), findsOneWidget);
    expect(find.textContaining('Агент'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the Russian text for 2 and 5 chats uses the plural', (tester) async {
    for (final (count, text) in <(int, String)>[
      (2, 'Ещё идёт работа в 2 чатах.'),
      (5, 'Ещё идёт работа в 5 чатах.'),
    ]) {
      final repository = await pumpGuard(tester, busy: count, locale: const Locale('ru'));
      repository.close();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining(text), findsOneWidget, reason: '$count');
      await disposeTestApp(tester, dependencies);
    }
  });
}
