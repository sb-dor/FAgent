import 'package:flutter/foundation.dart';

/// One thing from the running app that the `@` menu can insert into the message.
@immutable
final class RunMention {
  /// Creates a mention: [detail] is the muted line of its row, [text] what gets inserted.
  const RunMention({required this.detail, required this.text});

  /// The second line of the row, e.g. `BookingCard · booking_card.dart:42`.
  final String detail;

  /// The text the mention inserts, without the trailing space.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RunMention && other.detail == detail && other.text == text;

  @override
  int get hashCode => Object.hash(detail, text);
}

/// What the running app offers the `@` menu: the picked widget and the last error. Plain data, so
/// the chat does not depend on the run. Equal offers are equal, so a log line that changes neither
/// part does not rebuild the composer.
@immutable
final class RunMentions {
  /// Creates the offer; an absent part is not shown.
  const RunMentions({this.widget, this.error, this.isPreview = false});

  /// The widget picked in the app.
  final RunMention? widget;

  /// The last error of the app.
  final RunMention? error;

  /// Whether the run is made up (the menu says so next to the offer).
  final bool isPreview;

  /// Nothing to offer.
  bool get isEmpty => widget == null && error == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunMentions &&
          other.widget == widget &&
          other.error == error &&
          other.isPreview == isPreview;

  @override
  int get hashCode => Object.hash(widget, error, isPreview);
}
