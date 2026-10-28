import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/chat_search/data/chat_search_repository.dart';
import 'package:flutter_code_agent/src/feature/chat_search/models/chat_search_result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_search_controller.freezed.dart';

@freezed
sealed class ChatSearchState with _$ChatSearchState {
  const factory ChatSearchState.initial() = ChatSearch$InitialState;

  const factory ChatSearchState.inProgress() = ChatSearch$InProgressState;

  const factory ChatSearchState.error({Object? error}) = ChatSearch$ErrorState;

  /// The chats found for [query].
  const factory ChatSearchState.completed({
    required String query,
    required List<ChatSearchResult> results,
  }) = ChatSearch$CompletedState;
}

/// Runs the searches of the chat search dialog.
///
/// A new query matters more than an old one, so no query is dropped (not `Droppable`); the queries
/// run one after another, and the answer to any but the latest is thrown away.
final class ChatSearchController extends StateController<ChatSearchState>
    with SequentialControllerHandler {
  ChatSearchController({
    required this._repository,
    super.initialState = const ChatSearchState.initial(),
  });

  final IChatSearchRepository _repository;
  int _requests = 0;

  /// Searches the chats for [query]; a blank [query] lists the latest chats.
  void search(String query) {
    final request = ++_requests;
    handle(
      () async {
        // A newer query was made while this one waited its turn.
        if (request != _requests) return;
        setState(const ChatSearchState.inProgress());
        final results = await _repository.search(query);
        if (request != _requests) return;
        setState(ChatSearchState.completed(query: query, results: results));
      },
      error: (error, stackTrace) async {
        if (request == _requests) setState(ChatSearchState.error(error: error));
      },
    );
  }
}
