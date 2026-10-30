/// {@template tool_row_label}
/// What a tool row shows: the agent's [title] (without the path it repeats), the file [name] and
/// the [folder] it lies in.
/// {@endtemplate}
final class ToolRowLabel {
  /// {@macro tool_row_label}
  const ToolRowLabel({this.title, this.name, this.folder});

  /// The agent's wording, e.g. `Write`; `null` when nothing but the path was there.
  final String? title;

  /// The file's base name; `null` when the call touches no file.
  final String? name;

  /// The folder of [name] with a trailing `/`, relative to the project when inside it; `null` for
  /// a file in the project root.
  final String? folder;
}

/// [path] relative to [projectRoot] when it lies inside it, else [path] itself.
String relativeToRoot(String path, String? projectRoot) {
  if (projectRoot == null || projectRoot.isEmpty) return path;
  final root = projectRoot.endsWith('/') ? projectRoot : '$projectRoot/';
  return path.length > root.length && path.startsWith(root) ? path.substring(root.length) : path;
}

/// Builds the row label of a tool call touching [path] (its first location).
///
/// A title that merely ends with the path (as Claude's `Write /abs/path`), with the path relative
/// to the project or with the base name, loses that part so the path is not shown twice.
ToolRowLabel toolRowLabel({required String title, String? path, String? projectRoot}) {
  if (path == null || path.isEmpty) return ToolRowLabel(title: title.isEmpty ? null : title);
  final relative = relativeToRoot(path, projectRoot);
  final slash = relative.lastIndexOf('/');
  final name = relative.substring(slash + 1);
  final folder = slash == -1 ? null : relative.substring(0, slash + 1);
  var verb = title.trim();
  for (final repeated in <String>{path, relative, name}) {
    if (verb == repeated) {
      verb = '';
      break;
    }
    if (verb.endsWith(' $repeated')) {
      verb = verb.substring(0, verb.length - repeated.length).trim();
      break;
    }
  }
  return ToolRowLabel(
    title: verb.isEmpty ? null : verb,
    name: name.isEmpty ? path : name,
    folder: folder,
  );
}
