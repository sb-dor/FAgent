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

/// What the running app offers the `@` menu: the picked widget, the last error and the last
/// screenshot. Plain data, so the chat does not depend on the run. Equal offers are equal, so a
/// log line that changes no part does not rebuild the composer.
@immutable
final class RunMentions {
  /// Creates the offer; an absent part is not shown.
  const RunMentions({
    this.widget,
    this.error,
    this.screenshot,
    this.attachable = const <String>{},
    this.isPreview = false,
  });

  /// The widget picked in the app.
  final RunMention? widget;

  /// The last error of the app.
  final RunMention? error;

  /// The last screenshot of the app: [RunMention.detail] is its time, [RunMention.text] the
  /// `@path` that mentions it.
  final RunMention? screenshot;

  /// The paths (relative to the project) of every screenshot of the project taken in this
  /// session. They are not in the project's file list, so sending a message that mentions one
  /// takes them from here and attaches the file.
  final Set<String> attachable;

  /// Whether the run is made up (the menu says so next to the offer).
  final bool isPreview;

  /// Nothing to offer.
  bool get isEmpty => widget == null && error == null && screenshot == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunMentions &&
          other.widget == widget &&
          other.error == error &&
          other.screenshot == screenshot &&
          setEquals(other.attachable, attachable) &&
          other.isPreview == isPreview;

  @override
  int get hashCode =>
      Object.hash(widget, error, screenshot, Object.hashAllUnordered(attachable), isPreview);
}
