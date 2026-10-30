import 'package:meta/meta.dart';

// `/` commands in the prompt text.

/// Who runs a [SlashCommand].
enum SlashSource {
  /// The app itself (run, reload, …).
  app,

  /// The agent (its ACP `availableCommands`).
  agent,
}

/// {@template slash_command}
/// One entry of the `/` menu: [name] without the slash.
/// {@endtemplate}
@immutable
final class SlashCommand {
  /// {@macro slash_command}
  const SlashCommand({
    required this.name,
    required this.source,
    this.description,
    this.enabled = true,
    this.hint,
  });

  /// Name without the leading `/`; has no whitespace.
  final String name;

  /// What the command does, if known.
  final String? description;

  /// Who runs the command.
  final SlashSource source;

  /// The command can be inserted now.
  final bool enabled;

  /// Why a disabled command cannot be used: the milestone it comes in (`M2`).
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is SlashCommand &&
      other.name == name &&
      other.description == description &&
      other.source == source &&
      other.enabled == enabled &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(name, description, source, enabled, hint);
}

final RegExp _whitespace = RegExp(r'\s');

/// Commands of the app. All wait for the run/debug milestone.
const List<SlashCommand> appCommands = <SlashCommand>[
  SlashCommand(name: 'run', source: SlashSource.app, enabled: false, hint: 'M2'),
  SlashCommand(name: 'reload', source: SlashSource.app, enabled: false, hint: 'M2'),
  SlashCommand(name: 'restart', source: SlashSource.app, enabled: false, hint: 'M2'),
  SlashCommand(name: 'screenshot', source: SlashSource.app, enabled: false, hint: 'M2'),
];

/// Commands of the agent from the raw ACP `availableCommands` ([raw] entries are
/// `{name, description?, input?}`). Entries without a usable name are skipped and
/// of equal names the first one wins.
List<SlashCommand> agentCommands(List<Map<String, Object?>> raw) {
  final seen = <String>{};
  final commands = <SlashCommand>[];
  for (final entry in raw) {
    final name = entry['name'];
    if (name is! String || name.isEmpty || name.contains(_whitespace) || !seen.add(name)) {
      continue;
    }
    final description = entry['description'];
    commands.add(
      SlashCommand(
        name: name,
        source: SlashSource.agent,
        description: description is String && description.isNotEmpty ? description : null,
      ),
    );
  }
  return commands;
}

/// Up to [limit] of [all] matching [query] (case does not matter): a name
/// prefix first, then a name containing it, then a description containing it.
/// Of equal rank the order of [all] stays.
List<SlashCommand> searchCommands(List<SlashCommand> all, String query, {int limit = 12}) {
  final needle = query.toLowerCase();
  if (needle.isEmpty) return all.take(limit).toList();
  final ranked = <(int, int, SlashCommand)>[];
  for (final (index, command) in all.indexed) {
    final name = command.name.toLowerCase();
    final rank = name.startsWith(needle)
        ? 0
        : name.contains(needle)
        ? 1
        : (command.description?.toLowerCase().contains(needle) ?? false)
        ? 2
        : null;
    if (rank != null) ranked.add((rank, index, command));
  }
  ranked.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });
  return <SlashCommand>[for (final (_, _, command) in ranked.take(limit)) command];
}

/// What the `/` menu shows for [query]: matching [app] commands, then matching
/// [agent] commands, [limit] rows in all.
List<SlashCommand> slashSuggestions(
  List<SlashCommand> app,
  List<SlashCommand> agent,
  String query, {
  int limit = 12,
}) {
  final apps = searchCommands(app, query, limit: limit);
  return <SlashCommand>[...apps, ...searchCommands(agent, query, limit: limit - apps.length)];
}

final RegExp _slash = RegExp(r'^/(\S*)$');

/// The query of the `/` command being typed right before [cursor]: the text
/// after the slash. `null` unless the text up to the cursor is a slash at the
/// start followed by no whitespace.
String? slashQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  return _slash.firstMatch(text.substring(0, cursor))?.group(1);
}
