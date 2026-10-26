import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// {@template app_error}
/// Shown instead of the app when initialization fails.
/// {@endtemplate}
class AppError extends StatelessWidget {
  /// {@macro app_error}
  const AppError({this.error, super.key});

  /// Error
  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,
    theme: View.of(context).platformDispatcher.platformBrightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(error?.toString() ?? Localization.of(context).somethingWentWrong),
          ),
        ),
      ),
    ),
  );
}
