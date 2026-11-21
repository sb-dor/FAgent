import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class ScrollWithMouseBehavior extends MaterialScrollBehavior {
  const ScrollWithMouseBehavior();

  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  };
}
