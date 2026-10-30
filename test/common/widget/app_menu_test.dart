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

  group('search, footer and scrolling', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required List<AppMenuSection<String>> sections,
      Widget Function(BuildContext, void Function(String?))? footerBuilder,
      bool searchable = true,
      ValueChanged<String?>? onResult,
    }) async {
      final buttonKey = GlobalKey();
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                key: buttonKey,
                onPressed: () async {
                  final box = buttonKey.currentContext!.findRenderObject()! as RenderBox;
                  final result = await showAppMenu<String>(
                    context: context,
                    anchor: box.localToGlobal(Offset.zero) & box.size,
                    sections: sections,
                    searchable: searchable,
                    footerBuilder: footerBuilder,
                  );
                  onResult?.call(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    const models = <AppMenuSection<String>>[
      AppMenuSection<String>(
        items: <AppMenuItem<String>>[
          AppMenuItem<String>(value: 'opus', title: 'Opus 5.5'),
          AppMenuItem<String>(value: 'sonnet', title: 'Sonnet 5.5'),
          AppMenuItem<String>(value: 'haiku', title: 'Haiku 5.5'),
        ],
      ),
    ];

    testWidgets('a searchable menu filters items as you type', (tester) async {
      String? picked;
      await openMenu(tester, sections: models, onResult: (value) => picked = value);

      await tester.enterText(find.byType(TextField), 'son');
      await tester.pumpAndSettle();
      expect(find.text('Sonnet 5.5'), findsOneWidget);
      expect(find.text('Opus 5.5'), findsNothing);
      expect(find.text('Haiku 5.5'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, 'sonnet');
    });

    testWidgets('the search field has focus and arrows move over the filtered list', (
      tester,
    ) async {
      String? picked;
      await openMenu(tester, sections: models, onResult: (value) => picked = value);

      await tester.enterText(find.byType(TextField), '5.5');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, 'haiku');
    });

    testWidgets('Escape closes a searchable menu without a value', (tester) async {
      var results = 0;
      String? picked = 'unset';
      await openMenu(
        tester,
        sections: models,
        onResult: (value) {
          results++;
          picked = value;
        },
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Sonnet 5.5'), findsNothing);
      expect(results, 1);
      expect(picked, isNull);
    });

    testWidgets('search ignores case and hides empty sections', (tester) async {
      await openMenu(
        tester,
        sections: const <AppMenuSection<String>>[
          AppMenuSection<String>(
            title: 'Fast',
            items: <AppMenuItem<String>>[AppMenuItem<String>(value: 'haiku', title: 'Haiku')],
          ),
          AppMenuSection<String>(
            title: 'Smart',
            items: <AppMenuItem<String>>[
              AppMenuItem<String>(value: 'opus', title: 'Opus', subtitle: 'Most capable'),
            ],
          ),
        ],
      );
      expect(find.text('Fast'), findsOneWidget);
      expect(find.text('Smart'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'HAI');
      await tester.pumpAndSettle();
      expect(find.text('Fast'), findsOneWidget);
      expect(find.text('Smart'), findsNothing);

      await tester.enterText(find.byType(TextField), 'CAPABLE');
      await tester.pumpAndSettle();
      expect(find.text('Smart'), findsOneWidget);
      expect(find.text('Fast'), findsNothing);
    });

    testWidgets('the footer closes the menu with a value', (tester) async {
      String? picked;
      await openMenu(
        tester,
        sections: models,
        footerBuilder: (context, close) =>
            TextButton(onPressed: () => close('x'), child: const Text('Footer action')),
        onResult: (value) => picked = value,
      );
      await tester.tap(find.text('Footer action'));
      await tester.pumpAndSettle();
      expect(picked, 'x');
      expect(find.text('Footer action'), findsNothing);
    });

    testWidgets('the selected item is scrolled into view', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openMenu(
        tester,
        searchable: false,
        sections: <AppMenuSection<String>>[
          AppMenuSection<String>(
            items: <AppMenuItem<String>>[
              for (var i = 0; i < 40; i++)
                AppMenuItem<String>(value: 'v$i', title: 'Item $i', selected: i == 35),
            ],
          ),
        ],
      );
      final rect = tester.getRect(find.text('Item 35'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(400));
    });
  });

  testWidgets('a chip with empty sections acts like a plain chip', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(
            label: 'Empty',
            sections: const <AppMenuSection<String>>[],
            onPressed: () => pressed++,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    expect(pressed, 1);

    await tester.pumpWidget(
      testApp(
        Center(
          child: SelectorChip<String>(
            label: 'Hollow',
            sections: const <AppMenuSection<String>>[AppMenuSection<String>(items: [])],
            onPressed: () => pressed++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hollow'));
    await tester.pumpAndSettle();
    expect(pressed, 2);
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
