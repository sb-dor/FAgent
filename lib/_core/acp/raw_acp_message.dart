import 'package:meta/meta.dart';

/// {@template raw_acp_message}
/// One incoming JSON-RPC message exactly as decoded from the wire, before the
/// SDK turns it into typed models.
///
/// "Raw" means the original JSON object (not a byte-for-byte copy: whitespace
/// and key order are not kept). The journal stores these, so a message the SDK
/// cannot decode is still kept and shown.
/// {@endtemplate}
@immutable
final class RawAcpMessage {
  /// {@macro raw_acp_message}
  RawAcpMessage(this.json, {DateTime? receivedAt}) : receivedAt = receivedAt ?? DateTime.now();

  /// The decoded JSON-RPC object.
  final Map<String, Object?> json;

  /// When the app received the message.
  final DateTime receivedAt;

  /// JSON-RPC method, for requests and notifications.
  String? get method => switch (json['method']) {
    final String value => value,
    _ => null,
  };

  /// JSON-RPC id, for requests and responses.
  Object? get id => json['id'];

  /// Agent → client request (expects a response).
  bool get isRequest => method != null && json.containsKey('id');

  /// Agent → client notification.
  bool get isNotification => method != null && !json.containsKey('id');

  /// Response to one of our requests.
  bool get isResponse => method == null && json.containsKey('id');

  /// `params` of a request or notification.
  Map<String, Object?>? get params => _object(json['params']);

  /// `result` of a successful response.
  Map<String, Object?>? get result => _object(json['result']);

  /// `params.sessionId`, when the message belongs to a session.
  String? get sessionId => switch (params?['sessionId']) {
    final String value => value,
    _ => null,
  };

  static Map<String, Object?>? _object(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => null,
  };

  @override
  String toString() => 'RawAcpMessage(${method ?? 'response'} #$id)';
}
