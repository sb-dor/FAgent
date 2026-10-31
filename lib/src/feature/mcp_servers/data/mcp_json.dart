import 'dart:convert';

import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';

/// What a `.mcp.json` holds: the servers that can be added and the entries left out, each with an
/// English reason code (`sse is not supported`, `no command or url`).
typedef McpJsonEntries = ({
  List<McpServerDraft> servers,
  List<(String name, String reason)> skipped,
});

/// Reads the `mcpServers` object of a `.mcp.json` [text].
///
/// An entry with a `command` is `stdio`; one with a `url` (and `type: "http"` or no type) is `http`.
/// Throws [McpJsonException] when [text] is not JSON or has no `mcpServers` object.
McpJsonEntries parseMcpJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw McpJsonException('not JSON: ${error.message}');
  }
  final servers = decoded is Map<String, Object?> ? decoded['mcpServers'] : null;
  if (servers is! Map<String, Object?>) throw const McpJsonException('no mcpServers object');

  final drafts = <McpServerDraft>[];
  final skipped = <(String, String)>[];
  for (final MapEntry(key: name, value: entry) in servers.entries) {
    if (entry is! Map<String, Object?>) {
      skipped.add((name, 'no command or url'));
      continue;
    }
    final type = entry['type'];
    final command = _text(entry['command']);
    final url = _text(entry['url']);
    if (type == 'sse') {
      skipped.add((name, 'sse is not supported'));
    } else if (type == 'http' || (command == null && url != null)) {
      if (url == null) {
        skipped.add((name, 'no command or url'));
      } else {
        drafts.add(
          McpServerDraft(
            name: name,
            transport: McpTransport.http,
            url: url,
            headers: _strings(entry['headers']),
          ),
        );
      }
    } else if (command != null) {
      drafts.add(
        McpServerDraft(
          name: name,
          transport: McpTransport.stdio,
          command: command,
          args: [
            if (entry['args'] case final List<Object?> args)
              for (final arg in args)
                if (arg != null) '$arg',
          ],
          env: _strings(entry['env']),
        ),
      );
    } else {
      skipped.add((name, 'no command or url'));
    }
  }
  return (servers: drafts, skipped: skipped);
}

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

Map<String, String> _strings(Object? value) => {
  if (value is Map<String, Object?>)
    for (final MapEntry(:key, :value) in value.entries)
      if (value != null) key: '$value',
};
