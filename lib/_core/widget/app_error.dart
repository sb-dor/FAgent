import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_code_agent/_core/localization/error_text.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

/// {@template app_error}
/// Shown instead of the app when initialization fails.
/// {@endtemplate}
class AppError extends StatelessWidget {
  /// {@macro app_error}
  const AppError({this.error, this.onRetry, super.key});

  /// Error
  final Object? error;

  /// Starts the app again; no Retry button without it.
  final VoidCallback? onRetry;

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
      builder: (context) {
        final lcl = Localization.of(context);
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SelectableText(error == null ? lcl.somethingWentWrong : errorText(lcl, error)),
                  if (onRetry case final retry?) ...<Widget>[
                    const SizedBox(height: 16),
                    FilledButton(onPressed: retry, child: Text(lcl.retry)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
