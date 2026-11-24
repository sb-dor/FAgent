import 'package:flutter_code_agent/_core/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/turn_files/models/file_change_kind.dart';

/// The localized word for [kind] (new, modified, deleted, renamed, reverted).
String fileChangeLabel(GeneratedLocalization localization, FileChangeKind kind) => switch (kind) {
  FileChangeKind.added => localization.fileStatusAdded,
  FileChangeKind.modified => localization.fileStatusModified,
  FileChangeKind.deleted => localization.fileStatusDeleted,
  FileChangeKind.renamed => localization.fileStatusRenamed,
  FileChangeKind.clean => localization.fileStatusReverted,
};
