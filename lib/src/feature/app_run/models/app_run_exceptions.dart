import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';

/// A run has no project folder to work in: the project is gone from the database.
final class ProjectFolderUnknownException extends ExpectedException {
  /// Creates the exception.
  const ProjectFolderUnknownException();

  @override
  String toString() => 'The project folder is unknown.';
}

/// The running app has no root widget, so there is nothing to take a screenshot of.
final class NoRootWidgetException extends ExpectedException {
  /// Creates the exception.
  const NoRootWidgetException();

  @override
  String toString() => 'The app returned no root widget.';
}

/// The running app could not render a screenshot.
final class ScreenshotFailedException extends ExpectedException {
  /// Creates the exception.
  const ScreenshotFailedException();

  @override
  String toString() => 'The app could not render a screenshot.';
}

/// A monorepo has no app to run: there is no Flutter app under `apps/` (or the apps are not known
/// yet) and no selected configuration names a folder with its `cwd`. `flutter run` would run in the
/// workspace root, which has no `lib/main.dart`.
final class RunNoAppException extends ExpectedException {
  /// Creates the exception.
  const RunNoAppException();

  @override
  String toString() => 'The monorepo has no Flutter app to run.';
}
