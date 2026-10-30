import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';

/// How many of the newest log lines a project keeps (and replays to a new `logs` listener).
const int kRunLogLimit = 2000;

/// The Flutter build mode of a run.
enum BuildMode { debug, profile, release }

/// Runs a project's app (`flutter run`) and reports on it. Every method takes the project it is for.
abstract interface class IAppRunRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// The project's current [RunState] right away, then every change. Ends when the subscription is
  /// cancelled or the repository is disposed.
  Stream<RunState> watchRun(int projectId);

  /// The project's buffered output (at most [kRunLogLimit] newest lines, with their `sentToAgent`
  /// flags), then every new line, the same way [watchRun] replays the state. Ends when the
  /// subscription is cancelled or the repository is disposed.
  Stream<LogEntry> logs(int projectId);

  /// Flags the buffered line [seq] of the project as sent to the agent, so the flag survives a
  /// listener that leaves and comes back. Does nothing when the line is no longer buffered.
  Future<void> markSent(int projectId, int seq);

  /// Starts the app on [deviceId] and returns once the build began; follow it through [watchRun].
  /// A running app is stopped and started again.
  Future<void> start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  });

  /// Stops the app. Does nothing when it is not running.
  Future<void> stop(int projectId);

  /// Hot-reloads the app and returns how long that took; [Duration.zero] when it is not running.
  Future<Duration> hotReload(int projectId);

  /// Hot-restarts the app. Does nothing when it is not running.
  Future<void> hotRestart(int projectId);

  /// Stops every run and closes every stream.
  Future<void> dispose();
}
