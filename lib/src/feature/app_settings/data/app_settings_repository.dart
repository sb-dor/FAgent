import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';

/// Window-level settings storage.
abstract interface class IAppSettingsRepository {
  /// The current settings, then every change. Closes when cancelled.
  Stream<AppSettings> watch();

  /// Replaces the stored settings.
  Future<void> update(AppSettings settings);
}

/// Drift-backed [IAppSettingsRepository]: one `app_settings` row with the key `app`.
final class AppSettingsRepositoryImpl implements IAppSettingsRepository {
  /// Creates the repository.
  AppSettingsRepositoryImpl({required this._database});

  static const String _key = 'app';

  final AppDatabase _database;

  @override
  Stream<AppSettings> watch() =>
      (_database.select(_database.appSettingsTable)..where((row) => row.key.equals(_key)))
          .watchSingleOrNull()
          .map((row) => row == null ? const AppSettings() : _decode(row.value));

  @override
  Future<void> update(AppSettings settings) => _database
      .into(_database.appSettingsTable)
      .insertOnConflictUpdate(
        AppSettingsTableCompanion.insert(
          key: _key,
          value: jsonEncode(settings.toJson()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  AppSettings _decode(String value) {
    try {
      return AppSettings.fromJson(jsonDecode(value));
    } on FormatException {
      return const AppSettings();
    }
  }
}
