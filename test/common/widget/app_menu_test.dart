import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  const modelSections = <AppMenuSection<String>>[
    AppMenuSection<String>(
      title: 'Model',
      items: <AppMenuItem<String>>[
        AppMenuItem<String>(value: 'opus', title: 'Opus', subtitle: 'Most capable', selected: true),
        AppMenuItem<String>(value: 'sonnet', title: 'Sonnet'),
      ],
    ),
  ];

  testWidgets('a chip opens its menu and returns the picked value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(
            label: 'Opus',
            sections: modelSections,
            onSelected: (value) => picked = value,
          ),
        ),
      ),
    );
    expect(find.text('Sonnet'), findsNothing);

    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(find.text('Sonnet'), findsOneWidget);

    await tester.tap(find.text('Sonnet'));
    await tester.pumpAndSettle();
    expect(picked, 'sonnet');
    expect(find.text('Sonnet'), findsNothing);
  });

  testWidgets('arrows and Enter pick, disabled items are skipped', (tester) async {
    String? picked;
    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(
            label: 'Pick',
            sections: const <AppMenuSection<String>>[
              AppMenuSection<String>(
                items: <AppMenuItem<String>>[
                  AppMenuItem<String>(value: 'a', title: 'A'),
                  AppMenuItem<String>(value: 'b', title: 'B', enabled: false),
                  AppMenuItem<String>(value: 'c', title: 'C'),
                ],
              ),
            ],
            onSelected: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();

    // A is highlighted first; one step down must jump over disabled B to C.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, 'c');
    expect(find.text('C'), findsNothing);
  });

  testWidgets('Escape closes only the menu', (tester) async {
    var pageClosed = false;
    String? picked;
    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(
            label: 'Opus',
            sections: modelSections,
            onSelected: (value) => picked = value,
          ),
        ),
        builder: (context, child) => Focus(
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.escape): () => pageClosed = true,
            },
            child: child!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(find.text('Sonnet'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Sonnet'), findsNothing);
    expect(pageClosed, isFalse);
    expect(picked, isNull);
  });

  testWidgets('a click outside closes the menu with null', (tester) async {
    String? picked;
    await tester.pumpWidget(
      testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SelectorChip<String>(
            label: 'Opus',
            sections: modelSections,
            onSelected: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Opus'));
    await tester.pumpAndSettle();
    expect(find.text('Sonnet'), findsOneWidget);

    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    expect(find.text('Sonnet'), findsNothing);
    expect(picked, isNull);
  });

  testWidgets('a chip without sections just calls onPressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(label: 'Plain', onPressed: () => pressed++),
        ),
      ),
    );
    await tester.tap(find.text('Plain'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });

  group('placement', () {
    Widget chipAt(Alignment alignment, {List<AppMenuSection<String>> sections = modelSections}) =>
        testApp(
          Align(
            alignment: alignment,
            child: SelectorChip<String>(label: 'Opus', sections: sections),
          ),
        );

    testWidgets('opens above a chip near the bottom edge', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(chipAt(Alignment.bottomLeft));
      final chipTop = tester.getTopLeft(find.byType(SelectorChip<String>)).dy;
      await tester.tap(find.byType(SelectorChip<String>));
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.text('Sonnet'));
      expect(menu.bottom, lessThanOrEqualTo(chipTop));
    });

    testWidgets('opens below a chip near the top edge', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(chipAt(Alignment.topLeft));
      final chipBottom = tester.getBottomLeft(find.byType(SelectorChip<String>)).dy;
      await tester.tap(find.byType(SelectorChip<String>));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('Sonnet')).top, greaterThanOrEqualTo(chipBottom));
    });

    testWidgets('stays inside the view for a chip near the right edge', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(chipAt(Alignment.centerRight));
      await tester.tap(find.byType(SelectorChip<String>));
      await tester.pumpAndSettle();

      final menu = tester.getRect(
        find.ancestor(of: find.text('Sonnet'), matching: find.byType(DecoratedBox)).last,
      );
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(find.text('Sonnet'), findsOneWidget);
      expect(menu.right, lessThanOrEqualTo(view.width));
    });

    testWidgets('a tall menu in a short view never covers the anchor', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 300)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tall = <AppMenuSection<String>>[
        AppMenuSection<String>(
          items: <AppMenuItem<String>>[
            for (var i = 0; i < 30; i++) AppMenuItem<String>(value: 'v$i', title: 'Item $i'),
          ],
        ),
      ];
      await tester.pumpWidget(chipAt(Alignment.centerLeft, sections: tall));
      final chip = tester.getRect(find.byType(SelectorChip<String>));
      await tester.tap(find.byType(SelectorChip<String>));
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.ancestor(of: find.text('Item 0'), matching: find.byType(DecoratedBox)).last,
      );
      expect(card.overlaps(chip), isFalse);
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.bottom, lessThanOrEqualTo(300));
    });
  });

  testWidgets('danger tone paints the chip red', (tester) async {
    await tester.pumpWidget(
      testApp(
        const Center(
          child: SelectorChip<String>(label: 'Bypass', tone: AppTone.danger),
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(of: find.byType(SelectorChip<String>), matching: find.byType(DecoratedBox))
          .first,
    );
    expect((box.decoration as BoxDecoration).color, AppColors.light.dangerSoft);
  });
}
