import 'package:flutter/services.dart';

/// The skills and rules that ship with the app.
abstract interface class IBuiltinKnowledge {
  /// The text of every built-in file. A key is the path relative to `assets/knowledge/`, for
  /// example `skills/feature-architecture/SKILL.md`.
  Future<Map<String, String>> load();
}

/// [IBuiltinKnowledge] that reads the files declared as assets under `assets/knowledge/`.
final class AssetBuiltinKnowledge implements IBuiltinKnowledge {
  /// Creates the reader.
  AssetBuiltinKnowledge({required this._bundle});

  static const String _prefix = 'assets/knowledge/';

  final AssetBundle _bundle;
  Future<Map<String, String>>? _cache;

  @override
  Future<Map<String, String>> load() => _cache ??= _read();

  Future<Map<String, String>> _read() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
      final keys = manifest.listAssets().where((key) => key.startsWith(_prefix)).toList()..sort();
      final texts = await Future.wait(keys.map(_bundle.loadString));
      return {for (var i = 0; i < keys.length; i++) keys[i].substring(_prefix.length): texts[i]};
    } on Object {
      // Do not cache a failure: the next call tries again.
      _cache = null;
      rethrow;
    }
  }
}
