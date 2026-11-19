import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// {@template prompt_attachment}
/// What goes to the agent beside a prompt's text.
/// {@endtemplate}
@immutable
sealed class PromptAttachment {
  /// {@macro prompt_attachment}
  const PromptAttachment();
}

/// {@template prompt_file_link}
/// A link to a file or folder that the agent reads itself.
/// {@endtemplate}
final class PromptFileLink extends PromptAttachment {
  /// {@macro prompt_file_link}
  const PromptFileLink(this.path, {this.folder = false});

  /// Absolute path.
  final String path;

  /// A folder, not a file.
  final bool folder;

  @override
  bool operator ==(Object other) =>
      other is PromptFileLink && other.path == path && other.folder == folder;

  @override
  int get hashCode => Object.hash(path, folder);

  @override
  String toString() => 'PromptFileLink($path${folder ? '/' : ''})';
}

/// {@template prompt_image}
/// An image sent with the prompt.
/// {@endtemplate}
final class PromptImage extends PromptAttachment {
  /// {@macro prompt_image}
  const PromptImage(this.mimeType, this.base64Data, {required this.thumbnailBase64});

  /// `image/png`, `image/jpeg`, …
  final String mimeType;

  /// The image file, base64-encoded.
  final String base64Data;

  /// A PNG thumbnail of the image, base64-encoded: the chat's journal keeps it instead of the
  /// image.
  final String thumbnailBase64;

  @override
  bool operator ==(Object other) =>
      other is PromptImage &&
      other.mimeType == mimeType &&
      other.base64Data == base64Data &&
      other.thumbnailBase64 == thumbnailBase64;

  @override
  int get hashCode => Object.hash(mimeType, base64Data, thumbnailBase64);

  @override
  String toString() => 'PromptImage($mimeType, ${base64Data.length} chars)';
}

/// {@template prompt_skill}
/// The `SKILL.md` text of skill [name], embedded so the agent does not look for it on disk.
/// {@endtemplate}
final class PromptSkill extends PromptAttachment {
  /// {@macro prompt_skill}
  const PromptSkill(this.name, this.markdown);

  /// The skill's name.
  final String name;

  /// Its `SKILL.md`.
  final String markdown;

  @override
  bool operator ==(Object other) =>
      other is PromptSkill && other.name == name && other.markdown == markdown;

  @override
  int get hashCode => Object.hash(name, markdown);

  @override
  String toString() => 'PromptSkill($name)';
}

/// Links to the files [paths], relative to [projectRoot].
List<PromptAttachment> projectFileLinks(String projectRoot, List<String> paths) =>
    <PromptAttachment>[for (final path in paths) PromptFileLink(p.join(projectRoot, path))];
