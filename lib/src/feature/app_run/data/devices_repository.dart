import 'dart:async';

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/emulator_launcher.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:l/l.dart';

/// The devices `flutter run` can target.
abstract interface class IDevicesRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// The current device list, then every change. Ends when the subscription is cancelled, and with
  /// an error when the devices cannot be followed (`FlutterNotFoundException` when there is no
  /// Flutter SDK, `DaemonClosedException` when the daemon dies).
  Stream<List<Device>> watchDevices();

  /// Boots the emulator behind [deviceId]. Does nothing for a device that is not
  /// [DeviceKind.available]. The booted device shows up in [watchDevices]; it keeps running when
  /// the app quits.
  Future<void> launch(String deviceId);

  /// Stops following the devices and ends every stream.
  Future<void> dispose();
}

/// The devices of one `flutter daemon` shared by every listener: it starts with the first one and
/// stops when the last one leaves.
///
/// Emulators are booted by a launcher of their own ([launchEmulatorDetached]), not by the daemon:
/// an emulator the daemon starts is a member of its process group, and ending the group (on quit,
/// or when the daemon fails) would shut the emulator down with it.
final class DevicesRepositoryImpl implements IDevicesRepository {
  DevicesRepositoryImpl({
    required this._flutter,
    required this._environment,
    this._start = startGroupedDaemonProcess,
    this._launchEmulator = launchEmulatorDetached,
  });

  /// The `flutter` executable to run; `null` when there is none.
  final String? Function() _flutter;
  final Map<String, String> _environment;
  final DaemonProcessStarter _start;
  final EmulatorLauncher _launchEmulator;

  final List<StreamController<List<Device>>> _watchers = <StreamController<List<Device>>>[];
  _DaemonSession? _session;
  bool _disposed = false;

  static const String _emulatorPrefix = 'emulator:';

  @override
  bool get isPreview => false;

