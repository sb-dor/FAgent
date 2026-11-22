import 'dart:async';

import 'package:{{package}}/_core/api_client/api_client.dart';
import 'package:{{package}}/_core/api_client/expected_exception.dart';
import 'package:{{package}}/_core/telemetry/telemetry_setup.dart' show isSocketException;

/// The packages of this project: their stack frames count as its own in the fingerprint and in
/// the crash reporter. Add a package of the project here when it gets one.
const Set<String> projectPackages = <String>{'{{package}}', 'ui'};

/// Whether [error] is expected: the user or the outside world caused it and the UI shows it. It is
/// written to the log, but not queued for the crash reporter. The one place that decides (see
/// "Expected and unexpected errors" in docs/rules/controllers.md): a new kind of expected failure
/// is added here, not in a `catch`.
///
/// Expected: every [ExpectedException] (a server refusal with a code, `RejectedException`, among
/// them), the network and 5xx answers ([APIClientException$Network]), 401 and 403
/// ([APIClientException$Authorization]), a [TimeoutException], and a dropped connection
/// (`SocketException`, on the VM only).
bool isExpectedFailure(Object error) =>
    error is ExpectedException ||
    error is APIClientException$Network ||
    error is APIClientException$Authorization ||
    error is TimeoutException ||
    isSocketException(error);
