import 'package:flutter_code_agent/src/common/process/bounded_line_splitter.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';

/// One finished line of the run log: its [level], its [text] and the [error] behind it, if any.
typedef ParsedLine = ({LogLevel level, String text, RunError? error});

/// {@template run_output_parser}
/// Turns the lines `flutter run` prints into log lines, recognising errors on the way: Flutter
/// error blocks, `Another exception was thrown`, unhandled exceptions and compile errors.
///
/// The parser is fed one line at a time. A multi-line error is collected and comes out as one
/// [ParsedLine] once it ends; [flush] gives out whatever is still collected. At most [maxBlockLines]
/// lines are kept, so a flood of output never grows the memory.
/// {@endtemplate}
final class RunOutputParser {
  /// {@macro run_output_parser}
  ///
  /// [projectRoot] is the absolute path of the project, [packageName] its Dart package name: they
  /// turn the paths in the output into project-relative ones.
  RunOutputParser({required String projectRoot, required this.packageName})
    : _root = projectRoot.endsWith('/') ? projectRoot : '$projectRoot/';

  /// The most lines of one Flutter error block (header included) the parser collects.
  static const int maxBlockLines = 400;

  /// The Dart package name of the project.
  final String packageName;

  final String _root;

  static final RegExp _blockStart = RegExp('^═*╡ EXCEPTION CAUGHT BY (.+?) ╞');
  static final RegExp _blockEnd = RegExp(r'^═+$');
  static final RegExp _thrown = RegExp(r'^The following .* (?:was|were) thrown.*:$');
  static final RegExp _frame = RegExp(r'^#\d+\s');
  static final RegExp _anotherException = RegExp(r'^Another exception was thrown: (.*)$');
  static final RegExp _unhandled = RegExp(r'^\[ERROR:[^\]]*\]\s*Unhandled Exception: (.*)$');
  static final RegExp _compileError = RegExp(r'^(\S.*?\.dart):(\d+):(\d+): Error: (.*)$');
  static final RegExp _place = RegExp(
    r'(file:///\S+?\.dart|package:\S+?\.dart|/\S+?\.dart|[\w./-]+?\.dart):(\d+):(\d+)',
  );
  static final RegExp _warning = RegExp('^[Ww]arning:');

  RunError? _firstBuildError;

  // An open Flutter error block, header first.
  List<String>? _block;

  // An unhandled exception waiting for its stack frames.
  String? _unhandledMessage;
  final List<String> _unhandledFrames = <String>[];

  /// The first compile error since the start, for the run to fail with.
  RunError? get firstBuildError => _firstBuildError;

  /// Takes one line of output — [isError] when it came from stderr — and returns the log lines it
  /// completes: none while an error block is being collected.
  List<ParsedLine> add(String text, {bool isError = false}) {
    var line = BoundedLineSplitter.stripAnsi(text);
    if (line.startsWith('flutter: ')) {
      line = line.substring(9);
    } else if (line == 'flutter:') {
      line = '';
    }

    final out = <ParsedLine>[];

    final block = _block;
    if (block != null) {
      final trimmed = line.trimRight();
      if (_blockStart.hasMatch(trimmed)) {
        // The previous block lost its end: give it out and start over.
        out.add(_finishBlock());
        _block = <String>[trimmed];
      } else {
        block.add(trimmed);
        if (_blockEnd.hasMatch(trimmed) || block.length >= maxBlockLines) {
          out.add(_finishBlock());
        }
      }
      return out;
    }

    if (_unhandledMessage != null) {
      if (_frame.hasMatch(line) || line.trim() == '<asynchronous suspension>') {
        if (_unhandledFrames.length < maxBlockLines) _unhandledFrames.add(line.trimRight());
        return out;
      }
      out.add(_finishUnhandled());
    }

    final trimmed = line.trimRight();
    if (_blockStart.hasMatch(trimmed)) {
      _block = <String>[trimmed];
      return out;
    }

    final unhandled = _unhandled.firstMatch(line);
    if (unhandled != null) {
      _unhandledMessage = unhandled.group(1)!.trim();
      return out;
    }

    out.add(_plain(line, isError: isError));
    return out;
  }

  /// Gives out the error that is still being collected, if any. Call it when the run stops or its
  /// process ends.
  List<ParsedLine> flush() {
    final out = <ParsedLine>[];
    if (_block != null) out.add(_finishBlock());
    if (_unhandledMessage != null) out.add(_finishUnhandled());
    return out;
  }

