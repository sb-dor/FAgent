import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template drop_zone_overlay}
/// The hint over a drop target while files are dragged over it: the area is dimmed, a dashed
/// rounded frame pulses around it, and two lines say "Drop files here" / "to attach them to your
/// message". It takes no pointer events.
///
/// After the overlay of PlugFox's drop zone gist (`e94689b8e708c5ab191764506f5da089`), with the
/// app's colors and radius instead of fixed white-on-black, and the lines as text widgets.
/// {@endtemplate}
class DropZoneOverlay extends StatefulWidget {
  /// {@macro drop_zone_overlay}
  const DropZoneOverlay({super.key});

  @override
  State<DropZoneOverlay> createState() => _DropZoneOverlayState();
}

class _DropZoneOverlayState extends State<DropZoneOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    duration: const Duration(milliseconds: 1600),
    vsync: this,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduced motion the frame stands still, fully lit.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final textTheme = Theme.of(context).textTheme;
    return IgnorePointer(
      child: CustomPaint(
        painter: DropZoneOverlayPainter(animation: _pulse, colors: colors),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.file_download_outlined, size: 36, color: colors.accent),
                const SizedBox(height: 12),
                Text(
                  localization.dropZoneTitle,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.dropZoneSubtitle,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// {@template drop_zone_overlay_painter}
/// Paints [DropZoneOverlay]: a dim layer over the whole area and, inset from its edges, a rounded
/// frame with a soft fill, a pulsing glow and a dashed border, breathing with [animation].
/// {@endtemplate}
class DropZoneOverlayPainter extends CustomPainter {
  /// {@macro drop_zone_overlay_painter}
  DropZoneOverlayPainter({required Animation<double> animation, required this.colors})
    : _animation = animation,
      super(repaint: animation);

  final Animation<double> _animation;

  /// The app's colors.
  final AppColors colors;

  /// The gap between the area's edges and the frame at rest; the frame grows into it as it pulses.
  static const double inset = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = Curves.easeInOut.transform(_animation.value);
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.bg.withValues(alpha: 0.85));

    final rect = (Offset.zero & size).deflate(inset - 4 * pulse);
    if (rect.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.large));

    canvas
      ..drawRRect(rrect, Paint()..color = colors.accentSoft.withValues(alpha: 0.35))
      ..drawRRect(
        rrect,
        Paint()
          ..color = colors.accent.withValues(alpha: 0.15 + 0.2 * pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 6 * pulse),
      );

    final border = Paint()
      ..color = colors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 12.0;
    const gap = 8.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += dash + gap) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), border);
      }
    }
  }

  @override
  bool shouldRepaint(DropZoneOverlayPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate._animation != _animation;
}
