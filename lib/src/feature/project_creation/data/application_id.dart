import 'dart:io';

import 'package:path/path.dart' as p;

/// A full application ID, for example `com.example.shop`: two or more segments of lowercase
/// letters, digits and underscores, each starting with a letter.
final RegExp applicationIdPattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

/// What `flutter create --org` gets for [applicationId]: every segment but the last.
String applicationIdOrg(String applicationId) =>
    applicationId.substring(0, applicationId.lastIndexOf('.'));

/// The ID on Android and Linux that `flutter create --org [org] --project-name [name]` writes.
String androidIdentifier(String org, String name) => '$org.$name';

/// The bundle ID on iOS and macOS that `flutter create --org [org] --project-name [name]` writes:
/// a bundle ID has no underscores, so the name goes camelCase (`my_app` → `myApp`) and the org
/// loses them.
String appleIdentifier(String org, String name) {
  final parts = name.split('_').where((part) => part.isNotEmpty).toList();
  final camel = <String>[
    if (parts.isNotEmpty) parts.first,
    for (final part in parts.skip(1)) part[0].toUpperCase() + part.substring(1),
  ].join();
  return '${org.replaceAll('_', '')}.$camel';
}

/// Rewrites the IDs `flutter create --org [org] --project-name [package]` wrote into the project at
/// [root] to [applicationId]: `applicationId`, `namespace` and the `MainActivity` package on
/// Android, `APPLICATION_ID` on Linux and `PRODUCT_BUNDLE_IDENTIFIER` on iOS and macOS (with
/// underscores dropped, as [appleIdentifier] does). Platforms the project does not have are
/// skipped. Returns the changed files, relative to [root].
Future<List<String>> applyApplicationId(
  String root, {
  required String org,
  required String package,
  required String applicationId,
}) async {
  final changed = <String>[];
  Future<void> rewrite(String relative, String Function(String text) change) async {
    final file = File(p.join(root, relative));
    if (!file.existsSync()) return;
    final text = await file.readAsString();
    final next = change(text);
    if (next == text) return;
    await file.writeAsString(next);
    changed.add(relative);
  }

  final oldAndroid = androidIdentifier(org, package);
  if (oldAndroid != applicationId) {
    for (final gradle in const <String>[
      'android/app/build.gradle.kts',
      'android/app/build.gradle',
    ]) {
      await rewrite(gradle, (text) => text.replaceAll('"$oldAndroid"', '"$applicationId"'));
    }
    changed.addAll(await _moveMainActivity(root, oldAndroid, applicationId));
    await rewrite(
      'linux/CMakeLists.txt',
      (text) => text.replaceAll('APPLICATION_ID "$oldAndroid"', 'APPLICATION_ID "$applicationId"'),
    );
  }

  final oldApple = appleIdentifier(org, package);
  final newApple = appleIdentifier(
    applicationIdOrg(applicationId),
    applicationId.substring(applicationId.lastIndexOf('.') + 1),
  );
  if (oldApple != newApple) {
    final bundle = RegExp(
      'PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(oldApple)}(?=[;.\\s]|\$)',
      multiLine: true,
    );
    for (final file in const <String>[
      'ios/Runner.xcodeproj/project.pbxproj',
      'macos/Runner.xcodeproj/project.pbxproj',
      'macos/Runner/Configs/AppInfo.xcconfig',
    ]) {
      await rewrite(
        file,
        (text) => text.replaceAll(bundle, 'PRODUCT_BUNDLE_IDENTIFIER = $newApple'),
      );
    }
  }
  return changed;
}

/// Moves `MainActivity` from the package [from] to [to] under `android/app/src/main/{kotlin,java}`
/// and rewrites its `package` line; the emptied folders of [from] go. Returns the new files.
Future<List<String>> _moveMainActivity(String root, String from, String to) async {
  final moved = <String>[];
  for (final language in const <String>['kotlin', 'java']) {
    final sources = p.join(root, 'android', 'app', 'src', 'main', language);
    final oldDir = Directory(p.joinAll(<String>[sources, ...from.split('.')]));
    if (!oldDir.existsSync()) continue;
    final newDir = Directory(p.joinAll(<String>[sources, ...to.split('.')]));
    await newDir.create(recursive: true);
    final packageLine = RegExp('^package ${RegExp.escape(from)}(?=;|\\s*\$)', multiLine: true);
    for (final entity in oldDir.listSync().whereType<File>()) {
      final text = await entity.readAsString();
      final target = File(p.join(newDir.path, p.basename(entity.path)));
      await target.writeAsString(text.replaceFirst(packageLine, 'package $to'));
      await entity.delete();
      moved.add(p.relative(target.path, from: root));
    }
    // The emptied folders of the old package, up to the language folder.
    for (
      var dir = oldDir;
      p.isWithin(sources, dir.path) && dir.existsSync() && dir.listSync().isEmpty;
      dir = dir.parent
    ) {
      await dir.delete();
    }
  }
  return moved;
}
