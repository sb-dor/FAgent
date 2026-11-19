import 'dart:io';

import 'package:flutter_code_agent/src/common/widget/app_error.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/initialization_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppError shows the cause and Retry calls onRetry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      AppError(
        error: const InitializationException(
          'Connect to database',
          FileSystemException('Cannot open', '/p/db.sqlite'),
        ),
        onRetry: () => retries++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('/p/db.sqlite'), findsOneWidget);
    expect(find.textContaining('Connect to database'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('AppError without onRetry has no Retry button', (tester) async {
    await tester.pumpWidget(const AppError());
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
  });
}
