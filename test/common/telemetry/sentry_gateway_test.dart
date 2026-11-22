import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/sentry_gateway.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry/sentry.dart';

final class _Transport implements Transport {
  int sent = 0;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    sent++;
    return SentryId.newId();
  }
}

final class _Capture implements Transport {
  _Capture(this.bodies);

  final List<String> bodies;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      bodies.add(utf8.decode(await item.dataFactory()));
    }
    return SentryId.newId();
  }
}

OutboxEntry _entry({int count = 7, String? stack}) => OutboxEntry(
  id: 1,
  fingerprint: 'abc',
  firstAt: DateTime.utc(2026, 11, 1, 8),
  lastAt: DateTime.utc(2026, 11, 2, 8),
  count: count,
  attempts: 0,
  level: 'fatal',
  type: 'StateError',
  message: 'Bad state: failure',
  stack: stack ?? '#0 Repo.load (package:flutter_code_agent/src/repo.dart:10:5)',
  hint: 'ROOT ERROR',
  breadcrumbs: const ['2026-11-01T07:59:00.000Z [I] first', '2026-11-01T08:00:00.000Z [E] second'],
  appVersion: '1.0.0+1',
  platform: 'windows',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'send: an event with the original time, the count, the log, the version and no personal data',
    () async {
      final events = <SentryEvent>[];
      SentryOptions? seen;
      final gateway = SentryGateway(
        dsn: 'https://key@o1.ingest.sentry.io/123',
        projectPackages: const {'flutter_code_agent'},
        environment: 'production',
        release: '1.0.0+1',
        configureOptions: (options) {
          seen = options;
          options
            ..transport = _Transport()
            ..beforeSend = (event, hint) {
              events.add(event);
              return event;
            };
        },
      );
      addTearDown(gateway.close);

      final accepted = await gateway.send(_entry());

      expect(accepted, isTrue);
      final event = events.single;
      expect(event.timestamp, DateTime.utc(2026, 11, 1, 8));
      expect(event.level, SentryLevel.fatal);
      expect(event.release, '1.0.0+1');
      expect(event.environment, 'production');
      expect(event.exceptions!.single.type, 'StateError');
      expect(event.exceptions!.single.value, 'Bad state: failure');
      expect(event.exceptions!.single.stackTrace!.frames, isNotEmpty);
      expect(event.fingerprint, ['abc']);
      expect(event.tags, {'platform': 'windows', 'app_version': '1.0.0+1'});
      // ignore: deprecated_member_use
      expect(event.extra!['count'], 7);
      expect(
        event.breadcrumbs!.map((b) => b.message),
        contains('2026-11-01T08:00:00.000Z [E] second'),
      );
      expect(seen!.sendDefaultPii, isFalse);
      expect(seen!.integrations.whereType<IsolateErrorIntegration>(), isEmpty);
    },
  );

  test('a repeated start and parallel sends start Sentry once', () async {
    var inits = 0;
    final gateway = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      configureOptions: (options) {
        inits++;
        options.transport = _Transport();
      },
    );
    addTearDown(gateway.close);

    await Future.wait([gateway.start(), gateway.start(), gateway.send(_entry())]);
    await gateway.start();
    await gateway.send(_entry());

    expect(inits, 1);
  });

  test('M3: the event has no absolute paths, the OS, the Dart version, the language and the time zone stay', () async {
    final bodies = <String>[];
    final gateway = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      configureOptions: (options) => options.transport = _Capture(bodies),
    );
    addTearDown(gateway.close);

    expect(await gateway.send(_entry()), isTrue);

    final event = jsonDecode(bodies.firstWhere((b) => b.contains('"contexts"')));
    final contexts = event['contexts'] as Map<String, Object?>;
    expect(contexts.keys, containsAll(['os', 'dart', 'culture']));
    expect(jsonEncode(contexts), isNot(contains('package_config')));
    expect(jsonEncode(contexts), isNot(contains('/Users/')));
    expect(jsonEncode(contexts), isNot(contains('file://')));
  });

  test('send: Sentry returned no identifier, the entry is not accepted', () async {
    final gateway = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      environment: 'production',
      release: '1.0.0+1',
      configureOptions: (options) {
        options
          ..transport = _Transport()
          ..beforeSend = (event, hint) => null;
      },
    );
    addTearDown(gateway.close);

    expect(await gateway.send(_entry()), isFalse);
  });

  test('reachable: any answer of the host means a connection, a closed port does not', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var heads = 0;
    server.listen((request) {
      if (request.method == 'HEAD') heads++;
      request.response
        ..statusCode = 404
        ..close();
    });
    final up = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      probeUri: Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    expect(await up.reachable(), isTrue);
    expect(heads, 1);

    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    final down = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      probeUri: Uri.parse('http://127.0.0.1:$port/'),
    );
    expect(await down.reachable(), isFalse);
  });

  test('M5: the probe address comes from the DSN: scheme and port', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requested = '';
    server.listen((request) {
      requested =
          '${request.method} ${request.uri.path} ${request.headers.host}:${request.headers.port}';
      request.response.close();
    });

    final gateway = SentryGateway(
      dsn: 'http://key@127.0.0.1:${server.port}/5',
      projectPackages: const {'flutter_code_agent'},
    );

    expect(await gateway.reachable(), isTrue);
    expect(requested, 'HEAD / 127.0.0.1:${server.port}');
  });

  test('M5: one timeout for the whole request, a hung host is unreachable', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) {
      // Accept the connection and stay silent.
      addTearDown(socket.destroy);
    });
    final gateway = SentryGateway(
      dsn: 'http://key@127.0.0.1:${server.port}/5',
      projectPackages: const {'flutter_code_agent'},
      timeout: const Duration(milliseconds: 300),
    );

    final watch = Stopwatch()..start();
    expect(await gateway.reachable(), isFalse);
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });

  test('the gateway fits the sender: an accepted entry leaves the queue', () async {
    final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final outbox = ErrorOutbox(
      db,
      appVersion: '1.0.0+1',
      platform: 'windows',
      projectPackages: const {'flutter_code_agent'},
    );
    await outbox.add(
      error: StateError('x'),
      stack: StackTrace.fromString('#0 f (package:flutter_code_agent/a.dart:1:1)'),
      level: 'error',
      breadcrumbs: const [],
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) => r.response.close());
    final gateway = SentryGateway(
      dsn: 'https://key@o1.ingest.sentry.io/123',
      projectPackages: const {'flutter_code_agent'},
      environment: 'production',
      release: '1.0.0+1',
      probeUri: Uri.parse('http://127.0.0.1:${server.port}/'),
      configureOptions: (options) => options.transport = _Transport(),
    );
    addTearDown(gateway.close);

    await TelemetrySender(outbox: outbox, gateway: gateway, enabled: () => true).runPass();

    expect(await outbox.length(), 0);
  });

  test('an empty DSN turns sending off: no connection, Sentry does not start', () async {
    final gateway = SentryGateway(
      dsn: '  ',
      projectPackages: const {'flutter_code_agent'},
      environment: 'development',
    );

    expect(gateway.enabled, isFalse);
    expect(await gateway.reachable(), isFalse);
    expect(await gateway.send(_entry()), isFalse);
    expect(Sentry.isEnabled, isFalse);
  });

  test('options: no PII, no debug, no print breadcrumbs', () async {
    SentryOptions? seen;
    final gateway = SentryGateway(
      dsn: 'https://key@sentry.example/1',
      projectPackages: const {'flutter_code_agent'},
      environment: 'production',
      release: '1.0.0',
      configureOptions: (options) {
        options.transport = _Transport();
        seen = options;
      },
    );
    addTearDown(gateway.close);

    await gateway.send(_entry());

    expect(seen!.environment, 'production');
    expect(seen!.release, '1.0.0');
    expect(seen!.debug, isFalse);
    expect(seen!.sendDefaultPii, isFalse);
    expect(seen!.enablePrintBreadcrumbs, isFalse);
    expect(seen!.integrations.whereType<IsolateErrorIntegration>(), isEmpty);
  });

  test('close stops Sentry; the next send starts it again', () async {
    final gateway = SentryGateway(
      dsn: 'https://key@sentry.example/1',
      projectPackages: const {'flutter_code_agent'},
      configureOptions: (options) => options.transport = _Transport(),
    );

    await gateway.send(_entry());
    expect(Sentry.isEnabled, isTrue);
    await gateway.close();
    expect(Sentry.isEnabled, isFalse);

    await gateway.send(_entry());
    expect(Sentry.isEnabled, isTrue);
    await gateway.close();
  });

  test('close during start waits for the start and closes Sentry', () async {
    final gateway = SentryGateway(
      dsn: 'https://key@sentry.example/1',
      projectPackages: const {'flutter_code_agent'},
      configureOptions: (options) => options.transport = _Transport(),
    );

    final starting = gateway.start();
    await gateway.close();
    await starting;

    expect(Sentry.isEnabled, isFalse);
  });

  test(
    'stack not recognised (obfuscated): the raw stack goes as a string in extra.stack',
    () async {
      final events = <SentryEvent>[];
      final gateway = SentryGateway(
        dsn: 'https://key@sentry.example/1',
        projectPackages: const {'flutter_code_agent'},
        configureOptions: (options) {
          options
            ..transport = _Transport()
            ..beforeSend = (event, hint) {
              events.add(event);
              return event;
            };
        },
      );
      addTearDown(gateway.close);
      const raw =
          '*** *** ***\nbuild_id: abc\n#00 abs 000 virt 1 _kDartIsolateSnapshotInstructions+0x1';

      await gateway.send(_entry(stack: raw));

      // ignore: deprecated_member_use
      expect(events.single.extra!['stack'], raw);
    },
  );

  test('marks frames of the project packages inApp', () async {
    final events = <SentryEvent>[];
    final gateway = SentryGateway(
      dsn: 'https://key@sentry.example/1',
      projectPackages: const {'my_app'},
      configureOptions: (options) {
        options
          ..transport = _Transport()
          ..beforeSend = (event, hint) {
            events.add(event);
            return event;
          };
      },
    );
    addTearDown(gateway.close);

    await gateway.send(
      _entry(stack: '#0 A.run (package:my_app/x.dart:1:1)\n#1 B.run (package:other/y.dart:2:2)'),
    );

    final frames = events.single.exceptions!.single.stackTrace!.frames;
    expect(
      {for (final f in frames) f.absPath: f.inApp},
      {'package:my_app/x.dart': true, 'package:other/y.dart': false},
    );
  });
}
