import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/status.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';

/// {@template run_status}
/// The status line of the Run tab: the build progress, how long the app has been running with the
/// time of the last reload, the error that stopped it, or that it is not running.
/// {@endtemplate}
class RunStatus extends StatelessWidget {
  /// {@macro run_status}
  const RunStatus({required this.run, super.key});

  /// Where the run is.
  final RunState run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11);
    switch (run) {
      case RunBuilding(:final progress, :final label):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(label, style: style),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: colors.accent,
              backgroundColor: colors.surface,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        );
      case RunRunning(:final startedAt, :final lastReload):
        return Row(
          children: <Widget>[
            const StatusDot(tone: AppStatusTone.ok),
            const SizedBox(width: 6),
            Flexible(
              child: _RunningFor(
                startedAt: startedAt,
                suffix: lastReload == null
                    ? null
                    : localization.lastReload(lastReload.inMilliseconds),
                style: style,
              ),
            ),
          ],
        );
      case RunFailed(:final error):
        return Row(
          children: <Widget>[
            const StatusDot(tone: AppStatusTone.danger),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                error.title,
                style: style.copyWith(color: colors.danger),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case RunIdle() || RunStopped():
        return Text(localization.runIdle, style: style);
    }
  }
}

/// "Running 4:12 · reload 180 ms", ticking every second while it is on screen. The timer lives
/// here, so a tick rebuilds only this line and never the logs.
class _RunningFor extends StatefulWidget {
  const _RunningFor({required this.startedAt, required this.suffix, required this.style});

  final DateTime startedAt;
  final String? suffix;
  final TextStyle style;

  @override
  State<_RunningFor> createState() => _RunningForState();
}

class _RunningForState extends State<_RunningFor> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// `m:ss`, or `h:mm:ss` from one hour on.
  static String format(Duration duration) {
    final total = duration.isNegative ? Duration.zero : duration;
    final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');
    if (total.inHours == 0) return '${total.inMinutes}:$seconds';
    return '${total.inHours}:${(total.inMinutes % 60).toString().padLeft(2, '0')}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = format(DateTime.now().difference(widget.startedAt));
    final suffix = widget.suffix;
    final text = Localization.of(context).runningFor(elapsed);
    return Text(
      suffix == null ? text : '$text · $suffix',
      style: widget.style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
