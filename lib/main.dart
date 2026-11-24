import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/_core/utils/app_zone.dart';
import 'package:flutter_code_agent/_core/widget/app_error.dart';
import 'package:flutter_code_agent/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/initialization/data/initialization.dart';
import 'package:flutter_code_agent/initialization/widget/app.dart';

void main() => appZone(() async => _start());

void _start() {
  $initializeApp(
    onSuccess: (dependencies) async =>
        runApp(dependencies.inject(child: const AppSettingsConfigWidget(child: App()))),
    onError: (error, stackTrace) {
      runApp(AppError(error: error, onRetry: _start));
    },
  ).ignore();
}
