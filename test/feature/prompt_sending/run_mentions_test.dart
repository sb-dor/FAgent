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

    test('the screenshot and the attachable paths are part of the equality', () {
      const shot = RunMention(detail: '09:05:07', text: '@shots/a.png');
      const offer = RunMentions(screenshot: shot, attachable: <String>{'shots/a.png'});
      expect(offer, const RunMentions(screenshot: shot, attachable: <String>{'shots/a.png'}));
      expect(
        offer.hashCode,
        const RunMentions(screenshot: shot, attachable: <String>{'shots/a.png'}).hashCode,
      );
      expect(offer, isNot(const RunMentions(screenshot: shot)));
      expect(
        offer,
        isNot(const RunMentions(screenshot: shot, attachable: <String>{'shots/b.png'})),
      );
    });

    test('what can be done is part of the equality and is no offer for the @ menu', () {
      expect(const RunMentions(), const RunMentions());
      expect(const RunMentions(canStart: true), isNot(const RunMentions()));
      expect(const RunMentions(canReload: true), isNot(const RunMentions()));
      expect(const RunMentions(canScreenshot: true), isNot(const RunMentions()));
      expect(
        const RunMentions(canReload: true).hashCode,
        const RunMentions(canReload: true).hashCode,
      );
      expect(
        const RunMentions(canStart: true, canReload: true, canScreenshot: true).isEmpty,
        isTrue,
      );
      const defaults = RunMentions();
      expect(
        (defaults.canStart, defaults.canReload, defaults.canScreenshot),
        (false, false, false),
      );
    });

    test('a screenshot alone is an offer', () {
      expect(
        const RunMentions(
          screenshot: RunMention(detail: '09:05:07', text: '@a.png'),
        ).isEmpty,
        isFalse,
      );
    });

    test('the flag alone does not make an offer', () {
      expect(const RunMentions(isPreview: true).isEmpty, isTrue);
      expect(const RunMentions(widget: widget).isEmpty, isFalse);
    });
  });
}
