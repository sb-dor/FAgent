import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_code_agent/src/common/acp/prompt_images.dart';
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

/// Longest side of an image's thumbnail, in pixels.
const int kComposerThumbnailSize = 256;

/// {@template composer_image}
/// An image waiting in the composer (dropped or pasted) to go with the next message.
/// {@endtemplate}
@immutable
final class ComposerImage {
  /// {@macro composer_image}
  const ComposerImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.thumbnail,
  });

  /// The image [bytes] with a thumbnail made from them; throws when they are not an image the
  /// engine can decode.
  static Future<ComposerImage> of({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async => ComposerImage(
    name: name,
    mimeType: mimeType,
    bytes: bytes,
    thumbnail: await _thumbnail(bytes),
  );

  /// File name, shown in the chip's tooltip.
  final String name;

  /// `image/png`, `image/jpeg`, …
  final String mimeType;

  /// The image file as it is.
  final Uint8List bytes;

  /// A PNG of the image, its longest side at most [kComposerThumbnailSize]: shown in the chip and
  /// kept in the chat's journal instead of the image.
  final Uint8List thumbnail;

  /// The ACP content block that sends the image; the thumbnail rides in the app's `_meta`, which
  /// the hub journals in place of the image and never sends to the agent.
  Map<String, Object?> toBlock() => <String, Object?>{
    'type': 'image',
    'mimeType': mimeType,
    'data': base64Encode(bytes),
    '_meta': <String, Object?>{
      kAppMetaKey: <String, Object?>{
        'thumbnail': base64Encode(thumbnail),
        'thumbnailMimeType': 'image/png',
      },
    },
  };

  static Future<Uint8List> _thumbnail(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    // Takes the buffer over and disposes it.
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final longest = width > height ? width : height;
        if (longest <= kComposerThumbnailSize) {
          return ui.TargetImageSize(width: width, height: height);
        }
        final scale = kComposerThumbnailSize / longest;
        return ui.TargetImageSize(
          width: (width * scale).round().clamp(1, kComposerThumbnailSize),
          height: (height * scale).round().clamp(1, kComposerThumbnailSize),
        );
      },
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw const FormatException('The image could not be encoded');
        return png.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
