---
name: security
description: "Client-side security: nothing in the app stays secret, obfuscation, token storage, refresh and sign-out, JWT and what the server checks, OAuth sign-in with PKCE, biometrics, logs, and the supply chain (pubspec.lock)."
---

# Security

## Rules

- Everything in the app can be read: its code, its strings, its assets and its `--dart-define`
  values. Secrets, and logic that must stay hidden, live on the server. See "What an installed app
  gives away".
- Name the threat before adding protection: who attacks, with what access, to get what. A package
  with "secure" in its name, added without reading what it does, is not protection. Ask what
  changes if it is not there.
- Checks that protect something (PIN attempts, paid features, roles, limits) are made by the
  server. The same check in the app is only for the UI.
- Password rules for sign-up are checked by the server; the app's check only explains them early.
  NIST SP 800-63B asks for length and a check against known-breached passwords rather than
  composition rules (an uppercase letter, a digit); `String.length` counts UTF-16 code units, not
  the characters the user typed: count those with `password.characters.length` (checked:
  `'Ann👨‍👩‍👧'` has `length` 11 and 4 characters; see "Strings and text length" in
  `docs/rules/dart.md`).
- Never log passwords, tokens, card data or personal data: not to the console, a file, Crashlytics
  or Sentry. Logs and crash reports are read by more people than the database. Analytics too: no
  email, phone, name or text the user typed in an event parameter or `setUserId` (Google Analytics'
  policies forbid it); send the app's opaque user id.
- Tokens are read from storage once, into memory; the HTTP client's authentication middleware takes
  them from memory and never reads the storage or crosses a platform channel per request. See
  "Tokens".
- One object owns the tokens (`AuthSession`); the middleware and everything else ask it and keep
  no copy. The state widgets rebuild on holds the user, never the tokens. See "Tokens".
- Sign-out forgets the tokens on the device first, always; telling the server is best-effort and
  never awaited. See "Tokens".
- Sign-in with Google, Apple or any OAuth provider goes through the system browser with PKCE,
  never a `WebView`; the session arrives on the authentication stream, not as the sign-in
  method's result. See "Sign-in through a browser (OAuth)".
- A wrong password or a taken email is an answer, not a failure: shown to the user, not sent to the
  crash reporter. See "Expected errors".
- The refresh token goes to the Keychain or the Keystore, never to `SharedPreferences` or a plain
  file. See "Storing tokens".
- Biometrics unlock a key, not a boolean: `local_auth` alone protects nothing. See "Biometrics".
- Apps commit `pubspec.lock`, CI runs `flutter pub get --enforce-lockfile`, and every change of the
  lockfile is reviewed. See "Dependencies".

## What an installed app gives away

An APK unpacks with `apktool d app.apk`:

- `assets/flutter_assets/`: every asset as it is, `.env` files and JSON configs included.
- `lib/<abi>/libapp.so`: the app's Dart code, compiled ahead of time, with all its string
  literals in plain text. `strings`, Blutter and reFlutter read them: URLs, keys, and
  `--dart-define` values, which the compiler turns into the same literals as a hard-coded `const`.
  Checked: a define built with `--obfuscate` is still found as plain text in the snapshot, while
  the class names are gone.
