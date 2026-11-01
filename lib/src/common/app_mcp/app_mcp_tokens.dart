import 'dart:convert';
import 'dart:math';

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';

/// The bearer tokens of the app's MCP server: one per chat, kept in memory only.
///
/// A token is 32 random bytes from [Random.secure], base64url-encoded. Tokens are never logged.
final class AppMcpTokens {
  /// Creates the registry.
  AppMcpTokens({required this._database});

  final AppDatabase _database;
  final Random _random = Random.secure();
  final Map<String, AppMcpCaller> _callers = <String, AppMcpCaller>{};
  final Map<int, String> _tokens = <int, String>{};

  /// A new token for the chat [sessionId] of [projectId]. The chat's previous token stops working.
  String issue(int sessionId, int projectId) {
    final previous = _tokens.remove(sessionId);
    if (previous != null) _callers.remove(previous);
    final token = base64Url.encode(List<int>.generate(32, (_) => _random.nextInt(256)));
    _tokens[sessionId] = token;
    _callers[token] = (sessionId: sessionId, projectId: projectId);
    return token;
  }

  /// The chat [token] belongs to, or null when the token is unknown, replaced, or its chat was
  /// deleted.
  Future<AppMcpCaller?> resolve(String token) async {
    final caller = _callers[token];
    if (caller == null) return null;
    final row = await (_database.select(
      _database.sessionsTable,
    )..where((session) => session.id.equals(caller.sessionId))).getSingleOrNull();
    if (row != null) return caller;
    // The chat is gone: forget its token, unless it was replaced meanwhile.
    if (_tokens[caller.sessionId] == token) {
      _tokens.remove(caller.sessionId);
      _callers.remove(token);
    }
    return null;
  }
}
