import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;
  late AppDatabase database;
  late int projectId;
  late File prompts;
  final hubs = <AgentHub>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_hub_images_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
    prompts = File('${temp.path}/prompts-${DateTime.now().microsecondsSinceEpoch}.jsonl');
  });

  tearDown(() async {
    for (final hub in hubs) {
      await hub.dispose();
    }
    hubs.clear();
    await database.close();
  });

  AgentHub newHub() {
    final agent = AgentDefinition(
      id: 'fake',
      displayName: fakeAgent.displayName,
      executable: fakeAgent.executable,
      environment: <String, String>{
        ...fakeAgent.environment,
        'FAKE_AGENT_PROMPTS_FILE': prompts.path,
      },
    );
    final hub = AgentHub(
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{'fake': agent},
      connector: (definition, onPermission) => AgentConnection.start(
        definition: definition,
        environment: environment,
        onPermissionRequest: onPermission,
        initializeTimeout: const Duration(seconds: 20),
      ),
      cancelTimeout: const Duration(seconds: 1),
    );
    hubs.add(hub);
    return hub;
  }

  Future<int> newChat({String? acpSessionId}) => database
      .into(database.sessionsTable)
      .insert(
        SessionsTableCompanion.insert(
          projectId: projectId,
          agentId: 'fake',
          acpSessionId: acpSessionId == null
              ? const Value<String?>.absent()
              : Value<String?>(acpSessionId),
        ),
      );

  /// The prompt blocks of every `session/prompt` the agent received, as they came over the wire.
  List<List<Map<String, Object?>>> received() => !prompts.existsSync()
      ? const <List<Map<String, Object?>>>[]
      : <List<Map<String, Object?>>>[
          for (final line in prompts.readAsLinesSync())
            if (line.isNotEmpty)
              <Map<String, Object?>>[
                for (final block
                    in ((jsonDecode(line) as Map<String, Object?>)['params']!
                            as Map<String, Object?>)['prompt']!
                        as List<Object?>)
                  (block! as Map<String, Object?>),
              ],
        ];

  final full = base64Encode(Uint8List.fromList(List<int>.generate(200 * 1024, (i) => i % 251)));
  const thumbnail = 'dGh1bWJuYWls';

  /// An image block as the composer builds it: the full image and the app's thumbnail.
  Map<String, Object?> composerImage() => <String, Object?>{
    'type': 'image',
    'mimeType': 'image/jpeg',
    'data': full,
    '_meta': <String, Object?>{
      'flutter_code_agent': <String, Object?>{
        'thumbnail': thumbnail,
        'thumbnailMimeType': 'image/png',
      },
    },
  };

  const agentImage = <String, Object?>{'type': 'image', 'mimeType': 'image/jpeg'};

  test('the agent gets the full image without the app meta; the journal the thumbnail', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    await hub.prompt(chat, 'echo look', resources: <Map<String, Object?>>[composerImage()]);

    final sent = received().single;
    expect(sent.first, <String, Object?>{'type': 'text', 'text': 'echo look'});
    expect(sent.last, <String, Object?>{...agentImage, 'data': full});
    final journaled = live.store.events.singleWhere((e) => e.kind == SessionEventKind.prompt);
    final block = (journaled.payload['prompt']! as List<Object?>).last! as Map<String, Object?>;
    expect(block, <String, Object?>{
      'type': 'image',
      'mimeType': 'image/png',
      'data': thumbnail,
      '_meta': <String, Object?>{
        'flutter_code_agent': <String, Object?>{'thumbnail': true},
      },
    });
    expect(jsonEncode(journaled.payload).length, lessThan(full.length ~/ 100));
    final message = ChatTranscript.fold(live.store.events).whereType<UserMessageItem>().single;
    expect(message.images, const <MessageImage>[
      MessageImage(mimeType: 'image/png', data: thumbnail, isThumbnail: true),
    ]);
  });

  test('a retry sends the full image again', () async {
    final hub = newHub();
    final chat = await newChat(acpSessionId: 'bypass-images');
    await hub.session(chat);
    await expectLater(
      hub.prompt(chat, 'echo look', resources: <Map<String, Object?>>[composerImage()]),
      throwsA(isA<BypassNotAllowedException>()),
    );
    expect(received(), isEmpty);

    await hub.acknowledgeBypass(chat);
    await hub.retryPrompt(chat);

    expect(received().single.last, <String, Object?>{...agentImage, 'data': full});
  });

  test('a prompt of images only sends no text block', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    await hub.prompt(chat, '', resources: <Map<String, Object?>>[composerImage()]);

    expect(received().single, <Map<String, Object?>>[
      <String, Object?>{...agentImage, 'data': full},
    ]);
    final message = ChatTranscript.fold(live.store.events).whereType<UserMessageItem>().single;
    expect(message.text, isEmpty);
    expect(message.images.single.data, thumbnail);
  });
}
