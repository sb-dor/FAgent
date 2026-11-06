---
name: widgets
description: "Widget conventions: ListenableBuilder, super.key, what goes in a screen's file, UI state in data controllers."
---

# Widgets

## Rules

- Observe a `ChangeNotifier` with `ListenableBuilder`, not `ValueListenableBuilder`. To rebuild on
  one part of it only, `select` that part into a `ValueListenable` once, in a `State` field. See
  "Rebuilding on one part of a notifier".
- Use `const Foo({super.key})`. `StatefulWidget` for roots and anything owning controllers,
  focus, scroll or animation; `StatelessWidget` for small presentational widgets.
- `const` says a class is immutable and lets equal instances be one canonical object; it is not a
  performance tool. See "`const` and performance".
- No `Container`: use the widget that does the one thing (`SizedBox`, `Padding`, `ColoredBox`,
  `DecoratedBox`, `Align`, `ConstrainedBox`). They say what they do, can be `const`, and do not
  stack hidden layers the way a `Container` with several arguments does.
- No methods that return widgets (`Widget _buildHeader()`): make a widget class (`_Header`) in the
  same file. A method is rebuilt with everything around it, cannot be `const`, has no
  `BuildContext` of its own (an `InheritedWidget` read in it rebuilds the parent) and does not
  show in the DevTools widget tree.
- A screen's file holds the screen and its private parts (`_Header`, `_ProductRow`, a form
  controller only it uses). A widget gets its own file when it is used in several places or you
  keep coming back to it. Never `part` / `part of`. See "Splitting files".
- UI-only state (filters, selection) lives in a `ChangeNotifier` data controller in
  `widgets/controllers/` when several widgets of the feature share it; one only a single widget
  uses can stay in that widget's file.
- Mix `ChangeNotifier` in, `class X with ChangeNotifier`, never `extends ChangeNotifier`: it is a
  `mixin class` (a class only because it predates mixins), and `with` leaves the one superclass
  free.
- Controllers are for asynchronous work that can fail. Inside widgets, `setState`, `ValueNotifier`,
  `ChangeNotifier` and `StreamController` stay fine, and a synchronous check (is the form filled
  in) needs no controller.
- Where the project has desktop and mobile UIs, pick them with `context.screenSizeMaybeWhen`
  from `widgets/desktop/` and `widgets/mobile/`; add tablet only for a real tablet UI.
- Show a passing error from the `listener` of `StateConsumer` (a SnackBar or banner with a retry
  that calls the controller again): the state goes back to `idle` right after an `error`, so the
  `builder` renders the data, not the error. An error that must stay as a widget (an error view in
  place of a list that never loaded) is read from the data (`state.data.error`), where the
  controller keeps it; see "One recipe for states" in `docs/rules/controllers.md`. The text comes
  from `errorText` (see "Error messages" in `docs/rules/localization.md`).
- Dispose what the widget created (that drops its listeners too); remove the listeners you added to
  what it did not create. See "Listeners and dispose".
- `didUpdateWidget` runs on almost every rebuild of the parent: compare the old and new fields
  yourself and act only on what changed. Call `super` first in `initState`,
  `didChangeDependencies` and `didUpdateWidget`, and last in `dispose`. See "Lifecycle of a `State`".
- No `GlobalKey` to reach a `State` or its `context` from outside: pass a controller or a callback.
  See "Keys".
- Never use a `BuildContext` after an `await` without checking `mounted` first; take what you
  need from the context before the `await`. See "`BuildContext` after `await`".
- Moving a number or a URL into a `static const` does not make it less magic. Shared values come
  from the theme, a component or the configuration. See "Magic numbers".
- Forms need no package (`flutter_form_builder`): one controller per field, merged, with validity
  recomputed on every change. Validation errors are enum values the widget turns into localized
  text. See "Forms".
- How to test widgets: `docs/rules/testing.md`.
- A 2D UI that lags is the code's fault, whatever the device: see "Performance".
- Choose a layout by the space the window has (`MediaQuery.sizeOf(context)`, `LayoutBuilder`),
  never by device type, platform or orientation. A screen's root picks the layout from Material's
  window size class; small widgets use `LayoutBuilder`. See "Adaptive and responsive".
- Several lists, a grid and headers in one scrolling screen are one `CustomScrollView` of slivers,
  never lists nested with `shrinkWrap: true`. See "Scrolling and slivers".
- Key presses go to the focused widget, then up its ancestors: a `Shortcuts` sees nothing until
  the focus is inside it, so put a `Focus(autofocus: true)` below it. See "Focus and keyboard".
- A popup attached to a widget (a menu, a dropdown, a hint) is a framework widget (`MenuAnchor`,
  `DropdownMenu`, `Autocomplete`, `Tooltip`) first, then an `OverlayPortal` placed by its layout
  builder, then a `LayerLink`; never coordinates read through a `GlobalKey`. See "Anchored popups".
- A control the design repeats is a component of the project's UI kit, not a Material widget
  restyled where it is used. See "Components".
- `Color.withOpacity` and `Radio(groupValue:, onChanged:)` are deprecated: `withValues(alpha:)` and
  a `RadioGroup` ancestor. See "Replaced APIs".
- A widget or `State` that shows data overrides `debugFillProperties`, so the DevTools inspector
  shows the data. See "Diagnostics".

## Performance

Flutter draws a list, a header animation and a paginated feed at full speed on a weak phone. When
it lags, the cause is in the code, and it is almost always one of these:

- **Rebuilding too much.** A `setState`, `ListenableBuilder`, `StreamBuilder` or `StateConsumer`
  high in the tree rebuilds everything under it. Put builders as low as possible, around just what
  changes, and pass the parts that do not change as the builder's `child`.
- **Animating with `setState`** (see "Animations"). A header that hides on scroll should not call
  `setState` for every scroll offset. Drive one `AnimationController` from the scroll direction and use transitions
  (`SizeTransition`, `SlideTransition`, `FadeTransition`): they change only the render object, not
  the widget tree.
- **No `RepaintBoundary`.** Something that repaints on its own (an animated header, a spinner, a
  ticking value) repaints its neighbours too unless it has a `RepaintBoundary` around it. A
  boundary is a layer of its own, which costs memory and compositing: add one where a part repaints
  much more often than what surrounds it, not around every widget, and check the effect.
- **Lists that measure every row.** A `ListView.builder` whose rows all have the same height gets
  `itemExtent` (or `prototypeItem`): the list then skips laying out rows just to find where it is.
  A long or growing list is a `ListView.builder` (`SliverList.builder`). `ListView(children: ...)`
  (`SliverList.list`) also builds and lays out only the visible rows, but every row's widget
  object is created up front in the parent's `build`. That is fine for a screenful, wasteful for
  a thousand. What does build every row is a `Column` in a `SingleChildScrollView`, or a
  `shrinkWrap: true` list inside another scrollable: never do either with a long list (see
  "Scrolling and slivers").
- **Costly layout.** `IntrinsicHeight` / `IntrinsicWidth` lay their children out twice; a `Stack` of
  `Positioned` widgets whose offsets are computed in `build` relayouts on every frame. Use rows,
  columns and constrained boxes, or a `CustomMultiChildLayout` when positions really depend on
  sizes.
- **Pagination that rebuilds the list.** Appending a page must not recreate the whole list or reset
  its scroll; keys keep rows stable (`ValueKey(item.id)`), and the footer spinner is one more row,
  not a new list.

Measure before fixing, and only in profile mode (`flutter run --profile`) with the DevTools
performance view: debug mode is several times slower and lags where a real build does not.

### State in list rows

A lazy list builds rows as they scroll in and destroys them as they scroll out, `State` included:
text typed into a `TextEditingController` held by a row's `State` is gone after the user scrolls
away and back. A list of forms keeps its data above the list: in the controller, or in a map of
controllers by item id owned by the screen's `State` and disposed there. `AutomaticKeepAliveClientMixin`
keeps rows alive instead, and is only for a few rows: every kept row stays in memory.

### Measuring in production

A release build (AOT) has no VM service: DevTools, the memory view and the timeline exist only in
debug and profile builds. What an installed app can report:

- Frame times: `SchedulerBinding.instance.addTimingsCallback` receives `FrameTiming`s in batches
  (the first frame at once). Count frames whose `buildDuration` or `rasterDuration` exceeds the
  frame budget (16 ms at 60 Hz, 8 ms at 120 Hz), per screen. An average FPS for the app means
  nothing: an idle screen draws no frames, and a smooth average hides a janky scroll.
- Startup: time from `main` to the first frame (`WidgetsBinding.instance.waitUntilFirstFrameRasterized`),
  and the steps of initialization. Send them as analytics from the first release.
- Crash rate, ANRs and frozen frames, and network errors and timings, from the crash reporter's
  performance monitoring (Sentry, Firebase Performance).
- Battery and heat, from user reports and platform tools (Android vitals, Xcode Organizer). The
  usual cause is an animation that never stops: a shimmer still repeating behind loaded content, or
  a ticker in an `Offstage` subtree (see "Hiding a widget").

### Animations

An animation runs once per frame, at the display's refresh rate (up to 120 Hz on 120 Hz screens;
on an iPhone with ProMotion only after `CADisableMinimumFrameDurationOnPhone` is `true` in
`Info.plist`). Whatever runs on each frame must be cheap, so:

- **Drive it from a `Ticker`**, through an `AnimationController` or the ticker itself
  (`createTicker` of a `TickerProviderStateMixin`, disposed in `dispose`), never from
  `Timer.periodic`: the ticker follows the frames and stops when the screen is not visible.
- **Repaint, do not rebuild.** A `setState` per tick, or an `AnimatedBuilder` high in the tree,
  rebuilds widgets on every frame. Use transitions (`FadeTransition`, `SlideTransition`,
  `ScaleTransition`, `SizeTransition`), which update their render object directly; keep an
  `AnimatedBuilder` around the smallest part and pass the rest as its `child`.
- **Start with `CustomPainter`** for anything drawn: pass the animation as `repaint`
  (`super(repaint: animation)`) and it repaints on every tick without build or layout. In a custom
  `RenderBox`, call `markNeedsPaint()` from the animation's listener (`markNeedsLayout()` only when
  the size really changes).
- **Move and transform with `Flow`.** A flip, a fan of cards, items that follow the scroll: a
  `Flow` with a `FlowDelegate(repaint: animation)` paints its children with a transform on every
  tick, with no rebuild and no relayout (`flip_card.dart` below). Not `Transform` widgets
  recomputed in an `AnimatedBuilder`, and never `setState` per frame.
- **Keep the tree's shape.** Do not add and remove widgets while animating (`if (visible) ...` every
  few frames); animate the opacity, size or offset of widgets that stay, so Flutter reuses their
  elements and render objects.
- **Isolate what repaints.** Wrap the animated part in a `RepaintBoundary` so the rest of the
  screen is not repainted with it; a custom render object can be a boundary itself
  (`bool get isRepaintBoundary => true`). Check with "Highlight repaints" in DevTools.
