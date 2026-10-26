// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';

/// Folds a chat journal into the feed.
///
/// One pure function serves history and the live stream: live events are
/// appended to the same list and folded again. Agent frames are raw ACP
/// JSON, read leniently — an unknown field is ignored, an unknown event kind
/// becomes an [UnknownItem].
abstract final class ChatTranscript {
  /// Update kinds that carry state, not feed content.
  static const Set<String> _silentKinds = <String>{
    'usage_update',
    'session_info_update',
    'current_mode_update',
    'config_option_update',
    'available_commands_update',
    'user_message_chunk',
  };

  /// Turn ends worth a marker; `end_turn` is the normal case and is hidden.
  static const Set<String> _shownStopReasons = <String>{
    'cancelled',
    'refusal',
    'max_tokens',
    'max_turn_requests',
  };

  /// Folds [events] (any order; sorted by `seq`).
  ///
  /// Permission requests still open in this run of the app are listed in
  /// [openPermissionIds]; any other unanswered request is [PermissionState.stale].
  static List<ChatItem> fold(
    Iterable<SessionEvent> events, {
    Set<String> openPermissionIds = const <String>{},
  }) {
    final items = <ChatItem>[];
    final toolCalls = <String, int>{};
    final permissions = <String, int>{};
    int? planIndex;

    for (final event in events.toList()..sort((a, b) => a.seq.compareTo(b.seq))) {
      final payload = event.payload;
      switch (event.kind) {
        case SessionEventKind.prompt:
          items.add(_userMessage(event.seq, payload));
          planIndex = null;
        case SessionEventKind.permissionRequest:
          final item = _permission(event.seq, payload);
          if (item != null) {
            permissions[item.requestId] = items.length;
            items.add(item);
          }
        case SessionEventKind.permissionResolution:
          final index = permissions[payload['requestId']];
          if (index != null) {
            final item = items[index] as PermissionItem;
            items[index] = payload['outcome'] == 'selected'
                ? item.resolve(PermissionState.selected, optionId: _string(payload['optionId']))
                : item.resolve(PermissionState.cancelled);
          }
        case SessionEventKind.system:
          final type = _string(payload['type']) ?? 'system';
          if (type == 'turn_end') {
            final reason = _string(payload['stopReason']) ?? 'end_turn';
            if (_shownStopReasons.contains(reason))
              items.add(TurnEndItem(event.seq, stopReason: reason));
          } else {
            items.add(SystemItem(event.seq, type: type, message: _string(payload['message'])));
          }
        case SessionEventKind.turnFiles:
          // Rendered by the turn_files feature (later); nothing in the feed yet.
          break;
        default:
          final update = _map(_map(payload['params'])?['update']);
          if (update == null) {
            items.add(UnknownItem(event.seq, kind: event.kind));
            continue;
          }
          switch (event.kind) {
            case 'agent_message_chunk':
              _appendText(items, event.seq, update, thought: false);
            case 'agent_thought_chunk':
              _appendText(items, event.seq, update, thought: true);
            case 'tool_call':
              final id = _string(update['toolCallId']);
              if (id == null) continue;
              final call = ToolCallItem(
                event.seq,
                toolCallId: id,
                title: _string(update['title']) ?? '',
                kind: _string(update['kind']),
                status: _string(update['status']) ?? 'pending',
                content: _content(update['content']),
                locations: _locations(update['locations']),
              );
              final existing = toolCalls[id];
              if (existing == null) {
                toolCalls[id] = items.length;
                items.add(call);
              } else {
                items[existing] = (items[existing] as ToolCallItem).merge(
                  title: call.title.isEmpty ? null : call.title,
                  kind: call.kind,
                  status: call.status,
                  content: update.containsKey('content') ? call.content : null,
                  locations: update.containsKey('locations') ? call.locations : null,
                );
              }
            case 'tool_call_update':
              final index = toolCalls[_string(update['toolCallId'])];
              if (index == null) continue;
              items[index] = (items[index] as ToolCallItem).merge(
                title: _string(update['title']),
                kind: _string(update['kind']),
                status: _string(update['status']),
                content: update['content'] is List ? _content(update['content']) : null,
                locations: update['locations'] is List ? _locations(update['locations']) : null,
                rawOutput: _text(update['rawOutput']),
              );
            case 'plan':
              final plan = PlanItem(event.seq, entries: _planEntries(update['entries']));
              if (planIndex == null) {
                planIndex = items.length;
                items.add(plan);
              } else {
                items[planIndex] = PlanItem(items[planIndex].seq, entries: plan.entries);
              }
            default:
              if (!_silentKinds.contains(event.kind))
                items.add(UnknownItem(event.seq, kind: event.kind));
          }
      }
    }

    for (final index in permissions.values) {
      final item = items[index] as PermissionItem;
      if (item.state == PermissionState.pending && !openPermissionIds.contains(item.requestId)) {
        items[index] = item.resolve(PermissionState.stale);
      }
    }
    return items;
  }

