import 'package:{{package}}/src/_core/utils/platform/keyboard_observer_interface.dart';
import 'package:{{package}}/src/_core/utils/platform/keyboard_observer_vm.dart'
    if (dart.library.js_interop) 'package:{{package}}/src/_core/utils/platform/keyboard_observer_js.dart';

sealed class KeyboardObserver {
  KeyboardObserver._();
  static IKeyboardObserver? _keyboardObserver;
  static IKeyboardObserver get instance => _keyboardObserver ??= $getKeyboardObserver();
  static IKeyboardObserver get I => instance;
}
