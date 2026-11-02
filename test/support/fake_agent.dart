// A scripted ACP agent for tests, run as a real child process over stdio.
//
// The first word of the prompt selects the behaviour:
//   echo <text>   reply with <text> in two chunks of one message
//   permission [n] [title=<t>]
//                 ask for permission n times (default 1) for a tool call titled <t>
//                 (default: Run `rm -rf build`), reply with each selected option id
//                 or `cancelled`
//   mcp-call <codex|gemini|gemini-command> <server> <tool> [always-only]
//                 announce a call of MCP tool <tool> of <server> with a tool_call update and
//                 ask for permission for it, both as that agent sends them, with its option
//                 list (codex-acp 2.5.0: identity only in the update, the request names just
//                 the call; Gemini CLI 0.66.0: `<tool> (<server> MCP Server)` in both;
//                 `gemini-command`: the title Gemini takes from a `command` argument,
//                 `x (flutter_code_agent MCP Server)`; the Gemini titles are reconstructed
//                 from the Gemini CLI 0.66.0 source, not recorded from a running CLI).
//                 `always-only` drops the allow-once option. Call ids come from a counter.
//                 Replies like `permission`
//   hang          never finish until the client sends session/cancel
//   spawn         start a background process re-parented to launchd; its pid goes
//                 to the file named by FAKE_AGENT_PID_FILE
//   auth          fail with authRequired (-32000) until `authenticate` succeeded, then
//                 reply `authenticated`
//   stderr <text> write <text> to stderr, then reply `ok`
//   crash         exit the process with code 3
//   say-crash <t> reply with <t>, then exit with code 3
//   garbage       write a line that is not JSON to stdout, then reply `ok`
// Run with `--cli auth login <method>` it prints a line and exits 0 (login).
// session/load replays one user and one agent message for the loaded session;
// loading the id `missing` fails with -32002 like the real adapter.
// Sessions have a `mode` select option (default, acceptEdits, bypassPermissions)
// that session/set_config_option changes, plus a `model` select (m1, m2, bad, slow,
// cmd) and an `effort` select (low, high). Setting model `bad` fails with an error,
// `slow` is never answered, `cmd` first sends an available_commands_update.
// A loaded session whose id starts with `bypass` is in bypassPermissions mode
// (as a session saved in it). With FAKE_AGENT_NEW_SESSION_MODE=<mode> new sessions
// start in that mode (as with a default mode from the user's agent settings).
// With FAKE_AGENT_REQUESTS_FILE set, the params of every session/new,
// session/load, authenticate and logout are appended to that file as JSON lines
// {"method", "params"}; `authenticate` also appends the client's capabilities as
// {"method": "client/capabilities", "params"}. session/new and session/load are
// recorded raw, as they came over the wire, so params the SDK does not model (a
// top-level `systemPrompt`) are kept.
// Sign-in: the agent offers `browser-login` and `api-key` (with
// `_meta.api-key.provider: fake`) and can log out. `authenticate` succeeds, or
// fails with FAKE_AGENT_AUTH_FAIL=1, or never answers with FAKE_AGENT_AUTH_HANG=1.
// `logout` forgets a successful `authenticate`.
// With FAKE_AGENT_AUTH_STATUS=<kind>:<label> (for example `account:ChatGPT Plus`) the agent
// pushes an `_auth/status_update` notification right after answering `initialize`,
// like codex-acp does for clients that advertise `_meta.authStatus`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart';

