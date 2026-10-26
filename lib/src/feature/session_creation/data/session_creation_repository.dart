import 'package:flutter_code_agent/src/common/database/database.dart';

/// Creates chats. The agent session is created later, by the first prompt.
abstract interface class ISessionCreationRepository {
  /// Adds an empty chat for [agentId] to [projectId] and returns its id.
  Future<int> create({required int projectId, required String agentId});
}

/// Drift-backed [ISessionCreationRepository].
final class SessionCreationRepositoryImpl implements ISessionCreationRepository {
  /// Creates the repository.
  SessionCreationRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<int> create({required int projectId, required String agentId}) => _database
      .into(_database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: agentId));
}
