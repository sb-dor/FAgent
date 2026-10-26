import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Locale locale) => MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      Localization.delegate,
    ],
    supportedLocales: Localization.supportedLocales,
    home: const WorkspaceWidget(),
  );

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
  });

  testWidgets('Workspace shows the three empty panes', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('Open a project and start a chat with an agent'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('Workspace is localized to Russian', (tester) async {
    await tester.pumpWidget(app(const Locale('ru')));
    await tester.pumpAndSettle();

    expect(find.text('Проекты'), findsOneWidget);
    expect(find.text('Запуск'), findsOneWidget);
  });
}
