import 'package:flutter_code_agent/src/common/acp/permission_broker.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionStatus', () {
    test('follows the state table from docs/M1_PLAN.md', () {
      const allowed = <(SessionStatus, SessionStatus)>[
        (SessionStatus.cold, SessionStatus.starting),
        (SessionStatus.starting, SessionStatus.loading),
        (SessionStatus.starting, SessionStatus.creating),
        (SessionStatus.loading, SessionStatus.idle),
        (SessionStatus.loading, SessionStatus.setupFailed),
        (SessionStatus.creating, SessionStatus.needsAuth),
        (SessionStatus.setupFailed, SessionStatus.loading),
        (SessionStatus.idle, SessionStatus.running),
        (SessionStatus.running, SessionStatus.awaitingPermission),
        (SessionStatus.awaitingPermission, SessionStatus.running),
        (SessionStatus.running, SessionStatus.cancelling),
        (SessionStatus.cancelling, SessionStatus.idle),
        (SessionStatus.running, SessionStatus.needsAuth),
        (SessionStatus.needsAuth, SessionStatus.cold),
        (SessionStatus.error, SessionStatus.starting),
        (SessionStatus.running, SessionStatus.error),
        (SessionStatus.idle, SessionStatus.disposed),
      ];
      for (final (from, to) in allowed) {
        expect(from.canMoveTo(to), isTrue, reason: '${from.name} → ${to.name}');
      }
    });

    test('rejects transitions outside the table', () {
      const forbidden = <(SessionStatus, SessionStatus)>[
        (SessionStatus.cold, SessionStatus.running),
        (SessionStatus.idle, SessionStatus.loading),
        (SessionStatus.cancelling, SessionStatus.running),
        (SessionStatus.error, SessionStatus.loading),
        (SessionStatus.setupFailed, SessionStatus.idle),
        (SessionStatus.disposed, SessionStatus.error),
        (SessionStatus.disposed, SessionStatus.starting),
      ];
      for (final (from, to) in forbidden) {
        expect(from.canMoveTo(to), isFalse, reason: '${from.name} → ${to.name}');
      }
    });

    test('busy states are the ones closing the app interrupts', () {
      expect(SessionStatus.values.where((s) => s.isBusy), <SessionStatus>[
        SessionStatus.starting,
        SessionStatus.loading,
        SessionStatus.creating,
        SessionStatus.running,
        SessionStatus.awaitingPermission,
        SessionStatus.cancelling,
      ]);
    });
  });

  group('PermissionBroker', () {
    test('the first decision wins; late ones are ignored', () async {
      final broker = PermissionBroker();
      final decision = broker.wait('1', sessionId: 7);

      expect(broker.resolve('1', const PermissionSelected('allow')), isTrue);
      expect(broker.resolve('1', const PermissionCancelled('late')), isFalse);
      expect(await decision, isA<PermissionSelected>());
    });

    test('cancelSession only touches that session', () async {
      final broker = PermissionBroker();
      final a = broker.wait('1', sessionId: 1);
      final b = broker.wait('2', sessionId: 2);

      broker.cancelSession(1, 'stop');

      expect(await a, isA<PermissionCancelled>());
      expect(broker.pendingFor(2), <String>['2']);
      broker.cancelAll('app closed');
      expect(await b, isA<PermissionCancelled>());
    });

    test('rejects a duplicate request id', () {
      final broker = PermissionBroker()..wait('1', sessionId: 1);
      expect(() => broker.wait('1', sessionId: 1), throwsStateError);
    });
  });
}
