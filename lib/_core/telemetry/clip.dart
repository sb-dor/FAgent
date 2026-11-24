/// The longest text the log and the queue accept whole, in characters.
const int logClipLength = 16384;

/// Cuts [text] to [logClipLength] characters and appends `…` when something was dropped.
/// Never splits a surrogate pair.
String clipForLog(String text) {
  if (text.length <= logClipLength) {
    return text;
  }
  return '${cutSafely(text, logClipLength)}…';
}

/// The first [max] characters of [text], without a dangling half of a surrogate pair.
String cutSafely(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  var end = max;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    end--;
  }
  return text.substring(0, end);
}
