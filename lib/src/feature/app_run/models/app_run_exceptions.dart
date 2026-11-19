import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';

/// A run has no project folder to work in: the project is gone from the database.
final class ProjectFolderUnknownException extends ExpectedException {
  /// Creates the exception.
  const ProjectFolderUnknownException();

  @override
  String toString() => 'ProjectFolderUnknownException: the project folder is unknown';
}

/// The running app has no root widget, so there is nothing to take a screenshot of.
final class NoRootWidgetException extends ExpectedException {
  /// Creates the exception.
  const NoRootWidgetException();

  @override
  String toString() => 'NoRootWidgetException: the app returned no root widget';
}

/// The running app could not render a screenshot.
final class ScreenshotFailedException extends ExpectedException {
  /// Creates the exception.
  const ScreenshotFailedException();

  @override
  String toString() => 'ScreenshotFailedException: the app could not render a screenshot';
}
