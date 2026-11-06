import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:{{package}}/src/_core/model/virtual_key_codes.dart';
import 'package:{{package}}/src/_core/utils/platform/keyboard_observer_interface.dart';
import 'package:meta/meta.dart';
import 'package:win32/win32.dart' show GetKeyState; // GetAsyncKeyState, GetKeyboardState

IKeyboardObserver $getKeyboardObserver$Windows() => _KeyboardObserver$Windows();

@sealed
class _KeyboardObserver$Windows with _IsKeyPressed, ChangeNotifier implements IKeyboardObserver {
  _KeyboardObserver$Windows() {
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      notifyListeners();
    }
    return false;
  }

  @override
  bool get isControlPressed => isKeyPressed(.LCONTROL) || isKeyPressed(.RCONTROL);

  @override
  bool get isShiftPressed => isKeyPressed(.LSHIFT) || isKeyPressed(.RSHIFT);

  @override
  bool get isAltPressed => isKeyPressed(.LMENU) || isKeyPressed(.RMENU);

  @override
  bool get isMetaPressed => isKeyPressed(.LWIN) || isKeyPressed(.RWIN);

  @override
  bool get enterPressed => isKeyPressed(.RETURN);

  @override
  int? get numberPressed {
    if (isKeyPressed(.NUMPAD0)) {
      return 0;
    } else if (isKeyPressed(.NUMPAD1)) {
      return 1;
    } else if (isKeyPressed(.NUMPAD2)) {
      return 2;
    } else if (isKeyPressed(.NUMPAD3)) {
      return 3;
    } else if (isKeyPressed(.NUMPAD4)) {
      return 4;
    } else if (isKeyPressed(.NUMPAD5)) {
      return 5;
    } else if (isKeyPressed(.NUMPAD6)) {
      return 6;
    } else if (isKeyPressed(.NUMPAD7)) {
      return 7;
    } else if (isKeyPressed(.NUMPAD8)) {
      return 8;
    } else if (isKeyPressed(.NUMPAD9)) {
      return 9;
    }
    return null;
  }

  @override
  bool get backspacePressed => isKeyPressed(.BACK);
}

mixin _IsKeyPressed {
  /// Returns true if the given [VK] is pressed.
  bool isKeyPressed(VK key) {
    final state = GetKeyState(key.code);
    return state != 0 && state != 1;
  }
}
