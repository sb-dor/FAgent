import 'package:flutter_code_agent/prompt_sending/models/composer_file.dart';
import 'package:flutter_code_agent/prompt_sending/models/composer_image.dart';
import 'package:flutter_code_agent/prompt_sending/models/prompt_attachment.dart';
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

    /// What is sent after [text] (files, an embedded skill), as it was when the message was
    /// queued; the [images] follow it.
    required List<PromptAttachment> resources,

    /// The composer text as the user typed it, when it differs from [text] (a `/skill` command):
    /// shown in the queue and put back into the field by ✎.
    String? draft,

    /// The composer's images when the message was queued: sent after [resources] (only then are
    /// they encoded, see [attachments]), and put back as chips by ✎.
    @Default(<ComposerImage>[]) List<ComposerImage> images,

    /// The composer's cards (files and folders outside the project) when the message was queued:
    /// sent as links after [resources], and put back as cards by ✎.
    @Default(<ComposerFile>[]) List<ComposerFile> files,
  }) = _QueuedPrompt;

  const QueuedPrompt._();

  /// What the queue shows and ✎ gives back.
  String get typed => draft ?? text;

  /// What goes to the agent after [text]: [resources], the [files], then the [images].
  List<PromptAttachment> get attachments => <PromptAttachment>[
    ...resources,
    for (final file in files) file.toAttachment(),
    for (final image in images) image.toAttachment(),
  ];

  /// The files among [resources], the [files] and the [images].
  int get attachmentCount =>
      resources.whereType<PromptFileLink>().length + files.length + images.length;
}
