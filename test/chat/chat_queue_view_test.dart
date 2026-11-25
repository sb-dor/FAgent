import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/chat/models/queued_prompt.dart';
import 'package:flutter_code_agent/chat/widgets/chat_queue_view.dart';
import 'package:flutter_code_agent/prompt_sending/models/composer_image.dart';
import 'package:flutter_code_agent/prompt_sending/models/prompt_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

const _link = PromptFileLink('/p/a.dart');
final _image = ComposerImage(
  name: 'shot.png',
  mimeType: 'image/png',
  bytes: Uint8List.fromList(<int>[0]),
  thumbnail: Uint8List.fromList(<int>[0]),
);
const _skill = PromptSkill('x', '# x');

void main() {
  final items = <QueuedPrompt>[
    QueuedPrompt(
      text: 'Fix the tests\nthen run them again',
      resources: const <PromptAttachment>[_link],
      images: <ComposerImage>[_image],
    ),
    const QueuedPrompt(
      text: 'Use the x skill.',
      draft: '/x',
      resources: <PromptAttachment>[_skill],
    ),
  ];

  Widget view({
    List<QueuedPrompt>? queued,
    bool paused = false,
    ValueChanged<int>? onEdit,
    ValueChanged<int>? onRemove,
    VoidCallback? onSendNext,
    Locale locale = const Locale('en'),
  }) => testApp(
    locale: locale,
    ChatQueueView(
      items: queued ?? items,
      paused: paused,
      onEdit: onEdit ?? (_) {},
      onRemove: onRemove ?? (_) {},
      onSendNext: onSendNext,
    ),
  );

  testWidgets('a message of images only is named by its attachments', (tester) async {
    await tester.pumpWidget(
      view(
        queued: <QueuedPrompt>[
          QueuedPrompt(text: '', resources: const <PromptAttachment>[], images: [_image]),
        ],
      ),
    );

    expect(find.text('1 attachment'), findsOneWidget);
  });

  testWidgets('rows with first line and attachment count, ✎ and ✕, paused banner', (tester) async {
    final edited = <int>[];
    final removed = <int>[];
    var sentNext = 0;
    await tester.pumpWidget(
      view(paused: true, onEdit: edited.add, onRemove: removed.add, onSendNext: () => sentNext++),
    );

    // The first line of what the user typed, in order.
    expect(find.text('Fix the tests'), findsOneWidget);
    expect(find.textContaining('then run them'), findsNothing);
    expect(find.text('/x'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Fix the tests')).dy,
      lessThan(tester.getTopLeft(find.text('/x')).dy),
    );
    // Files and images count as attachments; an embedded skill does not.
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('2 attachments'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byTooltip('Back to the field').last);
    await tester.tap(find.byTooltip('Remove from the queue').first);
    expect(edited, <int>[1]);
    expect(removed, <int>[0]);

    expect(find.text('Queue paused'), findsOneWidget);
    await tester.tap(find.text('Send next'));
    expect(sentNext, 1);
  });

  testWidgets('no banner while the queue runs', (tester) async {
    await tester.pumpWidget(view());

    expect(find.text('Queue paused'), findsNothing);
    expect(find.text('Send next'), findsNothing);
  });

  testWidgets('Send next is off when the chat cannot take a message', (tester) async {
    await tester.pumpWidget(view(paused: true));

    final button = find.ancestor(of: find.text('Send next'), matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(button).onPressed, isNull);
  });

  testWidgets('an empty queue shows nothing', (tester) async {
    await tester.pumpWidget(view(queued: const <QueuedPrompt>[], paused: true));

    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Queue paused'), findsNothing);
  });

  testWidgets('the Russian strings', (tester) async {
    await tester.pumpWidget(view(paused: true, onSendNext: () {}, locale: const Locale('ru')));

    expect(find.text('Очередь на паузе'), findsOneWidget);
    expect(find.text('Отправить следующее'), findsOneWidget);
    expect(find.byTooltip('2 вложения'), findsOneWidget);
    expect(find.byTooltip('Вернуть в поле'), findsNWidgets(2));
    expect(find.byTooltip('Убрать из очереди'), findsNWidgets(2));
  });
}
