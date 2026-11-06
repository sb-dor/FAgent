---
name: web
description: "Flutter web: canvas renderers, the semantics tree, search engines and what belongs in plain HTML, and driving the app from Playwright or Puppeteer."
---

# Web

## Rules

- Flutter web is for apps: tools, dashboards, anything behind a sign-in, a mobile app also opened
  in a browser. A site that must be found by search (landing, marketing, blog, docs, product pages)
  is plain HTML or a static site generator, next to the Flutter app, which lives under its own path
  or subdomain. See "Search engines".
- Every Flutter web app draws on a canvas, with CanvasKit or skwasm. The HTML (DOM) renderer was
  removed in Flutter 3.29, so `--web-renderer html` and advice built on it ("DOM on mobile, canvas
  on desktop") are out of date. See "Renderers".
- Text on the canvas is not in the page: browser search (Ctrl+F), translators, extensions,
  crawlers and DOM selectors see it only through the semantics tree, which is off until something
  turns it on. See "Semantics".
- Every control a user, a screen reader or a browser test must find has a label: Material buttons
  take theirs from the text, an `IconButton` needs `tooltip`, an image `semanticLabel`. Controls a
  browser test selects also get `Semantics(identifier: '...')`.
- Integration tests on the web run only through `flutter drive`: see "Integration tests" in
  `docs/rules/testing.md`. The download size is in "Web bundle size" in
  `docs/rules/configuration.md`.

## Renderers

| Build | Renderer | Notes |
|---|---|---|
| `flutter build web` | CanvasKit | Skia compiled to WebAssembly, the app to JavaScript. Works in every current browser. |
| `flutter build web --wasm` | skwasm | Smaller and faster than CanvasKit, the app to WebAssembly. Needs WasmGC; older browsers get the JavaScript and CanvasKit build instead. |

skwasm uses a separate render thread only when the page is cross-origin isolated (the server sends
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` or
`credentialless`); without them it runs single-threaded and logs a warning. Those headers also block
cross-origin iframes and resources that do not opt in, so check embeds and third-party scripts
before turning them on.

The page's DOM holds the canvas, a real `<input>` or `<textarea>` for the focused text field,
platform views (`HtmlElementView`), and the semantics tree when it is on. Text selection with the
mouse needs `SelectionArea` around the content.

## Semantics

On the web the semantics tree is a layer of `<flt-semantics>` elements over the canvas, one per
semantics node, with ARIA roles and labels. It is off by default because building and updating
those elements every frame costs time. The engine puts an off-screen
`<flt-semantics-placeholder>` button in the page; a screen reader user activates it, and the tree
appears.

Turn it on from code with `SemanticsBinding.instance.ensureSemantics()`: the first semantics update
turns on the DOM tree and removes the placeholder. It stays on while the returned `SemanticsHandle`
is not disposed. It costs every frame, so do not turn it on for every user of a production web
app: screen reader users get it through the placeholder anyway. Turn it on for a test build (a
define), or on request: a setting, or a query parameter such as `?semantics=true` for QA and
browser tests.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb &&
      (const bool.fromEnvironment('SEMANTICS') || Uri.base.queryParameters['semantics'] == 'true')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const App());
}
```

On other platforms, tests do not need it: widget and integration tests find widgets directly.

What the widgets become in the DOM:

- `Semantics(headingLevel: 1)` (1 to 6) is an `<h1>`.
- `Semantics(link: true, linkUrl: Uri.parse('https://...'))` is an `<a href>`, so middle-click,
  "Copy link" and crawlers work.
- `Semantics(identifier: 'sign-in')` adds `flt-semantics-identifier="sign-in"`. Users never see
  or hear it, so it does not interfere with what screen readers announce.
- A button is `role="button"` with its label; a text field is a real input.

For accessibility in general, what matters most is that the app is usable: labels, focus order,
keyboard navigation, contrast, and text that scales.

## Search engines

Treat SEO as not supported by a Flutter web app:

- Without semantics the body is a canvas and a few empty elements.
- With semantics on, only what is built is there: a lazy list has the visible rows, another route
  has nothing until the user opens it.
- Every URL serves the same `web/index.html`, so every page has the same `<title>` and meta tags.
- The content appears only after the engine and the app have loaded and run. Google may render
  JavaScript; many other crawlers and every link preview (messengers, social networks) do not.

So pages that must be indexed or previewed are HTML. In the Flutter app's `web/index.html`, set a
real `<title>`, `<meta name="description">` and Open Graph tags for the app's entry page, and a
`<noscript>` text.

## Caching and installing

The first visit downloads the engine and the app; a service worker makes the next ones instant.
It is a script that sits between the page and the network for its origin: every request goes
through its `fetch` handler, which answers from its cache or from the server.

- Flutter's own service worker is gone: `--pwa-strategy` is deprecated, and the
  `flutter_service_worker.js` a build writes now only unregisters itself and reloads the page. For
  caching, write a small service worker of your own (`sw.js`, cache-first for the app's files,
  network for the API), register it from `web/index.html`, and add a `web/flutter_bootstrap.js`
  that calls `_flutter.loader.load()` without `serviceWorkerSettings`, so the default one does not
  replace it.
- Name the cache after the build (a version or the build time) and delete the other caches in
  `activate`: every release replaces `main.dart.wasm` and `main.dart.js`, so the whole cache goes,
  which is fine. A cache that is never dropped keeps users on an old release.
- Serve `index.html`, `flutter_bootstrap.js`, `sw.js` and the app's files with
  `Cache-Control: no-cache` (stored, but checked with the server each time): their names do not
  change between releases, and an HTTP cache that keeps them a day shows users a mix of releases
  and fights the service worker.
- Compress: `.wasm` and `.js` shrink two to three times with Brotli or gzip. A server that sends
  them as they are makes every first visit that much slower. Firebase Hosting and most CDNs
  compress by default.
- `flutter create` already adds `web/manifest.json` and links it from `index.html`. Fill in
  `name`, `short_name`, `start_url`, `display: standalone`, the colours and the icons (192 and
  512 px, and `maskable` ones), and browsers offer to install the site as an app, opened in its
  own window.

Check the second visit in Chrome's DevTools: the Network tab with "Fast 4G" or "Offline"
throttling, and Application > Service workers to clear and update.

## Browser automation

Playwright, Puppeteer and Selenium find nothing on the canvas. To drive a Flutter web app from them:

1. Turn semantics on in the build under test: the `SEMANTICS` define above
   (`flutter build web --dart-define=SEMANTICS=true`), or a click on the placeholder from the
   script:
   `await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click())`.
2. Select by `[flt-semantics-identifier="sign-in"]`, or by role and label
   (`page.getByRole('button', { name: 'Sign in' })`).
3. Type after clicking the field: the focused field is a real `<input>`.

To open a screen, sign out or set up data without clicking through the UI, give the test build a
remote control: commands the script sends and the app runs with its own code (the navigation
controller, a repository). Two ways, both in a web-only file behind a conditional import (see
"Platform-specific code" in `docs/rules/dart.md`), and both only in a build with the define, since
anyone could call them:

```dart
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

void installTestCommands(void Function(String command) run) {
  if (!const bool.fromEnvironment('TEST_COMMANDS')) return;
  // A function on window: page.evaluate(() => window.testCommand('open-settings'))
  globalContext['testCommand'] = ((JSString command) => run(command.toDart)).toJS;
  // Or a channel, which another tab of the same origin can also post to:
  // page.evaluate(() => new BroadcastChannel('test-commands').postMessage('open-settings'))
  web.BroadcastChannel('test-commands').onmessage = ((web.MessageEvent event) {
    if (event.data.dartify() case final String command) run(command);
  }).toJS;
}
```

A `BroadcastChannel` delivers a `message` event with the posted value in `event.data`; there are no
named events like `command`. `run` switches over the commands and calls the app's code, for example
`navigation.value = [...navigation.value, const SettingsPage()]` on the controller of
`AppNavigator.controlled`. For screenshots the script needs nothing from the app:
`page.screenshot()` captures the canvas.

Use this for flows that leave the app (an HTML landing page into the app, an OAuth redirect) or
need a real browser feature. Flows inside the app are integration tests (`flutter drive -d chrome`),
written with `find` instead of selectors.
