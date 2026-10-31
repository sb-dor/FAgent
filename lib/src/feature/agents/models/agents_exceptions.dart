/// The agent is a preview: its real support arrives with [milestone].
final class AgentPreviewException implements Exception {
  /// Creates the exception for the milestone that ships the feature.
  const AgentPreviewException(this.milestone);

  /// The roadmap milestone, for example `M5`.
  final String milestone;

  @override
  String toString() => 'AgentPreviewException: available with $milestone';
}

/// The agent has no settings file or folder yet, so there is nothing to open.
final class AgentSettingsMissingException implements Exception {
  /// Creates the exception for the agent [agentId].
  const AgentSettingsMissingException(this.agentId);

  /// The agent whose settings are missing.
  final String agentId;

  @override
  String toString() => 'AgentSettingsMissingException: no settings for $agentId';
}
