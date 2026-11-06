---
name: configuration
description: "Build-time configuration with --dart-define, no .env assets, what assets and fonts ship, and generated icon fonts and asset paths."
---

# Configuration

## Rules

- Build-time values (API URL, flavor, public keys) come from `--dart-define` or
  `--dart-define-from-file`, read with `const String.fromEnvironment(...)`. No `flutter_dotenv`
  and no `.env` file among the assets.
- Everything in `assets` ships inside the app, readable by anyone who has it (on the web it is a
  plain `GET` away). Never put credentials there. `.gitignore` keeps a `.env` out of git, not out of
  the app: listed in `assets`, it still ships, and a web build serves it to anyone.
- No secret belongs on the client at all: anything compiled into or shipped with the app can be
  extracted. A key the app must have is restricted on the provider's side instead. See
  `docs/rules/security.md`.
- Fonts go under `flutter: fonts:`, not `assets`.
- The version is `MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`: semantic versioning for the name, and
  a build number that grows with every build, set by CI. See "Versioning".
- Every change users or developers should know about adds an entry to `CHANGELOG.md` under
  `[Unreleased]` in the same pull request; a release turns that section into the new version. See
  "Changelog".

## Build-time values

Pass values to the build and read them as compile-time constants:

```bash
flutter run --dart-define=API_URL=https://api.example.com --dart-define=FLAVOR=dev
flutter build apk --dart-define-from-file=config/prod.json
```

```dart
// lib/src/_core/config/config.dart
abstract final class Config {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.example.com',
  );
  static const String flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const bool isProduction = flavor == 'prod';
}
```

- Read them only in `const` expressions: `String.fromEnvironment`, `bool.fromEnvironment` and
  `int.fromEnvironment` are guaranteed only when evaluated as constants.
- `--dart-define-from-file` takes a `.json` or a `.env` file; repeat the flag for several files, and
  a `--dart-define` with the same key wins. The file stays on the build machine: only the values
  are compiled in. (That is the difference from `flutter_dotenv`, which ships the `.env` file
  itself as an asset.)
- In CI, take the values from the CI's secrets: `--dart-define=MAPS_KEY=${{ secrets.MAPS_KEY }}`.
- Where `--dart-define` cannot be used, generate a Dart file before the build, keep it out of git,
  and import its constants:

```bash
echo "const String mapsKey = '$MAPS_KEY';" > lib/src/_core/config/env.dart
```

- Keep one `Config` (in `_core/config/`) as the only place that reads the environment; the rest
  of the app imports its constants.

## Flavors

A flavor is one more app built from the same code: its own application and bundle ID, name, icon,
splash, Firebase app and signing key. `flutter run --flavor globex` picks the Gradle product
flavor of that name on Android, the Xcode scheme of that name on iOS and macOS, a separate build
folder on Windows and Linux, and in Dart sets `appFlavor` (`package:flutter/services.dart`), a
compile-time constant. The web has no flavors.

- **Flavor and environment are two things.** The flavor says which app (a brand, a store
  listing); the environment says which backend and settings, from
  `--dart-define-from-file=config/<flavor>/<environment>.json`. A staging build is a flavor only
  when it must be installed next to the production app (its own `applicationIdSuffix`); otherwise
  it is an environment of the same app.
- **Dart reads the flavor as constants** (`app_brand.dart`): `AppBrand.current` and the brand's
  names, logos and accent colors are `static const`, so `const` widgets keep working and the
  other brand's branches are removed from the build. Not `static get`, which turns every check into
  a run-time one. Business logic is the same for every flavor; only presentation and
  configuration differ, and a brand-specific widget is chosen in one place.
- **Check the combination at startup**: every config file carries a `BRAND` key, and
  `validateBrandBuild()` stops the app when the config belongs to another flavor, instead of
  building one brand pointed at the other's server. Every config file has the same keys.
- `pubspec.yaml`: `default-flavor: <name>` keeps plain `flutter run` (and builds without a flavor)
  working once Android has product flavors. Assets only one brand ships go under
  `- path: assets/brands/globex/` with `flavors: [globex]`; builds of other flavors, and
  `flutter test` without `--flavor globex`, do not have them.
