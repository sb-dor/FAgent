import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:flutter_code_agent/src/feature/app_close/widgets/app_close_guard.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final class _FakeAppCloseRepository implements IAppCloseRepository {
  _FakeAppCloseRepository({this.busy = 0});

  int busy;
  final StreamController<void> requests = StreamController<void>.broadcast();
  final List<String> calls = <String>[];
  Completer<void>? shutdownGate;

  void close() => requests.add(null);

  @override
  Stream<void> closeRequests() => requests.stream;

  @override
  Future<int> busyChats() async => busy;

  @override
  Future<void> shutdown() async {
    calls.add('shutdown');
    await shutdownGate?.future;
  }

  @override
  Future<void> closeWindow() async => calls.add('closeWindow');
}

void main() {
  late Dependencies dependencies;

  Future<_FakeAppCloseRepository> pumpGuard(WidgetTester tester, {int busy = 0}) async {
    useDesktopView(tester);
    final repository = _FakeAppCloseRepository(busy: busy);
    dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(
        AppCloseGuard(repository: repository, child: const Text('workspace')),
        dependencies: dependencies,
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('closing an idle app quits without asking', (tester) async {
    final repository = await pumpGuard(tester);

    repository.close();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.calls, <String>['shutdown', 'closeWindow']);
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
    expect(repository.calls, isEmpty);

    repository.close();
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('Quit stops the agents behind a barrier, then closes the window', (tester) async {
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
    expect(repository.calls, <String>['shutdown', 'closeWindow']);
    await disposeTestApp(tester, dependencies);
  });
}
