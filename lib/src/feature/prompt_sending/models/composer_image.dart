import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// At most this many images go with one message.
const int kMaxComposerImages = 10;

/// An image larger than this (5 MB) is refused.
const int kMaxComposerImageBytes = 5 * 1024 * 1024;

/// The MIME type of the image files the composer takes, by lower-case extension (no dot).
const Map<String, String> kComposerImageTypes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// The MIME type of the image file at [path] by its extension; `null` when it is not one the
/// composer takes.
String? composerImageType(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension.isEmpty ? null : kComposerImageTypes[extension.substring(1)];
}

/// {@template composer_image}
/// An image waiting in the composer (dropped or pasted) to go with the next message.
/// {@endtemplate}
@immutable
final class ComposerImage {
  /// {@macro composer_image}
  const ComposerImage({required this.name, required this.mimeType, required this.bytes});

  /// File name, shown in the chip's tooltip.
  final String name;

  /// `image/png`, `image/jpeg`, …
  final String mimeType;

  /// The image file as it is.
  final Uint8List bytes;

  /// The ACP content block that sends the image.
  Map<String, Object?> toBlock() => <String, Object?>{
    'type': 'image',
    'mimeType': mimeType,
    'data': base64Encode(bytes),
  };
}
