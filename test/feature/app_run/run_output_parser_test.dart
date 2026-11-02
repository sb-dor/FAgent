import 'package:flutter_code_agent/src/feature/app_run/data/run_output_parser.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_test/flutter_test.dart';

const String _overflowBlock = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 24 pixels on the right.

The relevant error-causing widget was:
  Row Row:file:///p/app/lib/src/booking_card.dart:42:12

To fix this, consider using Expanded or Flexible.
The overflowing RenderFlex has an orientation of Axis.horizontal.

When the exception was thrown, this was the stack:
#0      RenderFlex.performLayout.<anonymous closure> (package:flutter/src/rendering/flex.dart:1001:9)
#1      RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1010:7)
#2      RenderObject.layout (package:flutter/src/rendering/object.dart:2800:7)
(elided 3 frames from class _RawReceivePort and dart:async)

The following RenderObject was being processed when the exception was fired: RenderFlex#6a4e1
════════════════════════════════════════════════════════════════════════════════════════════════════''';

const String _widgetsBlock = '''
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following _TypeError was thrown building Home(dirty):
type 'Null' is not a subtype of type 'String' in type cast

The relevant error-causing widget was:
  Home Home:package:app/home.dart:7:5

When the exception was thrown, this was the stack:
#0      Home.build (package:app/home.dart:7:5)
#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:5000:12)
════════════════════════════════════════════════════════════════════════════════════════════════════''';

List<ParsedLine> _feed(RunOutputParser parser, String text, {String prefix = ''}) => <ParsedLine>[
  for (final line in text.split('\n')) ...parser.add('$prefix$line'),
];

RunOutputParser _parser() => RunOutputParser(projectRoot: '/p/app', packageName: 'app');

void main() {
  group('Flutter error block', () {
    test('becomes one error line with a layout overflow', () {
      final parser = _parser();
      final lines = _feed(parser, _overflowBlock);

      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line.level, LogLevel.error);
      expect(line.text, 'A RenderFlex overflowed by 24 pixels on the right.');
      final error = line.error!;
      expect(error.title, 'Layout overflow');
      expect(error.message, 'A RenderFlex overflowed by 24 pixels on the right.');
      expect(error.file, 'lib/src/booking_card.dart');
      expect(error.line, 42);
      expect(error.location, 'booking_card.dart:42:12');
      expect(error.stack, startsWith('#0'));
      expect(error.stack, contains('#2'));
      expect(error.stack, isNot(contains('elided')));
    });

    test('gives nothing out while the block is open', () {
      final parser = _parser();
      final lines = <ParsedLine>[
        for (final line in _overflowBlock.split('\n').take(6)) ...parser.add(line),
      ];

      expect(lines, isEmpty);
    });

    test('is the same behind the `flutter: ` prefix of iOS and macOS', () {
      final parser = _parser();
      final lines = _feed(parser, _overflowBlock, prefix: 'flutter: ');

      expect(lines, hasLength(1));
      expect(lines.single.error!.title, 'Layout overflow');
      expect(lines.single.error!.file, 'lib/src/booking_card.dart');
      expect(lines.single.error!.stack, startsWith('#0'));
    });

    test('names a non-overflow error after its library', () {
      final lines = _feed(_parser(), _widgetsBlock);

      expect(lines, hasLength(1));
      final error = lines.single.error!;
      expect(error.title, 'Widgets library error');
      expect(lines.single.text, "type 'Null' is not a subtype of type 'String' in type cast");
      expect(error.message, "type 'Null' is not a subtype of type 'String' in type cast");
      expect(error.file, 'lib/home.dart');
      expect(error.line, 7);
      expect(error.location, 'home.dart:7:5');
    });

    test('keeps the framework place without a file', () {
      final lines = _feed(_parser(), '''
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══
The following assertion was thrown:
Oops.

The relevant error-causing widget was:
  Text Text:package:flutter/src/widgets/text.dart:3:4
