// A scripted ACP agent for tests, run as a real child process over stdio.
//
// The first word of the prompt selects the behaviour:
//   echo <text>   reply with <text> in two chunks of one message
//   permission    ask for permission, reply with the selected option id or `cancelled`
//   hang          never finish until the client sends session/cancel
//   spawn         start a background process re-parented to launchd; its pid goes
//                 to the file named by FAKE_AGENT_PID_FILE
//   auth          fail with authRequired (-32000)
//   stderr <text> write <text> to stderr, then reply `ok`
//   crash         exit the process with code 3
// Run with `--cli auth login <method>` it prints a line and exits 0 (login).
// session/load replays one user and one agent message for the loaded session;
// loading the id `missing` fails with -32002 like the real adapter.

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
          .onNewSession((_) => NewSessionResponse(sessionId: SessionId('s${nextSession++}')))
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
            return LoadSessionResponse();
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
                final response = await context.client.requestPermission(
                  RequestPermissionRequest(
                    sessionId: session,
                    toolCall: ToolCallUpdate(
                      toolCallId: ToolCallId('call-1'),
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
              default:
                await say(context.client, session, 'unknown command: $command');
            }
            return PromptResponse(stopReason: StopReason.endTurn);
          });

  final connection = agent.connect(acpStdioTransport());
  await connection.closed;
  exit(0);
}
