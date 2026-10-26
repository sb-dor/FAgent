import 'package:meta/meta.dart';

/// An agent setting (ACP `configOptions`): mode, model, effort, …
@immutable
sealed class ConfigOption {
  const ConfigOption({required this.id, required this.name, this.description});

  /// Parses raw `configOptions`; entries without an id are skipped.
  static List<ConfigOption> parseAll(List<Map<String, Object?>> raw) => <ConfigOption>[
    for (final option in raw)
      if (option['id'] case final String id) _parse(id, option),
  ];

  static ConfigOption _parse(String id, Map<String, Object?> option) {
    final name = option['name'] is String ? option['name']! as String : id;
    final description = option['description'] is String ? option['description']! as String : null;
    return switch (option['type']) {
      'select' => SelectConfigOption(
        id: id,
        name: name,
        description: description,
        category: option['category'] is String ? option['category']! as String : null,
        currentValue: '${option['currentValue'] ?? ''}',
        choices: <ConfigChoice>[
          for (final choice in (option['options'] as List<Object?>?) ?? const <Object?>[])
            if (choice case {'value': final String value})
              ConfigChoice(
                value: value,
                name: (choice as Map)['name'] is String ? choice['name']! as String : value,
                description: choice['description'] is String
                    ? choice['description']! as String
                    : null,
              ),
        ],
      ),
      'boolean' => BooleanConfigOption(
        id: id,
        name: name,
        description: description,
        currentValue: option['currentValue'] == true,
      ),
      final Object? type => UnknownConfigOption(
        id: id,
        name: name,
        description: description,
        type: '$type',
      ),
    };
  }

  /// `configId` to send back.
  final String id;

  /// Label.
  final String name;

  /// Tooltip.
  final String? description;
}

/// One value of a [SelectConfigOption].
@immutable
final class ConfigChoice {
  /// Creates a choice.
  const ConfigChoice({required this.value, required this.name, this.description});

  /// Value to send.
  final String value;

  /// Label.
  final String name;

  /// Tooltip.
  final String? description;
}

/// A setting with a fixed list of values.
final class SelectConfigOption extends ConfigOption {
  /// Creates a select option.
  const SelectConfigOption({
    required super.id,
    required super.name,
    required this.currentValue,
    required this.choices,
    super.description,
    this.category,
  });

  /// `mode`, `model`, … when the agent says.
  final String? category;

  /// Selected value (may be missing from [choices], e.g. a model alias).
  final String currentValue;

  /// Values to choose from.
  final List<ConfigChoice> choices;

  /// Label of the selected value.
  String get currentName =>
      choices.where((c) => c.value == currentValue).firstOrNull?.name ?? currentValue;

  /// Whether this is the permission mode.
  bool get isMode => id == 'mode' || category == 'mode';
}

/// An on/off setting.
final class BooleanConfigOption extends ConfigOption {
  /// Creates a boolean option.
  const BooleanConfigOption({
    required super.id,
    required super.name,
    required this.currentValue,
    super.description,
  });

  /// Whether it is on.
  final bool currentValue;
}

/// A setting type the app does not know: shown read-only.
final class UnknownConfigOption extends ConfigOption {
  /// Creates an unknown option.
  const UnknownConfigOption({
    required super.id,
    required super.name,
    required this.type,
    super.description,
  });

  /// The agent's type name.
  final String type;
}

/// Permission mode that accepts every permission; needs explicit consent per
/// chat.
const String bypassPermissionMode = 'bypassPermissions';

/// Permission modes that act without asking (shown with a warning colour).
const Set<String> unattendedPermissionModes = <String>{'acceptEdits', 'auto', bypassPermissionMode};

/// The permission mode among [options], if the agent has one.
SelectConfigOption? permissionModeOf(List<ConfigOption> options) =>
    options.whereType<SelectConfigOption>().where((o) => o.isMode).firstOrNull;
