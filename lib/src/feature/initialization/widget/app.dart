import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// {@template app}
/// App widgets.
/// {@endtemplate}
class App extends StatefulWidget {
  /// {@macro app}
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final Key builderKey = GlobalKey(); // Disable recreate widgets tree

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => Localization.of(context).appTitle,
    debugShowCheckedModeBanner: false,

    // Localizations
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,

    // Theme
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),

    home: const WorkspaceWidget(),
    builder: (context, child) => MediaQuery(
      key: builderKey,
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

ThemeData _theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0175C2), brightness: brightness),
);
