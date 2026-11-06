import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:{{package}}/src/_core/localization/localization.dart';
import 'package:{{package}}/src/home/widgets/home_screen.dart';
import 'package:{{package}}/src/initialization/models/dependencies.dart';
import 'package:{{package}}/src/initialization/widget/app.dart';

/// The app does not read the preferences yet, so the test needs no platform storage.
class _FakePreferences implements SharedPreferencesWithCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the app shows its title', (tester) async {
    final dependencies = Dependencies()..sharedPreferences = _FakePreferences();

    await tester.pumpWidget(dependencies.inject(child: const App()));
    await tester.pumpAndSettle();

    final title = Localization.of(tester.element(find.byType(HomeScreen))).appTitle;
    expect(find.text(title), findsOneWidget);
  });
}
