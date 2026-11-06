import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:{{package}}/src/_core/utils/app_zone.dart';
import 'package:{{package}}/src/_core/utils/error_util/error_util.dart';
import 'package:{{package}}/src/_core/widget/app_error.dart';
import 'package:{{package}}/src/initialization/data/initialization.dart';
import 'package:{{package}}/src/initialization/widget/app.dart';

void main() => appZone(() async {
  $initializeApp(
    onSuccess: (dependencies) async => runApp(dependencies.inject(child: const App())),
    onError: (error, stackTrace) {
      runApp(AppError(error: error));
      ErrorUtil.logError(error, stackTrace).ignore();
    },
  ).ignore();
});
