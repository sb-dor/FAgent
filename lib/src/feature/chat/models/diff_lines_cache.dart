import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:l/l.dart';

/// Line diffs of tool calls, computed once per distinct change.
///
/// The feed is folded again for every journal event, so the diff objects are
/// new each time while their texts stay equal; the diff (LCS, O(n·m)) must
/// not run on the UI thread for each streamed chunk. Small diffs are computed
/// at once; large ones on a background isolate, and [onReady] fires when one
/// lands (or failed, and shows every line as changed).
class DiffLinesCache {
  /// Creates a cache that calls [onReady] when a background diff is done.
  DiffLinesCache({required this.onReady});

  /// Called once per background diff that landed, never after [dispose].
  final VoidCallback onReady;

  final Map<(String?, String), List<DiffLine>> _entries = <(String?, String), List<DiffLine>>{};
  final Set<(String?, String)> _pending = <(String?, String)>{};
  bool _disposed = false;

  /// How many diffs were actually computed (for tests).
  @visibleForTesting
  int computeCount = 0;

  /// Diff lines of each of [diffs], in order; `null` while it is still being
  /// computed. Anything not among [diffs] is forgotten.
  List<List<DiffLine>?> resolve(List<ToolDiffContent> diffs) {
    final keys = <(String?, String)>[for (final d in diffs) (d.oldText, d.newText)];
    final lines = <List<DiffLine>?>[for (final key in keys) _entries[key] ?? _start(key)];
    _entries.removeWhere((key, _) => !keys.contains(key));
    _pending.removeWhere((key) => !keys.contains(key));
    return lines;
  }

  List<DiffLine>? _start((String?, String) key) {
    if (_pending.contains(key)) return null;
    computeCount++;
    if (LineDiff.cells(key.$1, key.$2) <= LineDiff.syncCells) {
      return _entries[key] = LineDiff.compute(key.$1, key.$2);
    }
    _pending.add(key);
    unawaited(_computeInBackground(key));
    return null;
  }

  /// A diff that fails on the background isolate shows as [LineDiff.allChanged], so the card
  /// does not wait for it forever.
  Future<void> _computeInBackground((String?, String) key) async {
    List<DiffLine> lines;
    try {
      lines = await LineDiff.computeAsync(key.$1, key.$2);
    } on Object catch (error, stackTrace) {
      l.w('DiffLinesCache | the diff failed, showing every line as changed: $error', stackTrace);
      lines = LineDiff.allChanged(key.$1, key.$2);
    }
    if (_disposed || !_pending.remove(key)) return;
    _entries[key] = lines;
    onReady();
  }

  /// Stops [onReady] for diffs still being computed.
  void dispose() => _disposed = true;
}
