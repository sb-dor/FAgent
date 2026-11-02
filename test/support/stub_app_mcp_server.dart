import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';

/// An [IAppMcpServer] with a fixed [url] and [startError]; it never listens.
final class StubAppMcpServer implements IAppMcpServer {
  /// Creates the stub.
  StubAppMcpServer({this.url, this.toolCount = 9, this.startError});

  @override
  Uri? url;

  @override
  int toolCount;

  @override
  Object? startError;

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}
}