  static UserMessageItem _userMessage(int seq, Map<String, Object?> payload) {
    final blocks =
        _list(payload['prompt']) ?? _list(_map(payload['params'])?['prompt']) ?? const <Object?>[];
    final text = StringBuffer();
    final resources = <String>[];
    for (final block in blocks.map(_map).whereType<Map<String, Object?>>()) {
      switch (block['type']) {
        case 'text':
          text.write(_string(block['text']) ?? '');
        case 'resource_link':
          if (_string(block['uri']) case final String uri) resources.add(uri);
      }
    }
    return UserMessageItem(seq, text: text.toString(), resources: resources);
  }

  static void _appendText(
    List<ChatItem> items,
    int seq,
    Map<String, Object?> update, {
    required bool thought,
  }) {
    final content = _map(update['content']);
    final text = content?['type'] == 'text' ? _string(content?['text']) ?? '' : '';
    final messageId = _string(update['messageId']);
    final last = items.isEmpty ? null : items.last;
    // Consecutive chunks of one message merge; a new messageId starts a new item.
    if (thought) {
      if (last is AgentThoughtItem && last.messageId == messageId) {
        items[items.length - 1] = AgentThoughtItem(
          last.seq,
          text: last.text + text,
          messageId: messageId,
        );
        return;
      }
      items.add(AgentThoughtItem(seq, text: text, messageId: messageId));
    } else {
      if (last is AgentMessageItem && last.messageId == messageId) {
        items[items.length - 1] = AgentMessageItem(
          last.seq,
          text: last.text + text,
          messageId: messageId,
        );
        return;
      }
      items.add(AgentMessageItem(seq, text: text, messageId: messageId));
    }
  }

  static PermissionItem? _permission(int seq, Map<String, Object?> payload) {
    final requestId = _string(payload['requestId']);
    final params = _map(payload['params']);
    if (requestId == null || params == null) return null;
    final toolCall = _map(params['toolCall']);
    final content = _content(toolCall?['content']);
    final rawInput = _map(toolCall?['rawInput']);
    return PermissionItem(
      seq,
      requestId: requestId,
      title: _string(toolCall?['title']) ?? 'The agent asks for permission',
      toolCallId: _string(toolCall?['toolCallId']),
      diffs: content.whereType<ToolDiffContent>().toList(),
      command: _string(rawInput?['command']),
      options: <PermissionOptionView>[
        for (final option in (_list(params['options']) ?? const <Object?>[]).map(_map))
          if (option != null && _string(option['optionId']) != null)
            PermissionOptionView(
              optionId: _string(option['optionId'])!,
              name: _string(option['name']) ?? _string(option['optionId'])!,
              kind: _string(option['kind']) ?? 'allow_once',
            ),
      ],
    );
  }

  static List<ToolContent> _content(Object? value) => <ToolContent>[
    for (final block in (_list(value) ?? const <Object?>[]).map(_map))
      if (block != null)
        ...switch (block['type']) {
          'diff' when _string(block['path']) != null => <ToolContent>[
            ToolDiffContent(
              path: _string(block['path'])!,
              oldText: _string(block['oldText']),
              newText: _string(block['newText']) ?? '',
            ),
          ],
          'content' => <ToolContent>[
            if (_map(block['content']) case {'type': 'text', 'text': final String text})
              ToolTextContent(text),
          ],
          _ => const <ToolContent>[],
        },
  ];

  static List<String> _locations(Object? value) => <String>[
    for (final location in (_list(value) ?? const <Object?>[]).map(_map))
      if (_string(location?['path']) case final String path) path,
  ];

  static List<PlanEntry> _planEntries(Object? value) => <PlanEntry>[
    for (final entry in (_list(value) ?? const <Object?>[]).map(_map))
      if (entry != null)
        PlanEntry(
          content: _string(entry['content']) ?? '',
          status: _string(entry['status']) ?? 'pending',
        ),
  ];

  static Map<String, Object?>? _map(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => null,
  };

  static List<Object?>? _list(Object? value) => value is List<Object?> ? value : null;

  static String? _string(Object? value) => value is String ? value : null;

  /// Tool output may be a string or structured JSON.
  static String? _text(Object? value) => switch (value) {
    null => null,
    final String text => text,
    _ => '$value',
  };
}
