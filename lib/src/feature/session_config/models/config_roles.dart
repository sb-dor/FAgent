import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';

/// The model option among [options], if the agent has one (id or category `model`).
SelectConfigOption? modelOption(List<ConfigOption> options) => options
    .whereType<SelectConfigOption>()
    .where((o) => o.id == 'model' || o.category == 'model')
    .firstOrNull;

/// The effort option among [options], if the agent has one (id `effort` or category
/// `thought_level`).
SelectConfigOption? effortOption(List<ConfigOption> options) => options
    .whereType<SelectConfigOption>()
    .where((o) => o.id == 'effort' || o.category == 'thought_level')
    .firstOrNull;

/// Modes Shift+Tab goes through, in the agent's order: everything except
/// `bypassPermissions`, which needs a confirmation.
List<String> cycleModes(SelectConfigOption mode) => <String>[
  for (final choice in mode.choices)
    if (choice.value != bypassPermissionMode) choice.value,
];

/// The mode after the current one in [cycleModes], wrapping around; `null` when there is no
/// mode to switch to. From a mode outside the cycle (bypass) it goes to the first one.
String? nextCycleMode(SelectConfigOption mode) {
  final modes = cycleModes(mode);
  if (modes.isEmpty) return null;
  final next = modes[(modes.indexOf(mode.currentValue) + 1) % modes.length];
  return next == mode.currentValue ? null : next;
}

/// The settings "make default for new chats" stores: model, effort and mode, never bypass.
Map<String, String> defaultsOf(List<ConfigOption> options) {
  final mode = permissionModeOf(options);
  final model = modelOption(options);
  final effort = effortOption(options);
  return <String, String>{
    if (mode != null && mode.currentValue != bypassPermissionMode) mode.id: mode.currentValue,
    if (model != null) model.id: model.currentValue,
    if (effort != null) effort.id: effort.currentValue,
  };
}
