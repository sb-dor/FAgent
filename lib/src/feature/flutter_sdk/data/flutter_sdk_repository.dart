import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';

/// What the app knows about the Flutter tooling of this machine.
abstract interface class IFlutterSdkRepository {
  /// The SDK that [projectPath] builds with. Without a project (`null`) only the SDK on `PATH`
  /// is described.
  Future<FlutterSdk> sdkFor(String? projectPath);

  /// The `flutter` executable that [projectPath] builds with; `null` when there is none. Starts no
  /// process, so a caller that only needs the path does not wait for [sdkFor] to ask `flutter` for
  /// its version.
  Future<String?> pathFor(String? projectPath);

  /// Runs `flutter doctor` and returns its checks in report order.
  Future<List<DoctorCheck>> doctor();
}