═══════════════''');

      final error = lines.single.error!;
      expect(error.file, isNull);
      expect(error.line, isNull);
      expect(error.location, 'text.dart:3:4');
    });

    test('does not swallow the lines around it', () {
      final parser = _parser();
      final lines = <ParsedLine>[
        ...parser.add('before'),
        ..._feed(parser, _widgetsBlock),
        ...parser.add('after'),
      ];

      expect(lines.map((line) => line.text), <String>[
        'before',
        "type 'Null' is not a subtype of type 'String' in type cast",
        'after',
      ]);
    });

    test('is cut at 400 lines when it never ends', () {
      final parser = _parser();
      final lines = <ParsedLine>[
        ...parser.add('══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══'),
        ...parser.add('The following assertion was thrown during layout:'),
        ...parser.add('Boom.'),
        ...parser.add(''),
      ];
      expect(lines, isEmpty);

      var emittedAt = -1;
      for (var i = 5; i <= 1000; i++) {
        final out = parser.add('filler $i');
        if (out.isEmpty) continue;
        if (emittedAt == -1) {
          emittedAt = i;
          expect(out, hasLength(1));
          expect(out.single.error!.message, 'Boom.');
        } else {
          expect(out.single.text, 'filler $i');
          expect(out.single.error, isNull);
        }
      }

      expect(emittedAt, 400);
    });

    test('a new header while a block is open gives out the unfinished one', () {
      final parser = _parser()
        ..add('══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══')
        ..add('The following assertion was thrown during layout:')
        ..add('First.');

      final out = parser.add('══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══');

      expect(out, hasLength(1));
      expect(out.single.error!.message, 'First.');
      parser
        ..add('The following assertion was thrown:')
        ..add('Second.');
      final rest = parser.add('═══════════');
      expect(rest.single.error!.message, 'Second.');
      expect(rest.single.error!.title, 'Widgets library error');
    });

    test('without a `The following` line takes the first text line as the message', () {
      final lines = _feed(_parser(), '''
