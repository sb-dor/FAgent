import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const widget = RunMention(
    detail: 'BookingCard · booking_card.dart:42',
    text: '@widget BookingCard',
  );

  group('RunMentions', () {
    test('equal offers are equal, so the composer does not rebuild for a repeated one', () {
      expect(
        const RunMentions(widget: widget, isPreview: true),
        const RunMentions(widget: widget, isPreview: true),
      );
      expect(
        const RunMentions(widget: widget, isPreview: true).hashCode,
        const RunMentions(widget: widget, isPreview: true).hashCode,
      );
    });

    test('the Preview flag is part of the equality', () {
      expect(
        const RunMentions(widget: widget, isPreview: true),
        isNot(const RunMentions(widget: widget)),
      );
    });

    test('the flag alone does not make an offer', () {
      expect(const RunMentions(isPreview: true).isEmpty, isTrue);
      expect(const RunMentions(widget: widget).isEmpty, isFalse);
    });
  });
}
