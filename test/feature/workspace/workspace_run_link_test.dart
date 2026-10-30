import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_run_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays the lines a test preloads.
final class _ScriptedRun implements IAppRunRepository {
  _ScriptedRun(this.lines);

  final List<LogEntry> lines;

  @override
  bool get isPreview => false;

  @override
  Stream<LogEntry> logs(int projectId) => Stream<LogEntry>.fromIterable(lines);

  @override
  Stream<RunState> watchRun(int projectId) => Stream<RunState>.value(const RunIdle());

  @override
  Future<void> markSent(int projectId, int seq) async {}

  @override
  Future<void> start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) async {}

  @override
  Future<void> stop(int projectId) async {}

  @override
  Future<Duration> hotReload(int projectId) async => Duration.zero;

  @override
  Future<void> hotRestart(int projectId) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  /// The `@` offer of a run whose last line carries [error].
  Future<String?> errorMention(RunError error, {bool isPreview = false}) async {
    final repository = _ScriptedRun(<LogEntry>[
      LogEntry(
        seq: 0,
        time: DateTime(2026, 10, 30),
        level: LogLevel.error,
        text: error.title,
        error: error,
      ),
    ]);
    final data = WorkspaceDataController()..selectProject(1);
    final run = RunController(repository: repository)..watch(1);
    final actions = RunActionsController(
      runRepository: repository,
      pickerRepository: FakeWidgetPickerRepositoryImpl(),
    );
    final link = WorkspaceRunLink(
      data: data,
      run: run,
      actions: actions,
      reloadAfterTurn: () => false,
      isPreview: isPreview,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final text = link.mentions?.error?.text;
    link.dispose();
    actions.dispose();
    run.dispose();
    data.dispose();
    return text;
  }

  group('the @error offer', () {
    test('names the file and the line', () async {
      expect(
        await errorMention(const RunError(title: 'Boom', message: 'm', file: 'a.dart', line: 7)),
        '@error Boom (a.dart:7)',
      );
    });

    test('a file without a line is only the file, never "file:null"', () async {
      expect(
        await errorMention(const RunError(title: 'Boom', message: 'm', file: 'a.dart')),
        '@error Boom (a.dart)',
      );
    });

    test('prefers the location the app printed', () async {
      expect(
        await errorMention(
          const RunError(title: 'Boom', message: 'm', location: 'a.dart:7:3', file: 'b.dart'),
        ),
        '@error Boom (a.dart:7:3)',
      );
    });

    test('without a place there are no parentheses', () async {
      expect(await errorMention(const RunError(title: 'Boom', message: 'm')), '@error Boom');
    });
  });

  group('RunError.place', () {
    test('is the location, else file:line, else the file, else nothing', () {
      expect(
        const RunError(
          title: 't',
          message: 'm',
          location: 'x.dart:1:2',
          file: 'y.dart',
          line: 3,
        ).place,
        'x.dart:1:2',
      );
      expect(const RunError(title: 't', message: 'm', file: 'y.dart', line: 3).place, 'y.dart:3');
      expect(const RunError(title: 't', message: 'm', file: 'y.dart').place, 'y.dart');
      expect(const RunError(title: 't', message: 'm', line: 3).place, isNull);
      expect(const RunError(title: 't', message: 'm').place, isNull);
    });
  });

  group('the offer is marked Preview when the run is made up', () {
    const error = RunError(title: 'Boom', message: 'm');
    test('mentions carry the flag of the link', () async {
      Future<bool?> flag({required bool preview}) async {
        final repository = _ScriptedRun(<LogEntry>[
          LogEntry(
            seq: 0,
            time: DateTime(2026, 10, 30),
            level: LogLevel.error,
            text: 'Boom',
            error: error,
          ),
        ]);
        final data = WorkspaceDataController()..selectProject(1);
        final run = RunController(repository: repository)..watch(1);
        final actions = RunActionsController(
          runRepository: repository,
          pickerRepository: FakeWidgetPickerRepositoryImpl(),
        );
        final link = WorkspaceRunLink(
          data: data,
          run: run,
          actions: actions,
          reloadAfterTurn: () => false,
          isPreview: preview,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final result = link.mentions?.isPreview;
        link.dispose();
        actions.dispose();
        run.dispose();
        data.dispose();
        return result;
      }

      expect(await flag(preview: true), isTrue);
      expect(await flag(preview: false), isFalse);
    });
  });
}
