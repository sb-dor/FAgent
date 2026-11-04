import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Characters of a file name a card shows before it cuts the middle out.
const int composerFileNameLength = 30;

/// {@template composer_file}
/// A file or folder from outside the project that goes with the next message, shown as a card
/// above the composer's text; the agent gets a `resource_link` to it and reads it itself.
/// {@endtemplate}
@immutable
final class ComposerFile {
  /// {@macro composer_file}
  const ComposerFile({required this.path, this.folder = false});

  /// The card of a `resource_link` [uri]: a `file:` URI, a folder by its trailing `/`; `null` for
  /// any other URI.
  static ComposerFile? fromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme('file')) return null;
    final path = parsed.toFilePath();
    final folder = path.length > 1 && path.endsWith('/');
    return ComposerFile(path: folder ? path.substring(0, path.length - 1) : path, folder: folder);
  }

  /// Absolute path.
  final String path;

  /// A folder, not a file.
  final bool folder;

  /// The extension in capitals (`HEIC`); `null` for a folder or a file without one.
  String? get badge {
    if (folder) return null;
    final extension = p.extension(path);
    return extension.length > 1 ? extension.substring(1).toUpperCase() : null;
  }

  /// The ACP block that goes to the agent.
  Map<String, Object?> toBlock() => <String, Object?>{
    'type': 'resource_link',
    'uri': (folder ? Uri.directory(path) : Uri.file(path)).toString(),
    'name': p.basename(path),
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerFile && other.path == path && other.folder == folder;

  @override
  int get hashCode => Object.hash(path, folder);

  @override
  String toString() => 'ComposerFile($path${folder ? '/' : ''})';
}

/// [path] as a card shows it: `~` for the [home] folder, a long name cut in the middle (its start
/// and its end, with the extension, stay), `/` after a [folder].
String composerFileLabel(String path, {required String? home, bool folder = false}) {
  final shown = home != null && p.isWithin(home, path) ? '~${path.substring(home.length)}' : path;
  final dir = p.dirname(shown);
  var name = p.basename(shown);
  if (name.length > composerFileNameLength) {
    const head = 16;
    const tail = composerFileNameLength - head - 1;
    name = '${name.substring(0, head)}…${name.substring(name.length - tail)}';
  }
  final prefix = dir == '.' ? '' : (dir.endsWith('/') ? dir : '$dir/');
  return '$prefix$name${folder ? '/' : ''}';
}

/// The cards of a sent message: its `file:` [resources] that its [text] does not `@mention` (those
/// show as mentions in the text).
List<ComposerFile> attachedFiles(String text, List<String> resources) {
  final mentions = <String>[
    for (final match in RegExp(r'@(\S+)').allMatches(text))
      match.group(1)!.replaceAll(RegExp('[.,;:!?)\\]}\'"]+\$'), '').replaceAll(RegExp(r'/$'), ''),
  ];
  return <ComposerFile>[
    for (final uri in resources)
      if (ComposerFile.fromUri(uri) case final file?)
        if (!mentions.any((mention) => file.path == mention || file.path.endsWith('/$mention')))
          file,
  ];
}
