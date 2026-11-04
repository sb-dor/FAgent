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

    /// The ACP content blocks sent after [text] (files, an embedded skill, images), as they were
    /// when the message was queued.
    required List<Map<String, Object?>> resources,

    /// The composer text as the user typed it, when it differs from [text] (a `/skill` command):
    /// shown in the queue and put back into the field by ✎.
    String? draft,

    /// The composer's images when the message was queued (their blocks are in [resources]): ✎
    /// puts them back as chips.
    @Default(<ComposerImage>[]) List<ComposerImage> images,
  }) = _QueuedPrompt;

  const QueuedPrompt._();

  /// What the queue shows and ✎ gives back.
  String get typed => draft ?? text;

  /// The files and images among [resources].
  int get attachmentCount => resources
      .where((block) => block['type'] == 'resource_link' || block['type'] == 'image')
      .length;
}