- `lib/<abi>/libflutter.so`: the engine, the same in every app built with that Flutter version.
- The Android side (`AndroidManifest.xml`, `MainActivity.kt`, plugins' Kotlin and Java) opens in
  `jadx` as readable source: a maps key in a `<meta-data>` tag or in Kotlin is as visible as one
  in Dart. On iOS, `Info.plist` and the app's resources are plain files in the `.ipa`.

Blutter rebuilds the Dart side from `libapp.so`: one file per library, in the project's own folder
structure, with every class, method and field name, and the machine code of each method. Given to
an AI model, a build without `--obfuscate` comes back as a close copy of the source. With
`--obfuscate`, the files and classes get random names (`aag.dart`, `_bZ`), and the rebuilt code is
much harder to follow; the strings stay readable either way.

On iOS the defines are written to `ios/Flutter/Generated.xcconfig` (on the build machine,
gitignored); they reach `Info.plist`, and so the app, only if the project references
`$(DART_DEFINES)` there. On the web, all of it is in `main.dart.js` and the network panel.

Runtime protection (RASP: `freerasp`, or root and jailbreak detection) detects a rooted device, a
debugger, hooking frameworks (Frida) or a modified binary. It makes an attack cost more, and it
is itself removed by patching the binary; checks that matter are verified by the server, with
Play Integrity or App Attest.

## Secrets

- A value compiled into the app (`--dart-define`, `env.dart`) or shipped as an asset can be read by
  anyone who has the app: unpack it, or on the web open the network panel. `--dart-define` only
  keeps it out of the repository, not out of the app.
- So real secrets (a payment provider's secret key, a database password, an admin token) never go
  to the client. The backend holds them, and the app calls the backend.
- Keys the client must have (a maps key, a public analytics key) are public by design: restrict
  them in the provider's console (to the app's bundle id or package name and signing certificate,
  or the site's domain) and to the APIs they need.
- Fetching a key from your server at run time does not hide it either: it is then in the app's
  memory and in its traffic. Only a call the server makes on the client's behalf keeps a secret.

### Secrets in the project folder

A coding agent works in the project folder and reads whatever is on disk there. `.gitignore`
keeps a file out of git, not out of the agent's reach, and a line in `CLAUDE.md` ("never read
.env") or an ignore file is a request, not a lock: an agent asked to run a migration has printed
the database password from `.env` into the chat.

The files that are real secrets in a Flutter project:

- `*.jks` / `*.keystore` (the Android signing key) and `android/key.properties` (its passwords):
  together they sign a build as you. Use Play App Signing, so Google holds the app signing key
  and a lost upload key can be reset.
- `serviceAccountKey.json` (Firebase Admin SDK): full access to Firestore and Storage, past every
  Security Rule. It belongs on a server, never in an app's project.
- `AuthKey_*.p8` (App Store Connect API and APNs keys), `*.p12`, `*.mobileprovision`.
- `.env` files and the code generated from them (`env.g.dart` from `envied`), and
  `android/local.properties` when API keys are kept there.

Not secrets: `google-services.json` and `GoogleService-Info.plist`. Their API key identifies the
Firebase project, and access is controlled by Security Rules, App Check and IAM; it is in every
installed app anyway. It becomes a secret when the same key also allows paid APIs (Gemini, Maps):
check the key's API restrictions in the Google Cloud Console.

- Keep the real ones outside the project folder: the keystore in a folder of its own, referenced
  from `key.properties` by an absolute path, or only in the CI's secret store; service-account
  keys on the server.
- Flutter's Android template already ignores `key.properties`, `*.jks`, `*.keystore` and
  `local.properties`; add what it does not: `serviceAccountKey.json`, `AuthKey_*.p8`, `*.p12`,
  `*.mobileprovision`, `.env`, `.env.*` with `!.env.example`, `env.g.dart`.
- An agent's deny rules cover its own file tools, not every shell command it may run; do not
  auto-approve commands in a folder that holds secrets. The only sure protection is that the
  file is not there.

## Obfuscation

`flutter build apk --obfuscate --split-debug-info=build/symbols` (also `appbundle`, `ipa`, `macos`,
...) replaces the names of classes, functions and fields in the compiled Dart code with random
ones, and writes the mapping to `build/symbols`.

- It makes reverse engineering slower, not impossible, and it hides nothing else: strings, assets,
  `--dart-define` values and native code stay as they were (see "What an installed app gives away"). Use it in release
  builds, for what it costs to undo; never count on it for secrets.
- Code that depends on names breaks: `runtimeType.toString()`, `Type.toString()` and stack traces
  return the obfuscated names (`flutter build --help` lists `Enum.toString()` too). Never use a
  type's name as a key, a log tag that must stay readable, or JSON; store an enum by `.name` and
  read it back with `values.asNameMap()` (see `preferences_entry.dart` in
  `docs/rules/repositories.md`).
- Stack traces from users are unreadable without the symbols. Keep `build/symbols` of every
  release (outside git, with the build's version) and upload them to the crash reporter: Sentry
  with `sentry_dart_plugin`, Crashlytics with `firebase crashlytics:symbols:upload`. A trace by
  hand: `flutter symbolize -i trace.txt -d build/symbols/app.android-arm64.symbols`.
- On the web there is no `--obfuscate`: a release build is minified; keep its source maps
  (`--source-maps`) for the crash reporter.

## Crash reports

What leaves the machine, and how it is cleaned. A project that has `ErrorUtil` reports through it
(`ErrorUtil` over `ErrorHub`, the log `logs.sqlite`, the queue, the sender, the gateway); a project
with another reporter keeps it and follows the same split; a new project starts with this
pipeline. The rules for calling it are in "Reporting an error" in `docs/rules/controllers.md`.

- **Only an unexpected error goes to the crash reporter.** The network, timeouts, a refused access
  (`APIClientException$Authorization`), a server refusal and every other `ExpectedException` stay
  in the log on the machine (`isExpectedFailure`). A user's switch ("Send crash reports", off
  until the user turns it on) stops the sender; a developer's own app, where the developer is the
  owner, sends whenever a reporter is configured.
- **Consent covers only what comes after it.** The log and the queue are kept while the switch is
  off, so a settings screen and the archive show them, but nothing recorded before the switch was
  turned on (its message, stack, breadcrumbs or count) ever leaves the machine. Store the moment
  of consent with the setting, give it to the sender, and move it when the switch is turned off
  and on again. An entry from before consent and the same fingerprint recurring after it do not
  send the earlier occurrence's data. Test both.
- **The event holds:** the type, the cleaned message, the stack frames (an obfuscated stack that
  does not parse goes as one raw string in `extra.stack`: symbolize it by hand, see "Obfuscation"),
  the time of the first occurrence, the counter of identical ones, the last 100 log lines, the app
  version, the platform and the environment. `sendDefaultPii` is `false`: no user, no IP, no
  request or headers. The SDK adds its own contexts (the operating system, the Dart runtime, the
  language and time zone, the processor count, the memory, the build mode); the path to
  `package_config.json` is removed in `beforeSend`, so no absolute path of the machine leaves it.
  Paths in texts lose the user name (`C:\Users\<name>`, `/Users/<name>`, `/home/<name>`).
- **`redactSecrets` runs before the queue, before the log database and before every archive.** It
  replaces with `[REDACTED]`:
  - `Bearer ...` and `Authorization: <scheme> ...` (the scheme stays);
  - the values of the fields `token`, `key`, `password`, `pin`, `secret` and `recoveryCode`, with
    any prefix or suffix (`apiKey`, `pin_code`), quoted or not;
  - keys that coding agents and their tools print: `sk-ant-...`, `sk-...` and `sk-proj-...`,
    `ghp_...`, `gho_...` and `github_pat_...`, `AIza...`, `xox[abp]-...`;
  - the secrets of the project's own server in free text, in the shape that server issues them;
  - the user name in paths (`C:\Users\<name>` in any case and with the doubled `\\` of JSON,
    `/Users/<name>`, `/home/<name>`; the name runs to the next separator, so `John Smith` goes
    whole);
  - phone numbers (fields in any format, text only with a leading `+`) and e-mail.

  Certificate fingerprints, a lone UUID and a sha256 are not touched: they are not secrets and
  support needs them. A line is cut to 16 KB first, so the expressions run in linear time on any
  input. A log line takes at most 1100 characters of the raw text before cleaning; when the raw
  text was longer, the last 200 characters of the cleaned text are dropped, because the cut may
  have split an e-mail, a token or a phone that the patterns no longer recognize.
- **A new kind of secret** is added to `redact.dart` with a test: a positive case and a look-alike
  that must stay (`microphone`, `Device is offline`, `sk-learn`).
- **An error with details that must not be shown** (SQLite, drift, `FormatException`) goes to the
  queue as `HiddenDetailsError`: the type of the original, no message. The module does it on its
  own (`hideDataDetails`, the default `hideDetails` of `startTelemetry`), so do not wrap these
  yourself; the log on the machine keeps the hidden form too, the full text goes only to the console. Another type whose text holds data goes into
  `hideDataDetails` with a test, or the app passes its own `hideDetails`.
- **Firebase Crashlytics** is a gateway behind the queue, like Sentry: the queue cleans, splits
  and counts, the gateway only sends (`recordError`) what it is given. Never assign
  `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError` (or
  `PlatformDispatcher.instance.onError` the same way): that path sends the raw error, with no
  cleaning, no `isExpectedFailure` and no consent. Keep collection off until the user's switch
  is on (`setCrashlyticsCollectionEnabled`).
- **Never in a log line or an error message:** a token, a password, an API key, a card number, a
  customer's phone. The cleaning is the last net, not the plan.

## Untrusted input

Everything that comes into the app is checked before it is used, the app's own backend included:
anyone can change a response with Burp or a patched app. That covers API responses, deep links
and push payloads, data from platform channels and intents, files the user opens, scanned QR
codes and text fields.

- JSON is parsed with patterns into the app's models (see "Patterns" in `docs/rules/dart.md`):
  a field of the wrong type or a missing one is a `FormatException`, not a crash three screens
  later.
- A deep link or a QR code is a request from a stranger: allow only the routes you expect, parse
  its parameters like JSON, and never let it pick a URL the app then opens with credentials.
- A link from content (a chat message, markdown, a server field) is opened only with an allowed
  scheme (`https`, `mailto`, `tel`): `javascript:`, `intent:` or `file:` URLs reach `url_launcher`
  as easily as `https:`.
- Flutter's own widgets draw text, they do not run it: a `<script>` in a `Text` is just text.
  Script injection (XSS) starts where HTML is rendered: a `WebView` with JavaScript on, a package
  that renders server HTML into a web view, or `HtmlElementView` and `innerHTML` on the web. Load
  only your own pages there, keep JavaScript off for content, and restrict navigation to your
  hosts.
- What the user is entitled to (a balance, the gold bought in a game, a price) comes from the
  server's answer to an action the server checked, never from a number the app sends.

## Network traffic

HTTPS encrypts the whole request (path, query, headers, body), so nobody on the network between
the user and the server reads or changes it, unless the device trusts a certificate authority
the attacker controls.

- **The device's owner can always read their own traffic**: install their own CA (on a rooted
  device as a system CA), or patch the app with reFlutter, which also routes it through Burp. What
  they get is their own token, so a token is not a secret from the user who holds it; the threat
  is someone else's token taken remotely, which TLS prevents.
- Every URL is `https`. Android's cleartext block and iOS's App Transport Security apply to the
  platforms' own networking; `dart:io` opens its own sockets, so an `http://` base URL in a
  Flutter app simply works, in plain text. Reject `http` in the API client, outside local
  development.
- Never ship `badCertificateCallback = (_, _, _) => true` (or a Dio adapter that accepts every
  certificate): copied in to reach a development server with a self-signed certificate, it lets
  anyone on the network read and change every request. Trust a development CA in debug builds only.
- Sensitive data does not travel in SMS or push notifications: their text is shown on the lock
  screen and kept by the platform. A push says that something happened; the app fetches the
  details over HTTPS.
- `dart:io`'s `HttpClient` trusts the platform's built-in roots and takes a proxy only from
  environment variables (`http_proxy`), not from the phone's Wi-Fi proxy setting; that is why a
  Flutter app does not show up in a proxy the way a native one does. A platform client
  (`cronet_http`, `cupertino_http`) follows the platform's proxy and trust settings instead.
- **Certificate pinning** (trusting only your own certificate authority or key) also refuses a CA
  the device trusts but you do not: a corporate proxy, a malicious profile. It costs a release
  whenever the server's certificate chain changes: pin the issuing CA or the public key, ship a
  backup pin, and plan the rotation. It does not stop the device's owner, who patches the check
  out. With `dart:io`: `SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(pem)`
  passed to `HttpClient(context: ...)`; the SDK notes that some of these methods are not
  implemented on iOS, so check pinning on every platform you ship. Use it when the threat model
  names such an attacker (banking, payments), not by default.

## Tokens

An access token is short-lived (minutes to an hour) and goes with every request; a refresh token
is the session, exchanged for new access tokens. A JWT access token is signed, not encrypted:
anyone can read its payload (`sub`, `exp`, roles), nobody can change it without the key. The app
may read `exp` to refresh ahead of time; deciding what the user may do from the claims is the
server's job, which checks the signature (one call with Firebase: `verifyIdToken` in the Admin
SDK). See "What the server checks".