- **Native checklist.**
  - Android: `productFlavors` with the same names. The label is `@string/app_name` from
    `src/<flavor>/res/values/strings.xml`, and anything in `src/<flavor>/` replaces `src/main/`.
    The `signingConfig` goes on each flavor and none on the `release` build type, which would
    override it. `google-services.json` needs a client for every application ID, or the build
    fails.
  - iOS: `Debug-<flavor>`, `Profile-<flavor>` and `Release-<flavor>` configurations, each with an
    xcconfig, plus a **shared** scheme named exactly like the flavor. The Podfile maps every new
    configuration to `:debug` or `:release`. `PRODUCT_BUNDLE_IDENTIFIER` and the app icon set are
    set per configuration, `Info.plist` reads the name from an xcconfig variable, and a build phase
    copies the flavor's `GoogleService-Info.plist`.
  - Icons and splash: one `flutter_launcher_icons-<flavor>.yaml` and
    `flutter_native_splash-<flavor>.yaml` per flavor. Once flavor files exist, the plain
    `flutter_launcher_icons.yaml` is ignored.
- **Builds**: outputs get the flavor in their path
  (`build/app/outputs/bundle/globexRelease/app-globex-release.aab`), so copy each one away before
  building the next. CI runs one job per flavor, with that flavor's secrets. Google Play takes the
  first upload of a new app only by hand.

### `app_brand.dart`

```dart
// file: app_brand.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;

/// The flavor this build was made with; builds without one (web, tests) are the default brand.
const String kFlavor = appFlavor ?? 'acme';

/// Whether this is the Globex app: a constant, so the other brand's code is removed.
const bool kIsGlobex = kFlavor == 'globex';

/// The apps built from this code.
enum AppBrand {
  acme,
  globex;

  /// The brand of this build.
  static const AppBrand current = kIsGlobex ? globex : acme;
}

/// What differs between the brands' presentation.
@immutable
final class BrandConfig {
  const BrandConfig._({required this.appName, required this.logoAsset});

  static const BrandConfig current = kIsGlobex
      ? BrandConfig._(appName: 'Globex', logoAsset: 'assets/brands/globex/logo.png')
      : BrandConfig._(appName: 'Acme', logoAsset: 'assets/brands/acme/logo.png');

  final String appName;
  final String logoAsset;
}

/// Stops the app when the flavor is unknown or the config file belongs to another brand.
void validateBrandBuild() {
  if (appFlavor case final String flavor
      when !AppBrand.values.any((brand) => brand.name == flavor)) {
    throw StateError('Unknown flavor "$flavor"');
  }
  const configBrand = String.fromEnvironment('BRAND');
  if (configBrand.isNotEmpty && configBrand != AppBrand.current.name) {
    throw StateError('The config is for "$configBrand", but this is the ${AppBrand.current.name} app');
  }
}
```

## Versioning

`version: 1.4.2+1777062097` in `pubspec.yaml` is the version name (`1.4.2`, shown to users and in
the stores) and the build number (after the `+`). `flutter build --build-name=1.4.2
--build-number=...` overrides both, which is how CI sets them.

- **The name: semantic versioning.** It tells a reader what kind of update this is: a patch for a
  fix, a minor version for features, a major one for a change that breaks what users or other
  apps rely on. Calendar versions (`26.4.25`) say only when; several builds on one day (a hotfix,
  a staging or beta build, a web or self-hosted release that skips store review) then need a
  build number anyway.
- **The build number: always larger than the last one**, across every build that may be
  installed, staging and beta included. The stores require it: Google Play rejects a
  `versionCode` it has seen, and App Store Connect one that is not higher for the same version.
- **Unix time works as the build number** (`--build-number=$(date +%s)`): it always grows, and no
  counter has to be stored anywhere. Its limits:
  - Android's `versionCode` may be at most 2,100,000,000, which Unix time reaches on 2036-07-18.
    With `--split-per-abi`, Flutter adds 1000, 2000 or 4000 per ABI, which still fits.
  - Windows keeps each part of a file version in 16 bits (at most 65535), so a ten-digit build
    number does not fit; MSIX packages have the same limit. A Windows build needs a small number:
    the CI run number, or the days since a fixed date.
  - Where those limits bite, use the CI run number (`github.run_number`) everywhere.