  ParsedLine _plain(String line, {required bool isError}) {
    final another = _anotherException.firstMatch(line);
    if (another != null) {
      final message = another.group(1)!.trim();
      return (
        level: LogLevel.error,
        text: line,
        error: RunError(
          title: _isOverflow(message) ? 'Layout overflow' : 'Exception',
          message: message,
        ),
      );
    }

    final compile = _compileError.firstMatch(line);
    if (compile != null) {
      final path = compile.group(1)!;
      final lineNumber = int.parse(compile.group(2)!);
      final error = RunError(
        title: 'Compilation error',
        message: compile.group(4)!.trim(),
        file: _projectFile(path),
        line: lineNumber,
        location: '${_basename(path)}:$lineNumber:${compile.group(3)}',
      );
      _firstBuildError ??= error;
      return (level: LogLevel.error, text: line, error: error);
    }

    return (
      level: isError
          ? LogLevel.error
          : _warning.hasMatch(line)
          ? LogLevel.warning
          : LogLevel.info,
      text: line,
      error: null,
    );
  }

  ParsedLine _finishBlock() {
    final lines = _block!;
    _block = null;

    final library = _blockStart.firstMatch(lines.first)!.group(1)!.toLowerCase();
    final libraryTitle = '${library[0].toUpperCase()}${library.substring(1)} error';

    final thrown = lines.indexWhere(_thrown.hasMatch);
    final message = <String>[];
    if (thrown != -1) {
      for (var i = thrown + 1; i < lines.length && lines[i].trim().isNotEmpty; i++) {
        message.add(lines[i]);
      }
    }
    // A block that does not say what was thrown: its first text line stands in for the message.
    if (message.isEmpty) {
      final first = lines
          .skip(1)
          .firstWhere(
            (line) => line.trim().isNotEmpty && !_blockEnd.hasMatch(line),
            orElse: () => '',
          );
      if (first.isNotEmpty) message.add(first);
    }
    final messageText = message.join('\n');

    String? file;
    int? lineNumber;
    String? location;
    final widget = lines.indexWhere(
      (line) => line.startsWith('The relevant error-causing widget was:'),
    );
    if (widget != -1) {
      for (var i = widget + 1; i < lines.length; i++) {
        if (lines[i].trim().isEmpty) continue;
        final place = _place.firstMatch(lines[i]);
        if (place != null) {
          file = _projectFile(place.group(1)!);
          lineNumber = int.parse(place.group(2)!);
          location = '${_basename(place.group(1)!)}:$lineNumber:${place.group(3)}';
        }
        break;
      }
    }

    final stack = lines.where(_frame.hasMatch).join('\n');

    return (
      level: LogLevel.error,
      text: message.isEmpty ? libraryTitle : message.first,
      error: RunError(
        title: _isOverflow(messageText) ? 'Layout overflow' : libraryTitle,
        message: messageText.isEmpty ? libraryTitle : messageText,
        file: file,
        line: file == null ? null : lineNumber,
        location: location,
        stack: stack.isEmpty ? null : stack,
      ),
    );
  }

  ParsedLine _finishUnhandled() {
    final message = _unhandledMessage!;
    final frames = List<String>.of(_unhandledFrames);
    _unhandledMessage = null;
    _unhandledFrames.clear();

    String? file;
    int? lineNumber;
    String? location;
    for (final frame in frames) {
      final place = _place.firstMatch(frame);
      final projectFile = place == null ? null : _projectFile(place.group(1)!);
      if (place != null && projectFile != null) {
        file = projectFile;
        lineNumber = int.parse(place.group(2)!);
        location = '${_basename(place.group(1)!)}:$lineNumber:${place.group(3)}';
        break;
      }
    }

    final stack = frames.where(_frame.hasMatch).join('\n');
    return (
      level: LogLevel.error,
      text: message,
      error: RunError(
        title: 'Unhandled exception',
        message: message,
        file: file,
        line: lineNumber,
        location: location,
        stack: stack.isEmpty ? null : stack,
      ),
    );
  }

  bool _isOverflow(String message) => message.contains('overflowed by');

  String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

  /// The project-relative form of [path], or `null` when it points outside the project.
  String? _projectFile(String path) {
    if (path.startsWith('package:')) {
      final prefix = 'package:$packageName/';
      return path.startsWith(prefix) ? 'lib/${path.substring(prefix.length)}' : null;
    }
    var absolute = path;
    if (absolute.startsWith('file://')) {
      absolute = absolute.substring(7);
      try {
        absolute = Uri.decodeFull(absolute);
      } on FormatException {
        // Keep the path as it is.
      }
    }
    if (absolute.startsWith('/')) {
      return absolute.startsWith(_root) ? absolute.substring(_root.length) : null;
    }
    return absolute;
  }
}