- One object owns the tokens in memory: `AuthSession`. The authentication middleware, the sign-in
  state and a socket ask it for the token or are called back by it; none keeps a copy. A second
  copy (a cache in the middleware fed by a storage stream, the tokens in the controller's state)
  is stale after the next refresh or sign-out.
- Keep the tokens out of the state that widgets rebuild on: a refresh every few minutes would
  make a new state and rebuild everything below its scope, for nothing the screen shows. The
  authentication state holds the user (see "Users, user info and sessions" in
  `docs/rules/architecture.md`).
- The authentication middleware of the HTTP client gets callbacks, not the storage (see "Callbacks
  instead of references" in `docs/rules/dependencies.md`): ask for the token, and report a 401.
- Refresh before the token expires, not after the first 401: a minute of margin. A 401 still
  triggers a refresh (the server may revoke a token early), but refreshing ahead spares the
  requests near the expiry a failed first attempt and a second round trip.
- Only an access token, without a refresh token, works when it lives long; then signing out on
  another device or a ban takes effect only when it expires. A short access token with a refresh
  token gives both: requests checked without a database, and sessions the server can end.
- Requests that need a refresh at the same time share one: ten requests with an expired token
  start one refresh, not ten, and the refresh token is not spent ten times. Share the refresh
  future, not a lock around every request: serializing all requests makes each wait for the one
  before it.
- With refresh token rotation (the server answers a refresh with a new refresh token and
  invalidates the old one), a spent refresh token sent again is taken as stolen: RFC 9700 (OAuth
  security best practice, 4.14.2) has the server then revoke the active one, which signs the user
  out. Two parallel refreshes do exactly that, one more reason for sharing one.
- Rotation also orders the writes: the new pair is in memory and in the store before the request
  is retried (checked: `accessToken()` completes only after the store's `write`). A process killed
  before the write leaves a dead refresh token on the device: the user signs in again. Refresh on
  demand, before a request, as `AuthSession` does: no timer refreshes while the app is in the
  background.
- A 401 for a token that has already been replaced is retried with the new one, without a
  refresh. The token to compare is the one the failed request carried, read back from its
  `Authorization` header: by the time the response arrives, memory may hold a newer one.
- The refresh call and the retry do not go through the authentication middleware again (see
  "HTTP middleware" in `docs/rules/dependencies.md`): a 401 for the refresh itself must not start
  another refresh.
- The refresh rejected (401 or 403): sign out. A network error during the refresh: keep the user
  signed in and fail the request.
- Sign-out forgets the tokens in memory and tells the app at once, clears the store, and asks the
  server to revoke the refresh token without waiting for the answer. A sign-out that first awaits
  the server fails offline and leaves the user signed in; a revocation that never arrives costs
  less, the token expires on the server. A refresh still running when the user signs out is
  discarded, and the refresh token it brought back is revoked too, so it cannot sign the old
  session back in (checked).
- At startup, the stored tokens are read with a timeout, since the store is a platform channel
  that can fail or hang: a store that fails or does not answer in time means signed out. This read is awaited before
  the first screen, since that screen depends on it; anything that calls the network is not (see
  "Startup and creating dependencies" in `docs/rules/dependencies.md`).
- When a vendor SDK owns sign-in (Firebase Auth, Supabase), it stores and refreshes the tokens
  itself: do not store them again and do not write a second refresh. The middleware asks the SDK
  per request: `await user.getIdToken()` returns the cached token and refreshes it only when
  expired; with Supabase, `auth.currentSession?.accessToken`.
- Ending a session (sign-out on another device, a ban, an unpaid account) is the server's: it
  deletes the refresh token, and keeps the access token on a deny list for the rest of its life.

`auth_session.dart` (in Examples) does all of this; `ApiClient$AuthenticationMiddleware` (in "HTTP
middleware" in `docs/rules/dependencies.md`) calls `accessToken()` for every request and
`onUnauthorized(token)` on a 401, then retries once.

### What the server checks

A JWT is trusted only after the server has checked all of it, not just the signature:

- The signature, with the algorithm the server expects. Never take the algorithm from the token's
  own `alg` header (`none`, or HS256 keyed with an RSA public key, are the classic forgeries).
- The key, by the token's `kid`, from the issuer's published key set (JWKS). Keys rotate: cache
  the set, and fetch it again once when a `kid` is unknown.
- `exp` (and `nbf`), with a small allowance for clock skew.
- `aud` and `iss`: the token was issued for this project by the expected issuer. A token signed
  by the same provider for another project passes the signature check.
- Revocation, where it matters: Firebase's `verifyIdToken(token, checkRevoked: true)` makes an
  extra call to Firebase Auth; without it, a revoked user's ID token is accepted until it expires
  (ID tokens live an hour).

`verifyIdToken` in the Firebase Admin SDK checks the signature, the expiry, the project (`aud`)
and the issuer; a verifier written by hand must check all of them.

### Sign-in through a browser (OAuth)

Google, Apple, GitHub and any OAuth or OpenID Connect provider sign the user in on the provider's
page:

- Open it in the system browser or the platform's sign-in session (`ASWebAuthenticationSession`
  on Apple platforms, Custom Tabs on Android), through the provider's SDK, `flutter_appauth` or
  `flutter_web_auth_2`. Never in a `WebView`: the app would see the user's password, and Google
  answers a sign-in from an embedded web view (`WKWebView` included) with `disallowed_useragent`.
- Use the authorization code flow with PKCE (RFC 7636): the app makes a random `code_verifier` and
  sends its SHA-256 (`code_challenge`, method `S256`) with the request; the code that comes back is
  useless without the verifier, so another app registered for the same redirect cannot use it.
  RFC 9700 requires PKCE for apps and says not to use the implicit flow, which returns the tokens
  themselves in the redirect URL. Checked: `supabase_flutter` 2.18 defaults to
  `AuthFlowType.pkce`.
- The redirect is a deep link into the app: prefer an `https` App Link or Universal Link to a
  custom scheme, which any app can register (Google no longer accepts custom schemes for Android
  clients). A desktop app on macOS, Windows or Linux uses a loopback redirect
  (`http://127.0.0.1:<port>`, RFC 8252), which Google recommends for desktop clients.
- The sign-in method has no result to return. It opens the browser and returns; the session
  arrives later, on the authentication stream, when the redirect brings the user back. The
  controller goes `processing` → `idle` when the browser opens, not `successful`, and takes the
  signed-in user from the stream, its single source. The user may close the browser and never
  come back, so no spinner waits for the redirect.
- Pick one path for the signed-in state: the stream. A password sign-in that returns the session
  while the stream also reports it updates the state twice for one event.

### Expected errors

A wrong password, a taken email or a weak password is the server's answer, not a failure of the
app. The data layer reads the server's error code from the `APIClientException`'s `data` and maps
it to the app's exception (`RejectedException(code: 'invalid_credentials')`, see "Errors" in
`docs/rules/repositories.md`), the screen shows it through `errorText`
(`docs/rules/localization.md`), and it is not reported. In the controller there is nothing to catch: the observer sees every error, and
`isExpectedFailure` keeps the expected ones (every `ExpectedException`, a `RejectedException`
included) out of the crash reporter, while `error:` sets the `error` state for all of them (see "Where the error goes" in
`docs/rules/controllers.md`):

```dart
void signIn(String email, String password) => handle(
  () async {
    setState(AuthState.processing(user: state.user));
    await _repository.signIn(email, password); // the user arrives on the stream
  },
  error: (error, stackTrace) async => setState(AuthState.error(user: state.user, error: error)),
  done: () async => setState(AuthState.idle(user: state.user)),
);

/// The app's one decision, used by the reporter behind the observer: the failures that are
/// answers to the user or conditions of the environment, not bugs.
bool isExpectedFailure(Object error) => switch (error) {
  ExpectedException() => true, // RejectedException included, with any code
  APIClientException$Network() => true, // no connection, a 5xx
  APIClientException$Authorization() => true, // the middleware refreshes or signs out
  TimeoutException() => true,
  SocketException() => true, // dart:io, so VM only: a web build leaves this case out
  _ => false,
};
```

Every `ExpectedException` is expected (`error is ExpectedException`), a `RejectedException` with
any code included: the server
said no and the screen shows its text. A failure that is a bug is not an `ExpectedException`:
the data layer does not turn a code it cannot place into a rejection, it passes the client's own
exception on, and that one is reported. A type the project does not own (a `PlatformException`
with a known code, say) is added as one more case in `isExpectedFailure`, never in a `catch`.
The list of expected failures lives in the type hierarchy and in this one function, not in a
list of codes.

### Storing tokens

The refresh token is the session, so it goes where the platform protects it:

- **Android**: the Keystore. `flutter_secure_storage` 10 and later encrypt with AES-GCM under a
  Keystore key by default; 9 used AES-CBC, and its `encryptedSharedPreferences` option (Jetpack
  Security, now deprecated) is gone in 11. Upgrade from 9 through 10, which migrates the stored
  data, before 11: a direct jump loses it. Plain `SharedPreferences` is
  an XML file that Android's Auto Backup copies to the user's cloud and restores on another device
  unless the app excludes it.
- **iOS**: the Keychain, with an accessibility that keeps it on this device. `flutter_secure_storage`
  defaults to `unlocked`, which lets the item move to a new device through an encrypted backup; set
  `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)` (also readable in the
  background, for a refresh from a push). `UserDefaults` goes into every backup.
- **Web**: there is no safe place for JavaScript. A refresh token readable by the page is stolen by
  any XSS; only an `HttpOnly`, `Secure`, `SameSite` cookie set by the server is out of the page's
  reach. Keep the access token in memory only.

The storage is a platform channel, slow and with a history of bugs (lost items after a major
upgrade, failures under concurrent access): read it once at startup (`AuthSession.restore`), write
it only on sign-in and refresh, put it behind one `ITokenStore`, and treat a missing or unreadable
item as "signed out", never as a crash. Nothing that cannot be recreated by signing in again is
kept there alone.

### Biometrics

`local_auth` returns `true` or `false`, and a hooked app (Frida on a rooted device) returns `true`.
Use it to confirm a person is there, not to protect anything. To protect a secret, the platform
must refuse to release a key without the biometric check:

- Android: a Keystore key with `setUserAuthenticationRequired(true)` and
  `setInvalidatedByBiometricEnrollment(true)`, used through `BiometricPrompt` with a
  `CryptoObject`.
- iOS: a Keychain item or a Secure Enclave key with the `biometryCurrentSet` access control, so a
  new fingerprint or face invalidates it.

`flutter_secure_storage` 11 (`AndroidOptions.biometric()`), `biometric_storage` and
`biometric_signature` wrap these; read what a package does on each platform before relying on it.
A PIN works the same way: the attempts are counted by the server, or a reinstall resets them.

## Dependencies

Every package runs with the app's rights: a malicious update of one (as with `event-stream` on
npm) reads what the app reads.

- `pubspec.lock` holds the exact version and the SHA-256 of every hosted package (since Dart
  2.19). Commit it for apps; packages do not commit it, so their users resolve fresh versions.
- CI and release builds run `flutter pub get --enforce-lockfile`: it fails when the lockfile does
  not match `pubspec.yaml` or a downloaded archive does not match its hash, instead of updating
  the lockfile.
- With the lockfile committed and enforced, `^` constraints in `pubspec.yaml` change nothing until
  someone runs `pub upgrade` and commits the result; review that diff like code.
- `pub get` reports known vulnerabilities from the GitHub Advisory Database; fix them or record why
  in `ignored_advisories` in `pubspec.yaml`. Dependabot (`package-ecosystem: "pub"`) or
  `osv-scanner --lockfile=pubspec.lock` watch for new ones.
- Git and path dependencies have no hash: pin a git dependency to a commit (`ref:`), never a
  branch.
- Prefer verified publishers, and read the code of any package that touches credentials, the
  network or storage before adding it (see `docs/rules/package-freshness.md`).

## Examples

### `auth_session.dart`

```dart
// file: auth_session.dart
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// The tokens of a signed-in user.
@immutable
final class Tokens {
  const Tokens({required this.access, required this.refresh});

  /// Short-lived: sent with every request.
  final String access;

  /// The session: exchanged for a new access token.
  final String refresh;
}

/// Where the tokens survive a restart: the Keychain or the Keystore.
abstract interface class ITokenStore {
  Future<Tokens?> read();

  Future<void> write(Tokens tokens);

  Future<void> clear();
}

/// The latest time a [DateTime] can hold, in seconds since the epoch.
const int _maxEpochSeconds = 8640000000000;

/// When [jwt] expires, from its `exp` claim; `null` when it is not a JWT or has no valid `exp`.
///
/// A JWT is signed, not encrypted: anyone can read it. Use the expiry to refresh ahead of time;
/// never decide from its claims what the user may do, since only the server checks the signature.
DateTime? jwtExpiry(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) return null;
  try {
    // base64url without padding, not base64: `normalize` adds the padding back.
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    // Seconds since the epoch. A JSON number: `1700000000`, but also `1.7e9`, which is a double.
    if (payload case {'exp': final num exp} when exp >= 0 && exp <= _maxEpochSeconds) {
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(), isUtc: true);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Holds the tokens in memory, refreshes the access token shortly before it expires, and lets
/// requests that need a refresh at the same time share one.
///
/// The one owner of the tokens: the HTTP client's authentication middleware calls [accessToken]
/// for every request and [onUnauthorized] on a 401, and keeps no copy; the storage is read once, in
/// [restore].
final class AuthSession {
  AuthSession({
    required this._store,
    required this._refresh,
    required this._onSignedOut,
    this._revoke,
    this.margin = const Duration(minutes: 1),
    this.readTimeout = const Duration(seconds: 3),
  });

  /// How long before expiry the access token is refreshed.
  final Duration margin;

  /// How long [restore] waits for the store before it gives up and starts signed out.
  final Duration readTimeout;

  final ITokenStore _store;

  /// Returns new tokens, or `null` when the server rejected the refresh token (the session ended);
  /// throws on a network error, which keeps the user signed in.
  ///
  /// Sent through a client without the authentication middleware: a 401 for the refresh itself
  /// must not start another refresh.
  final Future<Tokens?> Function(String refreshToken) _refresh;

  /// Asks the server to end the session of [refreshToken]; nothing waits for it.
  final Future<void> Function(String refreshToken)? _revoke;

  final void Function() _onSignedOut;

  Tokens? _tokens;
  Future<Tokens?>? _refreshing;

  /// Whether a user is signed in.
  bool get isSignedIn => _tokens != null;

  /// Reads the stored tokens, once at startup, before the first screen is chosen.
  ///
  /// A store that fails or does not answer within [readTimeout] (a locked device, a broken
  /// Keystore item) means "signed out": the user signs in again.
  Future<void> restore() async {
    try {
      _tokens = await _store.read().timeout(readTimeout);
    } on TimeoutException {
      _tokens = null;
    } on Exception {
      _tokens = null; // a PlatformException from the store: unreadable is "signed out"
    }
  }

  /// Keeps the tokens of a new sign-in.
  Future<void> signIn(Tokens tokens) async {
    _tokens = tokens;
    await _store.write(tokens);
  }

  /// Signs out here first, then asks the server to end the session without waiting for it: a
  /// sign-out works offline, and a refresh token the server never heard about expires there.
  Future<void> signOut() => _end(revoke: true);

  /// The access token for a request, refreshed first when it expires within [margin].
  Future<String?> accessToken() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    final expiry = jwtExpiry(tokens.access);
    if (expiry != null && !clock.now().toUtc().isBefore(expiry.subtract(margin))) {
      return (await _refreshOnce())?.access;
    }
    return tokens.access;
  }

  /// After a 401: the token to retry with, or `null` once signed out.
  ///
  /// [failedToken] is the token the failed request was sent with, read back from its
  /// `Authorization` header: by the time the response arrives, memory may hold a newer one.
  Future<String?> onUnauthorized(String failedToken) async {
    final current = _tokens?.access;
    // Another request has already refreshed it.
    if (current != null && current != failedToken) return current;
    return (await _refreshOnce())?.access;
  }

  Future<Tokens?> _refreshOnce() =>
      _refreshing ??= _refreshTokens().whenComplete(() => _refreshing = null);

  Future<Tokens?> _refreshTokens() async {
    final current = _tokens;
    if (current == null) return null;
    final tokens = await _refresh(current.refresh);
    if (!identical(_tokens, current)) {
      // Signed out (or in as someone else) while the refresh ran: its answer must not sign the
      // old session back in. End the session the server has just extended.
      if (tokens != null) _revoke?.call(tokens.refresh).ignore();
      return null;
    }
    if (tokens == null) {
      await _end(revoke: false); // the server has already ended it
      return null;
    }
    // A rotating refresh token is spent once the server answers: store the new pair before the
    // request is retried.
    await signIn(tokens);
    return tokens;
  }

  Future<void> _end({required bool revoke}) async {
    final refreshToken = _tokens?.refresh;
    _tokens = null;
    _onSignedOut();
    if (revoke && refreshToken != null) _revoke?.call(refreshToken).ignore();
    await _store.clear();
  }
}
```
