import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:meta/meta.dart';

/// One row of the feed: a single item or several folded together.
@immutable
sealed class FeedEntry {
  const FeedEntry();

  /// Stable list key: `seq` of the first item.
  int get seq;
}

/// A feed item shown as is.
final class SingleEntry extends FeedEntry {
  /// Creates an entry for [item].
  const SingleEntry(this.item);

  /// The item.
  final ChatItem item;

  @override
  int get seq => item.seq;
}

/// Two or more consecutive file reads shown as one row.
final class ReadGroupEntry extends FeedEntry {
  /// Creates a group of [calls].
  const ReadGroupEntry(this.calls);

  /// The read calls, in order.
  final List<ToolCallItem> calls;

  @override
  int get seq => calls.first.seq;
}

bool _isGroupableRead(ChatItem item) =>
    item is ToolCallItem && item.kind == 'read' && item.status != 'failed';

/// Folds runs of 2+ consecutive successful `read` tool calls into a
/// [ReadGroupEntry]; every other item stays a [SingleEntry].
List<FeedEntry> groupFeed(List<ChatItem> items) {
  final entries = <FeedEntry>[];
  var i = 0;
  while (i < items.length) {
    var end = i;
    if (_isGroupableRead(items[i])) {
      while (end + 1 < items.length && _isGroupableRead(items[end + 1])) {
        end++;
      }
    }
    if (end > i) {
      entries.add(ReadGroupEntry(items.sublist(i, end + 1).cast<ToolCallItem>()));
    } else {
      entries.add(SingleEntry(items[i]));
    }
    i = end + 1;
  }
  return entries;
}
