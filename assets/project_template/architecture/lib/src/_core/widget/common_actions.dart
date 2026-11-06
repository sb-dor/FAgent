import 'dart:collection';

import 'package:flutter/widgets.dart';

/// The actions of an app bar: the ones the screen passes, then the ones every screen shows (add
/// them here: a profile button, sign-out, a developer menu in debug builds).
class CommonActions extends ListBase<Widget> {
  CommonActions([List<Widget>? actions]) : _actions = <Widget>[...?actions];

  final List<Widget> _actions;

  @override
  int get length => _actions.length;

  @override
  set length(int newLength) => _actions.length = newLength;

  @override
  Widget operator [](int index) => _actions[index];

  @override
  void operator []=(int index, Widget value) => _actions[index] = value;
}
