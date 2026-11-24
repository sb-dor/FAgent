import 'dart:io' as io;

import 'package:flutter/foundation.dart';

/// Opens [url] in the default application for it (a web address opens in the browser).
typedef UrlOpener = Future<void> Function(Uri url);

/// The executable and arguments that open [url] on [operatingSystem] (a value of
/// `Platform.operatingSystem`). Throws [UnsupportedError] for a system without a known command.
@visibleForTesting
(String, List<String>) openCommand(Uri url, {required String operatingSystem}) =>
    switch (operatingSystem) {
      'macos' => ('open', <String>[url.toString()]),
      'linux' => ('xdg-open', <String>[url.toString()]),
      'windows' => ('cmd', <String>['/c', 'start', '', url.toString()]),
      _ => throw UnsupportedError('Cannot open a URL on $operatingSystem'),
    };

/// The [UrlOpener] of the system: `open` (macOS), `xdg-open` (Linux) or `cmd /c start` (Windows).
/// Throws when the command cannot be run or fails.
Future<void> openUrl(Uri url) async {
  final (executable, arguments) = openCommand(url, operatingSystem: io.Platform.operatingSystem);
  final result = await io.Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw io.ProcessException(executable, arguments, '${result.stderr}'.trim(), result.exitCode);
  }
}
