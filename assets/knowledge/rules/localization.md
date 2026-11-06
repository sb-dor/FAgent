---
name: localization
description: "All visible text is localized; add every key to every .arb file; one function turns any error into a localized message; styled parts of a sentence are tags in one message."
---

# Localization

- Every user-facing string uses `Localization.of(context).key`. No hardcoded text in widgets
  (temporary debug text excepted).
- Add each new key to every `.arb` file, e.g. `lib/src/_core/localization/intl_en.arb` and
  `intl_ru.arb`. Reuse an existing key first.
- Regenerate the strings with the project's localization tool; never edit files under
  `lib/src/_core/localization/generated/`.
- Use ICU placeholders and plurals in the `.arb` text, not string concatenation.
- Errors reach the user through one function, `errorText(lcl, error)`: never `error.toString()` in
  a widget. See "Error messages".
- A sentence with a link or a bold part is one message with tags named for their role
  (`<terms>...</terms>`), never several messages joined with `TextSpan`s. See "Styled parts of a
  sentence".

## Error messages

One function turns any error the app can meet into a localized sentence, and every widget that
shows an error (a SnackBar, an error view, a dialog) calls it with the error from the state. It is
long on purpose: every kind of error is handled in one place, and a new one is one more case.

```dart
// lib/src/_core/localization/error_text.dart
String errorText(Localization lcl, Object error) => switch (error) {
  NetworkException() => lcl.errorNoConnection,
  TimeoutException() => lcl.errorTimeout,
  UnauthorizedException() => lcl.errorSignedOut,
  ForbiddenException() => lcl.errorForbidden,
  NotFoundException() => lcl.errorNotFound,
  ServerException() => lcl.errorServer,
  RejectedException(code: 'email_taken') => lcl.errorEmailTaken,
  RejectedException(message: final String message) => message,
  RejectedException() => lcl.errorRejected,
  FirebaseAuthException(code: 'network-request-failed') => lcl.errorNoConnection,
  FirebaseAuthException(code: 'wrong-password' || 'invalid-credential') => lcl.errorWrongPassword,
  _ => kDebugMode ? '$error' : lcl.errorUnknown,
};
```

- The cases go from specific to general: the app's own exceptions (made at the boundary by the
  repositories: see "Errors" in `docs/rules/repositories.md`), the server's codes mapped to the
  app's texts, a message the server wrote for the user (send `Accept-Language` so it comes in the
  user's language), the SDK's and packages' exceptions by their codes, and last the fallback.
- The fallback is `toString()` in debug builds, to see what was missed, and a generic sentence in
  release: a raw `toString()` shows users class names, URLs and stack details.
- It does not import `dart:io`: `SocketException` does not exist on the web. The HTTP client turns
  transport errors into `NetworkException` before they leave it.
- When it grows, split it by family (`_apiText`, `_firebaseText`), behind the one entry point.
- A helper that shows the error as a toast or SnackBar lives next to it:
  `showError(context, error)`.

## Styled parts of a sentence

A sentence built from pieces (`'Learn more in the '`, a link label, `' and '`, ...) cannot be
translated: word order, grammatical case, spacing and punctuation differ between languages, and a
label kept as its own message has the form it takes alone, not the form the sentence needs.
Polish says "w Regulaminie" where the label alone is "Regulamin". So the whole sentence is one
message, and the parts that are styled or tappable are marked with tags:

```json
"termsNotice": "Learn more in the <terms>Terms of Service</terms> and <privacy>Privacy Policy</privacy>.",
```

```json
"termsNotice": "Dowiedz się więcej w <terms>Regulaminie</terms> i <privacy>Polityce Prywatności</privacy>.",
```

- A tag names the role (`<terms>`, `<time>`, `<count>`), not the look (`<bold>`, `<red>`): the
  design can change without touching a translation. The translator moves the tags with the words,
  and the code maps each tag name to a style or a tap.
- `gen-l10n` leaves the tags as they are, with placeholders and in plural cases (checked:
  `"Next due in <time>{time}</time>"` becomes `'Next due in <time>$time</time>'`, and
  `{count, plural, ... other{<b>{count}</b> files left}}` becomes `'<b>$count</b> files left'`).
- `MarkupText` (`markup_text.dart` in Examples, in `lib/src/_core/widget/`) parses the message
  into `TextSpan`s with a stack of open tags; the call site passes the styles (from the theme) and
  the taps:

```dart
MarkupText(
  lcl.termsNotice,
  styles: {'terms': linkStyle, 'privacy': linkStyle},
  onTap: {'terms': _openTerms, 'privacy': _openPrivacy},
)
```

- **Malformed markup does not throw.** An unclosed, stray or crossed tag makes `tryParseMarkup`
  return `null`, and the widget shows the sentence as plain text without its tags. A translator's
  typo then costs a link, not a crash. A unit test that runs `tryParseMarkup` over every tagged
  message of every locale (`lookupLocalization(locale)` for each of
  `Localization.supportedLocales`) catches it before release.
