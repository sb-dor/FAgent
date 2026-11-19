import 'package:flutter_code_agent/src/common/acp/prompt_images.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/prompt_attachment.dart';
import 'package:path/path.dart' as p;

/// The ACP content blocks of [attachments], in their order.
List<Map<String, Object?>> promptBlocks(List<PromptAttachment> attachments) =>
    <Map<String, Object?>>[for (final attachment in attachments) _block(attachment)];

Map<String, Object?> _block(PromptAttachment attachment) => switch (attachment) {
  // An image file (a screenshot of the run) names its `mimeType`, so the agent knows to look at it
  // as one.
  PromptFileLink(:final path, :final folder) => <String, Object?>{
    'type': 'resource_link',
    'uri': (folder ? Uri.directory(path) : Uri.file(path)).toString(),
    'name': p.basename(path),
    if (!folder) 'mimeType': ?_imageTypes[p.extension(path).toLowerCase()],
  },
  // The thumbnail rides in the app's `_meta`, which the hub journals in place of the image and
  // never sends to the agent.
  PromptImage(:final mimeType, :final base64Data, :final thumbnailBase64) => <String, Object?>{
    'type': 'image',
    'mimeType': mimeType,
    'data': base64Data,
    '_meta': <String, Object?>{
      kAppMetaKey: <String, Object?>{
        'thumbnail': thumbnailBase64,
        'thumbnailMimeType': 'image/png',
      },
    },
  },
  // The agent reads the skill from the prompt instead of looking for it on disk (the app serves
  // built-in and user skills; they are not in the project's `.claude/skills`).
  PromptSkill(:final name, :final markdown) => <String, Object?>{
    'type': 'resource',
    'resource': <String, Object?>{
      'uri': 'skill://$name/SKILL.md',
      'mimeType': 'text/markdown',
      'text': markdown,
    },
  },
};

const Map<String, String> _imageTypes = <String, String>{
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};
