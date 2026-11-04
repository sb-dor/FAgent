import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';

/// {@template image_chips}
/// The composer's images as thumbnails, each with ✕ ([onRemove] gets its index) when it can be
/// removed.
/// {@endtemplate}
class ImageChips extends StatelessWidget {
  /// {@macro image_chips}
  const ImageChips({required this.images, this.onRemove, super.key});

  /// The images, in the order they were added.
  final List<ComposerImage> images;

  /// Removes the image at the index; `null` hides the ✕.
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final (index, image) in images.indexed)
            Tooltip(
              message: image.name,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ImageThumbnail(bytes: image.bytes),
                  if (onRemove case final onRemove?)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: colors.surface,
                        shape: CircleBorder(side: BorderSide(color: colors.border)),
                        child: IconButton(
                          tooltip: localization.removeImage,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(width: 22, height: 22),
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          onPressed: () => onRemove(index),
                          icon: Icon(Icons.close_rounded, color: colors.muted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// {@template image_thumbnail}
/// A square, cropped preview of an image file; a broken one shows an icon.
/// {@endtemplate}
class ImageThumbnail extends StatelessWidget {
  /// {@macro image_thumbnail}
  const ImageThumbnail({required this.bytes, this.size = 56, super.key});

  /// The image file.
  final Uint8List bytes;

  /// Side of the square.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Decoded no larger than shown: a screenshot would otherwise take its full size in memory.
    final decoded = (size * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Image(
          image: ResizeImage(
            MemoryImage(bytes),
            width: decoded,
            height: decoded,
            policy: ResizeImagePolicy.fit,
          ),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, _, _) => SizedBox.square(
            dimension: size,
            child: ColoredBox(
              color: colors.surfaceAlt,
              child: Icon(Icons.broken_image_outlined, color: colors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