- **A recognizer on a parent span does not reach its children.** Only the span whose `text` was hit
  gets the tap (`TextSpan.recognizer` doc; checked). Tags nest (`<terms>the <b>full</b>
  terms</terms>`), so the widget copies the tag's recognizer onto every text span inside it
  (checked: a tap on "full" opens the terms; without the copy, no tap on a tag's text arrives).
- **The recognizers are owned.** A `TapGestureRecognizer` must be disposed by whoever created it;
  `TextSpan` does not. `MarkupText` is a `StatefulWidget` that keeps one recognizer per tappable
  tag across builds, updates its `onTap` in `didUpdateWidget` and disposes it when the tag or the
  widget goes. A recognizer created inside `build` is a new undisposed object on every rebuild.
- **Placeholders are filled before parsing.** The generated method returns a finished string, so a
  user's value containing `<terms>` would become a tag. Only the names the call site maps are
  tags, so most text with `<` stays as typed; for user-supplied values (names, titles) pass
  `escapeMarkup(value)` to the message, or show the value outside the tagged sentence.
- Tests find the parts with `tester.tapOnText(find.textRange.ofSubstring('Regulaminie'))`.

### `markup_text.dart`

Tested: taps reach each tag in the English and the Polish word order, a tap inside a nested tag
reaches the outer link, malformed markup returns `null` and is shown without tags, unknown tags
stay text, an escaped value is shown as typed.

```dart
// file: markup_text.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Builds the span of one tag from the spans between its opening and closing tag.
typedef MarkupTagBuilder = InlineSpan Function(List<InlineSpan> children);

final RegExp _tagPattern = RegExp(r'<(/?)([a-zA-Z][\w-]*)>');

/// Escapes a value put into a markup message (a user's name), so it is shown as typed.
String escapeMarkup(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;');

String _unescape(String text) => text.replaceAll('&lt;', '<').replaceAll('&amp;', '&');

/// Parses [markup], `Read the <terms>Terms</terms>`, into spans; `null` when the tags do not nest.
///
/// Only the names in [tags] are tags: any other `<name>` stays in the text.
TextSpan? tryParseMarkup(String markup, Map<String, MarkupTagBuilder> tags) {
  final stack = <(String?, List<InlineSpan>)>[(null, <InlineSpan>[])];
  var textStart = 0;
  void addText(int end) {
    if (end > textStart) {
      stack.last.$2.add(TextSpan(text: _unescape(markup.substring(textStart, end))));
    }
  }

  for (final match in _tagPattern.allMatches(markup)) {
    final name = match.group(2)!;
    final builder = tags[name];
    if (builder == null) continue;
    addText(match.start);
    textStart = match.end;
    if (match.group(1) == '/') {
      if (stack.length == 1 || stack.last.$1 != name) return null;
      final (_, children) = stack.removeLast();
      stack.last.$2.add(builder(children));
    } else {
      stack.add((name, <InlineSpan>[]));
    }
  }
  addText(markup.length);
  return stack.length == 1 ? TextSpan(children: stack.single.$2) : null;
}

/// One localized sentence whose parts are styled or tappable by tag name.
///
/// `MarkupText(lcl.termsNotice, styles: {'terms': link}, onTap: {'terms': openTerms})`. Markup
/// that does not nest is shown as plain text without its tags.
class MarkupText extends StatefulWidget {
  const MarkupText(
    this.markup, {
    this.styles = const <String, TextStyle>{},
    this.onTap = const <String, VoidCallback>{},
    this.style,
    this.textAlign,
    super.key,
  });

  /// The message, from `Localization`.
  final String markup;

  /// The style of each tag's text, merged into the surrounding style.
  final Map<String, TextStyle> styles;

  /// What a tap on each tag's text does.
  final Map<String, VoidCallback> onTap;

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<MarkupText> createState() => _MarkupTextState();
}

class _MarkupTextState extends State<MarkupText> {
  final Map<String, TapGestureRecognizer> _recognizers = <String, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(MarkupText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRecognizers();
  }

  /// One recognizer per tappable tag, kept across builds and disposed when its tag goes.
  void _syncRecognizers() {
    _recognizers.removeWhere((name, recognizer) {
      if (widget.onTap.containsKey(name)) return false;
      recognizer.dispose();
      return true;
    });
    for (final MapEntry(key: name, value: onTap) in widget.onTap.entries) {
      (_recognizers[name] ??= TapGestureRecognizer()).onTap = onTap;
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = <String, MarkupTagBuilder>{
      for (final name in <String>{...widget.styles.keys, ...widget.onTap.keys})
        name: (children) => TextSpan(
          style: widget.styles[name],
          children: switch (_recognizers[name]) {
            null => children,
            final recognizer => [for (final child in children) _tappable(child, recognizer)],
          },
        ),
    };
    final span =
        tryParseMarkup(widget.markup, tags) ??
        TextSpan(
          text: _unescape(
            widget.markup.replaceAllMapped(
              _tagPattern,
              (match) => tags.containsKey(match.group(2)) ? '' : match.group(0)!,
            ),
          ),
        );
    return Text.rich(span, style: widget.style, textAlign: widget.textAlign);
  }
}

/// [span] with [recognizer] on every text span below it that has none: a recognizer only
/// receives taps on its own span's `text`, never on its children.
InlineSpan _tappable(InlineSpan span, GestureRecognizer recognizer) => switch (span) {
  TextSpan() => TextSpan(
    text: span.text,
    style: span.style,
    recognizer: span.recognizer ?? recognizer,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
    children: [
      for (final child in span.children ?? const <InlineSpan>[]) _tappable(child, recognizer),
    ],
  ),
  _ => span,
};
```
