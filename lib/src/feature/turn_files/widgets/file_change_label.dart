import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';

/// The localized word for [kind] (new, modified, deleted, renamed, reverted).
String fileChangeLabel(GeneratedLocalization localization, FileChangeKind kind) => switch (kind) {
  FileChangeKind.added => localization.fileStatusAdded,
  FileChangeKind.modified => localization.fileStatusModified,
  FileChangeKind.deleted => localization.fileStatusDeleted,
  FileChangeKind.renamed => localization.fileStatusRenamed,
  FileChangeKind.clean => localization.fileStatusReverted,
};
