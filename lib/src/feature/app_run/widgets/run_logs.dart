import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/segmented_control.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_error_block.dart';

/// Which lines the logs show.
enum RunLogFilter {
  /// Every line.
  all,

  /// Errors only.
  errors,

  /// Lines already sent to the agent.
  sent,
}

/// {@template run_logs}
/// The output of the running app: filters (all / errors / sent to the agent), a case-insensitive
/// search, clearing, and a lazy list that follows new lines while the user is at the bottom.
/// Once the user scrolls up the list is frozen (so that dropping the oldest lines at the log limit
/// does not slide the lines being read) and a chip counts the new lines and jumps back to the end.
/// Errors that carry a [RunError] are shown as error blocks.
/// {@endtemplate}
class RunLogs extends StatefulWidget {
  /// {@macro run_logs}
  const RunLogs({
    required this.logs,
    required this.errorCount,
    required this.onClear,
    required this.onSend,
    required this.onOpenFile,
    super.key,
  });

  /// The lines to filter and show, oldest first.
  final List<LogEntry> logs;

  /// The number of errors among [logs], for the filter label.
  final int errorCount;

  /// Called when the user clears the logs.
  final VoidCallback onClear;

  /// Called when the user sends the error of [LogEntry] to the agent.
  final ValueChanged<LogEntry> onSend;

  /// Called with the file and the line when the user opens the file of an error.
  final void Function(String file, int? line) onOpenFile;

  @override
  State<RunLogs> createState() => _RunLogsState();
}

class _RunLogsState extends State<RunLogs> {
  /// How close to the end (in pixels) still counts as "at the bottom".
  static const double _bottomSlack = 24;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  RunLogFilter _filter = RunLogFilter.all;
  String _query = '';
  bool _atBottom = true;

  /// The lines the user saw when they left the bottom; shown until they come back.
  List<LogEntry>? _frozen;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _search.addListener(_onSearch);
    _scrollToEnd();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RunLogs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.isEmpty && _frozen != null) _frozen = null;
    final grew = widget.logs.lastOrNull?.seq != oldWidget.logs.lastOrNull?.seq;
    if (grew && _atBottom) _scrollToEnd();
  }

  void _onScroll() {
    final position = _scroll.position;
    final atBottom = position.pixels >= position.maxScrollExtent - _bottomSlack;
    if (atBottom == _atBottom) return;
    _atBottom = atBottom;
    final pending = !atBottom || _frozen != null;
    if (!pending) return;
    // The listener can run inside layout; the frozen list changes the next build.
    void apply() {
      if (!mounted) return;
      setState(() => _frozen = _atBottom ? null : (_frozen ?? widget.logs));
      if (_atBottom) _scrollToEnd();
    }

    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _onSearch() {
    final query = _search.text.trim().toLowerCase();
    if (query == _query) return;
    setState(() => _query = query);
    _follow();
  }

  /// Shows the end of the list again, e.g. after the filter changed.
  void _follow() {
    _atBottom = true;
    setState(() => _frozen = null);
    _scrollToEnd();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  bool _matches(LogEntry entry) {
    final filterOk = switch (_filter) {
      RunLogFilter.all => true,
      RunLogFilter.errors => entry.level == LogLevel.error,
      RunLogFilter.sent => entry.sentToAgent,
    };
    if (!filterOk) return false;
    if (_query.isEmpty) return true;
    return entry.text.toLowerCase().contains(_query) ||
        (entry.error?.title.toLowerCase().contains(_query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final frozen = _frozen;
    final latest = frozen == null
        ? null
        : <int, LogEntry>{for (final entry in widget.logs) entry.seq: entry};
    final shown = (frozen ?? widget.logs)
        .map((entry) => latest?[entry.seq] ?? entry)
        .where(_matches)
        .toList(growable: false);
    final frozenEnd = frozen?.lastOrNull?.seq;
    final fresh = frozenEnd == null
        ? 0
        : widget.logs.where((entry) => entry.seq > frozenEnd && _matches(entry)).length;
    final mono = AppText.mono(context, size: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: <Widget>[
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedControl<RunLogFilter>(
                    selected: _filter,
                    onChanged: (filter) {
                      setState(() => _filter = filter);
                      _follow();
                    },
                    segments: <(RunLogFilter, String)>[
                      (RunLogFilter.all, localization.logsAll),
                      (
                        RunLogFilter.errors,
                        widget.errorCount > 0
                            ? localization.logsErrorsCount(widget.errorCount)
                            : localization.logsErrors,
                      ),
                      (RunLogFilter.sent, localization.logsSent),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: widget.logs.isEmpty ? null : widget.onClear,
                tooltip: localization.logsClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                color: colors.muted,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          child: Row(
            children: <Widget>[
              Icon(Icons.search, size: 14, color: colors.muted),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _search,
                  style: mono,
                  cursorColor: colors.accent,
                  decoration: InputDecoration.collapsed(
                    hintText: localization.logsSearch,
                    hintStyle: mono.copyWith(color: colors.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(color: colors.border),
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final entry = shown[index];
                    final error = entry.error;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: error == null
                          ? Text(
                              entry.text,
                              style: switch (entry.level) {
                                LogLevel.info => mono,
                                LogLevel.warning => mono.copyWith(color: colors.warn),
                                LogLevel.error => mono.copyWith(color: colors.danger),
                              },
                            )
                          : RunErrorBlock(
                              error: error,
                              sent: entry.sentToAgent,
                              onSend: () => widget.onSend(entry),
                              onOpenFile: widget.onOpenFile,
                            ),
                    );
                  },
                ),
              ),
              if (fresh > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: CompactButton(
                      primary: true,
                      label: localization.logsNewLines(fresh),
                      onPressed: _follow,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
