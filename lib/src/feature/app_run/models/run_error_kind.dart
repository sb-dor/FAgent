/// What a [RunError] is, so the app can show its title in the user's language while the English
/// title stays for the agent.
enum RunErrorKind {
  /// The project folder does not exist.
  projectNotFound,

  /// No `flutter` executable was found.
  flutterNotFound,

  /// The app did not build or `flutter run` did not start.
  buildFailed,

  /// The running app ended without being stopped.
  appExited,

  /// A compilation error of the project's code.
  compilation,

  /// An exception nobody caught.
  unhandledException,

  /// A layout overflowed.
  layoutOverflow,

  /// An exception the framework reported.
  exception,

  /// DevTools could not be opened.
  devToolsFailed,

  /// Anything else; its title comes from the app or the framework and is shown as it is.
  other,
}