══╡ EXCEPTION CAUGHT BY GESTURE ╞═══
Something odd happened.
More detail.
═══════════''');

      expect(lines.single.text, 'Something odd happened.');
      expect(lines.single.error!.title, 'Gesture error');
      expect(lines.single.error!.message, 'Something odd happened.');
    });

    test('with nothing inside falls back to the library title', () {
      final lines = _feed(_parser(), '══╡ EXCEPTION CAUGHT BY GESTURE ╞═══\n═══════════');

      expect(lines.single.text, 'Gesture error');
      expect(lines.single.error!.message, 'Gesture error');
    });

    test('a compile error in the SDK has no file', () {
      final lines = _parser().add('dart:core/list.dart:5:6: Error: Nope.');

      expect(lines.single.error!.file, isNull);
    });

    test('flush gives out an unfinished block', () {
      final parser = _parser();
      final lines = _feed(parser, _overflowBlock.split('\n').take(6).join('\n'));
      expect(lines, isEmpty);

      final flushed = parser.flush();

      expect(flushed, hasLength(1));
      expect(flushed.single.error!.title, 'Layout overflow');
      expect(flushed.single.error!.file, 'lib/src/booking_card.dart');
      expect(parser.flush(), isEmpty);
    });
  });

  group('Another exception', () {
    test('overflow is a layout overflow', () {
      final lines = _parser().add(
        'Another exception was thrown: A RenderFlex overflowed by 12 pixels on the bottom.',
      );

      expect(lines, hasLength(1));
      expect(lines.single.level, LogLevel.error);
      expect(lines.single.error!.title, 'Layout overflow');
      expect(lines.single.error!.message, 'A RenderFlex overflowed by 12 pixels on the bottom.');
    });

    test('anything else is an exception', () {
      final lines = _parser().add('flutter: Another exception was thrown: Bad state: no element');

      expect(lines.single.error!.title, 'Exception');
      expect(lines.single.error!.message, 'Bad state: no element');
    });
  });

  group('unhandled exception', () {
    const head = '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: ';

    test('is one line with the stack and the first project frame', () {
      final parser = _parser();
      final lines = <ParsedLine>[
        ...parser.add('${head}Bad state: boom'),
        ...parser.add('#0      Foo.bar (package:flutter/src/foo.dart:1:2)'),
        ...parser.add('#1      main (package:app/main.dart:10:3)'),
        ...parser.add('#2      _runMain (dart:ui/hooks.dart:300:23)'),
      ];
      expect(lines, isEmpty);

      final out = parser.add('next line');

      expect(out.map((line) => line.text), <String>['Bad state: boom', 'next line']);
      final error = out.first.error!;
      expect(out.first.level, LogLevel.error);
      expect(error.title, 'Unhandled exception');
      expect(error.message, 'Bad state: boom');
      expect(error.file, 'lib/main.dart');
      expect(error.line, 10);
      expect(error.location, 'main.dart:10:3');
      expect(error.stack, startsWith('#0'));
      expect(error.stack, contains('#2'));
      expect(out.last.error, isNull);
    });

    test('flush gives out the pending exception', () {
      final parser = _parser()
        ..add('${head}oops')
        ..add('#0      main (file:///p/app/lib/main.dart:4:1)');

      final flushed = parser.flush();

      expect(flushed, hasLength(1));
      expect(flushed.single.error!.file, 'lib/main.dart');
      expect(flushed.single.error!.line, 4);
    });

    test('with only framework and SDK frames has no file', () {
      final parser = _parser()
        ..add('${head}oops')
        ..add('#0      Foo.bar (package:flutter/src/foo.dart:1:2)')
        ..add('#1      _runMain (dart:ui/hooks.dart:300:23)')
        ..add('#2      _Future.then (dart:async/future_impl.dart:20:5)')
        ..add('#3      sdk (org-dartlang-sdk:///sdk/lib/async/zone.dart:9:9)');

      final error = parser.flush().single.error!;

      expect(error.file, isNull);
      expect(error.line, isNull);
      expect(error.location, isNull);
    });

    test('skips an SDK frame before the project frame', () {
      final parser = _parser()
        ..add('${head}oops')
        ..add('#0      _Future.then (dart:async/future_impl.dart:20:5)')
        ..add('#1      main (package:app/main.dart:10:3)');

      final error = parser.flush().single.error!;

      expect(error.file, 'lib/main.dart');
      expect(error.line, 10);
      expect(error.location, 'main.dart:10:3');
    });

    test('without a stack is still reported', () {
      final parser = _parser();
      final out = <ParsedLine>[...parser.add('${head}oops'), ...parser.add('plain')];

      expect(out, hasLength(2));
      expect(out.first.error!.title, 'Unhandled exception');
      expect(out.first.error!.stack, isNull);
      expect(out.first.error!.file, isNull);
    });
  });

  group('compile error', () {
    test('is an error with a project-relative file', () {
      final parser = _parser();
      final lines = parser.add("lib/main.dart:12:5: Error: Expected ';' after this.");

      expect(lines, hasLength(1));
      expect(lines.single.level, LogLevel.error);
      final error = lines.single.error!;
      expect(error.title, 'Compilation error');
      expect(error.message, "Expected ';' after this.");
      expect(error.file, 'lib/main.dart');
      expect(error.line, 12);
      expect(error.location, 'main.dart:12:5');
      expect(parser.firstBuildError, error);
    });

    test('keeps the first one as firstBuildError', () {
      final parser = _parser()
        ..add('hello')
        ..add('file:///p/app/lib/a.dart:1:1: Error: First.')
        ..add('/p/app/lib/b.dart:2:2: Error: Second.');

      expect(parser.firstBuildError!.message, 'First.');
      expect(parser.firstBuildError!.file, 'lib/a.dart');
    });

    test('has no firstBuildError without one', () {
      final parser = _parser()..add('plain');

      expect(parser.firstBuildError, isNull);
    });

    test('outside the project has a location but no file', () {
      final lines = _parser().add('package:other/x.dart:3:4: Error: Nope.');

      expect(lines.single.error!.file, isNull);
      expect(lines.single.error!.location, 'x.dart:3:4');
    });
  });

  group('plain lines', () {
    test('are info', () {
      final lines = _parser().add('hello');

      expect(lines.single.level, LogLevel.info);
      expect(lines.single.text, 'hello');
      expect(lines.single.error, isNull);
    });

    test('from stderr are errors', () {
      expect(_parser().add('boom', isError: true).single.level, LogLevel.error);
    });

    test('starting with a warning are warnings', () {
      expect(_parser().add('Warning: careful').single.level, LogLevel.warning);
      expect(_parser().add('warning: careful').single.level, LogLevel.warning);
    });

    test('lose the `flutter: ` prefix and ANSI colors', () {
      expect(_parser().add('flutter: hi').single.text, 'hi');
      expect(_parser().add('\x1B[31mred\x1B[0m').single.text, 'red');
    });
  });

  group('with structured errors', () {
    RunOutputParser structured() => _parser()..structuredErrors = true;

    test('a Flutter error block comes out as plain lines without an error', () {
      final lines = _feed(structured(), _overflowBlock, prefix: 'flutter: ');

      expect(lines, hasLength(_overflowBlock.split('\n').length));
      expect(lines.every((line) => line.error == null), isTrue);
      expect(lines.every((line) => line.level == LogLevel.info), isTrue);
      expect(lines.first.text, startsWith('══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY'));
    });

    test('compile errors and unhandled exceptions are still errors', () {
      final parser = structured();

      final compile = parser.add('lib/main.dart:3:7: Error: Expected an identifier.');
      final unhandled = <ParsedLine>[
        ...parser.add('[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: x'),
        ...parser.add('#0      main (package:app/main.dart:5:3)'),
        ...parser.flush(),
      ];

      expect(compile.single.error!.title, 'Compilation error');
      expect(unhandled.single.error!.title, 'Unhandled exception');
    });

    test('switched off again, blocks are errors again', () {
      final parser = structured()..structuredErrors = false;

      expect(_feed(parser, _overflowBlock).single.error!.title, 'Layout overflow');
    });
  });

  group('flutterError', () {
    test('makes the file project-relative and the title the text of the line', () {
      final line = _parser().flutterError(
        const RunError(
          title: 'A RenderFlex overflowed by 42 pixels on the right.',
          message: 'The following assertion was thrown during layout:',
          file: 'file:///p/app/lib/main.dart',
          line: 14,
          location: 'main.dart:14:18',
        ),
      );

      expect(line.level, LogLevel.error);
      expect(line.text, 'A RenderFlex overflowed by 42 pixels on the right.');
      expect(
        line.error,
        const RunError(
          title: 'A RenderFlex overflowed by 42 pixels on the right.',
          message: 'The following assertion was thrown during layout:',
          file: 'lib/main.dart',
          line: 14,
          location: 'main.dart:14:18',
        ),
      );
    });

    test('a path under the resolved project folder is the project\'s too', () {
      final parser = RunOutputParser(
        projectRoot: '/var/p/app',
        resolvedProjectRoot: '/private/var/p/app',
        packageName: 'app',
      );

      final line = parser.flutterError(
        const RunError(
          title: 't',
          message: 'm',
          file: 'file:///private/var/p/app/lib/a.dart',
          line: 2,
        ),
      );

      expect(line.error!.file, 'lib/a.dart');
      expect(parser.add('/var/p/app/lib/b.dart:1:2: Error: x').single.error!.file, 'lib/b.dart');
    });

    test('a package path of the project is under lib/', () {
      final line = _parser().flutterError(
        const RunError(title: 't', message: 'm', file: 'package:app/src/a.dart', line: 3),
      );

      expect(line.error!.file, 'lib/src/a.dart');
      expect(line.error!.line, 3);
    });

    test('a place outside the project gives way to the first project frame', () {
      final line = _parser().flutterError(
        const RunError(
          title: 'Bad state: boom',
          message: 'm',
          file: 'file:///sdk/packages/flutter/lib/src/material/app.dart',
          line: 900,
          location: 'app.dart:900:3',
          stack:
              '#0      Element.build (package:flutter/src/widgets/framework.dart:10:1)\n'
              '#1      Home.build (package:app/home.dart:7:5)',
        ),
      );

      expect(line.error!.file, 'lib/home.dart');
      expect(line.error!.line, 7);
      expect(line.error!.location, 'home.dart:7:5');
    });

    test('without a project place keeps the location but names no file', () {
      final line = _parser().flutterError(
        const RunError(
          title: 't',
          message: 'm',
          file: 'file:///sdk/packages/flutter/lib/src/material/app.dart',
          line: 900,
          location: 'app.dart:900:3',
        ),
      );

      expect(line.error!.file, isNull);
      expect(line.error!.line, isNull);
      expect(line.error!.location, 'app.dart:900:3');
    });
  });
}