  @override
  Stream<List<Device>> watchDevices() {
    if (_disposed) return const Stream<List<Device>>.empty();
    final controller = StreamController<List<Device>>();
    controller
      ..onListen = () {
        _watchers.add(controller);
        final session = _session;
        if (session == null) {
          _startSession();
        } else if (session.latest case final latest?) {
          controller.add(latest);
        }
      }
      ..onCancel = () async {
        _watchers.remove(controller);
        if (_watchers.isEmpty) await _stopSession();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> launch(String deviceId) async {
    if (!deviceId.startsWith(_emulatorPrefix)) return;
    final executable = _flutter();
    if (executable == null) throw const FlutterNotFoundException();
    await _launchEmulator(
      executable,
      deviceId.substring(_emulatorPrefix.length),
      environment: _environment,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final watchers = List<StreamController<List<Device>>>.of(_watchers);
    _watchers.clear();
    await _stopSession();
    for (final watcher in watchers) {
      if (!watcher.isClosed) await watcher.close();
    }
  }

  void _startSession() {
    late final _DaemonSession session;
    session = _DaemonSession(
      flutter: _flutter,
      environment: _environment,
      starter: _start,
      onDevices: (devices) {
        if (_session != session) return;
        for (final watcher in List<StreamController<List<Device>>>.of(_watchers)) {
          if (!watcher.isClosed) watcher.add(devices);
        }
      },
      onFailed: (error, stackTrace) {
        if (_session != session) return;
        _session = null;
        final watchers = List<StreamController<List<Device>>>.of(_watchers);
        _watchers.clear();
        for (final watcher in watchers) {
          if (watcher.isClosed) continue;
          watcher
            ..addError(error, stackTrace)
            ..close().ignore();
        }
        session.stop().ignore();
      },
    );
    _session = session;
    session.start();
  }

  Future<void> _stopSession() async {
    final session = _session;
    _session = null;
    await session?.stop();
  }
}

typedef _Emulator = ({String id, String name, DevicePlatform platform});

/// One `flutter daemon` process and the device state it reports.
final class _DaemonSession {
  _DaemonSession({
    required this._flutter,
    required this._environment,
    required this._starter,
    required this.onDevices,
    required this.onFailed,
  });

  final String? Function() _flutter;
  final Map<String, String> _environment;
  final DaemonProcessStarter _starter;

  /// Called with every new device list.
  final void Function(List<Device> devices) onDevices;

  /// Called once when the session cannot go on (no SDK, the daemon died, a request failed).
  final void Function(Object error, StackTrace stackTrace) onFailed;

  /// The newest list; `null` until the first one is ready.
  List<Device>? latest;

  DaemonConnection? _connection;
  StreamSubscription<DaemonEvent>? _events;
  bool _stopped = false;
  Future<void> _queue = Future<void>.value();

  /// The running devices by id, in the order they arrived.
  final Map<String, Device> _running = <String, Device>{};
  List<_Emulator> _emulators = const <_Emulator>[];

  void start() => unawaited(_start());

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _events?.cancel();
    await _connection?.close();
  }

  Future<void> _start() async {
    final executable = _flutter();
    if (executable == null) {
      _fail(const FlutterNotFoundException(), StackTrace.current);
      return;
    }
    final DaemonProcess process;
    try {
      process = await _starter(executable, const <String>['daemon'], environment: _environment);
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
      return;
    }
    if (_stopped) {
      await process.stop();
      return;
    }
    // Listen at once: the events are broadcast and `daemon.connected` may come right away.
    final connection = DaemonConnection(process);
    _connection = connection;
    _events = connection.events.listen(_onEvent);
    unawaited(
      connection.done.then((_) => _fail(const DaemonClosedException(), StackTrace.current)),
    );
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_stopped) return;
    onFailed(error, stackTrace);
  }

  void _onEvent(DaemonEvent event) {
    switch (event.name) {
      case 'daemon.connected':
        _enqueue(_loadAll);
      case 'device.added':
        _enqueue(() => _change(added: event.params));
      case 'device.removed':
        _enqueue(() => _change(removedId: event.params['id']));
    }
  }

  /// Runs [action] after the previous one, so that the answers of a slow request never overwrite
  /// the result of a newer event.
  void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) async {
      if (_stopped) return;
      try {
        await action();
      } on Object catch (error, stackTrace) {
        _fail(error, stackTrace);
      }
    });
  }

  Future<void> _loadAll() async {
    final connection = _connection!;
    await connection.request('device.enable');
    final results = await Future.wait<Object?>(<Future<Object?>>[
      connection.request('device.getDevices'),
      _loadEmulators(connection),
    ]);
    _running.clear();
    for (final device in _parseDevices(results[0])) {
      _running[device.id] = device;
    }
    _emulators = results[1]! as List<_Emulator>;
    _publish();
  }

  Future<void> _change({Map<String, Object?>? added, Object? removedId}) async {
    if (added != null) {
      final device = _parseDevice(added);
      if (device != null) _running[device.id] = device;
    }
    if (removedId is String) _running.remove(removedId);
    _emulators = await _loadEmulators(_connection!);
    if (!_stopped) _publish();
  }

  /// The emulators the daemon knows. A daemon that cannot list them (no Android SDK, say) only
  /// costs the "available" part of the list, so the previous ones are kept.
  Future<List<_Emulator>> _loadEmulators(DaemonConnection connection) async {
    try {
      return _parseEmulators(await connection.request('emulator.getEmulators'));
    } on DaemonRequestException catch (error) {
      l.w('DevicesRepository | emulator.getEmulators failed: $error');
      return _emulators;
    }
  }

  void _publish() {
    final running = _running.values.toList(growable: false);
    final bootedEmulators = <String>{
      for (final device in running)
        if (device.emulatorId != null) device.emulatorId!,
    };
    final devices = List<Device>.unmodifiable(<Device>[
      ...running,
      for (final emulator in _emulators)
        if (!bootedEmulators.contains(emulator.id))
          Device(
            id: '${DevicesRepositoryImpl._emulatorPrefix}${emulator.id}',
            name: emulator.name,
            platform: emulator.platform,
            kind: DeviceKind.available,
            emulatorId: emulator.id,
          ),
    ]);
    latest = devices;
    onDevices(devices);
  }

  static DevicePlatform? _platform(Object? type) => switch (type) {
    'ios' => DevicePlatform.ios,
    'android' => DevicePlatform.android,
    'macos' => DevicePlatform.macos,
    'web' => DevicePlatform.web,
    'windows' => DevicePlatform.windows,
    'linux' => DevicePlatform.linux,
    _ => null,
  };

  static Iterable<Device> _parseDevices(Object? result) sync* {
    if (result is! List<Object?>) return;
    for (final entry in result) {
      if (entry is Map<String, Object?>) {
        final device = _parseDevice(entry);
        if (device != null) yield device;
      }
    }
  }

  static Device? _parseDevice(Map<String, Object?> json) {
    final id = json['id'];
    final platform = _platform(json['platformType']);
    if (id is! String || platform == null) return null;
    final name = json['name'];
    final sdk = json['sdk'];
    final emulatorId = json['emulatorId'];
    return Device(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      platform: platform,
      kind: DeviceKind.running,
      detail: sdk is String && sdk.isNotEmpty ? sdk : null,
      emulatorId: emulatorId is String && emulatorId.isNotEmpty ? emulatorId : null,
    );
  }

  static List<_Emulator> _parseEmulators(Object? result) {
    if (result is! List<Object?>) return const <_Emulator>[];
    return <_Emulator>[
      for (final entry in result)
        if (entry is Map<String, Object?> &&
            entry['id'] is String &&
            _platform(entry['platformType']) != null)
          (
            id: entry['id']! as String,
            name: entry['name'] is String ? entry['name']! as String : entry['id']! as String,
            platform: _platform(entry['platformType'])!,
          ),
    ];
  }
}
