import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:{{package}}/src/_core/utils/platform/keyboard_observer_interface.dart';
import 'package:meta/meta.dart';

IKeyboardObserver $getKeyboardObserver() => _KeyboardObserver$JS();

@sealed
class _KeyboardObserver$JS with _IsKeyPressed$JS, ChangeNotifier implements IKeyboardObserver {
  _KeyboardObserver$JS() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      notifyListeners();
    }
    return false;
  }

  @override
  bool get isControlPressed =>
      isKeyPressed(LogicalKeyboardKey.controlLeft) || isKeyPressed(LogicalKeyboardKey.controlRight);

  @override
  bool get isShiftPressed =>
      isKeyPressed(LogicalKeyboardKey.shiftLeft) || isKeyPressed(LogicalKeyboardKey.shiftRight);

  @override
  bool get isAltPressed =>
      isKeyPressed(LogicalKeyboardKey.altLeft) || isKeyPressed(LogicalKeyboardKey.altRight);

  @override
  bool get isMetaPressed =>
      isKeyPressed(LogicalKeyboardKey.metaLeft) || isKeyPressed(LogicalKeyboardKey.metaRight);

  @override
  bool get enterPressed => isKeyPressed(LogicalKeyboardKey.enter);

  @override
  int? get numberPressed {
    if (isKeyPressed(LogicalKeyboardKey.numpad0) || isKeyPressed(LogicalKeyboardKey.digit0)) {
      return 0;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad1) ||
        isKeyPressed(LogicalKeyboardKey.digit1)) {
      return 1;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad2) ||
        isKeyPressed(LogicalKeyboardKey.digit2)) {
      return 2;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad3) ||
        isKeyPressed(LogicalKeyboardKey.digit3)) {
      return 3;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad4) ||
        isKeyPressed(LogicalKeyboardKey.digit4)) {
      return 4;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad5) ||
        isKeyPressed(LogicalKeyboardKey.digit5)) {
      return 5;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad6) ||
        isKeyPressed(LogicalKeyboardKey.digit6)) {
      return 6;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad7) ||
        isKeyPressed(LogicalKeyboardKey.digit7)) {
      return 7;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad8) ||
        isKeyPressed(LogicalKeyboardKey.digit8)) {
      return 8;
    } else if (isKeyPressed(LogicalKeyboardKey.numpad9) ||
        isKeyPressed(LogicalKeyboardKey.digit9)) {
      return 9;
    }
    return null;
  }

  @override
  bool get backspacePressed => isKeyPressed(LogicalKeyboardKey.backspace);
}

mixin _IsKeyPressed$JS {
  /// Returns true if the given [KeyboardKey] is pressed.
  bool isKeyPressed(LogicalKeyboardKey key) =>
      HardwareKeyboard.instance.logicalKeysPressed.contains(key);
}
