import 'package:freezed_annotation/freezed_annotation.dart';

part 'run_arguments.freezed.dart';

/// What is wrong with [RunArguments], so the dialog can say so under the field it is about.
enum RunArgumentsProblem {
  /// A define that is not `KEY=VALUE`, or has an empty key. (The define field.)
  badDefine,

  /// A flag the app sets itself (device, mode, target, flavor, `--dart-define`). (The flags field.)
  reservedFlag,

  /// A quote in the flags that is not closed. (The flags field.)
  unbalancedQuotes,
}

/// The flags a user may not type among the free ones: the app passes them from its own controls.
/// `--dart-define-from-file` is a different flag and is allowed.
const Set<String> _reservedFlags = <String>{
  '-d',
  '--device-id',
  '--machine',
  '-t',
  '--target',
  '--debug',
  '--profile',
  '--release',
  '--flavor',
  '--dart-define',
};

bool _isReserved(String arg) {
  if (_reservedFlags.contains(arg)) return true;
  final equals = arg.indexOf('=');
  if (equals > 0 && arg.startsWith('--') && _reservedFlags.contains(arg.substring(0, equals))) {
    return true;
  }
  // `-dmacos` and `-tlib/x.dart`: a short option with its value attached.
  return arg.length > 2 && !arg.startsWith('--') && (arg.startsWith('-d') || arg.startsWith('-t'));
}

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

  /// The first thing wrong with these arguments, or `null` when `flutter run` can take them as
  /// they are.
  RunArgumentsProblem? get problem {
    for (final define in dartDefines) {
      final equals = define.indexOf('=');
      if (equals < 1 || define.substring(0, equals).trim().isEmpty) {
        return RunArgumentsProblem.badDefine;
      }
    }
    final args = splitArgs(extraArgs);
    if (args == null) return RunArgumentsProblem.unbalancedQuotes;
    if (args.any(_isReserved)) return RunArgumentsProblem.reservedFlag;
    return null;
  }

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
