import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_arguments.freezed.dart';

/// {@template run_arguments}
/// What a project adds to every `flutter run`: the flavor, the `--dart-define`s and the user's own
/// flags.
/// {@endtemplate}
@freezed
abstract class RunArguments with _$RunArguments {
  /// {@macro run_arguments}
  const factory RunArguments({
    /// The `--flavor`; `null` for none.
    String? flavor,

    /// The `--dart-define`s, each `KEY=VALUE`.
    @Default(<String>[]) List<String> dartDefines,

    /// More arguments as the user typed them, split by [splitArgs].
    @Default('') String extraArgs,
  }) = _RunArguments;

  const RunArguments._();

  /// The arguments for `flutter run`: `--flavor`, a `--dart-define` for each define, then
  /// [extraArgs] (left out when it cannot be split).
  List<String> toFlutterArgs() => <String>[
    if (flavor case final flavor?) ...<String>['--flavor', flavor],
    for (final define in dartDefines) ...<String>['--dart-define', define],
    ...?splitArgs(extraArgs),
  ];
}

/// Splits [text] into arguments the way a shell would: whitespace separates them, `'…'` and `"…"`
/// group, a backslash escapes the next character outside quotes and inside `"…"`. Returns `null`
/// when a quote is not closed.
List<String>? splitArgs(String text) {
  final args = <String>[];
  final current = StringBuffer();
  var inArg = false;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote == "'") {
      if (char == "'") {
        quote = null;
      } else {
        current.write(char);
      }
    } else if (quote == '"') {
      if (char == '"') {
        quote = null;
      } else if (char == r'\' && i + 1 < text.length) {
        current.write(text[++i]);
      } else {
        current.write(char);
      }
    } else if (char == "'" || char == '"') {
      quote = char;
      inArg = true;
    } else if (char == r'\' && i + 1 < text.length) {
      current.write(text[++i]);
      inArg = true;
    } else if (char.trim().isEmpty) {
      if (inArg) {
        args.add(current.toString());
        current.clear();
        inArg = false;
      }
    } else {
      current.write(char);
      inArg = true;
    }
  }
  if (quote != null) return null;
  if (inArg) args.add(current.toString());
  return args;
}
