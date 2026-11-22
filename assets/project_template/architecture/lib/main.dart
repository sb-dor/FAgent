import 'package:flutter/widgets.dart';
import 'package:{{package}}/_core/telemetry/app_zone.dart';
import 'package:{{package}}/_core/widget/app_error.dart';
import 'package:{{package}}/initialization/data/initialization.dart';
import 'package:{{package}}/initialization/widget/app.dart';

void main() => appZone(() async {
  $initializeApp(
    onSuccess: (dependencies) async => runApp(dependencies.inject(child: const App())),
    // The startup already reported the error.
    onError: (error, stackTrace) => runApp(AppError(error: error)),
  ).ignore();
});
