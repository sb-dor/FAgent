import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';

/// A project's `.claude/settings.local.json` exists but cannot be used: it is not JSON, or its
/// top level is not an object.
final class PermissionRulesUnreadableException extends ExpectedException {
  /// Creates the exception for the file at [path].
  const PermissionRulesUnreadableException(this.path);

  /// The settings file that could not be read.
  final String path;

  @override
  String toString() => 'PermissionRulesUnreadableException: cannot read $path';
}
