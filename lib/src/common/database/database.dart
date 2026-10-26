import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// {@template database}
/// The drift-managed database configuration
/// {@endtemplate}
@DriftDatabase(tables: [ProjectsTable])
class AppDatabase extends _$AppDatabase {
  /// {@macro database}
  AppDatabase(super.e);

  /// {@macro database}
  ///
  /// Stored in Application Support: drift's default on desktop is the user's Documents folder.
  AppDatabase.defaults({required String name})
    : super(
        driftDatabase(
          name: name,
          native: const DriftNativeOptions(
            shareAcrossIsolates: true,
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  @override
  int get schemaVersion => 1;
}
