import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/common/widget/app_card.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/common/widget/pane_tabs.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/segmented_control.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('an AppCard wraps its actions on a narrow width', (tester) async {
    await tester.pumpWidget(
      testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: AppCard(
              leading: const Icon(Icons.extension),
              title: const Text(
                'A very long card title that does not fit into the narrow card width',
              ),
              subtitle: const Text('Subtitle'),
              trailing: <Widget>[
                TextButton(onPressed: () {}, child: const Text('Enable')),
                TextButton(onPressed: () {}, child: const Text('Configure')),
                TextButton(onPressed: () {}, child: const Text('Remove')),
              ],
              body: const Text('Body'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('KeyValueGrid keeps labels within 120–170 px', (tester) async {
    Widget grid(double width) => testApp(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: const KeyValueGrid(
            rows: <(String, Widget)>[
              ('Модель по умолчанию', Text('claude-opus')),
              (
                'Путь',
                Text('/Users/avaz/some/very/long/path/that/must/wrap/when/the/grid/is/narrow'),
              ),
            ],
          ),
        ),
      ),
    );

    // The label column is the SizedBox that directly wraps the label text.
    double labelColumnWidth() => tester
        .getSize(
          find
              .ancestor(of: find.text('Модель по умолчанию'), matching: find.byType(SizedBox))
              .first,
        )
        .width;

    await tester.pumpWidget(grid(640));
    expect(tester.takeException(), isNull);
    expect(labelColumnWidth(), 170);

    await tester.pumpWidget(grid(300));
    expect(tester.takeException(), isNull);
    expect(labelColumnWidth(), 120);
  });

  testWidgets('PaneTabs shows an error badge and reports the picked tab', (tester) async {
    String? picked;
    await tester.pumpWidget(
      testApp(
        PaneTabs<String>(
          tabs: const <PaneTab<String>>[
            PaneTab<String>(id: 'run', label: 'Run', errors: 2),
            PaneTab<String>(id: 'changes', label: 'Изменения', count: 5),
          ],
          selected: 'run',
          onSelected: (id) => picked = id,
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.text('Изменения'));
    expect(picked, 'changes');
  });

  testWidgets('DiffView without lines shows the computing placeholder', (tester) async {
    await tester.pumpWidget(
      testApp(const DiffView(path: 'lib/a.dart', oldText: 'a', newText: 'b')),
    );

    expect(
      find.text(lookupGeneratedLocalization(const Locale('en')).diffComputing),
      findsOneWidget,
    );
    expect(find.text('+b'), findsNothing);
    expect(find.text('-a'), findsNothing);
  });

  testWidgets('DiffView paints its lines and frame from the dark tokens', (tester) async {
    await tester.pumpWidget(
      testApp(
        DiffView(
          path: 'lib/a.dart',
          oldText: 'a\nb',
          newText: 'a\nc',
          lines: LineDiff.compute('a\nb', 'a\nc'),
        ),
        theme: AppTheme.dark(),
      ),
    );
    Color rowColor(String line) => tester
        .widget<ColoredBox>(
          find.ancestor(of: find.text(line), matching: find.byType(ColoredBox)).first,
        )
        .color;

    expect(rowColor('+c'), AppColors.dark.okSoft);
    expect(rowColor('-b'), AppColors.dark.dangerSoft);
    expect(tester.widget<Text>(find.text('+1')).style?.color, AppColors.dark.ok);

    final frame = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('lib/a.dart'), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = frame.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(AppRadius.medium));
    expect(decoration.border, Border.all(color: AppColors.dark.border));
  });

  testWidgets('PaneTabs draws the error badge in the onAccent token of the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        PaneTabs<String>(
          tabs: const <PaneTab<String>>[PaneTab<String>(id: 'run', label: 'Run', errors: 2)],
          selected: 'run',
          onSelected: (_) {},
        ),
        theme: AppTheme.dark(),
      ),
    );
    final badge = tester.widget<Text>(find.text('2'));
    expect(badge.style?.color, AppColors.dark.onAccent);
  });

  testWidgets('EmptyState runs its action', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      testApp(
        EmptyState(
          icon: Icons.inbox,
          title: 'Nothing here',
          message: 'Add something',
          actionLabel: 'Add',
          onAction: () => pressed++,
          badge: const PreviewBadge(),
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Add'));
    expect(pressed, 1);
  });

  testWidgets('StatusDot maps tones to tokens', (tester) async {
    Color colorOf(AppStatusTone tone) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey<AppStatusTone>(tone)),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    await tester.pumpWidget(
      testApp(
        const Column(
          children: <Widget>[
            StatusDot(
              key: ValueKey<AppStatusTone>(AppStatusTone.active),
              tone: AppStatusTone.active,
            ),
            StatusDot(key: ValueKey<AppStatusTone>(AppStatusTone.warn), tone: AppStatusTone.warn),
            StatusDot(
              key: ValueKey<AppStatusTone>(AppStatusTone.danger),
              tone: AppStatusTone.danger,
            ),
            StatusDot(key: ValueKey<AppStatusTone>(AppStatusTone.ok), tone: AppStatusTone.ok),
            StatusDot(key: ValueKey<AppStatusTone>(AppStatusTone.none), tone: AppStatusTone.none),
          ],
        ),
      ),
    );
    expect(colorOf(AppStatusTone.active), AppColors.light.accent);
    expect(colorOf(AppStatusTone.warn), AppColors.light.warn);
    expect(colorOf(AppStatusTone.danger), AppColors.light.danger);
    expect(colorOf(AppStatusTone.ok), AppColors.light.ok);
    expect(colorOf(AppStatusTone.none), Colors.transparent);
  });

  testWidgets('StatusPill and SegmentedControl render and report taps', (tester) async {
    String? picked;
    await tester.pumpWidget(
      testApp(
        Column(
          children: <Widget>[
            const StatusPill(label: 'Connected', tone: AppStatusTone.ok),
            SegmentedControl<String>(
              segments: const <(String, String)>[('a', 'Alpha'), ('b', 'Beta')],
              selected: 'a',
              onChanged: (value) => picked = value,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    expect(picked, 'b');
  });
}
