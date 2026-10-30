// A scripted ACP agent for tests, run as a real child process over stdio.
//
// The first word of the prompt selects the behaviour:
//   echo <text>   reply with <text> in two chunks of one message
//   permission [n] ask for permission n times (default 1), reply with each selected
//                 option id or `cancelled`
//   hang          never finish until the client sends session/cancel
//   spawn         start a background process re-parented to launchd; its pid goes
//                 to the file named by FAKE_AGENT_PID_FILE
//   auth          fail with authRequired (-32000)
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
// (as a session saved in it).

import 'dart:async';
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
              auth: AgentAuthCapabilities(),
            ),
          )
          .onNewSession((_) {
            final session = 's${nextSession++}';
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
                final count = int.tryParse(rest) ?? 1;
                for (var asked = 0; asked < count; asked++) {
                  final response = await context.client.requestPermission(
                    RequestPermissionRequest(
                      sessionId: session,
                      toolCall: ToolCallUpdate(
                        toolCallId: ToolCallId('call-${asked + 1}'),
                        title: const AcpPatch<String>.set('Run `rm -rf build`'),
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

  final connection = agent.connect(acpStdioTransport());
  await connection.closed;
  exit(0);
}
