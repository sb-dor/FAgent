import 'package:flutter_code_agent/project_trust/data/project_trust_repository.dart';

/// [IProjectTrustRepository] for tests: no settings files; the trusted ids go into [trusted].
final class MemoryProjectTrustRepository implements IProjectTrustRepository {
  /// The ids [trust] was called with.
  final List<int> trusted = <int>[];

  @override
  Future<List<String>> agentSettingsFiles(String projectPath) async => const <String>[];

  @override
  Future<void> trust(int projectId) async => trusted.add(projectId);
}
