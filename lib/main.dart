import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/utils/app_zone.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/common/widget/app_error.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/initialization.dart';
import 'package:flutter_code_agent/src/feature/initialization/widget/app.dart';

void main() => appZone(() async {
  $initializeApp(
    onSuccess: (dependencies) async =>
        runApp(dependencies.inject(child: const AppSettingsConfigWidget(child: App()))),
    onError: (error, stackTrace) {
      runApp(AppError(error: error));
      ErrorUtil.logError(error, stackTrace).ignore();
    },
  ).ignore();
});
