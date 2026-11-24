/// The `_meta` key of the app's own data on a prompt block.
const String kAppMetaKey = 'flutter_code_agent';

/// The app's data on [block] (`_meta.flutter_code_agent`); `null` when it has none.
Map<String, Object?>? _appMeta(Map<String, Object?> block) => switch (block['_meta']) {
  {kAppMetaKey: final Map<Object?, Object?> meta} => meta.cast<String, Object?>(),
  _ => null,
};

/// [block] without the app's data, as the agent gets it; the same map when there is none.
Map<String, Object?> promptBlockForAgent(Map<String, Object?> block) {
  if (_appMeta(block) == null) return block;
  final meta = <String, Object?>{...(block['_meta']! as Map<Object?, Object?>).cast()}
    ..remove(kAppMetaKey);
  return <String, Object?>{
    for (final MapEntry(:key, :value) in block.entries)
      if (key != '_meta') key: value,
    if (meta.isNotEmpty) '_meta': meta,
  };
}

/// [block] as the journal keeps it: an image with a thumbnail (`_meta.flutter_code_agent.thumbnail`,
/// base64, of `thumbnailMimeType`) is journaled as the thumbnail, marked with
/// `_meta.flutter_code_agent.thumbnail: true`; the full image goes to the agent only. Any other
/// block is kept as it is.
Map<String, Object?> promptBlockForJournal(Map<String, Object?> block) {
  final app = _appMeta(block);
  if (block['type'] != 'image' || app == null) return block;
  final thumbnail = app['thumbnail'];
  if (thumbnail is! String) return block;
  return <String, Object?>{
    ...block,
    'mimeType': app['thumbnailMimeType'] is String ? app['thumbnailMimeType'] : block['mimeType'],
    'data': thumbnail,
    '_meta': <String, Object?>{
      ...(block['_meta']! as Map<Object?, Object?>).cast(),
      kAppMetaKey: const <String, Object?>{'thumbnail': true},
    },
  };
}

/// [block] is an image the journal holds as a thumbnail ([promptBlockForJournal]).
bool isJournaledThumbnail(Map<String, Object?> block) => _appMeta(block)?['thumbnail'] == true;
