import 'package:flutter/material.dart';
import 'package:{{package}}/src/_core/widget/common_actions.dart';

class SliverCommonHeader extends SliverAppBar {
  SliverCommonHeader({
    super.leading,
    super.automaticallyImplyLeading = true,
    super.pinned = true,
    super.floating = true,
    super.snap = true,
    super.title,
    super.surfaceTintColor = Colors.transparent,
    List<Widget>? actions,
    super.key,
  }) : super(actions: actions ?? CommonActions());
}

class CommonHeader extends AppBar {
  CommonHeader({
    super.leading,
    super.automaticallyImplyLeading = true,
    super.title,
    super.surfaceTintColor = Colors.transparent,
    List<Widget>? actions,
    super.key,
  }) : super(actions: actions ?? CommonActions());
}
