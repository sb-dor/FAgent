import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat_search/models/chat_search_result.dart';

/// Search over the titles of all chats.
abstract interface class IChatSearchRepository {
  /// Chats whose title contains [query], ignoring case, the most recently changed first; at most
  /// [limit]. [query] is plain text: `%`, `_` and `\` match themselves. A blank [query] lists the
  /// latest chats.
  Future<List<ChatSearchResult>> search(String query, {int limit = 20});
}

/// Drift-backed [IChatSearchRepository].
///
/// The match is made in Dart, not with SQL `LIKE`: SQLite folds the case of ASCII letters only, so
/// it would not find «бронир» in «БРОНИРОВАНИЕ», and `LIKE` needs its wildcards escaped. A local
/// app has hundreds of chats, so reading them all is cheap.
final class ChatSearchRepositoryImpl implements IChatSearchRepository {
  /// Creates the repository.
  ChatSearchRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<List<ChatSearchResult>> search(String query, {int limit = 20}) async {
    final needle = query.trim().toLowerCase();
    final sessions = _database.sessionsTable;
    final projects = _database.projectsTable;
    final rows =
        await (_database.select(sessions).join(<Join<HasResultSet, dynamic>>[
              innerJoin(projects, projects.id.equalsExp(sessions.projectId)),
            ])..orderBy(<OrderingTerm>[
              OrderingTerm.desc(sessions.updatedAt),
              OrderingTerm.desc(sessions.id),
            ]))
            .get();
    final results = <ChatSearchResult>[];
    for (final row in rows) {
      final session = row.readTable(sessions);
      if (needle.isNotEmpty && !session.title.toLowerCase().contains(needle)) continue;
      results.add(
        ChatSearchResult(
          sessionId: session.id,
          projectId: session.projectId,
          title: session.title,
          projectName: row.readTable(projects).name,
          updatedAt: session.updatedAt,
        ),
      );
      if (results.length == limit) break;
    }
    return results;
  }
}