- On the web, `flutter build web` writes the version and the build number to `version.json`, which
  `package_info_plus` reads; on the other platforms they end up in the platform's own fields.

### Changelog

`CHANGELOG.md` at the root of the project lists every release, newest first. New projects start
with one.

```markdown
## [Unreleased]

## [1.4.0] - 2026-11-06

### Added

- Orders can be filtered by status and date on the orders screen.

### Improved

- The product list keeps its scroll position after a refresh.

### Fixed

- Signing out on one device no longer signs the user out on the others.

### Technical

- Upgraded to Flutter 3.47 and moved the database to drift 2.35.
```

- One section per release: `## [<version>] - <YYYY-MM-DD>`, with the version name from
  `pubspec.yaml` without the build number. A build that only raises the build number (a staging
  upload, a rebuilt release) gets no section.
- Inside it, only the groups that have entries, in this order: `Added` (new features), `Improved`
  (changes to what exists), `Fixed` (bugs), `Technical` (upgrades, CI, refactors users do not see).
- An entry is one or two sentences about what changed for the person who uses the app: the
  screen, the action, the result. Not the files, classes or commits; the pull request has those.
- Every pull request with such a change adds its entry under `## [Unreleased]`, so nothing has to
  be reconstructed from the history at release time.
- A release, in one commit: rename `[Unreleased]` to the new version and today's date, add an
  empty `## [Unreleased]` above it, and raise `version:` in `pubspec.yaml`. The entries choose the
  step: only `Fixed` and `Technical` is a patch, anything `Added` or `Improved` a minor version, a
  change that breaks what users or other apps rely on a major one.
- The section is also the source of the store's "What's new" text: shorten it, do not rewrite it.

## Secrets

Secrets, obfuscation and what an installed app gives away: `docs/rules/security.md`.

## Assets and fonts

- Every file listed under `flutter: assets:` is bundled with the app: it makes the app bigger, and
  on the web each one is downloaded with a `GET` to the web server. List only what the app shows,
  and do not ship sources (design files, unused SVGs).
- Fonts are declared under `flutter: fonts:`. That section takes only fonts, and icon fonts are
  tree-shaken in release builds (`--tree-shake-icons`, on by default): only the glyphs the code
  uses, through constant `IconData`, stay in `MaterialIcons` and other icon fonts. Text fonts ship
  whole: include only the weights the design uses.
- Prefer WebP to PNG and JPEG for raster images: often a third smaller or more at the same quality.
  It matters most on the web, where every asset the first screen needs is downloaded before it
  appears. Keep the PNG sources and convert at build time with the `webp` transformer (below), so
  no path changes; or convert once with ImageMagick (with WebP support), then update every
  reference in `pubspec.yaml` and the code from `.png` to `.webp`:

```bash
cd assets
find . -name '*.png' -exec mogrify -format webp {} \;   # writes x.webp next to x.png
find . -name '*.png' -delete                            # only after checking the results
```

- Asset paths typed as strings fail only at run time. Generate them: `spider` (dev dependency,
  `dart run spider build`) reads `spider.yaml` and writes a class of `static const String` paths
  per group. Set `use_part_of: false` (the file `spider create` writes has `true`, and the rules
  use no `part` files), and `generate_tests: true` for a test that each file exists (it imports
  `package:test`, so add `test` to `dev_dependencies`). Checked with spider 4.2.3:

```yaml
# spider.yaml
generate_tests: true
no_comments: true
export: true
use_part_of: false
package: src/_core/resources        # lib/src/_core/resources/images.dart
groups:
  - path: assets/images
    class_name: Images               # Images.logo == 'assets/images/logo.png'
    types: [ .png, .webp ]
```

  A class of paths is not a "magic numbers" constants file: paths are not design values. Icons in
  a font need no paths at all (`AppIcons.search`).


### Icons

- **Icons are a font.** The app's icons, drawn as SVGs by the designer, are turned into one icon
  font (IcoMoon, Fontello, FlutterIcon or a similar generator) and used as `const IconData`
  constants (`static const IconData home = IconData(0xe800, fontFamily: 'AppIcons')`) in the
  `Icon` widget. A glyph is drawn like text: no loading, no parsing, the color and size come from
  `IconTheme`, and it scales with the text. A release build keeps only the glyphs the code uses
  (icon tree shaking is on by default); a non-`const` `IconData` anywhere makes that build fail,
  and each icon font family must be a single font file.
