final RegExp _command = RegExp(r'^/(\S+)(?:\s+([\s\S]*))?$');

/// The leading `/name` of the composer [text] and what follows it (trimmed); `null` when the
/// text does not start with a command.
({String name, String rest})? leadingCommand(String text) {
  final match = _command.firstMatch(text.trim());
  if (match == null) return null;
  return (name: match.group(1)!, rest: (match.group(2) ?? '').trim());
}

/// What the agent is told for the skill [name] when [rest] is all the user wrote after `/name`.
String skillPromptText(String name, String rest) => rest.isEmpty ? 'Use the $name skill.' : rest;
