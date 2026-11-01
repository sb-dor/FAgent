import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/widgets/hub_notices_listener.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// A server whose start failed because its port was taken.
final class _FailedAppMcpServer implements IAppMcpServer {
  @override
  Future<void> start() async {}

  @override
  Uri? get url => null;

  @override
  int get toolCount => 0;

  @override
  Object? get startError => const SocketException('Address already in use');

  @override
  Future<void> close() async {}
}

void main() {
  group('HubNoticesListener', () {
    testWidgets('says the Flutter tools are unavailable when the MCP server did not start', (
      tester,
    ) async {
      final dependencies = testDependencies(appMcpServer: _FailedAppMcpServer());

      await tester.pumpWidget(
        testApp(const HubNoticesListener(child: SizedBox()), dependencies: dependencies),
      );
      await tester.pump();

      expect(find.textContaining('Flutter tools are unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await dependencies.database.close();
    });

    testWidgets('says nothing while the MCP server has not failed', (tester) async {
      final dependencies = testDependencies();

      await tester.pumpWidget(
        testApp(const HubNoticesListener(child: SizedBox()), dependencies: dependencies),
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await dependencies.database.close();
    });
  });
}
