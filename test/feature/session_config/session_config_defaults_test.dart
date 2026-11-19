import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/session_config/controller/session_config_controller.dart';
import 'package:flutter_code_agent/src/feature/session_config/data/session_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSettings implements IAppSettingsRepository {
  _FakeSettings(this.settings);

  AppSettings settings;

  @override
  Stream<AppSettings> watch() => Stream<AppSettings>.value(settings);

  @override
  Future<void> update(AppSettings value) async => settings = value;
}

final class _NoopRepository implements ISessionConfigRepository {
  @override
  Future<void> set(int sessionId, String configId, Object value) async {}

  @override
  Future<void> acknowledgeBypass(int sessionId) async {}
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
    final controller = SessionConfigController(repository: _NoopRepository(), settings: settings);
    addTearDown(controller.dispose);

    controller.saveDefaults('claude', <String, String>{
      'model': 'sonnet',
      'effort': 'high',
      'mode': 'bypassPermissions',
    });
    await Future<void>.delayed(Duration.zero);

    expect(settings.settings.sessionDefaults, <String, Map<String, String>>{
      'claude': <String, String>{'model': 'sonnet', 'effort': 'high'},
      'codex': <String, String>{'model': 'gpt'},
    });
    expect(controller.state, isA<SessionConfig$CompletedState>());
  });
}
