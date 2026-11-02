import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:{{package}}/src/common/utils/app_zone.dart';
import 'package:{{package}}/src/common/utils/error_util.dart';
import 'package:{{package}}/src/common/widget/app_error.dart';
import 'package:{{package}}/src/feature/initialization/data/initialization.dart';
import 'package:{{package}}/src/feature/initialization/widget/app.dart';

void main() => appZone(() async {
  $initializeApp(
    onSuccess: (dependencies) async => runApp(dependencies.inject(child: const App())),
    onError: (error, stackTrace) {
      runApp(AppError(error: error));
      ErrorUtil.logError(error, stackTrace).ignore();
    },
  ).ignore();
});
