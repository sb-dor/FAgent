import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_file.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'queued_prompt.freezed.dart';

/// {@template queued_prompt}
/// A message waiting in a chat's queue: what goes to the agent, built when it was queued.
/// {@endtemplate}
@freezed
abstract class QueuedPrompt with _$QueuedPrompt {
  /// {@macro queued_prompt}
  const factory QueuedPrompt({
    /// The text sent to the agent.
    required String text,

    /// The ACP content blocks sent after [text] (files, an embedded skill), as they were when the
    /// message was queued; the [images] follow them.
    required List<Map<String, Object?>> resources,

    /// The composer text as the user typed it, when it differs from [text] (a `/skill` command):
    /// shown in the queue and put back into the field by ✎.
    String? draft,

    /// The composer's images when the message was queued: sent after [resources] (their blocks are
    /// built only then, see [blocks]), and put back as chips by ✎.
    @Default(<ComposerImage>[]) List<ComposerImage> images,

    /// The composer's cards (files and folders outside the project) when the message was queued:
    /// sent as links after [resources], and put back as cards by ✎.
    @Default(<ComposerFile>[]) List<ComposerFile> files,
  }) = _QueuedPrompt;

  const QueuedPrompt._();

  /// What the queue shows and ✎ gives back.
  String get typed => draft ?? text;

  /// What goes to the agent after [text]: [resources], the [files], then the [images].
  List<Map<String, Object?>> get blocks => <Map<String, Object?>>[
    ...resources,
    for (final file in files) file.toBlock(),
    for (final image in images) image.toBlock(),
  ];

  /// The files among [resources], the [files] and the [images].
  int get attachmentCount =>
      resources.where((block) => block['type'] == 'resource_link').length +
      files.length +
      images.length;
}
