import 'dart:io';

import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:path/path.dart' as p;

part 'drop_classification.freezed.dart';

/// {@template dropped_path}
/// What one path dropped on the chat becomes.
/// {@endtemplate}
@freezed
sealed class DroppedPath with _$DroppedPath {
  /// A file or folder inside the project: `@relative`, or `@relative/` for a folder.
  const factory DroppedPath.mention(String relative, {@Default(false) bool folder}) = DropMention;

  /// A file or folder outside the project: a card above the composer's text.
  const factory DroppedPath.absolute(String path, {@Default(false) bool folder}) = DropAbsolute;

  /// An image file (wherever it is): an image chip of the composer.
  const factory DroppedPath.image(String path) = DropImage;

  const DroppedPath._();

  /// What goes into the composer text; `null` for an image or a card.
  String? get text => switch (this) {
    DropMention(:final relative, :final folder) => folder ? '@$relative/' : '@$relative',
    DropAbsolute() || DropImage() => null,
  };
}

/// The dropped paths, in drop order.
typedef DropClassification = List<DroppedPath>;

/// Sorts the dropped [paths] (absolute) into mentions of [projectRoot], outside paths and
/// images, keeping their order.
DropClassification classifyDrop(List<String> paths, {required String projectRoot}) {
  final root = _real(projectRoot);
  return <DroppedPath>[
    for (final path in paths)
      if (!FileSystemEntity.isDirectorySync(path) && composerImageType(path) != null)
        DropImage(path)
      else if (_real(path) case final real when p.isWithin(root, real))
        DropMention(
          p.posix.joinAll(p.split(p.relative(real, from: root))),
          folder: FileSystemEntity.isDirectorySync(path),
        )
      else
        DropAbsolute(path, folder: FileSystemEntity.isDirectorySync(path)),
  ];
}

/// [path] with its links resolved (macOS temp folders live behind `/var` → `/private/var`), or
/// as it is when it cannot be resolved.
String _real(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(path);
  }
}
