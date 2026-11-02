import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/picked_widget_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_widget_picker_repository.dart';
import '../../support/test_app.dart';

const PickedWidget _card = ScriptedWidgetPickerRepository.bookingCard;

const String _shot = '.dart_tool/flutter_code_agent/screenshots/widget-BookingCard.png';

/// The card's state right after [widget] was picked.
RunPickState _picked(PickedWidget widget, {PickResult? problem}) => RunPickState(
  projectId: 1,
  widget: widget,
  chain: <PickedAncestor>[
    PickedAncestor(
      name: widget.name,
      file: widget.file,
      line: widget.line,
      column: widget.column,
      id: widget.id!,
    ),
    ...widget.ancestors,
  ],
  problem: problem,
);

PickedWidget _withShot(PickedWidget widget) => PickedWidget(
  name: widget.name,
  file: widget.file,
  line: widget.line,
  column: widget.column,
  id: widget.id,
  ancestors: widget.ancestors,
  screenshot: _shot,
);

void main() {
  late List<String> calls;

  setUp(() => calls = <String>[]);

  Future<void> pumpCard(WidgetTester tester, RunPickState pick, {String? root = '/p'}) =>
      tester.pumpWidget(
        testApp(
          SizedBox(
            width: 340,
            child: PickedWidgetCard(
              pick: pick,
              projectRoot: root,
              onCancel: () => calls.add('cancel'),
              onSelect: (id) => calls.add('select $id'),
              onAddToMessage: (widget) => calls.add('add ${widget.name}'),
              onOpenFile: (file, line) => calls.add('open $file:$line'),
            ),
          ),
        ),
      );

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  bool enabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(button(label)).onPressed != null;

  Text link(WidgetTester tester, int index) => tester.widget<Text>(
    find.descendant(
      of: find.byKey(ValueKey<String>('picked-link-$index')),
      matching: find.byType(Text),
    ),
  );

  testWidgets('picking shows the hint and Cancel ends the pick', (tester) async {
    await pumpCard(tester, const RunPickState(projectId: 1, picking: true));

    expect(find.text('Tap a widget in the running app…'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    expect(calls, <String>['cancel']);
    expect(find.text('Add to message'), findsNothing);
  });

  testWidgets('picked shows the name, file:line:column, the chain and the actions', (tester) async {
    await pumpCard(tester, _picked(_card));

    expect(find.text('booking_card.dart:42:7'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('picked-link-0')), findsOneWidget);
    expect(link(tester, 0).data, 'BookingCard');
    expect(link(tester, 1).data, 'BookingList');
    expect(link(tester, 2).data, 'BookingScreen');
    expect(enabled(tester, 'Add to message'), isTrue);

    await tester.tap(find.text('Add to message'));
    await tester.tap(find.text('Open file'));
    expect(calls, <String>[
      'add BookingCard',
      'open lib/src/feature/booking/widgets/booking_card.dart:42',
    ]);
  });

  testWidgets('the current link is highlighted and tapping another one selects it', (tester) async {
    await pumpCard(tester, _picked(_card));
    final colors = tester.element(find.byType(PickedWidgetCard)).colors;

    expect(link(tester, 0).style?.color, colors.accent);
    expect(link(tester, 1).style?.color, isNot(colors.accent));
    final highlight = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('picked-link-0')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((highlight.decoration as BoxDecoration).color, colors.accentSoft);

    await tester.tap(find.byKey(const ValueKey<String>('picked-link-1')));
    await tester.tap(find.byKey(const ValueKey<String>('picked-link-0')));
    expect(calls, <String>['select inspector-list'], reason: 'the current one does nothing');
  });

  group('the thumbnail', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('picked_widget_card_test');
      await File('${root.path}/$_shot').create(recursive: true);
    });

    tearDown(() => root.delete(recursive: true));

    /// Writes [bytes] as the PNG of the shot, pumps the card for [pick] and lets the read finish.
    Future<void> show(WidgetTester tester, RunPickState pick, List<int> bytes) async {
      await tester.runAsync(() => File('${root.path}/$_shot').writeAsBytes(bytes));
      await pumpCard(tester, pick, root: root.path);
      // The read goes back and forth between the real file system and the test's fake time.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    List<int> shown(WidgetTester tester) {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      return ((provider is ResizeImage ? provider.imageProvider : provider) as MemoryImage).bytes;
    }

    testWidgets('shows the PNG of the project when a screenshot exists', (tester) async {
      await show(tester, _picked(_withShot(_card)), <int>[1, 2, 3]);

      expect(shown(tester), <int>[1, 2, 3]);
      expect(find.text('No snapshot of this widget'), findsNothing);
    });

    testWidgets('a new pick with the same path shows the new bytes, not a cached image', (
      tester,
    ) async {
      await show(tester, _picked(_withShot(_card)), <int>[1, 2, 3]);
      expect(shown(tester), <int>[1, 2, 3]);

      await show(tester, _picked(_withShot(_card)), <int>[4, 5, 6]);

      expect(shown(tester), <int>[4, 5, 6]);
    });
  });

  testWidgets('without the project folder the thumbnail is skipped and the note shows', (
    tester,
  ) async {
    await pumpCard(tester, _picked(_withShot(_card)), root: null);

    expect(find.byType(Image), findsNothing);
    expect(find.text('No snapshot of this widget'), findsOneWidget);
  });

  testWidgets('without a screenshot a small note says so', (tester) async {
    await pumpCard(tester, _picked(_card));

    expect(find.byType(Image), findsNothing);
    expect(find.text('No snapshot of this widget'), findsOneWidget);
  });

  testWidgets('no project widget says so and Add is disabled', (tester) async {
    await pumpCard(tester, const RunPickState(projectId: 1, problem: PickNoProjectWidget()));

    expect(find.text('No widget of your project here'), findsOneWidget);
    expect(enabled(tester, 'Add to message'), isFalse);
  });

  testWidgets('gone says so and keeps the last data', (tester) async {
    await pumpCard(tester, _picked(_card, problem: const PickGone()));

    expect(find.text('This widget is gone, pick again'), findsOneWidget);
    expect(find.text('booking_card.dart:42:7'), findsOneWidget);
    expect(enabled(tester, 'Add to message'), isTrue);
  });

  for (final (failure, message) in <(PickFailed, String)>[
    (
      const PickFailed(PickFailure.inspectorUnavailable),
      'The widget inspector is not available in this app',
    ),
    (const PickFailed(PickFailure.notDebug), 'The app is not running in debug'),
    (const PickFailed(PickFailure.connectionLost), 'Lost the connection to the app'),
    (
      const PickFailed(PickFailure.inspectorError, detail: 'boom'),
      'The widget inspector failed: boom',
    ),
  ]) {
    testWidgets('a failed pick (${failure.kind.name}) says why', (tester) async {
      await pumpCard(tester, RunPickState(projectId: 1, problem: failure));

      expect(find.text(message), findsOneWidget);
      expect(enabled(tester, 'Add to message'), isFalse);
    });
  }
}
