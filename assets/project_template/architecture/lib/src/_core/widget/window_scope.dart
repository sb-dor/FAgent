import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:{{package}}/src/_core/localization/localization.dart';
import 'package:platform_info/platform_info.dart';
import 'package:window_manager/window_manager.dart';

/// {@template window_scope}
/// WindowScope widget.
/// {@endtemplate}
class WindowScope extends StatefulWidget {
  /// {@macro window_scope}
  const WindowScope({required this.title, required this.child, super.key});

  /// Title of the window.
  final String title;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<WindowScope> createState() => _WindowScopeState();
}

class _WindowScopeState extends State<WindowScope> {
  @override
  Widget build(BuildContext context) => kIsWeb || io.Platform.isAndroid || io.Platform.isIOS
      ? widget.child
      : Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _WindowTitle(),
            Expanded(child: widget.child),
          ],
        );
}

class _WindowTitle extends StatefulWidget {
  const _WindowTitle();

  @override
  State<_WindowTitle> createState() => _WindowTitleState();
}

class _WindowTitleState extends State<_WindowTitle> {
  /// The app's window (window_manager 0.6 and later: one [Window] per native window).
  final Window? _window = WindowManager.instance.getCurrent();
  late final ValueNotifier<bool> _isFullScreen = ValueNotifier(_window?.isFullScreen ?? false);
  late final ValueNotifier<bool> _isAlwaysOnTop = ValueNotifier(_window?.isAlwaysOnTop ?? false);
  ListenerId? _listener;

  @override
  void initState() {
    super.initState();
    _listener = _window?.addListener(_onWindowEvent);
  }

  @override
  void dispose() {
    if (_listener case final ListenerId listener) _window?.removeListener(listener);
    _isFullScreen.dispose();
    _isAlwaysOnTop.dispose();
    super.dispose();
  }

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowEnteredFullScreenEvent():
        _isFullScreen.value = true;
      case WindowExitedFullScreenEvent():
        _isFullScreen.value = false;
      case WindowFocusedEvent():
        if (mounted) setState(() {});
      default:
        break;
    }
  }

  // ignore: avoid_positional_boolean_parameters
  void setAlwaysOnTop(bool value) {
    final window = _window;
    if (window == null) return;
    window.isAlwaysOnTop = value;
    _isAlwaysOnTop.value = window.isAlwaysOnTop;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: DragToMoveArea(
      child: Material(
        color: Theme.of(context).primaryColor,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Builder(
              builder: (context) {
                final size = MediaQuery.of(context).size;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  left: size.width < 800 ? 8 : 78,
                  right: 78,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: Text(
                        context.findAncestorWidgetOfExactType<WindowScope>()?.title ??
                            Localization.of(context).app,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(height: 1),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (platform.windows)
              _WindowButtons$Windows(
                window: _window,
                isFullScreen: _isFullScreen,
                isAlwaysOnTop: _isAlwaysOnTop,
                setAlwaysOnTop: setAlwaysOnTop,
              ),
          ],
        ),
      ),
    ),
  );
}

class _WindowButtons$Windows extends StatelessWidget {
  const _WindowButtons$Windows({
    required this.window,
    required this.isFullScreen,
    required this.isAlwaysOnTop,
    required this.setAlwaysOnTop,
  });

  final Window? window;
  final ValueListenable<bool> isFullScreen;
  final ValueListenable<bool> isAlwaysOnTop;
  final ValueChanged<bool> setAlwaysOnTop;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Is always on top
        ValueListenableBuilder<bool>(
          valueListenable: isAlwaysOnTop,
          builder: (context, isAlwaysOnTop, _) => _WindowButton(
            onPressed: () => setAlwaysOnTop(!isAlwaysOnTop),
            icon: isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
          ),
        ),

        // Minimize
        _WindowButton(onPressed: () => window?.minimize(), icon: Icons.minimize),

        // Set full screen
        ValueListenableBuilder<bool>(
          valueListenable: isFullScreen,
          builder: (context, isFullScreen, _) => _WindowButton(
            onPressed: () => window?.isFullScreen = !isFullScreen,
            icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
        ),

        // Close: asks the window's close listeners first.
        _WindowButton(onPressed: () => window?.close(), icon: Icons.close),
        const SizedBox(width: 4),
      ],
    ),
  );
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.onPressed, required this.icon});

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 16,
      alignment: Alignment.center,
      padding: EdgeInsets.zero,
      splashRadius: 12,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    ),
  );
}
