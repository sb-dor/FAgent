import 'package:flutter/painting.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/feed_grouping.dart';
import 'package:flutter_code_agent/src/feature/chat/models/mention_spans.dart';
import 'package:flutter_test/flutter_test.dart';

ToolCallItem _call(int seq, String kind, {String status = 'completed'}) =>
    ToolCallItem(seq, toolCallId: 't$seq', title: 'call $seq', kind: kind, status: status);

void main() {
  group('groupFeed', () {
    test('consecutive reads collapse into one group', () {
      final entries = groupFeed(<ChatItem>[
        _call(0, 'read'),
        _call(1, 'read'),
        _call(2, 'read'),
        _call(3, 'edit'),
        _call(4, 'read'),
      ]);

      expect(entries, hasLength(3));
      expect((entries[0] as ReadGroupEntry).calls, hasLength(3));
      expect((entries[1] as SingleEntry).item.seq, 3);
      expect((entries[2] as SingleEntry).item.seq, 4);
    });

    test('a failed read is not grouped', () {
      final entries = groupFeed(<ChatItem>[
        _call(0, 'read'),
        _call(1, 'read', status: 'failed'),
        _call(2, 'read'),
        _call(3, 'read'),
      ]);

      expect(entries.map((e) => e.runtimeType), <Type>[SingleEntry, SingleEntry, ReadGroupEntry]);
      expect((entries[2] as ReadGroupEntry).calls.map((c) => c.seq), <int>[2, 3]);
    });

    test('another item between reads breaks the group', () {
      final entries = groupFeed(<ChatItem>[
        _call(0, 'read'),
        const AgentMessageItem(1, text: 'hm'),
        _call(2, 'read'),
      ]);

      expect(entries.every((e) => e is SingleEntry), isTrue);
    });
  });

  group('mentionSpans', () {
    const pill = TextStyle(backgroundColor: Color(0xFF123456));

    test('a known mention becomes a pill, the text around it stays plain', () {
      final spans = mentionSpans('fix @lib/a.dart now', <String>[
        'file:///p/lib/a.dart',
      ], pill: pill);

      expect(spans, hasLength(3));
      expect((spans[0] as TextSpan).text, 'fix ');
      expect((spans[1] as TextSpan).text, '@lib/a.dart');
      expect((spans[1] as TextSpan).style?.backgroundColor, const Color(0xFF123456));
      expect((spans[2] as TextSpan).text, ' now');
      expect((spans[0] as TextSpan).style, isNull);
    });

    test('an @ that matches no attached file stays plain text', () {
      final spans = mentionSpans('mail @bob now', <String>['file:///p/lib/a.dart'], pill: pill);

      expect(spans.map((s) => (s as TextSpan).text).join(), 'mail @bob now');
      expect(spans.every((s) => (s as TextSpan).style == null), isTrue);
    });

    test('a path that only shares a suffix with a URI is not a mention', () {
      final spans = mentionSpans('@a.dart', <String>['file:///p/lib/xa.dart'], pill: pill);

      expect(spans.single, isA<TextSpan>().having((s) => s.style, 'style', isNull));
    });

    List<String> pills(String text, String path) => <String>[
      for (final span in mentionSpans(text, <String>[Uri.file(path).toString()], pill: pill))
        if ((span as TextSpan).style != null) span.text!,
    ];

    test('a path with a space is matched through its encoded URI', () {
      expect(pills('see @lib/a b.dart!', '/p/lib/a b.dart'), <String>['@lib/a b.dart']);
    });

    test('a non-ASCII (Cyrillic) path is matched', () {
      expect(pills('открой @lib/экран.dart', '/p/lib/экран.dart'), <String>['@lib/экран.dart']);
    });

    test('# and % in a name are matched', () {
      expect(pills('@lib/a#1%.dart', '/p/lib/a#1%.dart'), <String>['@lib/a#1%.dart']);
    });

    test('trailing punctuation stays outside the pill', () {
      final spans = mentionSpans('see @lib/a.dart, ok', <String>[
        'file:///p/lib/a.dart',
      ], pill: pill);

      expect(spans.map((s) => (s as TextSpan).text), <String?>['see ', '@lib/a.dart', ', ok']);
    });

    test('an @ inside the file name is part of the path', () {
      expect(pills('@assets/Icon@2x.png.', '/p/assets/Icon@2x.png'), <String>[
        '@assets/Icon@2x.png',
      ]);
    });

    test('foo@path is not a mention', () {
      expect(pills('foo@lib/a.dart', '/p/lib/a.dart'), isEmpty);
    });
  });
}