- **The font is generated from the SVGs** by the designer's tool or on the command line with
  `icon_font_generator` (dev dependency). It writes the `.otf` and a class of `static const
  IconData` constants; register the font under `flutter: fonts:` with the same family name.
  Checked with 4.1.0:

```bash
dart run icon_font_generator:generator assets/icons assets/fonts/app_icons.otf \
  --font-name AppIcons --class-name AppIcons \
  --output-class-file lib/src/_core/design/app_icons.dart --no-ignore-shapes
```

  `--no-ignore-shapes` turns `<circle>`, `<rect>` and other shapes into paths (by default they
  are skipped); `-r` also reads subfolders. Never edit the outputs: re-run the command when an
  icon changes and keep the font and the class from the same run. A build does not run it, so
  commit both, or run it in CI before building.
- **Multi-colour illustrations** are compiled when the app is built (the `vector_graphics_compiler`
  transformer below) and shown with `VectorGraphic(loader: AssetBytesLoader('assets/x.svg'))`.
- **Simple shapes** (a notch, a badge, a divider with a curve) are a `CustomPainter`.
- **`flutter_svg` at run time** is for SVGs that only arrive at run time. It compiles each
  distinct SVG from XML into a `vector_graphics` picture on first use (in an isolate through
  `compute`, which on the web runs on the main thread), keeps up to 100 compiled results, and
  keeps the picture only while a widget shows it. It does not reparse on every frame, but a list
  where every row shows different SVG icons compiles each of them, and on the web every SVG
  asset is one more download.

### Asset transformers

An asset can be transformed while the app builds, so the repository keeps the source and the app
ships the result (Flutter's "Asset transformation" docs). The transformer is a package in
`dev_dependencies`, and the asset keeps its path:

```yaml
flutter:
  assets:
    - path: assets/photo.png
      transformers:
        - package: webp            # to WebP (cwebp); args: ['--quality=75']
    - path: assets/logo.svg
      transformers:
        - package: vector_graphics_compiler
```

- `webp`: raster images to WebP. `Image.asset('assets/photo.png')` still works: Flutter decodes
  by content, not by extension.
- `vector_graphics_compiler`: an SVG to the binary format of `vector_graphics`, which loads without
  parsing XML at run time. Show it with `VectorGraphic(loader: AssetBytesLoader('assets/logo.svg'))`
  (or `SvgPicture(AssetBytesLoader(...))` from `flutter_svg`), not `SvgPicture.asset`.
- What `vector_graphics` caches (checked in 1.2.3): `AssetBytesLoader` does not cache bytes (its
  doc). Widgets that show the same asset at the same time share one decoded picture (a
  reference-counted cache keyed by the loader's `cacheKey`, the locale, the text direction and
  `clipViewbox`), and loads of the same key that overlap run once. When the last widget showing it
  goes, the picture is disposed: the next one reads and decodes the asset again, and shows nothing
  until that finishes. Raster images embedded in the SVG go through `imageCache`.
- `jovial_svg_transformer`: SVG to `jovial_svg`'s binary format, for apps that render with
  `jovial_svg`.

### Web bundle size

What makes a Flutter web app slow to open is its first download: the engine (CanvasKit or skwasm,
several megabytes of WebAssembly), `main.dart.js`, and the assets.

- Fewer and smaller assets: drop unused ones, WebP instead of PNG, no SVG that a font icon or a
  compiled vector would replace.
- Split the code with deferred imports. On the web, every `deferred as` library becomes its own
  `.part.js`, downloaded when `loadLibrary()` is first awaited: the total stays the same, but the
  first screen arrives sooner. On other platforms the library ships in the app and `loadLibrary()`
  just completes.

```dart
import 'reports_screen.dart' deferred as reports;

Future<void> openReports(BuildContext context) async {
  await reports.loadLibrary();
  if (!context.mounted) return;
  AppNavigator.push(context, reports.ReportsPage());
}
```

- Show a real splash in `web/index.html` (plain HTML and CSS), so the page is not blank while the
  engine loads; Flutter replaces it when its first frame is ready.
