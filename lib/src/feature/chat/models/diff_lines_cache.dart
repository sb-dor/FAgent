import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/utils/line_diff.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// Line diffs of tool calls, computed once per distinct change.
///
/// The feed is folded again for every journal event, so the diff objects are
/// new each time while their texts stay equal; the diff (LCS, O(n·m)) must
/// not run on the UI thread for each streamed chunk.
class DiffLinesCache {
  final Map<(String?, String), List<DiffLine>> _entries = <(String?, String), List<DiffLine>>{};

  /// How many diffs were actually computed (for tests).
  @visibleForTesting
  int computeCount = 0;

  /// Diff lines of each of [diffs], in order; anything not among [diffs] is
  /// forgotten.
  List<List<DiffLine>> resolve(List<ToolDiffContent> diffs) {
    final keys = <(String?, String)>[for (final d in diffs) (d.oldText, d.newText)];
    final lines = <List<DiffLine>>[
      for (final key in keys)
        _entries.putIfAbsent(key, () {
          computeCount++;
          return LineDiff.compute(key.$1, key.$2);
        }),
    ];
    _entries.removeWhere((key, _) => !keys.contains(key));
    return lines;
  }
}
