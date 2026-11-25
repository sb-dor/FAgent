import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:flutter_code_agent/code_view/controller/code_document.dart';
import 'package:material_ui/material_ui.dart';

/// {@template code_conflict_bar}
/// Over a file with unsaved edits that changed on disk: take the file from disk or keep the edits.
/// {@endtemplate}
class CodeConflictBar extends StatelessWidget {
  /// {@macro code_conflict_bar}
  const CodeConflictBar({required this.document, super.key});

  /// The file.
  final CodeDocument document;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    return ColoredBox(
      color: colors.warnSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 16, color: colors.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localization.codeChangedOnDisk,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.text),
              ),
            ),
            TextButton(
              onPressed: () => document.reloadFromDisk().ignore(),
              child: Text(localization.codeLoadFromDisk),
            ),
            TextButton(onPressed: document.keepMine, child: Text(localization.codeKeepMine)),
          ],
        ),
      ),
    );
  }
}

/// {@template code_error_line}
/// Why the last read or save of a file failed.
/// {@endtemplate}
class CodeErrorLine extends StatelessWidget {
  /// {@macro code_error_line}
  const CodeErrorLine({required this.message, super.key});

  /// The failure.
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.dangerSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.danger),
        ),
      ),
    );
  }
}

/// {@template code_not_openable}
/// A file the editor does not open (binary, too large, unreadable), with a way to open it in the
/// system's default app.
/// {@endtemplate}
class CodeNotOpenable extends StatelessWidget {
  /// {@macro code_not_openable}
  const CodeNotOpenable({required this.document, required this.onOpenExternally, super.key});

  /// The file.
  final CodeDocument document;

  /// Opens it in the system's default app.
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.block, size: 28, color: colors.muted),
          const SizedBox(height: 10),
          Text(
            localization.codeNotOpenable,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          if (document.error case final error?) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenExternally,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(localization.codeOpenExternally),
          ),
        ],
      ),
    );
  }
}

/// {@template code_image_view}
/// An image file, read-only.
/// {@endtemplate}
class CodeImageView extends StatelessWidget {
  /// {@macro code_image_view}
  const CodeImageView({required this.path, super.key});

  /// The image's path.
  final String path;

  /// Widths are decoded in steps of this many pixels, so dragging a divider does not decode the
  /// image again at every pixel.
  static const int _decodeStep = 256;

  /// The width to decode at for a pane of [pixels]: rounded up to a step, and at least one step
  /// (a pane narrower than its padding has no width).
  static int _decodeWidth(double pixels) =>
      math.max(1, (pixels / _decodeStep).ceil()) * _decodeStep;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.surfaceAlt,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) => Image.file(
            io.File(path),
            fit: BoxFit.scaleDown,
            cacheWidth: constraints.hasBoundedWidth
                ? _decodeWidth(constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                : null,
            // A new width decodes again: the old image stays until the new one is ready.
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.broken_image_outlined, size: 32, color: context.colors.muted),
          ),
        ),
      ),
    ),
  );
}