Future<void> main(List<String> arguments) async {
  // `--cli auth login …` pretends to be the adapter's login command.
  if (arguments.isNotEmpty && arguments.first == '--cli') {
    stdout.writeln('Logged in (${arguments.last})');
    exit(0);
  }
  var nextSession = 0;
  final cancels = <String, Completer<void>>{};
  final modes = <String, String>{};
  final models = <String, String>{};
  final efforts = <String, String>{};
  var authenticated = false;

  Map<String, Object?> select(String id, String current, List<String> values) => <String, Object?>{
    'id': id,
    'name': id,
    'type': 'select',
    'currentValue': current,
    'options': <Map<String, Object?>>[
      for (final value in values) <String, Object?>{'value': value, 'name': value},
    ],
  };

  List<Map<String, Object?>> configOptions(String session) => <Map<String, Object?>>[
    <String, Object?>{
      'id': 'mode',
      'name': 'Mode',
      'category': 'mode',
      'type': 'select',
      'currentValue': modes[session] ?? 'default',
      'options': <Map<String, Object?>>[
        <String, Object?>{'value': 'default', 'name': 'Manual'},
        <String, Object?>{'value': 'acceptEdits', 'name': 'Accept edits'},
        <String, Object?>{'value': 'bypassPermissions', 'name': 'Bypass permissions'},
      ],
    },
    select('model', models[session] ?? 'm1', <String>['m1', 'm2', 'bad', 'slow', 'cmd']),
    select('effort', efforts[session] ?? 'low', <String>['low', 'high']),
  ];

  void record(String method, Map<String, Object?> params) {
    final file = Platform.environment['FAKE_AGENT_REQUESTS_FILE'];
    if (file == null) return;
    File(file).writeAsStringSync(
      '${jsonEncode(<String, Object?>{'method': method, 'params': params})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  // Ids of the tool calls `mcp-call` announces.
  var toolCalls = 0;

  Future<void> say(AcpAgentContext client, SessionId session, String text, {String? id}) =>
      client.updateSession(
        SessionNotification(
          sessionId: session,
          update: SessionUpdateAgentMessageChunk(
            ContentChunk(
              content: ContentBlockText(TextContent(text: text)),
              messageId: id == null ? null : MessageId(id),
            ),
          ),
        ),
      );

  final agent =
      AcpAgentApp.v1(
            implementation: Implementation(name: 'fake-agent', version: '1.0.0'),
            capabilities: AgentCapabilities(
              loadSession: true,
              promptCapabilities: PromptCapabilities(
                image: false,
                audio: false,
                embeddedContext: true,
              ),
              mcpCapabilities: McpCapabilities(http: false, sse: false),
              sessionCapabilities: SessionCapabilities(),
              auth: AgentAuthCapabilities(logout: LogoutCapabilities()),
            ),
            authMethods: <AuthMethod>[
              AuthMethodAgentVariant(
                AuthMethodAgent(id: AuthMethodId('browser-login'), name: 'Browser login'),
              ),
              AuthMethodAgentVariant(
                AuthMethodAgent(
                  id: AuthMethodId('api-key'),
                  name: 'API key',
                  meta: AcpJsonObject.fromObject(<String, Object?>{
                    'api-key': <String, Object?>{'provider': 'fake'},
                  }),
                ),
              ),
            ],
          )
          .onAuthenticate((context) async {
            record('authenticate', context.params.toJson());
            record('client/capabilities', <String, Object?>{
              'capabilities': context.client.lifecycle.peerCapabilities.value.toObject(),
            });
            if (Platform.environment['FAKE_AGENT_AUTH_HANG'] == '1') {
              await Completer<void>().future;
            }
            if (Platform.environment['FAKE_AGENT_AUTH_FAIL'] == '1') {
              throw JsonRpcRequestException(
                JsonRpcErrorObject(code: -32000, message: 'Sign-in failed'),
              );
            }
            authenticated = true;
            return AuthenticateResponse();
          })
          .onLogout((context) {
            record('logout', context.params.toJson());
            authenticated = false;
            return LogoutResponse();
          })
          .onNewSession((context) {
            final session = 's${nextSession++}';
            if (Platform.environment['FAKE_AGENT_NEW_SESSION_MODE'] case final String mode) {
              modes[session] = mode;
            }
            return NewSessionResponse.fromJson(<String, Object?>{
              'sessionId': session,
              'configOptions': configOptions(session),
            });
          })
          .onSetSessionConfigOption((context) async {
            final session = context.params.sessionId.value;
            final request = context.params.toJson();
            final value = '${request['value']}';
            if (request['configId'] == 'mode') modes[session] = value;
            if (request['configId'] == 'effort') efforts[session] = value;
            if (request['configId'] == 'model') {
              if (value == 'bad') {
                throw JsonRpcRequestException(
                  JsonRpcErrorObject(code: -32602, message: 'Unsupported model'),
                );
              }
              if (value == 'slow') await Completer<void>().future;
              if (value == 'cmd') {
                await context.client.updateSession(
                  SessionNotification(
                    sessionId: context.params.sessionId,
                    update: SessionUpdateAvailableCommandsUpdate(
                      AvailableCommandsUpdate(
                        availableCommands: <AvailableCommand>[
                          AvailableCommand(name: 'late', description: 'sent while setting up'),
                        ],
                      ),
                    ),
                  ),
                );
              }
              models[session] = value;
            }
            return SetSessionConfigOptionResponse.fromJson(<String, Object?>{
              'configOptions': configOptions(session),
            });
          })
          .onLoadSession((context) async {
            final session = context.params.sessionId;
            if (session.value == 'missing') {
              throw JsonRpcRequestException(
                JsonRpcErrorObject(code: -32002, message: 'Resource not found: missing'),
              );
            }
            await context.client.updateSession(
              SessionNotification(
                sessionId: session,
                update: SessionUpdateUserMessageChunk(
                  ContentChunk(content: ContentBlockText(TextContent(text: 'earlier prompt'))),
                ),
              ),
            );
            await say(context.client, session, 'earlier answer');
            if (session.value.startsWith('bypass')) modes[session.value] = 'bypassPermissions';
            return LoadSessionResponse.fromJson(<String, Object?>{
              'configOptions': configOptions(session.value),
            });
          })
          .onCancelSession((context) {
            cancels.remove(context.params.sessionId.value)?.complete();
          })
          .onPrompt((context) async {
            final session = context.params.sessionId;
            final text = <String>[
              for (final block in context.params.prompt)
                if (block case ContentBlockText(:final value)) value.text,
            ].join(' ');
            final command = text.split(' ').first;
            final rest = text.substring(command.length).trim();
            switch (command) {
              case 'echo':
                final half = rest.length ~/ 2;
                await say(context.client, session, rest.substring(0, half), id: 'm1');
                await say(context.client, session, rest.substring(half), id: 'm1');
              case 'permission':
                final words = rest.split(' ');
                final count = words.map(int.tryParse).nonNulls.firstOrNull ?? 1;
                final title =
                    words
                        .where((word) => word.startsWith('title='))
                        .map((word) => word.substring('title='.length))
                        .firstOrNull ??
                    'Run `rm -rf build`';
                for (var asked = 0; asked < count; asked++) {
                  final response = await context.client.requestPermission(
                    RequestPermissionRequest(
                      sessionId: session,
                      toolCall: ToolCallUpdate(
                        toolCallId: ToolCallId('call-${asked + 1}'),
                        title: AcpPatch<String>.set(title),
                      ),
                      options: <PermissionOption>[
                        PermissionOption(
                          optionId: PermissionOptionId('allow'),
                          name: 'Allow',
                          kind: PermissionOptionKind.allowOnce,
                        ),
                        PermissionOption(
                          optionId: PermissionOptionId('reject'),
                          name: 'Reject',
                          kind: PermissionOptionKind.rejectOnce,
                        ),
                      ],
                    ),
                  );
                  await say(context.client, session, switch (response.outcome) {
                    RequestPermissionOutcomeSelected(:final value) => value.optionId.value,
                    _ => 'cancelled',
                  });
                }
              case 'mcp-call':
                final [style, server, tool, ...flags] = rest.split(' ');
                final alwaysOnly = flags.contains('always-only');
                final id = ++toolCalls;
                final codex = style == 'codex';
                final announced = codex
                    ? <String, Object?>{
                        'toolCallId': 'exec-$id',
                        'kind': 'execute',
                        'title': 'mcp.$server.$tool',
                        'status': 'in_progress',
                        'rawInput': <String, Object?>{
                          'server': server,
                          'tool': tool,
                          'arguments': <String, Object?>{},
                        },
                        '_meta': <String, Object?>{'is_mcp_tool_call': true},
                      }
                    : <String, Object?>{
                        'toolCallId': '${server}_$tool-1793609305463-$id',
                        'status': 'pending',
                        'title': style == 'gemini-command'
                            ? 'x (flutter_code_agent MCP Server)'
                            : '$tool ($server MCP Server)',
                        'content': <Object?>[],
                        'locations': <Object?>[],
                        'kind': 'other',
                      };
                Map<String, Object?> option(String optionId, String kind) => <String, Object?>{
                  'optionId': optionId,
                  'name': optionId,
                  'kind': kind,
                };
                final options = codex
                    ? <Map<String, Object?>>[
                        if (!alwaysOnly) option('allow_once', 'allow_once'),
                        option('allow_session', 'allow_always'),
                        option('allow_always', 'allow_always'),
                        option('cancel', 'reject_once'),
                      ]
                    : <Map<String, Object?>>[
                        option('proceed_always_server', 'allow_always'),
                        option('proceed_always_tool', 'allow_always'),
                        if (!alwaysOnly) option('proceed_once', 'allow_once'),
                        option('cancel', 'reject_once'),
                      ];
                await context.client.updateSession(
                  SessionNotification.fromJson(<String, Object?>{
                    'sessionId': session.value,
                    'update': <String, Object?>{'sessionUpdate': 'tool_call', ...announced},
                  }),
                );
                final response = await context.client.requestPermission(
                  RequestPermissionRequest.fromJson(<String, Object?>{
                    'sessionId': session.value,
                    'toolCall': codex
                        ? <String, Object?>{
                            'toolCallId': 'exec-$id',
                            'kind': 'execute',
                            'status': 'pending',
                          }
                        : announced,
                    'options': options,
                  }),
                );
                await say(context.client, session, switch (response.outcome) {
                  RequestPermissionOutcomeSelected(:final value) => value.optionId.value,
                  _ => 'cancelled',
                });
              case 'hang':
                final cancelled = Completer<void>();
                cancels[session.value] = cancelled;
                await cancelled.future;
                return PromptResponse(stopReason: StopReason.cancelled);
              case 'spawn':
                final pidFile = Platform.environment['FAKE_AGENT_PID_FILE']!;
                await Process.run('/bin/sh', <String>[
                  '-c',
                  '( sleep 300 >/dev/null 2>&1 & echo \$! > "$pidFile" )',
                ]);
                await say(context.client, session, 'spawned');
              case 'auth' when authenticated:
                await say(context.client, session, 'authenticated');
              case 'auth':
                throw JsonRpcRequestException(
                  JsonRpcErrorObject(code: -32000, message: 'Authentication required'),
                );
              case 'stderr':
                stderr.writeln(rest);
                await say(context.client, session, 'ok');
              case 'crash':
                exit(3);
              case 'say-crash':
                await say(context.client, session, rest);
                // Let the frame reach the client before dying.
                await Future<void>.delayed(const Duration(milliseconds: 200));
                exit(3);
              case 'garbage':
                stdout.writeln('{this is not json');
                await stdout.flush();
                await say(context.client, session, 'ok');
              default:
                await say(context.client, session, 'unknown command: $command');
            }
            return PromptResponse(stopReason: StopReason.endTurn);
          });

  // The SDK's request models drop params they do not know: record session/new and
  // session/load from the raw frames.
  final stdio = acpStdioTransport();
  final connection = agent.connect(
    AcpDuplexStream<Object?>(
      readable: stdio.readable.map((frame) {
        for (final message in frame is List<Object?> ? frame : <Object?>[frame]) {
          if (message
              case {'method': final String method, 'params': final Map<String, Object?> params}
              when method == 'session/new' || method == 'session/load') {
            record(method, params);
          }
        }
        return frame;
      }),
      writable: stdio.writable,
    ),
  );
  final authStatus = Platform.environment['FAKE_AGENT_AUTH_STATUS'];
  if (authStatus != null) {
    unawaited(
      connection.lifecycle.ready.then((_) async {
        // Let the `initialize` response reach the client first.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final colon = authStatus.indexOf(':');
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'method': '_auth/status_update',
            'params': <String, Object?>{
              'authStatus': <String, Object?>{
                'kind': authStatus.substring(0, colon),
                'label': authStatus.substring(colon + 1),
                // The real adapter sends the account; the app must never keep it.
                'account': <String, Object?>{'email': 'user@example.com'},
              },
            },
          }),
        );
        await stdout.flush();
      }),
    );
  }
  await connection.closed;
  exit(0);
}
