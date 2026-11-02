/// The agent has no settings file or folder yet, so there is nothing to open.
final class AgentSettingsMissingException implements Exception {
  /// Creates the exception for the agent [agentId].
  const AgentSettingsMissingException(this.agentId);

  /// The agent whose settings are missing.
  final String agentId;

  @override
  String toString() => 'AgentSettingsMissingException: no settings for $agentId';
}
