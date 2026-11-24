/// The chats whose message queue still holds messages, app-wide (the chat feature keeps the
/// queues; quitting asks first while any of them is not empty).
abstract interface class IQueuedChats {
  /// `sessions.id` of every chat with at least one queued message.
  Set<int> get sessionIds;

  /// Forgets the queued messages of chat [sessionId]: the chat was deleted.
  void discard(int sessionId);

  /// Stops every queue: nothing more is sent (the app is closing).
  void dispose();
}
