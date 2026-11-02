import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart' show appMcpServerName;

/// The forms of a tool call title (regular expressions) that name a tool of
/// the app's own MCP server, as the agents really send them; group 1 is the
/// tool. Only one so far:
///
/// * codex-acp 2.5.0: `mcp.<server>.<tool>`, in the `tool_call` update that
///   announces the call (its permission request has no title). It counts only
///   together with `rawInput` `{server, tool}` and `_meta.is_mcp_tool_call`
///   ([isAppToolPermission]): a shell command can have any title.
///
/// Gemini CLI has no form: it builds a title from a `command` argument, so
/// any server's tool can be titled `x (flutter_code_agent MCP Server)`. Its
/// app-tool calls ask the user.
///
/// The whole title must match, so `mcp.my_flutter_code_agent.x` never does.
const List<String> appToolTitleForms = <String>['^mcp\\.$appMcpServerName\\.([A-Za-z0-9_-]+)\$'];

/// Whether the `session/request_permission` [params] (raw JSON) ask for a tool
/// of the app's own MCP server ([appMcpServerName]), which the app allows
/// once without asking the user.
///
/// [announced] is the call as the agent's earlier `tool_call` updates
/// described it ([announcedToolCall]); the request's own fields win over it,
/// as an ACP `ToolCallUpdate` does.
///
/// Only Codex's calls qualify: the title in the form of [appToolTitleForms],
/// `rawInput.server` equal to the name, `rawInput.tool` equal to the titled
/// tool and `_meta.is_mcp_tool_call` `true` (codex-acp reports every MCP call
/// as kind `execute`). Argument values, `content`, `locations` and the call
/// id are never read (they can mention the name without being the app's
/// tool).
bool isAppToolPermission(Map<String, Object?> params, {Map<String, Object?>? announced}) {
  final own = params['toolCall'];
  if (own is! Map<Object?, Object?>) return false;
  final toolCall = <Object?, Object?>{...?announced, ...own};
  final title = toolCall['title'];
  if (title is! String) return false;
  final codex = RegExp(appToolTitleForms.single).firstMatch(title);
  if (codex == null) return false;
  final rawInput = toolCall['rawInput'];
  final meta = toolCall['_meta'];
  return rawInput is Map<Object?, Object?> &&
      rawInput['server'] == appMcpServerName &&
      rawInput['tool'] == codex.group(1) &&
      meta is Map<Object?, Object?> &&
      meta['is_mcp_tool_call'] == true;
}

/// The tool call [toolCallId] as the agent's `tool_call` and
/// `tool_call_update` frames among [events] describe it, merged in order
/// (later fields win); `null` when the agent announced no such call or
/// [toolCallId] is `null`.
Map<String, Object?>? announcedToolCall(Iterable<SessionEvent> events, Object? toolCallId) {
  if (toolCallId == null) return null;
  Map<String, Object?>? merged;
  for (final event in events) {
    if (event.origin != SessionEventOrigin.agent) continue;
    if (event.kind != 'tool_call' && event.kind != 'tool_call_update') continue;
    if (event.payload case {'params': {'update': final Map<Object?, Object?> update}}
        when update['toolCallId'] == toolCallId) {
      merged = <String, Object?>{
        ...?merged,
        for (final MapEntry(:key, :value) in update.entries)
          if (key is String && key != 'sessionUpdate') key: value,
      };
    }
  }
  return merged;
}