- **On a `Canvas`:** create `Paint` and `Path` objects once (fields, not in `paint`) and reuse them;
  draw many sprites with one `drawAtlas` call and many points or triangles with `drawRawPoints` /
  `drawVertices` instead of a loop of `drawCircle`; prefer `save` / `restore` for transforms and
  clips, since `saveLayer` allocates an offscreen buffer and is expensive. Every `save` has its
  `restore`: a missing one leaks the transform and clip into whatever is drawn next. Details in
  "Large scenes on a canvas".
- **Heavy effects on the GPU:** fragment shaders (`.frag` files listed under `flutter: shaders:`,
  loaded with `FragmentProgram.fromAsset`). Flutter has no vertex shaders.

A shimmer (a loading placeholder) needs no package: one fragment shader, painted by a
`CustomPainter` (a full example: https://gist.github.com/PlugFox/7cb6362f020363d1544495fa262aa6a1).

- The shader file is listed under `flutter: shaders:` and loaded once for the whole app
  (`FragmentProgram.fromAsset` in a static or app-wide holder), not once per widget.
- A `Ticker` writes the elapsed time into a `ValueNotifier`, and the painter gets it (with the
  widget's settings) through `repaint:`: every frame repaints the placeholder, nothing rebuilds.
- `paint` passes the uniforms with `setFloat`, in the order the shader declares them; colors go as
  `color.r`, `.g`, `.b`, `.a` (already 0 to 1; `red` and `value` are deprecated).
- In the shader, read the pixel's position with `FlutterFragCoord()` from
  `flutter/runtime_effect.glsl`, not `gl_FragCoord`.
- Where shaders are unavailable or still loading, paint a plain rounded rectangle, and wrap the
  placeholders in a `RepaintBoundary`.

More in [Effective animations in Flutter](https://plugfox.dev/effective-animations-in-flutter) and
the [`repaint`](https://github.com/PlugFox/repaint) package.

### Painters, clippers and layout delegates

Every delegate takes the `Listenable` it depends on through its constructor:
`CustomPainter(repaint:)`, `FlowDelegate(repaint:)`, `CustomClipper(reclip:)`,
`MultiChildLayoutDelegate(relayout:)`, `SingleChildLayoutDelegate(relayout:)`. Any `Listenable`
works: an `AnimationController`, a `ValueNotifier`, a `TextEditingController`, a
`Listenable.merge`. The render object listens to it and only repaints, reclips or relayouts;
nothing is rebuilt. Accept it even when nothing animates yet (an optional parameter passed to
`super`), so the delegate can be driven later without changing its callers.

```dart
// Not this: a rebuild of the subtree on every frame, for one repaint.
AnimatedBuilder(
  animation: controller,
  builder: (context, _) => CustomPaint(painter: GaugePainter(value: controller.value)),
);

// This: the painter reads the value when it paints.
CustomPaint(painter: GaugePainter(value: controller));

class GaugePainter extends CustomPainter {
  GaugePainter({required this._value}) : super(repaint: _value);

  final ValueListenable<double> _value;
  // paint() reads _value.value.
}
```

An `AnimatedBuilder` marks its element dirty on every tick; the next frame rebuilds it, creates
new widgets, runs `didUpdateWidget` and `build` below it and lays them out again, only to repaint
one painter. Through `repaint:` the tick marks that one render object as needing paint. The same
holds for any builder that creates a new painter on every change (`StateConsumer`,
`ValueListenableBuilder`, `setState` per tick): give the painter the `Listenable` instead.

- `shouldRepaint` (`shouldReclip`, `shouldRelayout`) triggers nothing: it is asked only when a new
  delegate instance replaces the old one, to decide whether the new one draws differently. A
  painter whose values change while it lives repaints through `repaint:`. `Paint`, `Path` and
  `TextPainter` objects are created once, not in every `paint`.
- A delegate may live in the `State`, created once, like a controller: it can keep its own
  caches (built `Path`s, measured text) and the `Rect`s it drew, and answer hit tests from them
  (`CustomPainter.hitTest`: `_rects.any((rect) => rect.contains(position))`; a quadtree for
  thousands). Its `shouldRepaint` / `shouldReclip` / `shouldRelayout` then compares identity.
- A position or size that layout decides is passed on by layout, not read back: never a
  `GlobalKey` with `currentContext?.findRenderObject() as RenderBox` in `build`. On the first build
  there is no render object yet (the cast throws), and a render object has a `size` only after
  its layout; anything read in `build` is the previous frame's. Lay the children out in a
  `CustomMultiChildLayout` (or `Flow`, or a custom `RenderBox`) and hand the result to who needs
  it, as `ticket.dart` hands the notch position from its layout delegate to its clipper.
- Animate moving parts with `Flow` or `CustomMultiChildLayout` rather than a `Stack` of
  `Positioned` rebuilt per frame: a side panel over the whole app relayouts only itself.
- A scene with many objects that changes all the time (a chart, a game board) is a custom
  `RenderBox` that owns a `Ticker` and marks itself for paint only when something changed; that is
  how Flame draws games.
- A decoration that sticks out of the widget (a focus ring around a button, a glow) is painted
  by a `CustomPaint(foregroundPainter: ...)` that draws past its `size`: painting is not clipped
  to the constraints, so nothing has to reserve space with padding and nothing jumps when it
  appears. Drive it with `repaint:` from the focus state. Only an ancestor that clips cuts it: a
  scroll view (`clipBehavior` is `Clip.hardEdge` by default), a `ClipRRect`, a `Card` with a clip.
- When a parent really needs a child's size after the fact (to show a badge, to log it),
  `size_reporter.dart` reports it from the child's own layout, after the frame. It costs a second
  frame, so a layout decided by sizes still belongs in a layout delegate.
- A painter driven by the state's own values gets a small notifier: a `ValueNotifier`, or a class
  `with ChangeNotifier` with a method that changes the value and notifies. Not a bare
  `ChangeNotifier()` whose `notifyListeners()` is called from outside (it is `@protected`), and
  the notifier is disposed with the state. A `Ticker` that moves something toward a target stops
  when it arrives and starts again on the next change.

### Custom render objects

When a `CustomPainter` is not enough (the widget sizes itself from its content, handles its own
taps, draws thousands of items), write a `LeafRenderObjectWidget` (or `SingleChild...` /
`MultiChildRenderObjectWidget`) and its `RenderBox`:

- `createRenderObject` reads what the render object needs from the context (`Theme.of`,
  `Directionality.of`, `MediaQuery.textScalerOf`) and `updateRenderObject` passes the same again.
  Every setter of the render object compares the value and calls `markNeedsLayout()` or
  `markNeedsPaint()`; a setter that only assigns ignores the new theme, text or data.
- `performLayout` sets `size = constraints.constrain(...)`, and `computeDryLayout` returns the same
  without side effects. Do not override `size`; `performResize` runs only with
  `sizedByParent => true`.
- Expensive drawing is recorded once into a `Picture` (`PictureRecorder`) when the content or the
  size changes, drawn with `canvas.drawPicture` in `paint`, and the previous `Picture` is
  `dispose()`d: it holds native memory. More in "Large scenes on a canvas".
- Taps: `hitTestSelf` returns `true`, `handleEvent` gets the pointer events, and the tap targets
  are the `Rect`s kept from layout.
- Nothing runs a `Ticker` to poll a flag: a ticker that never stops asks for a frame on every
  vsync, and the phone renders sixty frames a second of nothing. Call `markNeedsPaint()` when the
  change happens; a ticker runs only while something animates, and is disposed in `detach`. The
  exception is a scene that advances with time on every frame (a game, a simulation): see "Large
  scenes on a canvas".
- Text and controls drawn on the canvas are invisible to screen readers until
  `describeSemanticsConfiguration` labels them.

### Large scenes on a canvas

A scene bigger than the screen (a map, a diagram editor, a board with thousands of objects) is one
custom render object (above) with a camera, a few painters and an index of the objects.

- **Camera.** The scene lives in world coordinates. The camera holds the viewport size, the world
  point at the viewport's centre and the zoom (`camera.dart`): painting converts world to screen,
  taps and drags convert screen to world. It is a `ChangeNotifier` whose setters notify only on a
  real change, and the render object listens to it and marks itself for paint. Set the viewport
  size from `performLayout`, never from `paint`: a listener that calls `markNeedsPaint()` while
  painting fails its assertion (`!owner.debugDoingPaint`).
- **Painters with dirty flags.** Split the scene into small painters with a fixed paint order
  (background, objects, selection, debug, HUD), owned by the render object. Each has `needsPaint`,
  an `update` that recomputes what changed (the visible objects after the camera moved) and
  `paint(Canvas canvas, Size size)`. A camera or data change marks only the painters that depend on
  it; the render object calls `markNeedsPaint()` only when one of them needs paint. Pointer events
  go to the painters topmost first (reverse paint order) and stop at the first that handles them.
- **Culling.** Up to a few hundred objects, a scan with `Rect.overlaps` is fine. For thousands,
  keep their rectangles in a spatial index (a quadtree, as in the `repaint` package) and query it
  with the camera's visible rect inflated by a margin, so objects do not pop in at the edge. Query
  when the camera or the data change, not in every `paint`. Hit tests compare bounding rectangles
  first and run the exact test only on what is left.
- **Batches.** `drawRawAtlas(atlas, transforms, rects, colors, blendMode, cullRect, paint)` draws
  many sprites of one image in one call. `transforms` is a `Float32List` of four numbers per
  sprite, `scos, ssin, tx, ty` (`RSTransform.fromComponents` computes them; without rotation `scos`
  is the scale and `ssin` is 0); `rects` has four per sprite, `left, top, right, bottom` of the
  sprite in the atlas; `colors` (an `Int32List`, one per sprite, or `null`) tints them with
  `blendMode`. Fill the lists when the layout changes and keep them; draw a part of them with
  `Float32List.sublistView(list, start * 4, end * 4)`. `drawRawPoints(PointMode.points, xy, paint)`
  draws a `Float32List` of x, y pairs: `strokeWidth` is the dot size, `StrokeCap.round` draws round
  dots and `StrokeCap.square` square ones, and `Paint.style` is ignored; `PointMode.lines` takes
  each pair of points as a segment, `PointMode.polygon` draws one open line. (Checked by rendering:
  the atlas layout, round against square dots.)
- **Paints.** Keep one `Paint` per kind of drawing and change its `color` between calls: each call
  reads the paint as it is then (checked). Pixel art and atlases: `isAntiAlias = false`,
  `filterQuality = FilterQuality.none`. Lines and curves: antialiasing on.
  A clip whose edge lies on whole pixels needs no antialiasing: `clipRect(rect, doAntiAlias:
  false)`, the hard edge that `Clip.hardEdge` documents as the fastest clip (the default is `true`).
- **Cached layers.** A part that rarely changes (a grid, a minimap) is recorded once into a
  `Picture`, which replays its commands on every draw. `picture.toImage(w, h)` (a `Future`) or
  `picture.toImageSync(w, h)` turns it into an `Image`, drawn with `drawImageRect`.
  `toImageSync` does not block: it returns the image at once and rasterizes it in the background,
  on the GPU when there is one, and a failure shows when the image is drawn. Rebuild the cache when
  the size or the content change, never per frame, and `dispose()` the old `Picture` and the old
  `Image`: both hold native memory.
- **Scenes that advance with time.** A game or a simulation changes on every frame, so its render
  object may run a `Ticker` from `attach` to `detach` and move things by the time between ticks,
  capped, not by a fixed step per frame. `TickerMode` (a covered route, `Visibility(maintainState:
  true)`) mutes only tickers made by a `State`'s `TickerProvider`: pass
  `TickerMode.valuesOf(context).enabled` through `createRenderObject` / `updateRenderObject` and set
  `ticker.muted`. A muted ticker's clock keeps running, hence the cap. While the app is hidden or
  paused the binding draws no frames, so the ticker does not run in the background.
- **Debug overlay.** In debug builds a key (F2) toggles a painter that draws the camera rect and
  zoom, the index's cells and the number of paints per second, and adds the engine's graphs with
  `context.addLayer(PerformanceOverlayLayer(overlayRect: rect, optionsMask: mask))`, where `mask`
  has the bits `1 << PerformanceOverlayOption.x.index` set. Keep it out of release builds
  (`kDebugMode`).

### `camera.dart`

```dart
// file: camera.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The view onto a scene larger than the screen. The scene lives in world coordinates; the
/// camera's [position] is the world point at the centre of the viewport.
final class Camera with ChangeNotifier {
  Camera({this._position = Offset.zero, double zoom = 1, this.minZoom = 0.1, this.maxZoom = 10})
    : _zoom = zoom.clamp(minZoom, maxZoom);

  final double minZoom;
  final double maxZoom;

  Size _viewport = Size.zero;
  Offset _position;
  double _zoom;

  Size get viewport => _viewport;
  Offset get position => _position;
  double get zoom => _zoom;

  /// The part of the world on screen. Inflate it by a margin before culling, so objects do not
  /// pop in at the edge.
  Rect get visible => Rect.fromCenter(
    center: _position,
    width: _viewport.width / _zoom,
    height: _viewport.height / _zoom,
  );

  /// Called from `performLayout` (or a `LayoutBuilder`), never from `paint`: it notifies, and a
  /// listener that marks a render object for paint while painting fails an assertion.
  void resize(Size viewport) => _update(viewport: viewport);

  void moveTo(Offset position) => _update(position: position);

  void zoomTo(double zoom) => _update(zoom: zoom.clamp(minZoom, maxZoom));

  /// World to screen, for painting.
  Offset toLocal(Offset world) => (world - visible.topLeft) * _zoom;

  /// Screen to world, for taps and drags.
  Offset toWorld(Offset local) => local / _zoom + visible.topLeft;

  void _update({Size? viewport, Offset? position, double? zoom}) {
    final changed =
        (viewport != null && viewport != _viewport) ||
        (position != null && position != _position) ||
        (zoom != null && zoom != _zoom);
    if (!changed) return; // listeners repaint: only on a real change
    _viewport = viewport ?? _viewport;
    _position = position ?? _position;
    _zoom = zoom ?? _zoom;
    notifyListeners();
  }
}
```

### `size_reporter.dart`

```dart
// file: size_reporter.dart
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports [child]'s size after every layout that changed it.
///
/// The callback runs after the frame, so it may call `setState`; what it reports is the size
/// the child got in that frame. To decide a layout from a size, lay the children out yourself
/// (`CustomMultiChildLayout`) instead: a size reported afterwards always costs a second frame.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({required this.onSize, required super.child, super.key});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, covariant RenderSizeReporter renderObject) {
    // A new callback replaces the old one; without this the first closure would be called forever.
    renderObject.onSize = onSize;
  }
}

/// The render object of [SizeReporter].
class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final current = size;
    if (current == _reported) return;
    _reported = current;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(current);
    });
  }
}
```

### `ticket.dart`

```dart
// file: ticket.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A ticket: [top] and [bottom] with a gap between them, cut by round notches on both sides of the
/// gap. The notches follow wherever layout puts the gap; no `GlobalKey`, no `findRenderObject`.
class Ticket extends StatefulWidget {
  const Ticket({
    required this.top,
    required this.bottom,
    required this.color,
    this.gap = 24,
    super.key,
  });

  final Widget top;
  final Widget bottom;
  final Color color;

  /// The space between [top] and [bottom], and the notches' diameter.
  final double gap;

  @override
  State<Ticket> createState() => _TicketState();
}

enum _Slot { top, bottom }

class _TicketState extends State<Ticket> {
  late final ValueNotifier<double> _gap = ValueNotifier<double>(widget.gap);

  /// Where the gap's middle ended up, written by the layout and read by the clipper.
  final ValueNotifier<double> _notch = ValueNotifier<double>(0);

  // The delegates live as long as the state: they read the notifiers on every layout and clip.
  late final _TicketLayout _layout = _TicketLayout(gap: _gap, notch: _notch);
  late final _TicketClipper _clipper = _TicketClipper(gap: _gap, notch: _notch);

  @override
  void didUpdateWidget(covariant Ticket oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gap.value = widget.gap; // Relayout and reclip, without rebuilding the children.
  }

  @override
  void dispose() {
    _gap.dispose();
    _notch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _clipper,
    child: ColoredBox(
      color: widget.color,
      child: CustomMultiChildLayout(
        delegate: _layout,
        children: <Widget>[
          LayoutId(id: _Slot.top, child: widget.top),
          LayoutId(id: _Slot.bottom, child: widget.bottom),
        ],
      ),
    ),
  );
}

/// Gives [top] and [bottom] half of the height left after the gap each, centred in their half.
class _TicketLayout extends MultiChildLayoutDelegate {
  _TicketLayout({required this._gap, required this._notch}) : super(relayout: _gap);

  final ValueListenable<double> _gap;
  final ValueNotifier<double> _notch;

  @override
  void performLayout(Size size) {
    final gap = _gap.value;
    final half = (size.height - gap) / 2;
    final constraints = BoxConstraints.loose(Size(size.width, half));
    final top = layoutChild(_Slot.top, constraints);
    final bottom = layoutChild(_Slot.bottom, constraints);
    final topY = (half - top.height) / 2;
    final bottomY = half + gap + (half - bottom.height) / 2;
    positionChild(_Slot.top, Offset((size.width - top.width) / 2, topY));
    positionChild(_Slot.bottom, Offset((size.width - bottom.width) / 2, bottomY));
    // Only the clipper listens: it marks the clip for repaint, which comes after layout.
    _notch.value = (topY + top.height + bottomY) / 2;
  }

  @override
  bool shouldRelayout(covariant _TicketLayout oldDelegate) => !identical(this, oldDelegate);
}

/// A rounded rectangle without a circle on each side at the notch.
class _TicketClipper extends CustomClipper<Path> {
  _TicketClipper({required this._gap, required this._notch})
    : super(reclip: Listenable.merge(<Listenable>[_gap, _notch]));

  final ValueListenable<double> _gap;
  final ValueListenable<double> _notch;

  @override
  Path getClip(Size size) {
    final gap = _gap.value;
    final notch = _notch.value;
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(gap / 2))),
      Path()
        ..addOval(Rect.fromCircle(center: Offset(0, notch), radius: gap / 2))
        ..addOval(Rect.fromCircle(center: Offset(size.width, notch), radius: gap / 2)),
    );
  }

  @override
  bool shouldReclip(covariant _TicketClipper oldClipper) => !identical(this, oldClipper);
}
```

### `sign_in_form.dart`

```dart
// file: sign_in_form.dart
import 'package:flutter/material.dart';

/// What is wrong with the form. A value, not a sentence: the widget turns it into text.
enum SignInError { invalidEmail, shortPassword }

/// A sign-in form: typed controllers per field, validity recomputed on every change.
class SignInForm extends StatefulWidget {
  const SignInForm({required this.onSubmit, super.key});

  /// Receives the typed values when the form is valid and submitted.
  final void Function(String email, String password, {required bool remember}) onSubmit;

  @override
  State<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<SignInForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final ValueNotifier<bool> _remember = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _valid = ValueNotifier<bool>(false);
  final ValueNotifier<SignInError?> _error = ValueNotifier<SignInError?>(null);
  late final Listenable _form = Listenable.merge(<Listenable>[_email, _password, _remember]);

  @override
  void initState() {
    super.initState();
    _form.addListener(_onChanged);
    _onChanged();
  }

  void _onChanged() {
    final email = _email.text.trim();
    final error = switch ((email, _password.text)) {
      ('', _) || (_, '') => null, // nothing to complain about before the user has typed
      (final e, _) when !e.contains('@') => SignInError.invalidEmail,
      (_, final p) when p.length < 8 => SignInError.shortPassword,
      _ => null,
    };
    _error.value = error;
    _valid.value = error == null && email.isNotEmpty && _password.text.isNotEmpty;
  }

  void _submit() {
    if (!_valid.value) return;
    widget.onSubmit(_email.text.trim(), _password.text, remember: _remember.value);
  }

  @override
  void dispose() {
    _form.removeListener(_onChanged);
    for (final notifier in <ChangeNotifier>[_email, _password, _remember, _valid, _error]) {
      notifier.dispose();
    }
    super.dispose();
  }

  // Texts are literal only to keep the template self-contained: in the app each one is
  // `Localization.of(context).<key>`, here and in the labels below.
  static String _errorText(SignInError error) => switch (error) {
    SignInError.invalidEmail => 'Enter a valid email',
    SignInError.shortPassword => 'The password needs at least 8 characters',
  };

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: _remember,
        builder: (context, remember, _) => CheckboxListTile(
          value: remember,
          onChanged: (value) => _remember.value = value ?? false,
          title: const Text('Remember me'),
        ),
      ),
      ValueListenableBuilder<SignInError?>(
        valueListenable: _error,
        builder: (context, error, _) => switch (error) {
          null => const SizedBox.shrink(),
          final error => Text(_errorText(error)),
        },
      ),
      ValueListenableBuilder<bool>(
        valueListenable: _valid,
        builder: (context, valid, _) =>
            FilledButton(onPressed: valid ? _submit : null, child: const Text('Sign in')),
      ),
    ],
  );
}
```

### `flip_card.dart`

```dart
// file: flip_card.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A card that flips between [front] and [back] as [animation] goes from 0 to 1, painted by
/// [Flow]: each tick repaints it with a new transform, without a rebuild or a relayout.
class FlipCard extends StatelessWidget {
  const FlipCard({
    required this.animation,
    required this.front,
    required this.back,
    super.key,
  });

  final Animation<double> animation;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) => Flow(
    delegate: _FlipDelegate(animation),
    children: <Widget>[front, back],
  );
}

class _FlipDelegate extends FlowDelegate {
  _FlipDelegate(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paintChildren(FlowPaintingContext context) {
    final angle = animation.value * math.pi;
    final showsFront = angle <= math.pi / 2;
    final center = context.size.width / 2;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // perspective
      ..translateByDouble(center, 0, 0, 1)
      // The back is turned half a turn more, so it is not mirrored.
      ..rotateY(showsFront ? angle : angle - math.pi)
      ..translateByDouble(-center, 0, 0, 1);
    context.paintChild(showsFront ? 0 : 1, transform: transform);
  }

  @override
  bool shouldRepaint(_FlipDelegate oldDelegate) => animation != oldDelegate.animation;
}
```

### `const` and performance

- An immutable class gets a `const` constructor: it documents that the object never changes and
  lets callers create it as a canonical literal. Keep the lint `prefer_const_constructors_in_immutables`.
- Using `const` at call sites does not make an app faster in practice. When a parent rebuilds, a
  `const` child is the identical object as before, so Flutter keeps its element and skips that
  subtree; but building widgets is a tiny part of a frame next to layout, painting and the code's
  own work, and benchmarks of real apps showed no significant difference.
  [dart-lang/core#833](https://github.com/dart-lang/core/issues/833) removed
  `prefer_const_constructors`, `prefer_const_literals_to_create_immutables` and
  `prefer_const_declarations` from `flutter_lints` for that reason; a project may still turn them
  on, and then follows them.
- Never restructure code, or split widgets, just to make something `const`. Fix what the list
  above names instead.

## Adaptive and responsive

Responsive design fits the UI into the space: it moves and resizes elements as the window changes.
Adaptive design makes the UI usable in that space: it picks the layout and the input for it (a
bottom bar or a side rail on a tablet, a hover state for a mouse). An app needs both. Flutter's
guide: https://docs.flutter.dev/ui/adaptive-responsive.

- **Decide by the window, not the device.** Read `MediaQuery.sizeOf(context)` (it rebuilds only on
  a size change) or the constraints of a `LayoutBuilder`, and switch at breakpoints (Material's
  window size classes). A phone in split screen or a resizable desktop window is not "a phone" or
  "a tablet"; the device type and the orientation say nothing about the space the app has.
- **Do not lock the orientation.** Large Android devices and Apple's guidelines expect both, and
  Android can override the lock anyway.
- **Do not stretch content across a wide window**: cap the width of forms and text, or use a grid.
- **Support the mouse, the trackpad and the keyboard**: keyboard navigation for the main flows,
  shortcuts as accelerators. Material widgets already handle all three.
- **Keep state across a resize or rotation**: the layout changes, the data and the scroll position
  stay (`PageStorageKey` for a list that keeps its layout).
- **Small widgets** make it cheap to rearrange the same pieces for each size.

### Window size classes

Material 3 names five window size classes by width in logical pixels: compact (under 600), medium
(600 to 839), expanded (840 to 1199), large (1200 to 1599) and extra-large (1600 and up).

- The thresholds live in one enum (`window_class.dart`), never as `width > 840` spread over the
  widgets.
- The root widget of a screen reads `context.windowClass` and picks the layout: a bottom bar or a
  rail, one pane or two. A small widget never looks at the window: it decides from the space its
  parent gives it, with `LayoutBuilder`, so it works in a side panel as well as full screen.
- The class comes from `MediaQuery.sizeOf(context)`: it is the size of the window the widget is in
  (each `View` has its own `MediaQuery`, so a second desktop window gets its own), and a test sets
  it through `MediaQuery`. Do not compute it from
  `PlatformDispatcher.instance.views.first` in a `WidgetsBindingObserver`: that is the first window
  only, and it ignores the `MediaQuery` the app provides.
- `MediaQuery.sizeOf` rebuilds its reader on every size change, every frame of a window being
  resized, even while the class stays the same. Read it in one place, the screen's root, and pass
  what it decided down as plain parameters.
- `AspectRatio` sizes a photo or video from the width it gets. `FittedBox` scales its child to fit,
  so around text it undoes the user's text scaling (see "Text scaling"): only for short labels that
  must stay on one line, such as a number in a badge.

```dart
// file: window_class.dart
import 'package:flutter/widgets.dart';

/// Material 3 window size classes, by the width of the window in logical pixels.
enum WindowClass implements Comparable<WindowClass> {
  /// Under 600: phones in portrait, narrow split screens.
  compact(0),

  /// 600 to 839: tablets in portrait, foldables.
  medium(600),

  /// 840 to 1199: tablets in landscape, small desktop windows.
  expanded(840),

  /// 1200 to 1599: desktop windows.
  large(1200),

  /// 1600 and wider.
  extraLarge(1600);

  const WindowClass(this.minWidth);

  /// The narrowest width of this class.
  final double minWidth;

  /// The class of a window [width] wide.
  static WindowClass of(double width) =>
      values.lastWhere((windowClass) => width >= windowClass.minWidth, orElse: () => compact);

  bool operator >=(WindowClass other) => index >= other.index;

  bool operator <(WindowClass other) => index < other.index;

  @override
  int compareTo(WindowClass other) => index - other.index;
}

/// `context.windowClass` in the root widget of a screen.
extension WindowClassContext on BuildContext {
  /// The class of the window (the `View`) this context is in. Rebuilds on every size change of
  /// the window, so read it in the screen's root, not in small widgets: they use `LayoutBuilder`.
  WindowClass get windowClass => WindowClass.of(MediaQuery.sizeOf(this).width);
}
```

```dart
@override
Widget build(BuildContext context) => switch (context.windowClass) {
  WindowClass.compact => const _OnePane(),
  _ => const _TwoPanes(),
};
```

### Text scaling

The system font size (an accessibility setting) scales all text. Clamp it once, in the app's
`builder`, to the range the layout was tested at, instead of letting a large setting break it:

```dart
MaterialApp(
  builder: (context, child) => MediaQuery.withClampedTextScaling(
    minScaleFactor: 1,
    maxScaleFactor: 1.5,
    child: child!,
  ),
);
```

- Clamp rather than fix at 1: users who need bigger text then still get some of it.
  `MediaQuery.withNoTextScaling` turns it off entirely; use it for a widget that must not scale (a
  fixed-size badge), not for the whole app.
- Do not use old snippets with `MediaQueryData.fromWindow(WidgetsBinding.instance.window)` and
  `copyWith(textScaleFactor: 1)`: `fromWindow`, `window` and `textScaleFactor` are deprecated
  (`fromView`, `View.of(context)`, `TextScaler`), and data built from the window ignores the
  `MediaQuery` the app already provides; `withClampedTextScaling` starts from that one.
- Read the scale with `MediaQuery.textScalerOf(context)`; check the screens at the maximum.
- A `FittedBox` around text scales the enlarged text back down to its box, which cancels the
  setting for that text.

### Constraints

Flutter lays out in one pass: constraints go down, sizes go up, the parent sets the position
(https://docs.flutter.dev/ui/layout/constraints).

- A widget gets a minimum and maximum width and height from its parent and picks its size inside
  them; `width: 100` under a tight constraint is ignored. It does not know or choose its position.
- **Tight** constraints allow one size (the screen gives the root exactly its size); **loose**
  ones have a minimum of zero (`Center` loosens tight constraints, so its child can be smaller).
- **Unbounded** constraints are infinite in one direction: inside a scroll view along its axis,
  and for the children of a `Row` or `Column` along theirs. A widget that wants to be as big as
  possible cannot be, and throws in debug mode: a vertical `ListView` straight inside a `Column`, or
  an `Expanded` inside a `Column` inside a scroll view. Give it a bound (`Expanded` around the
  `ListView`, a `SizedBox`).

## Scrolling and slivers

A scroll view is a `Scrollable` (gestures, `ScrollController`, `ScrollPosition`, `ScrollPhysics`), a
viewport that shows the part of the content at the position's offset, and the content as slivers.
`ListView`, `GridView` and `CustomScrollView` are all built this way: a `ListView` is a scroll view
with one list sliver (`SliverFixedExtentList` when `itemExtent` is set, `SliverPrototypeExtentList`
for `prototypeItem`).

- **Two layout protocols.** A box gets `BoxConstraints` and returns a `Size`. A sliver gets
  `SliverConstraints` (how far the viewport has scrolled into it, `scrollOffset`; the room left to
  paint, `remainingPaintExtent`) and returns a `SliverGeometry` (its length, `scrollExtent`; what it
  paints now, `paintExtent`). That is how a sliver builds only what is visible plus a cache (250
  logical pixels on each side by default), and how a header pins or floats: it paints more or less
  than it scrolls.
- **One scrolling screen, one `CustomScrollView`.** Several lists, a grid and headers between them
  are slivers in one `slivers:` list: one viewport, one scroll position, every list lazy. A box
  widget joins through `SliverToBoxAdapter`. A `ListView(shrinkWrap: true, physics:
  NeverScrollableScrollPhysics())` inside another `ListView`, or in a `Column` in a
  `SingleChildScrollView`, is the mistake this replaces: `shrinkWrap` measures itself by laying out
  every row (checked: 1000 of 1000 rows built, against 18 of 1030 for the slivers of
  `section_sliver.dart`).
- **`shrinkWrap` is for short lists**, a few items in a dialog or a `Column`. Never use it to
  silence "Vertical viewport was given unbounded height": bound the list (`Expanded`, `SizedBox`)
  or make it a sliver.
- **`SingleChildScrollView` has no slivers**: it lays out and paints its whole child. It is for
  content that is short but may not fit, such as a form in a small window or above the keyboard.
- **Sections are widgets that return slivers.** Split a long `CustomScrollView` into widget classes
  named `...Sliver` (`SectionSliver`), as the SDK names its own. A header and its rows are one
  `SliverMainAxisGroup`; a `PinnedHeaderSliver` inside the group sticks to the top while the
  section scrolls and leaves with its last row (checked). A small box widget stays a box, and the
  parent wraps it in `SliverToBoxAdapter`.
- **A horizontal list inside a vertical one** needs a height:
  `SizedBox(height: 120, child: ListView(scrollDirection: Axis.horizontal, ...))`. A scroll view
  inside another on the same axis needs a bounded inner one; when an outer header should collapse
  as the inner list scrolls, use `NestedScrollView`.
- Rows of a sliver list are built and destroyed as they scroll, `State` included: see "State in
  list rows".

Use a built-in sliver before writing a `RenderSliver`:

| Need | Sliver |
|---|---|
| A lazy list or grid | `SliverList.builder`, `SliverList.separated`, `SliverGrid.builder`, `SliverFixedExtentList`, `SliverVariedExtentList` |
| A collapsing app bar | `SliverAppBar` (Material) |
| A header that stays at the top | `PinnedHeaderSliver`; one that shrinks first: `SliverResizingHeader` |
| A header that comes back on scrolling up | `SliverFloatingHeader` |
| A header with its own behaviour | `SliverPersistentHeader` and a delegate |
| A section of a header and rows; sections side by side | `SliverMainAxisGroup`; `SliverCrossAxisGroup` |
| An empty state or a footer filling the rest | `SliverFillRemaining(hasScrollBody: false)` |
| Padding, safe area, background | `SliverPadding`, `SliverSafeArea`, `DecoratedSliver` |
| Animated or reorderable rows | `SliverAnimatedList`, `SliverReorderableList` |
| A layout chosen from the sliver's constraints | `SliverLayoutBuilder` |
| Hiding, fading, blocking taps | `SliverVisibility`, `SliverOpacity`, `SliverOffstage`, `SliverIgnorePointer` |

### `section_sliver.dart`

```dart
// file: section_sliver.dart
import 'package:flutter/widgets.dart';

/// One section of a long scrolling screen: a header that sticks to the top while the section's
/// rows pass under it, then a lazy list. It returns a sliver, so a screen puts several of them
/// into one `CustomScrollView`, with one viewport and one scroll position.
class SectionSliver<T extends Object> extends StatelessWidget {
  const SectionSliver({
    required this.header,
    required this.items,
    required this.itemBuilder,
    required this.itemId,
    super.key,
  });

  final Widget header;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// A stable id per item, for the row keys.
  final Object Function(T item) itemId;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: <Widget>[
      // Pinned inside the group: it leaves with the section's last row.
      PinnedHeaderSliver(child: header),
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => KeyedSubtree(
          key: ValueKey<Object>(itemId(items[index])),
          child: itemBuilder(context, items[index]),
        ),
      ),
    ],
  );
}
```

```dart
CustomScrollView(
  slivers: <Widget>[
    const SliverAppBar(pinned: true, title: Text('News')),
    SectionSliver<Ad>(header: const AdsHeader(), items: ads, itemBuilder: ..., itemId: ...),
    const SliverToBoxAdapter(child: Divider()),
    SectionSliver<Story>(header: const NewsHeader(), items: news, itemBuilder: ..., itemId: ...),
    const SliverFillRemaining(hasScrollBody: false, child: Center(child: EndOfFeed())),
  ],
);
```

## Focus and keyboard

Focus nodes form a tree beside the widget tree: only `Focus`, `FocusScope` and the widgets built on
them (text fields, buttons) add a node. `FocusManager.instance.primaryFocus` is the one node that
receives the keys; `node.hasPrimaryFocus` is true for it only, `node.hasFocus` for it and every
ancestor.

- **Where a key goes.** To the primary focus, then up through its ancestors to the root. Each
  `onKeyEvent` returns a `KeyEventResult`: `ignored` passes the key to the parent, `handled` stops
  and consumes it, `skipRemainingHandlers` stops it in Flutter and hands it to the platform as
  unhandled (a native text field, the browser). A handler sees only what nobody below it handled,
  and nothing at all while the focus is elsewhere in the tree.
- **A `Shortcuts` needs focus inside it.** `Shortcuts` maps keys to `Intent`s, `Actions` maps an
  intent type to the code (`CallbackAction`), so a menu item, a button and a key run the same
  intent. A `Shortcuts` gets keys only from a focused node below it: a screen's shortcuts do nothing
  until the user clicks something focusable, unless a `Focus(autofocus: true)` sits below them
  (`save_shortcut.dart`). A text field inside passes on the keys it does not use: Ctrl+S still
  saves while typing (both checked). `CallbackShortcuts` is the short form for a key that only
  calls a function.
- **Bind with `SingleActivator`** (`SingleActivator(LogicalKeyboardKey.keyS, meta: true)`), which
  the SDK prefers to `LogicalKeySet`. The command key is `meta` on macOS and iOS and `control`
  elsewhere: choose by `defaultTargetPlatform`.
- **The default keys depend on the platform** (`WidgetsApp.defaultShortcuts`). Everywhere: Tab and
  Shift+Tab move the focus, Escape is `DismissIntent`, Enter and Space activate, Page Up and Page
  Down scroll. Off the web, arrows move the focus between widgets (`DirectionalFocusIntent`), and
  arrows scroll with Cmd on macOS and iOS, with Ctrl on Android, Windows and Linux. On the web,
  plain arrows scroll and Enter activates buttons only (`ButtonActivateIntent`).
- **Overriding a key.** A `Shortcuts` adds keys for its subtree and wins over those above it. To
  switch a key off below some point, map it to `DoNothingIntent()`, which consumes it, or to
  `DoNothingAndStopPropagationIntent()`, which keeps it from Flutter's handlers above and hands it
  to the platform as unhandled (checked: both stop an outer `Shortcuts`; only the first reports the
  key handled). A focused text field handles its editing keys first (`DefaultTextEditingShortcuts`):
  arrows, Home and End bound above it do not fire while it has focus.
- **`onKeyEvent` goes on the `Focus` widget**, not on the node by hand: the widget writes its
  handler into the node when it attaches it, and into a node it created on every update.
- **A focus change lands in a microtask.** Right after `node.requestFocus()`,
  `node.hasPrimaryFocus` is still `false`; it is `true` from the next microtask (checked). React to
  focus in a listener of the node, not on the line after the request.
- **A `FocusNode` is owned like a controller**: created in a field or `initState`, disposed in
  `dispose`, never created in `build`. Only the first `autofocus` in a scope takes effect.
- **Moving through a form** needs no nodes: `textInputAction: TextInputAction.next` moves to the
  next field on submit, `TextInputAction.done` unfocuses. `FocusManager.instance.primaryFocus
  ?.unfocus()` closes the keyboard from elsewhere (a tap on the background).

### Traversal order

Tab sends `NextFocusIntent`; its action calls `nextFocus()` on the primary focus, and the policy of
the nearest `FocusTraversalGroup` picks the next node. It skips nodes that cannot take focus or are
out of traversal (`canRequestFocus: false`, `skipTraversal: true`, under `descendantsAreFocusable:
false` or `descendantsAreTraversable: false`), focuses the next one and scrolls it into view
(`Scrollable.ensureVisible`).

- The default policy is `ReadingOrderTraversalPolicy`: the visual order, row by row. Two columns of
  fields are read across (checked: `a1, b1, a2, b2`). Fix the order by fixing the layout first.
  Where the logical order differs from the visual one (a form in two columns read column by
  column), wrap the part in `FocusTraversalGroup(policy: OrderedTraversalPolicy())` and give the
  fields `FocusTraversalOrder(order: NumericFocusOrder(n))`.
- A dialog is a route, and a route is a focus scope: Tab cycles inside it (checked). A panel that
  should be traversed as one block before the rest gets its own `FocusTraversalGroup`.
- After the last widget Tab goes back to the first (checked). On the web, the navigator of
  `WidgetsApp` lets the focus leave to the browser instead
  (`TraversalEdgeBehavior.leaveFlutterView`).
- `ExcludeFocus` takes a subtree out of focus altogether (see "Loading overlay");
  `ExcludeFocusTraversal` only skips it on Tab, and a click or `requestFocus` still focuses it
  (checked).

### `save_shortcut.dart`

```dart
// file: save_shortcut.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the user wants: save. A menu item, a button and the key all invoke the same intent.
class SaveIntent extends Intent {
  const SaveIntent();
}

/// Cmd+S on Apple platforms, Ctrl+S elsewhere, anywhere inside [child], also while a text field
/// inside it has focus.
class SaveShortcut extends StatelessWidget {
  const SaveShortcut({required this.onSave, required this.child, super.key});

  final VoidCallback onSave;
  final Widget child;

  static const Map<ShortcutActivator, Intent> _apple = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveIntent(),
  };
  static const Map<ShortcutActivator, Intent> _other = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => _apple,
      _ => _other,
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => onSave()),
      },
      // Keys reach `Shortcuts` only from a focused node below it: without this, the shortcut
      // does nothing until the user clicks something focusable.
      child: Focus(autofocus: true, child: child),
    ),
  );
}
```

## Lifecycle of a `State`

A widget is immutable configuration: a description of a piece of UI that its parent creates anew on
every build. What lives on is the element and its `State`; on each rebuild the element gets the new
widget and compares it with the old one. Strictly, Flutter keeps a tree of elements, not of
widgets: "widget tree" is shorthand.

- **`initState`**: once, when the `State` is inserted into the tree. Create what the `State` owns
  and subscribe to what it listens to. A scope can be read here with a lookup that does not
  subscribe (`DependenciesScope.of`); anything that must rebuild on an inherited change (`Theme`,
  `MediaQuery`, localization) belongs in `didChangeDependencies` or `build`.
- **`didChangeDependencies`**: right after `initState`, and again whenever an `InheritedWidget` this
  `State` depends on changes.
- **`didUpdateWidget(oldWidget)`**: the parent rebuilt and gave a widget of the same type and key.
  That happens on almost every rebuild of the parent, whether or not any field changed (only an
  identical instance, such as a `const` one, skips it). Compare the fields yourself and react to
  what changed; for a controller or notifier, compare with `identical`, stop listening to the old one
  and listen to the new one (example in "Listeners and dispose"). `build` always runs afterwards, so
  `setState` here is redundant.
- **`dispose`**: once, when the `State` leaves the tree for good.

`super` goes first in `initState`, `didChangeDependencies` and `didUpdateWidget`, so the framework
and the mixins (`TickerProviderStateMixin`) are set up before your code runs, and last in
`dispose`, so your code still has them while it cleans up. Where the IDE puts its generated
`// TODO` says nothing about this. `super.didUpdateWidget` takes `oldWidget`, not `widget`.

### Keys

A widget's `key` is `null` unless you pass one. On a rebuild, an element keeps its `State` and takes
the new widget when the old and new widgets have the same `runtimeType` and an equal `key`
(`Widget.canUpdate`); otherwise the old element and everything below it is thrown away and a new
one is created.

- A `LocalKey` (`ValueKey`, `ObjectKey`, `UniqueKey`) works among the children of one parent. It
  keeps state: siblings in a `Column` or a list that are reordered, inserted or removed each keep
  their own `State`. Without keys, children are matched by type and position, and the state of
  one item shows up on another. Remove the 5th of 10 unkeyed rows and the 5th element stays,
  updated with the 6th widget, each later element moves up one widget, and the element that goes
  is the last. So every row of a list that can insert, remove or reorder gets a key from its
  data: `ValueKey(item.id)`, never the index.
- It also resets state on purpose: `ProfileForm(key: ValueKey(user.id))` builds a fresh form, with
  fresh text controllers, when another user is shown in the same place.
- A `GlobalKey` must be unique in the whole app, not only among siblings, and it has one job: keep
  an element and its `State` while the widget moves to another parent or depth, which the framework does by moving the subtree instead of recreating it. That is
  expensive and almost never needed; keep the tree shape stable instead (see "Animations").
- Do not use a `GlobalKey` to read a widget's size or position (`findRenderObject()`): see
  "Painters, clippers and layout delegates".
- Do not use a `GlobalKey` to call a `State` or read its `context` from outside
  (`key.currentState!.open()`): give the widget a controller or a callback. When an API requires one,
  create it once in a `State` field, never in `build` (a new key on every build means a new `State`
  on every build).

### Hiding a widget

| Widget | `State` | Layout | Paint, taps | Focus | Animations |
|---|---|---|---|---|---|
| `if (show) child` | disposed | no | no | no | stopped |
| `Visibility(visible: false)` | disposed (shows `replacement`, `SizedBox.shrink()` by default) | no | no | no | stopped |
| `Visibility(maintainState: true)` | kept | yes, takes no space (an `Offstage`) | no | excluded | paused (`TickerMode` off) |
| `Visibility.maintain(visible: false)` | kept | yes, keeps its size | no | excluded | running |
| `Offstage()` | kept | yes, takes no space | no | **still focusable** | running |

Hide with `if` or `Visibility` by default. Keep state only when coming back must be instant or keep
what the user entered, and then prefer `Visibility(maintainState: true)`, which also pauses
animations and takes focus away. A bare `Offstage` keeps laying out, keeps its tickers running
(draining the battery), and what is inside it can still take keyboard focus.

## `BuildContext` after `await`

After an `await` the widget may be gone: the user left the screen, the dialog closed. Its context
then belongs to an unmounted element, and `Navigator.of(context)`, `Theme.of(context)` or a scope's
`of(context)` throws or acts on a screen that no longer exists.

```dart
// Wrong: the context is used after the await.
Future<void> _save() async {
  await _controller.save(_form);
  Navigator.pop(context);
}

// Right: take what you need first, then check that the widget is still there.
Future<void> _save() async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await _controller.save(_form);
  if (!mounted) return;
  navigator.pop();
  messenger.showSnackBar(const SnackBar(content: Text('Saved')));
}
```

- `State.mounted` and `context.mounted` are the same check: whether the element is still in the
  tree. Use `context.mounted` where there is no `State` (a function that takes a context).
- Check even when you took the navigator before the `await`: if the screen is gone, popping would
  close whatever is on top now.
- The `use_build_context_synchronously` lint (in `flutter_lints`) reports the wrong version; do not
  silence it.
- Better still, do not `await` in the widget at all: call the controller, and react to its
  `successful` state in the `listener` of `StateConsumer`, which only runs while the widget is
  mounted.

## Small layout habits

- Several children under one condition go in with a spread, not in an extra `Row` or `Column`:
  `Row(children: [a, if (expanded) ...[b, c, d]])`.
- For an exact size, `SizedBox(width: w, height: h)` (it is `BoxConstraints.tightFor`), not a
  `ConstrainedBox`. `ConstrainedBox(constraints: BoxConstraints(maxWidth: w))` means something else,
  "at most `w`", and is still the right widget for that.

## Message time in a chat bubble

A messenger puts the time in the bottom corner of a bubble: on the last line of the text when that
line has room, on a line of its own when it does not. One `Stack` does it: the text ends with an
invisible copy of the time, which reserves the space, and the visible time is pinned to the corner
over that space (idea from https://dartpad.dev/?id=60f41eb9f76d5513df0bfe80f9681271).

```dart
// file: message_bubble.dart
import 'package:flutter/material.dart';

/// A chat message with its [time] in the bottom end corner, on the text's last line when it fits.
class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.text, required this.time, super.key});

  /// The message.
  final String text;

  /// The time, already formatted (`DateFormat.Hm()` from `intl`).
  final String time;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Text(
        time,
        maxLines: 1,
        style: TextStyle(fontSize: 12, height: 1, color: colors.onSurfaceVariant),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Stack(
          children: <Widget>[
            // The invisible copy at the end of the text keeps its place on the last line.
            Text.rich(
              TextSpan(
                text: text,
                children: <InlineSpan>[
                  WidgetSpan(child: Visibility.maintain(visible: false, child: label)),
                ],
              ),
            ),
            // The visible time, pinned to the corner over the reserved place.
            PositionedDirectional(end: 0, bottom: 0, child: label),
          ],
        ),
      ),
    );
  }
}
```

- The `Stack` sizes itself to the text (with its reserved space), so the bubble needs no
  measuring and no `LayoutBuilder`.
- A clock that ticks (a "now" label) is one `ValueNotifier` with one `Timer` shared by every
  bubble, not a timer per bubble.

## Splitting files

Files are split so that working on one piece of a feature needs few tabs, not so that every file
is short.

- **A screen and its private parts share one file.** Widgets used nowhere else (`_Header`,
  `_ProductRow`, `_EmptyState`), and a form controller only that screen uses, are private classes
  in the screen's file, however many there are. A long file is navigated with the IDE: go to class
  or symbol, the outline, search, bookmarks, a split view of the same file.
- **A widget gets its own file** when it is used in several places, or when you come to the file
  for that widget rather than for the screen.
- **No `part` / `part of`.** It glues files back into one library: the parts share one namespace and
  their private members, so nothing is really separated. It is a sign that composition is missing;
  split into real libraries with their own imports instead.
- **Kinds stay apart.** Logic, models, repositories and business controllers never sit in a widget
  file; only UI pieces and UI-only state do.
- Hundreds of private widgets in a 5,000-line file are fine when they belong to one screen; a
  5,000-line file that mixes several screens, models and logic is not.

## Forms

A form is a few controllers, one per field, merged into one `Listenable`; every change recomputes
whether the form is valid and what error to show. Form packages put the values into a map keyed by
strings and lose the types on the way out, without making the code shorter (example
`sign_in_form.dart`).

- No `Form` with a `GlobalKey<FormState>`: the values sit in `FormField` states that only a key
  reaches, and `validate()` is called from outside. The controllers below give the same, typed.
- Each field keeps its own typed controller: `TextEditingController` for text, `ValueNotifier<T>`
  for a checkbox, a choice or a set of tags.
- `_onChanged` reads them all, synchronously, and writes the result into `ValueNotifier`s
  (`_valid`, `_error`); the submit button and the error text listen to those, so typing rebuilds
  only them.
- Call `_onChanged()` once in `initState`, so the state is right before the first change.
- Put the fields' `FocusNode`s into the merge too, to validate when a field loses focus (show
  "required" only after the user has left the field). `Listenable.merge` returns a `Listenable`,
  not a list: keep your own list of the controllers for `dispose`.
- The list given to `Listenable.merge` must not change after the call: the SDK says adding or
  removing items leads to leaks or exceptions (`null` items are ignored). Pass a fixed list, never a
  lazy `.map(...)`; a field shown only for some choices is created with the form and merged from
  the start (see "Fields that come and go").
- Dispose every controller. A list of them disposed with `whereType<ChangeNotifier>()` misses an
  `AnimationController`, which is a `Listenable` but not a `ChangeNotifier`: dispose that one
  itself.
- A validation error is a value: an enum (`SignInError.invalidEmail`) or a sealed class, never an
  English sentence. The widget turns it into text with `Localization.of(context)` where it shows
  it (`sign_in_form.dart`; see `docs/rules/localization.md`).
- A part of the UI that depends on several fields (a character counter, a live preview, a section
  shown for one choice) is one `ListenableBuilder(listenable: _form, ...)` around just that part.
  With the `FocusNode`s in the merge it also rebuilds on focus changes.
- A disabled submit button suits a form whose rules the labels state. When the user has to
  discover them (password strength, a name that must be free), keep the button enabled: on press,
  compute every error, show each under its field (`errorText` from a `ValueNotifier` of the errors
  by field) and focus the first field with an error.
- Submitting calls the controller with the typed values; showing the server's answer is the
  controller's state, as everywhere else.

### Validation that waits for a server

"Is this username free" is asynchronous and can fail, so it is a controller
(`docs/rules/controllers.md`), not an `await` in `_onChanged`:

- The form merges the controller (it is a `Listenable`) with its fields, and `_onChanged` treats a
  check that is still running as not valid yet, so the submit button waits.
- Check when the user leaves the field (its `FocusNode` in the merge) or when typing pauses (a
  `Timer` of about 300 ms, restarted on each change and cancelled in `dispose`), never on every key.
- The answer carries the name it checked, and `_onChanged` accepts it only while that is still the
  field's text: an answer to an older text is stale, however late it comes.
- Run the cheap checks (length, characters) first, and ask the server only when they pass.
- The server decides again on submit: a name that was free a minute ago may be taken now.

```dart
void _onChanged() {
  final name = _username.text.trim();
  final check = _usernameCheck.state; // data: the last answer, `({String name, bool free})?`
  final answer = check.data;
  final free = check is! UsernameCheck$ProcessingState && answer?.name == name && answer!.free;
  _valid.value = name.length >= 3 && free && _password.text.length >= 8;
}
```

### Fields that come and go

A choice that shows other fields (a card number for "card", an e-mail for "PayPal") is one more
`ValueNotifier` in the merge.

- Every field's controller is created with the form and merged once; `_onChanged` checks only the
  fields the current choice shows. A hidden field is not invalid because it is empty.
- Hide the group with `if` (see "Hiding a widget"): its controllers keep the text for when the user
  switches back, and submit sends only the shown group's values.
- `Form.validate()` would visit every field still in the tree, those kept by
  `Visibility(maintainState: true)` or `Offstage` too, which is why form packages grow a
  "validate this field" flag. With one `_onChanged` it is a condition.

```dart
void _onChanged() {
  final errors = switch (_method.value) {
    PaymentMethod.card => <PaymentError>{
      if (_cardNumber.text.length < 12) PaymentError.cardNumber,
      if (_cvv.text.length != 3) PaymentError.cvv,
    },
    PaymentMethod.paypal => <PaymentError>{
      if (!_paypalEmail.text.contains('@')) PaymentError.email,
    },
  };
  _errors.value = errors; // each field shows `errorText` when its error is in the set
  _valid.value = errors.isEmpty;
}
```

### A form over several screens

A form in steps (an application in three screens, each a page of a nested `Navigator`) keeps its
data above that navigator:

- One class `with ChangeNotifier` holds the typed answers of every step. The `State` of the widget
  that wraps the nested navigator creates and disposes it, and a scope (an `InheritedNotifier`)
  hands it to the steps.
- Text that must survive going back lives in controllers that the same `State` owns: a controller
  created by a step's `State` dies with that page, and the step shows empty fields when the user
  comes back. A step that does not need that reads its initial text from the data and writes back
  on change.
- The current step is derived from the data (the first step whose answers are incomplete), so the
  pages are built from it and a restored or reopened form lands on the right step.
- "Next" validates the current step only; the final submit validates every step and calls the
  controller with one typed object.

### Restoring what the user typed

On Android and iOS the system may kill an app in the background; state restoration gives small
values back when the user returns to it.

- It is off until `MaterialApp(restorationScopeId: 'app')` (`CupertinoApp` and `WidgetsApp` take
  the same).
- `TextField(restorationId: 'email')` restores its text only when it creates its own controller.
  With your own controllers, the form's `State` mixes in `RestorationMixin`, holds
  `RestorableTextEditingController`s (and `RestorableBool`, `RestorableEnum<T>`, ...), registers
  each in `restoreState` with `registerForRestoration(_email, 'email')`, reads the controller as
  `_email.value`, and disposes each.
- Only a restored page restores its fields: a `Page` with a `restorationId`, or a route opened with
  `Navigator.restorablePush`.
- Restore what the user typed, never what a repository can load again, and never a controller's
  state (see `docs/rules/controllers.md`).

## One-time codes and PINs

A code of N digits is one hidden `TextField` and a `CustomPainter` that draws the N boxes, not N
`TextField`s that move the focus between them: with one field, paste, the keyboard's suggestion,
autofill and backspace across boxes all work.

- The field: `keyboardType: TextInputType.number`, `inputFormatters` with
  `FilteringTextInputFormatter.digitsOnly` and `LengthLimitingTextInputFormatter(n)`,
  `autofillHints: [AutofillHints.oneTimeCode]` (the code from an SMS, offered by iOS), transparent
  text and cursor, no counter, and `obscureText` for a PIN.
- The painter repaints from `Listenable.merge([controller, focusNode])`, so typing and focus both
  redraw the boxes without a rebuild; it draws the digits (or dots) and a cursor in the current box.
- A tap on the boxes requests focus and may move the selection to the tapped box.

## Loading overlay

To block a screen while it saves, without throwing its content away: a `Stack` with the content and
a `Positioned.fill` overlay over it.

- `AbsorbPointer` takes every tap, so the content under it gets none.
- `ExcludeFocus` around the content: `AbsorbPointer` stops the pointer only, and a focused button
  still fires on Enter or Space.
- `AnimatedSwitcher` fades the overlay in and out.
- `ClipRect` around `BackdropFilter`: a backdrop filter blurs everything behind it up to the
  nearest clip, which without a `ClipRect` is the whole screen.
- `RepaintBoundary` around the spinner: it repaints every frame, and without the boundary the
  blur is redrawn with it.

The content is the `Stack`'s non-positioned child, so the stack takes its size and the overlay
covers exactly it. Keep the blur small and the overlay no bigger than what it blocks: a backdrop
filter is one of the costliest things to draw, more so on the web and on old phones.

```dart
// file: loading_overlay.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shows [child] and, while [processing], a blurred overlay with a spinner that takes every tap
/// and keeps keyboard focus out of [child].
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({required this.processing, required this.child, super.key});

  final bool processing;
  final Widget child;

  static const Duration _fade = Duration(milliseconds: 350);
  static const double _blur = 2;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      ExcludeFocus(excluding: processing, child: child),
      Positioned.fill(
        child: AbsorbPointer(
          absorbing: processing,
          child: AnimatedSwitcher(
            duration: _fade,
            child: processing
                ? ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
                      child: const Center(child: RepaintBoundary(child: CircularProgressIndicator())),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ],
  );
}
```

## Anchored popups

A popup attached to a widget (a dropdown, a menu, a hint, an onboarding step, a badge that follows a
moving item) is never placed from coordinates read after layout (a `GlobalKey` and
`findRenderObject`, see "Painters, clippers and layout delegates"), and never an `OverlayEntry`
inserted and removed by hand. In this order:

1. **A framework widget that does it**: `MenuAnchor`, `DropdownMenu`, `SearchAnchor`,
   `Autocomplete`, `Tooltip`, `PopupMenuButton`, or `RawMenuAnchor` for a menu with the app's own
   look. They already close on Escape and on a tap outside, and handle the keyboard.
2. **`OverlayPortal.overlayChildLayoutBuilder`** when the popup is placed from the anchor's size and
   position: below it, above it when there is no room, kept inside the window
   (`anchored_popup.dart`). The builder runs during layout and gets an `OverlayChildLayoutInfo`:
   the anchor's `childSize`, its `childPaintTransform` into the overlay, and the `overlaySize`. The
   popup's own size exists only in layout, so a `CustomSingleChildLayout` places it. The builder
   runs again on every frame, so the popup follows an anchor that scrolls (checked).
3. **`LayerLink`** when the popup is pinned to a corner of the anchor and needs no sizes:
   `CompositedTransformTarget(link:)` around the anchor, `CompositedTransformFollower(link:,
   targetAnchor:, followerAnchor:, offset:, showWhenUnlinked: false)` around the popup. The
   compositor moves the follower with the target, through scrolling and transforms, with no layout
   (checked); it cannot flip or clamp. One link has one target and any number of followers; it is a
   `State` field and has nothing to dispose. The overlay gives its children tight constraints, so
   the follower's child needs an `Align` to keep its own size (`LinkedPopup` below).

- An `OverlayPortal`'s overlay child is built below the portal in the element tree: it reads the
  same `Theme`, `Directionality` and scopes, and it goes away with the portal. An `OverlayEntry` is
  built under the `Overlay` and misses every scope between the two.
- The two ways do not nest: an `OverlayPortal.overlayChildLayoutBuilder` with a
  `CompositedTransformFollower` between it and its overlay (a layout-builder popup inside a
  follower popup) throws "The paint transform cannot be reliably computed because of
  RenderFollowerLayer(s)" (checked).
- Close it on a tap outside with `TapRegion`: the anchor and the popup share a `groupId`, so a tap
  on either is inside. Every pointer down outside closes it, the start of a scroll included
  (checked).
- The `OverlayPortalController` belongs to the widget that opens the popup: a `State` field.
- A popup needs an `Overlay` above it: what `MaterialApp.builder` puts above the navigator has
  none (see `docs/rules/navigation.md`).

### `anchored_popup.dart`

```dart
// file: anchored_popup.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shows [popup] under [child] while [controller] is showing, or above it when there is no room
/// below; a tap outside both hides it. It follows [child] when it scrolls or moves: the layout
/// builder runs again on every frame. No `GlobalKey`, no `findRenderObject`.
class AnchoredPopup extends StatefulWidget {
  const AnchoredPopup({
    required this.controller,
    required this.popup,
    required this.child,
    this.gap = 4,
    super.key,
  });

  /// Shows and hides the popup; created and owned by the caller's `State`.
  final OverlayPortalController controller;
  final Widget popup;
  final Widget child;

  /// The space between [child] and [popup].
  final double gap;

  @override
  State<AnchoredPopup> createState() => _AnchoredPopupState();
}

class _AnchoredPopupState extends State<AnchoredPopup> {
  /// Taps on the anchor and on the popup count as inside.
  final Object _tapGroup = Object();

  void _hide(PointerDownEvent _) => widget.controller.hide();

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: widget.controller,
    overlayChildBuilder: (context, info) {
      // The anchor's rectangle in the overlay's coordinates.
      final anchor = MatrixUtils.transformRect(
        info.childPaintTransform,
        Offset.zero & info.childSize,
      );
      return CustomSingleChildLayout(
        delegate: _PopupLayout(anchor: anchor, gap: widget.gap),
        child: TapRegion(groupId: _tapGroup, onTapOutside: _hide, child: widget.popup),
      );
    },
    child: TapRegion(groupId: _tapGroup, child: widget.child),
  );
}

/// Places the popup from its own size, which only layout knows.
class _PopupLayout extends SingleChildLayoutDelegate {
  const _PopupLayout({required this.anchor, required this.gap});

  final Rect anchor;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = anchor.bottom + gap;
    final y = below + childSize.height <= size.height
        ? below
        : anchor.top - gap - childSize.height; // no room below: flip above
    // Keep it inside the overlay.
    return Offset(
      anchor.left.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_PopupLayout oldDelegate) =>
      anchor != oldDelegate.anchor || gap != oldDelegate.gap;
}

/// The plain case: [follower] is pinned under [child] by a [LayerLink] and moves with it in the
/// compositor, with no layout at all. It knows neither its own nor the anchor's size, so it cannot
/// flip or clamp; use [AnchoredPopup] for that.
class LinkedPopup extends StatefulWidget {
  const LinkedPopup({
    required this.controller,
    required this.follower,
    required this.child,
    super.key,
  });

  final OverlayPortalController controller;
  final Widget follower;
  final Widget child;

  @override
  State<LinkedPopup> createState() => _LinkedPopupState();
}

class _LinkedPopupState extends State<LinkedPopup> {
  /// One link, one target; created once. A `LayerLink` has nothing to dispose.
  final LayerLink _link = LayerLink();

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: widget.controller,
    overlayChildBuilder: (context) => CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      // The overlay gives its children tight constraints: `Align` lets the follower take its
      // own size.
      child: Align(alignment: AlignmentDirectional.topStart, child: widget.follower),
    ),
    child: CompositedTransformTarget(link: _link, child: widget.child),
  );
}
```

## Magic numbers

A number or a string is magic because nothing outside the code can change it. Moving it into a
`static const` (`defaultPadding = 8`, `endpoint = 'https://...'`) and importing it elsewhere
changes nothing: it is still fixed in the code, only farther from where it is used, and a constant
that aliases another constant makes it worse.

A value stops being magic when it comes from outside the code that uses it:

1. a build variable (`--dart-define`, see `docs/rules/configuration.md`) or the environment;
2. a configuration file in the assets or from the backend;
3. Remote Config;
4. the theme: a `ThemeExtension` (in a design system package, if the project has one), read with
   `Theme.of(context).extension<AppSpacing>()!`;
5. a component that carries it: `DefaultPadding(child: ...)`, a `Gap` or an inset widget from the
   project's UI kit.

- A value used once stays a literal where it is used.
- A value the design repeats (spacing, radii, colors) comes from the theme or a component, never
  from a file of loose constants.
- An endpoint or a key comes from the configuration, never from a constant in the code.

## Themes

The app's themes are built once, in one place (`app_theme.dart`): `AppThemeData.light()` and
`.dark()`, an extension type over `ThemeData`, so `MaterialApp(theme: AppThemeData.light())` takes
it as it is and every call returns the same instance instead of building a new `ThemeData`.

- What the app's own components need beyond Material's `ColorScheme` and `TextTheme` (a focus
  ring, a bubble color, spacings) is a `ThemeExtension` in `ThemeData(extensions: {...})`, one
  class per group (`AppColors`, `AppSpacing`).
- A `ThemeExtension` implements `copyWith` and a real `lerp`: `MaterialApp` animates between light
  and dark through it, and a `lerp` that returns `this` makes the colors jump.
- Widgets read it through one shortcut (`context.colors`), never `Theme.of(context).extension<...>()!`
  spread over the code, and never a color literal (see "Magic numbers").

### `app_theme.dart`

```dart
// file: app_theme.dart
import 'package:flutter/material.dart';

/// The app's colors beyond the Material scheme, for its own components.
@immutable
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.focusRing, required this.bubble});

  /// The outline of a focused control.
  final Color focusRing;

  /// The background of a chat message.
  final Color bubble;

  @override
  AppColors copyWith({Color? focusRing, Color? bubble}) =>
      AppColors(focusRing: focusRing ?? this.focusRing, bubble: bubble ?? this.bubble);

  /// Called while the theme animates (light to dark): without it the colors jump.
  @override
  AppColors lerp(covariant AppColors? other, double t) => other == null
      ? this
      : AppColors(
          focusRing: Color.lerp(focusRing, other.focusRing, t)!,
          bubble: Color.lerp(bubble, other.bubble, t)!,
        );
}

/// The app's themes, built once.
extension type AppThemeData._(ThemeData data) implements ThemeData {
  factory AppThemeData.light() => AppThemeData._(_light);

  factory AppThemeData.dark() => AppThemeData._(_dark);

  static final ThemeData _light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB5442A)),
    extensions: const <ThemeExtension<Object?>>{
      AppColors(focusRing: Color(0xFF3B78E7), bubble: Color(0xFFE8F0FE)),
    },
  );

  static final ThemeData _dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFB5442A),
      brightness: Brightness.dark,
    ),
    extensions: const <ThemeExtension<Object?>>{
      AppColors(focusRing: Color(0xFF8AB4F8), bubble: Color(0xFF263238)),
    },
  );
}

/// `context.colors.bubble` in widgets.
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
```

## Components

A button, text field, card or text style that the design repeats is a component of the project's UI
kit (the shared widgets folder, or a design-system package), not a Material widget restyled where it
is used (`FilledButton(style: FilledButton.styleFrom(...))` in a screen). Restyled at each call
site, the design drifts one screen at a time and cannot be changed in one place. A component takes
its colors, text styles and radii from the theme (see "Themes").

- While the design is close to Material, keep `ColorScheme` and `TextTheme` and wrap Material
  widgets: they read those, and a parallel set of text styles would have to be kept in sync. A kit
  of its own from the ground up is for a design that leaves Material.
- A button with the app's look extends `ButtonStyleButton` and returns its `ButtonStyle` from
  `defaultStyleOf` (`ui_button.dart`). Focus, hover, ink, keyboard activation and semantics stay
  Material's (checked: Tab then Enter presses it, and it is a semantic button). The style resolves
  each property from the button's states with `WidgetStateProperty.resolveWith`
  (`WidgetState.disabled`, `pressed`, `hovered`, `focused`); one named constructor per variant.
- That default style sets every property Material's own buttons set (text style, padding, sizes,
  shape, visual density, tap target size, animation duration, alignment, splash factory, mouse
  cursor): `ButtonStyleButton` reads several of them with `!`, and a missing one throws (checked).
- `ButtonStyle.backgroundBuilder` and `foregroundBuilder` put a widget behind or over the content
  (a focus ring). With a builder set, `clipBehavior` defaults to `Clip.antiAlias` and cuts off what
  sticks out: pass `Clip.none`.
- Disabled colors in Material 3: the content is `onSurface` at alpha .38, the container at .12,
  written with `withValues(alpha: .38)`.
- A text field has no `ButtonStyleButton`. The kit's field is a widget around `TextField` that
  builds the `InputDecoration` from the theme (`isDense`, `contentPadding`, borders, a `hintStyle`
  that differs when disabled) together with what `TextField` takes outside the decoration (`style`,
  `cursorColor`); a screen passes only what varies (`hintText`, `errorText`) as the component's
  parameters.
- A component is also where a feature the Flutter widget lacks goes (a button's loading state), so
  screens do not each add it.

### `ui_button.dart`

```dart
// file: ui_button.dart
import 'package:flutter/material.dart';

enum UiButtonVariant { primary, outlined }

/// The app's button. Material's `ButtonStyleButton` keeps focus, hover, ink, semantics and
/// keyboard activation; only the look is the app's, in one place.
class UiButton extends ButtonStyleButton {
  const UiButton.primary({required super.onPressed, required super.child, super.key})
    : variant = UiButtonVariant.primary,
      super(
        onLongPress: null,
        onHover: null,
        onFocusChange: null,
        style: null,
        focusNode: null,
        autofocus: false,
        clipBehavior: Clip.none,
      );

  const UiButton.outlined({required super.onPressed, required super.child, super.key})
    : variant = UiButtonVariant.outlined,
      super(
        onLongPress: null,
        onHover: null,
        onFocusChange: null,
        style: null,
        focusNode: null,
        autofocus: false,
        clipBehavior: Clip.none,
      );

  final UiButtonVariant variant;

  @override
  ButtonStyle defaultStyleOf(BuildContext context) =>
      _UiButtonStyle(Theme.of(context).colorScheme, variant);

  /// No component theme: the style above is the whole design.
  @override
  ButtonStyle? themeStyleOf(BuildContext context) => null;
}

/// Every property is resolved from the button's states, so one object covers disabled, pressed,
/// hovered and focused.
class _UiButtonStyle extends ButtonStyle {
  const _UiButtonStyle(this._colors, this._variant)
    : super(
        // `ButtonStyleButton` needs every property from the default style: what Material's own
        // buttons set, set here too.
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 40)),
        maximumSize: const WidgetStatePropertyAll<Size>(Size.infinite),
        // The radius comes from the design tokens in the app (`AppRadius`).
        shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        animationDuration: kThemeChangeDuration,
        alignment: Alignment.center,
        splashFactory: InkRipple.splashFactory,
        mouseCursor: WidgetStateMouseCursor.clickable,
      );

  final ColorScheme _colors;
  final UiButtonVariant _variant;

  @override
  WidgetStateProperty<Color?> get backgroundColor => WidgetStateProperty.resolveWith(
    (states) => switch (_variant) {
      UiButtonVariant.outlined => const Color(0x00000000),
      _ when states.contains(WidgetState.disabled) => _colors.onSurface.withValues(alpha: .12),
      UiButtonVariant.primary => _colors.primary,
    },
  );

  @override
  WidgetStateProperty<Color?> get foregroundColor => WidgetStateProperty.resolveWith(
    (states) => switch (_variant) {
      _ when states.contains(WidgetState.disabled) => _colors.onSurface.withValues(alpha: .38),
      UiButtonVariant.primary => _colors.onPrimary,
      UiButtonVariant.outlined => _colors.primary,
    },
  );

  @override
  WidgetStateProperty<Color?> get overlayColor => WidgetStateProperty.resolveWith((states) {
    final base = _variant == UiButtonVariant.primary ? _colors.onPrimary : _colors.primary;
    if (states.contains(WidgetState.pressed)) return base.withValues(alpha: .1);
    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
      return base.withValues(alpha: .08);
    }
    return null;
  });

  @override
  WidgetStateProperty<BorderSide?> get side => WidgetStateProperty.resolveWith(
    (states) => switch (_variant) {
      UiButtonVariant.primary => null,
      _ when states.contains(WidgetState.disabled) => BorderSide(
        color: _colors.onSurface.withValues(alpha: .12),
      ),
      UiButtonVariant.outlined => BorderSide(color: _colors.outline),
    },
  );
}
```

## Replaced APIs

Old snippets still use these; the analyzer reports them as deprecated:

- `color.withOpacity(.5)`: `color.withValues(alpha: .5)` (`withOpacity` loses precision). Read the
  channels as `color.r`, `.g`, `.b`, `.a`, not `red` or `value`.
- `Radio(value: v, groupValue: selected, onChanged: ...)`: the radios sit under one
  `RadioGroup<T>(groupValue: selected, onChanged: ..., child: ...)` and each `Radio` keeps only its
  `value`.
- `MediaQueryData.fromWindow`, `textScaleFactor`: see "Text scaling".

## Listeners and dispose

- **What the widget created, it disposes.** A `TextEditingController`, `AnimationController`,
  `ScrollController`, `FocusNode` or controller created in `initState` is disposed in `dispose`.
  `ChangeNotifier.dispose` also drops all its listeners, so there is no need to `removeListener`
  from it first.
- **What it did not create, it only stops listening to.** A notifier from a scope, a parent or an
  app-wide controller lives longer than the widget: remove the listener in `dispose`, and in
  `didUpdateWidget` when the widget gets a different notifier. A listener left behind keeps the
  `State` alive and runs after it is unmounted.
- **Never dispose what you did not create**: the owner still uses it.
- **Listen with a method, never a closure**: `notifier.addListener(_onCart)`, not
  `notifier.addListener(() { ... })`. A listener is a reference in the notifier's list, and
  `removeListener` finds it by equality: two tear-offs of the same method on the same object are
  equal, two closures never are, so a closure cannot be removed. Write it this way even where
  `dispose` would drop it anyway: the notifier may later come from a parent and be swapped in
  `didUpdateWidget` or `didChangeDependencies`, and closures left behind pile up and keep running
  after the widget is gone.

```dart
@override
void initState() {
  super.initState();
  _search = TextEditingController()..addListener(_onSearch); // ours
  widget.cart.addListener(_onCart); // the parent's
}

@override
void didUpdateWidget(CartBadge oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (!identical(oldWidget.cart, widget.cart)) {
    oldWidget.cart.removeListener(_onCart);
    widget.cart.addListener(_onCart);
  }
}

@override
void dispose() {
  _search.dispose(); // drops _onSearch with it
  widget.cart.removeListener(_onCart); // not ours: stop listening, do not dispose
  super.dispose();
}
```

## Rebuilding on one part of a notifier

A `ListenableBuilder` around a `ChangeNotifier` rebuilds on every `notifyListeners()`, whatever
changed. When a widget shows one part of a larger notifier (the locale of the settings, the count
of a cart), select that part into a `ValueListenable` and build with `ValueListenableBuilder`
(`listenable_select.dart`):

```dart
late final ValueListenable<Locale> _locale = widget.settings.select((settings) => settings.locale);

@override
Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
  valueListenable: _locale,
  builder: (context, locale, child) => Text(locale.toLanguageTag()),
);
```

- Create the selection once, in a field of the `State`, never in `build`: a new one on every
  build makes the builder unsubscribe and subscribe again each time. When the notifier comes from
  the widget and can change, make the field a plain `late` one and select again in
  `didUpdateWidget` when `!identical(oldWidget.settings, widget.settings)`.
- A change is `previous != next` by default, so a selector may return a new record or data class
  with `==` each time: `(name: s.name, count: s.items.length)` notifies only when one of them
  differs (checked). A version that compares with `identical` notifies on every change of the
  source as soon as the selector builds a new object. Pass `changed` for another comparison.
- It listens to the source only while it has listeners, so a selection nobody watches keeps
  nothing alive and needs no `dispose` (checked: the source has no listeners left after the
  builder is gone).
- A `control` controller is a `ChangeNotifier` too: `controller.select((c) => c.state.data.total)`
  rebuilds a total only when it changes.

```dart
// file: listenable_select.dart
import 'package:flutter/foundation.dart';

/// `source.select((s) => s.locale)`: a [ValueListenable] of one part of a [Listenable], which
/// notifies only when that part changes.
///
/// Create it once (a `late final` field of the `State`), not in `build`: a new one on every build
/// re-subscribes the builder each time.
extension ListenableSelect<L extends Listenable> on L {
  /// [changed] decides whether a new value is a change; by default `previous != next`.
  ValueListenable<V> select<V>(
    V Function(L source) selector, [
    bool Function(V previous, V next)? changed,
  ]) => _Selected<L, V>(this, selector, changed ?? _differs);
}

bool _differs<V>(V previous, V next) => previous != next;

/// Listens to the source only while someone listens to it.
class _Selected<L extends Listenable, V> with ChangeNotifier implements ValueListenable<V> {
  _Selected(this._source, this._selector, this._changed);

  final L _source;
  final V Function(L source) _selector;
  final bool Function(V previous, V next) _changed;
  late V _value;

  @override
  V get value => hasListeners ? _value : _selector(_source);

  void _onSource() {
    final next = _selector(_source);
    if (!_changed(_value, next)) return;
    _value = next;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _value = _selector(_source);
      _source.addListener(_onSource);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _source.removeListener(_onSource);
  }

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}
```

## Diagnostics

A widget or `State` that shows data overrides `debugFillProperties`, so the DevTools inspector
lists that data next to the widget. The inspector and `toStringDeep` call it; a running app does
not.

```dart
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  super.debugFillProperties(properties);
  properties
    ..add(DiagnosticsProperty<ProductsState>('state', _controller.state))
    ..add(IntProperty('selected', _selected.length))
    ..add(FlagProperty('editing', value: _editing, ifTrue: 'editing'));
}
```
