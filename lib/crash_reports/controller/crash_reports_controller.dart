import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/_core/utils/error_util.dart';
import 'package:flutter_code_agent/crash_reports/data/crash_reports_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'crash_reports_controller.freezed.dart';

/// What the "Crash reports" section shows.
@freezed
abstract class CrashReportsData with _$CrashReportsData {
  const factory CrashReportsData({
    /// The last errors of the queue, newest first.
    @Default(<OutboxEntry>[]) List<OutboxEntry> recent,

    /// How many errors the queue holds. Rows from before the user's consent are among them and are
    /// never sent.
    @Default(0) int recorded,

    /// The state of the sender.
    @Default(TelemetryStatus.initial) TelemetryStatus status,

    /// Whether the last "Save log archive" succeeded.
    @Default(false) bool archiveSaved,

    /// Why the errors could not be read.
    Object? loadError,
  }) = _CrashReportsData;
}

@freezed
sealed class CrashReportsState with _$CrashReportsState {
  /// Nothing is running.
  const factory CrashReportsState.idle({required CrashReportsData data}) = CrashReports$IdleState;

  /// Something is running.
  const factory CrashReportsState.processing({required CrashReportsData data}) =
      CrashReports$ProcessingState;

  /// The last action finished.
  const factory CrashReportsState.successful({required CrashReportsData data}) =
      CrashReports$SuccessfulState;

  /// The last action failed with [error].
  const factory CrashReportsState.error({required CrashReportsData data, required Object error}) =
      CrashReports$ErrorState;
}

/// The data of any state.
extension CrashReportsStateX on CrashReportsState {
  /// What the section shows.
  CrashReportsData get data => switch (this) {
    CrashReports$IdleState(:final data) ||
    CrashReports$ProcessingState(:final data) ||
    CrashReports$SuccessfulState(:final data) ||
    CrashReports$ErrorState(:final data) => data,
  };
}

/// Settings → "Crash reports": the recorded errors, the switch and the log archive.
///
/// One action at a time, in order: an "off, on" from the settings must reach the runtime in the
/// same order.
final class CrashReportsController extends StateController<CrashReportsState>
    with SequentialControllerHandler {
  CrashReportsController({
    required this._repository,
    super.initialState = const CrashReportsState.idle(data: CrashReportsData()),
  });

  final ICrashReportsRepository _repository;
  StreamSubscription<TelemetryStatus>? _subscription;

  /// Whether this build has a reporter configured.
  bool get reporterConfigured => _repository.reporterConfigured;

  CrashReportsData get _data => state.data;

  /// Reads the errors and follows the sender.
  void load() => handle(
    () async {
      setState(CrashReportsState.processing(data: _data.copyWith(loadError: null)));
      _follow();
      setState(CrashReportsState.successful(data: await _read(archiveSaved: false)));
    },
    error: (error, stackTrace) async => setState(
      CrashReportsState.error(
        data: _data.copyWith(loadError: error),
        error: error,
      ),
    ),
    done: () async => setState(CrashReportsState.idle(data: _data)),
  );

  /// Applies the user's switch; [since] is the moment of consent.
  void apply({required bool enabled, DateTime? since}) => handle(
    () async {
      await _repository.apply(enabled: enabled, since: since);
    },
    error: (error, stackTrace) async =>
        setState(CrashReportsState.error(data: _data, error: error)),
    done: () async => setState(CrashReportsState.idle(data: _data)),
  );

  /// Writes the log archive to [path].
  void saveArchive(String path) => handle(
    () async {
      setState(CrashReportsState.processing(data: _data.copyWith(archiveSaved: false)));
      await _repository.saveArchive(path);
      setState(CrashReportsState.successful(data: _data.copyWith(archiveSaved: true)));
    },
    error: (error, stackTrace) async =>
        setState(CrashReportsState.error(data: _data, error: error)),
    done: () async => setState(CrashReportsState.idle(data: _data)),
  );

  void _follow() {
    _subscription ??= _repository.statusChanges.listen(
      (_) => _refresh(),
      onError: (Object error, StackTrace stackTrace) =>
          ErrorUtil.logError(error, stackTrace, hint: 'Crash reports status'),
    );
  }

  /// Re-reads the errors after the sender's state changed, without a visible "processing".
  void _refresh() => handle(
    () async {
      final data = await _read(archiveSaved: _data.archiveSaved);
      setState(CrashReportsState.idle(data: data));
    },
    error: (error, stackTrace) async => setState(
      CrashReportsState.error(
        data: _data.copyWith(loadError: error),
        error: error,
      ),
    ),
    done: () async => setState(CrashReportsState.idle(data: _data)),
  );

  Future<CrashReportsData> _read({required bool archiveSaved}) async => CrashReportsData(
    recent: await _repository.recent(),
    recorded: await _repository.recorded(),
    status: _repository.status,
    archiveSaved: archiveSaved,
  );

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
