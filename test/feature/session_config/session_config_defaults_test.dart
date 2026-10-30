import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/session_config/controller/session_config_controller.dart';
import 'package:flutter_code_agent/src/feature/session_config/data/session_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

final class _FakeSettings implements IAppSettingsRepository {
  _FakeSettings(this.settings);

  AppSettings settings;

  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(settings);

  @override
  Future<void> update(AppSettings value) async => settings = value;
}

final class _RecordingRepository implements ISessionConfigRepository {
  final List<(String, Map<String, String>)> saved = <(String, Map<String, String>)>[];

  @override
  Future<void> set(int sessionId, String configId, Object value) async {}

  @override
  Future<void> acknowledgeBypass(int sessionId) async {}

  @override
  Future<void> saveDefaults(String agentId, Map<String, String> values) async =>
      saved.add((agentId, values));
}

void main() {
  test('make default saves model, effort and mode but not bypass', () async {
    final settings = _FakeSettings(
      const AppSettings(
        sessionDefaults: <String, Map<String, String>>{
          'claude': <String, String>{'model': 'haiku', 'mode': 'plan'},
          'codex': <String, String>{'model': 'gpt'},
        },
      ),
    );
    final repository = SessionConfigRepositoryImpl(
      hub: testDependencies().agentHub,
      settings: settings,
    );

    await repository.saveDefaults('claude', <String, String>{
      'model': 'sonnet',
      'effort': 'high',
      'mode': 'bypassPermissions',
    });

    expect(settings.settings.sessionDefaults, <String, Map<String, String>>{
      'claude': <String, String>{'model': 'sonnet', 'effort': 'high'},
      'codex': <String, String>{'model': 'gpt'},
    });
  });

  test('the controller passes the defaults on to the repository', () async {
    final repository = _RecordingRepository();
    final controller = SessionConfigController(repository: repository);
    addTearDown(controller.dispose);

    controller.saveDefaults('claude', <String, String>{'model': 'opus'});
    await Future<void>.delayed(Duration.zero);

    expect(repository.saved.map((e) => e.$1), <String>['claude']);
    expect(repository.saved.single.$2, <String, String>{'model': 'opus'});
    expect(controller.state, isA<SessionConfig$CompletedState>());
  });
}
