import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';

/// The settings (model, mode, effort, …) each agent reported in chats, kept between runs so the
/// Settings screen can offer them without starting an agent.
abstract interface class IAgentOptionsCatalog {
  /// Agent id → raw `configOptions`: the stored value, then every change. Closes when cancelled.
  Stream<Map<String, List<Map<String, Object?>>>> watch();

  /// Remembers [options] of [agentId] without their `currentValue`, which is the state of one chat
  /// and not of the agent (Settings offers the choices, not the value a chat happens to hold).
  /// Writes only when they differ from the stored ones; an empty list is ignored.
  Future<void> save(String agentId, List<Map<String, Object?>> options);
}

/// Drift-backed [IAgentOptionsCatalog]: one `app_settings` row with the key `agentOptions`.
final class AgentOptionsCatalogImpl implements IAgentOptionsCatalog {
  /// Creates the catalog.
  AgentOptionsCatalogImpl({required this._database});

  static const String _key = 'agentOptions';

  final AppDatabase _database;

  // Saves run one after another so two options of different agents never overwrite each other.
  Future<void> _lastSave = Future<void>.value();

  @override
  Stream<Map<String, List<Map<String, Object?>>>> watch() =>
      (_database.select(_database.appSettingsTable)..where((row) => row.key.equals(_key)))
          .watchSingleOrNull()
          .map((row) => row == null ? const {} : _decode(row.value));

  @override
  Future<void> save(String agentId, List<Map<String, Object?>> options) {
    if (options.isEmpty) return Future<void>.value();
    final run = _lastSave.then((_) => _save(agentId, options));
    _lastSave = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _save(String agentId, List<Map<String, Object?>> options) async {
    final row = await (_database.select(
      _database.appSettingsTable,
    )..where((r) => r.key.equals(_key))).getSingleOrNull();
    final stored = row == null ? <String, List<Map<String, Object?>>>{} : _decode(row.value);
    // Round trip through JSON so the comparison sees what would be stored. The value of the chat is
    // dropped: changing the model or mode in any chat would otherwise rewrite the settings row and
    // wake everything that listens to it.
    final value = (jsonDecode(jsonEncode(options)) as List<Object?>)
        .whereType<Map<String, Object?>>()
        .map((option) => <String, Object?>{...option}..remove('currentValue'))
        .toList();
    if (value.isEmpty || _deepEquals(stored[agentId], value)) return;
    await _database
        .into(_database.appSettingsTable)
        .insertOnConflictUpdate(
          AppSettingsTableCompanion.insert(
            key: _key,
            value: jsonEncode(<String, Object?>{...stored, agentId: value}),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _deepEquals(a[key], b[key]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => _deepEquals(a[i], b[i]));
    }
    return a == b;
  }

  Map<String, List<Map<String, Object?>>> _decode(String value) {
    try {
      final json = jsonDecode(value);
      if (json is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is List)
            key: [
              for (final option in value)
                if (option is Map<String, Object?>) option,
            ],
      };
    } on FormatException {
      return const {};
    }
  }
}
