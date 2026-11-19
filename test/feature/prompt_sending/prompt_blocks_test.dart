import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_blocks.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/prompt_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a file link points at its absolute file URI', () {
    expect(
      promptBlocks(const <PromptAttachment>[PromptFileLink('/work/my app/lib/main.dart')]),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///work/my%20app/lib/main.dart',
          'name': 'main.dart',
        },
      ],
    );
  });

  test('the links of mentioned project files point at their absolute file URIs', () {
    expect(
      promptBlocks(projectFileLinks('/work/my app', <String>['lib/main.dart'])),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///work/my%20app/lib/main.dart',
          'name': 'main.dart',
        },
      ],
    );
  });

  test('an image link names its type, other files do not', () {
    expect(
      promptBlocks(const <PromptAttachment>[
        PromptFileLink('/work/shot.png'),
        PromptFileLink('/work/photo.JPG'),
        PromptFileLink('/work/lib/main.dart'),
        PromptFileLink('/Users/avaz/Desktop/a b.heic'),
      ]),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///work/shot.png',
          'name': 'shot.png',
          'mimeType': 'image/png',
        },
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///work/photo.JPG',
          'name': 'photo.JPG',
          'mimeType': 'image/jpeg',
        },
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///work/lib/main.dart',
          'name': 'main.dart',
        },
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///Users/avaz/Desktop/a%20b.heic',
          'name': 'a b.heic',
        },
      ],
    );
  });

  test('a folder links with a trailing / and no type', () {
    expect(
      promptBlocks(const <PromptAttachment>[
        PromptFileLink('/Users/avaz/Downloads', folder: true),
        PromptFileLink('/Users/avaz/shots.png', folder: true),
      ]),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///Users/avaz/Downloads/',
          'name': 'Downloads',
        },
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///Users/avaz/shots.png/',
          'name': 'shots.png',
        },
      ],
    );
  });

  test('an image goes as an image block with its thumbnail in the app meta', () {
    expect(
      promptBlocks(const <PromptAttachment>[
        PromptImage('image/jpeg', 'AQID', thumbnailBase64: 'BAU='),
      ]),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image',
          'mimeType': 'image/jpeg',
          'data': 'AQID',
          '_meta': <String, Object?>{
            'flutter_code_agent': <String, Object?>{
              'thumbnail': 'BAU=',
              'thumbnailMimeType': 'image/png',
            },
          },
        },
      ],
    );
  });

  test('a skill embeds SKILL.md as markdown', () {
    expect(
      promptBlocks(const <PromptAttachment>[PromptSkill('feature-architecture', '# Feature\n')]),
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'resource',
          'resource': <String, Object?>{
            'uri': 'skill://feature-architecture/SKILL.md',
            'mimeType': 'text/markdown',
            'text': '# Feature\n',
          },
        },
      ],
    );
  });

  test('the blocks keep the order of the attachments', () {
    final blocks = promptBlocks(const <PromptAttachment>[
      PromptSkill('s', 'md'),
      PromptFileLink('/p/a.dart'),
      PromptImage('image/png', 'AA==', thumbnailBase64: 'AA=='),
    ]);
    expect(blocks.map((block) => block['type']), <String>['resource', 'resource_link', 'image']);
  });
}
