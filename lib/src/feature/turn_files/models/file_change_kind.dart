/// What happened to a file, read from a git status code.
enum FileChangeKind {
  /// New (untracked or added).
  added,

  /// Content changed.
  modified,

  /// Removed.
  deleted,

  /// Moved to this path.
  renamed,

  /// Back to what git has: the change was reverted.
  clean,
}

/// The [FileChangeKind] of the two-letter git status [code] (`??`, ` M`, `R `, …) or `clean`.
/// Anything not recognized counts as [FileChangeKind.modified].
FileChangeKind fileChangeKind(String code) {
  if (code == 'clean') return FileChangeKind.clean;
  if (code == '??' || code.contains('A')) return FileChangeKind.added;
  if (code.contains('D')) return FileChangeKind.deleted;
  if (code.contains('R')) return FileChangeKind.renamed;
  return FileChangeKind.modified;
}
