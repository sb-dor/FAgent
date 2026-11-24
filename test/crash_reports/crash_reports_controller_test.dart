import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/crash_reports/controller/crash_reports_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_crash_reports_repository.dart';

Future<List<CrashReportsState>> _run(
  FakeCrashReportsRepository repository,
  void Function(CrashReportsController controller) act,
) async {
  final controller = CrashReportsController(repository: repository);
  addTearDown(controller.dispose);
  final states = <CrashReportsState>[];
  controller.addListener(() => states.add(controller.state));
  act(controller);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return states;
}

void main() {
  test('load reads the recent errors', () async {
    final repository = FakeCrashReportsRepository(
      entries: <OutboxEntry>[for (var i = 0; i < 3; i++) fakeOutboxEntry(i)],
    );
    final controller = CrashReportsController(repository: repository);
    addTearDown(controller.dispose);

    controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state, isA<CrashReports$IdleState>());
    expect(controller.state.data.recent, hasLength(3));
    expect(controller.state.data.recorded, 3);
  });

  test('saveArchive success goes processing, successful, idle', () async {
    final repository = FakeCrashReportsRepository();

    final states = await _run(repository, (c) => c.saveArchive('/tmp/a.zip'));

    expect(states, hasLength(3));
    expect(states[0], isA<CrashReports$ProcessingState>());
    expect(states[1], isA<CrashReports$SuccessfulState>());
    expect(states[1].data.archiveSaved, isTrue);
    expect(states[2], isA<CrashReports$IdleState>());
    expect(repository.saved, <String>['/tmp/a.zip']);
  });

  test('saveArchive failure goes processing, error, idle', () async {
    final repository = FakeCrashReportsRepository(saveError: Exception('disk full'));

    final states = await _run(repository, (c) => c.saveArchive('/tmp/a.zip'));

    expect(states, hasLength(3));
    expect(states[0], isA<CrashReports$ProcessingState>());
    expect(states[1], isA<CrashReports$ErrorState>());
    expect(states[2], isA<CrashReports$IdleState>());
  });

  test('apply passes the switch and the moment of consent to the repository', () async {
    final repository = FakeCrashReportsRepository();
    final since = DateTime.utc(2026, 11, 22);

    await _run(repository, (c) => c.apply(enabled: true, since: since));

    expect(repository.applied, <(bool, DateTime?)>[(true, since)]);
  });
}
