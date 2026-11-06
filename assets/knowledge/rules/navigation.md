---
name: navigation
description: "Declarative navigation in one widget: the screen stack is a list of typed pages, changed by push, pop and guards; no routing package."
---

# Navigation

## Rules

- No routing package (`go_router`, `auto_route`, `beamer`, ...). One `AppNavigator` widget holds
  the screen stack as a list of pages and builds `Navigator(pages: ...)` from it.
- Every screen is a typed page: a `final class XPage extends AppPage` with a stable `ValueKey`, a
  name and the screen as its child. Arguments are constructor parameters of the page, not a map.
- Open a screen with `AppNavigator.push(context, const XPage())`, go back with
  `AppNavigator.pop(context)`, replace the whole stack with `AppNavigator.change(context, (pages)
  => [...])`, and go back to the start with `AppNavigator.reset(context)`.
- Redirects (not signed in, no subscription), titles and analytics are guards: functions from the
  proposed stack to the stack to show, run on every change. Each guard checks its own condition.
  See "Guards".
- A signed-out user who asks for a protected screen (a deep link, a notification) gets
  `SignInPage(returnTo: ...)`, which keeps that stack; once signed in, they get it back. See
  "Returning after sign-in".
- Dialogs, sheets and menus are not screens: open them with `showDialog` /
  `showModalBottomSheet` and close them with `Navigator.pop` and the context their builder gets.
  `showDialog` opens above every page and stays there when a guard changes the stack. See "Dialogs
  and sheets".
- The stack is never empty: a change that would empty it is ignored.

## The navigator

`AppNavigator` is a `StatefulWidget` around `Navigator`. Its state holds the pages; a change runs
the guards, and only a stack that differs from the current one is shown. "Differs" compares the
page objects (`identical`), not `==`, which compares keys: a page replaced by one with the same key
and new data (`SignInPage(returnTo: ...)`) is shown. When the `Navigator`
removes a page itself (the back button of the app bar, a swipe back), `onDidRemovePage` drops it
from the stack, so the list is always what is on screen.

The static methods find the nearest `AppNavigatorState` with `findAncestorStateOfType`. That walks
up the tree, which is fine for an action like a tap; never call it on every build.

`MaterialApp` shows the navigator as its home (see `app.dart` in Examples):

```dart
MaterialApp(
  home: AppNavigator(pages: const <AppPage>[HomePage()]),
);
```

## Pages

A page is a `MaterialPage` with a key, a name and its screen:

```dart
final class ProductPage extends AppPage {
  ProductPage({required int id})
    : super(
        name: 'product',
        arguments: <String, Object?>{'id': id},
        child: ProductScreen(id: id),
        key: ValueKey<String>('product-$id'),
      );
}
```

- Two pages are the same page when their keys are equal. Pushing a page that is already on the
  stack moves it to the top instead of adding it twice: `Navigator` refuses two pages with one
  key. A `change` must keep the keys unique too (an assert says so).
- Put the arguments that make the page unique into its key (`product-$id`), so two products can
  be on the stack at once.
- The sealed `AppPage` lists every screen of the app in one file; a `switch` over it is
  exhaustive.

## Guards

A guard takes the stack a change proposes and returns the stack to show. Guards run in order on
every change, and again when `revalidate` (a `Listenable`, such as the authentication controller)
notifies:

```dart
AppNavigator(
  pages: const <AppPage>[HomePage()],
  revalidate: authenticationController,
  guards: <AppNavigatorGuard>[
    // First: the guards after them see the stack the user gets back after sign-in.
    ...signInGuards(() => authenticationController.state.isAuthenticated),
    // Then: a subscription guard, analytics.
  ],
);
```

- A guard returns a new list; it never changes the one it gets.
- A guard that returns an empty list cancels the change.
- Guards run once, in order, each on what the one before returned; they are not repeated until
  the result is stable. Put the guards whose result others depend on first.
- Each guard checks its own condition. A guard "never show the sign-in page" that does not first
  check that the user is signed in empties a signed-out user's stack (`[SignInPage()]` minus the
  sign-in page), the change is cancelled, and the protected screen stays. Checked: with the two
  guards written that way, a signed-out user saw `HomePage`.

### Returning after sign-in

`signInGuards` (in Examples) is the pair of guards for authentication:

- Signed out: a stack of public pages only (the sign-in page, a sign-up page pushed over it)
  passes as it is. Any other stack becomes `[SignInPage(returnTo: <its protected pages>)]`.
- Signed in: a stack with a public page in it becomes the `SignInPage`'s `returnTo`, or else the
  protected pages left, or else `[HomePage()]`.

The edge cases, each covered by a test:

- `returnTo` is typed pages held in memory, not a URL string read back later, so there is nothing
  to validate on the way back. A deep link is still parsed into pages first, by an allow-list (see
  "Untrusted input" in `docs/rules/security.md`).
- `returnTo` is not part of `SignInPage`'s key: there is one sign-in page, whatever it keeps.
  Because the navigator compares page objects, a second deep link while the sign-in page is shown
  replaces `returnTo`; the latest request wins. Checked: comparing with `listEquals` dropped it.
- When the navigator runs the guards again (`revalidate`) while the user is still signed out, the
  stack is `[SignInPage(returnTo: ...)]`, all public, and passes unchanged. A guard that always
  returned `[SignInPage(returnTo: pages)]` would replace what it kept with an empty list.
- The signed-in guard never returns an empty list: a sign-in page that kept nothing gives
  `[HomePage()]`. An empty list would cancel the change and leave a signed-in user on the
  sign-in page.
- A sign-out the user chose is followed by `AppNavigator.reset(context)`, so `returnTo` holds only
  the first page: the next person to sign in on the device may be someone else, and would land on
  the previous user's screens (the server still refuses them that user's data). Checked: either
  order of the two calls ends with `returnTo == [HomePage()]`. A session that ended by itself (the
  refresh rejected) keeps the stack: the same user signs in and continues.
- `returnTo` lives in memory: a restart while signed out forgets it, and the user starts from the
  first page.
- Add sign-up and password-reset pages to `isPublicPage`, or the first guard sends them back to
  the sign-in page.

## Dialogs and sheets

A dialog, a bottom sheet and a menu are routes pushed with the imperative API onto a `Navigator`,
into the same history as the pages: a pushed route belongs to the page below it. Which navigator
depends on `useRootNavigator`:

- `showDialog`, `showGeneralDialog`, `showCupertinoDialog`, `showCupertinoModalPopup` and
  `showDatePicker` default to `true`: the root navigator of `MaterialApp`, above `AppNavigator`
  and every page in it.
- `showModalBottomSheet` and `showMenu` default to `false`: the nearest navigator, the one
  `AppNavigator` builds.

What that means, checked in widget tests:

- A dialog on the root navigator stays open over any change of the stack, including the guard
  that shows the sign-in page when the session ends. Open a dialog that shows a signed-in user's
  data with `useRootNavigator: false`: it then belongs to its page, and goes when a guard removes
  that page.
- A route on `AppNavigator`'s navigator stays with its page: a page pushed over it covers it,
  going back to the page shows it again, and removing the page removes it.
- Close a dialog with the context its `builder` gets. `Navigator.pop(context)` with the page's
  context, under a dialog on the root navigator, pops the page and leaves the dialog open.

## Tabs

A tab with a history of its own is a second `AppNavigator` inside the tab, and the tabs stay alive
in an `IndexedStack`:

- The static methods find the nearest navigator: `AppNavigator.push(context, page)` inside a tab
  changes that tab's stack. To change the outer stack (a full-screen page over the tabs), pass a
  context above the tab's navigator: the tabs screen's own, or
  `AppNavigator.maybeOf(context)?.context`, which is the inner navigator's place in the tree and
  finds the outer one.
- System back pops the tab on screen only. `AppNavigator` reads `Visibility.of(context)`, which is
  `false` in a child an `IndexedStack` does not show, and disables its back handling there.
  Checked: without that, one back press popped the hidden tabs as well, and a hidden tab with
  pages kept the back press when the visible tab was at its first page.

## Controlled stack

`AppNavigator.controlled(controller: ValueNotifier<List<AppPage>>)` lets code outside the widget
tree read and set the stack: a deep link, a notification tap, a test. The navigator listens to the
controller and writes every change back to it, so both always agree.

## System back

On Android the system back button reaches the root navigator of `MaterialApp`, not the one
`AppNavigator` builds. `AppNavigatorState.build` therefore wraps its `Navigator` in a
`NavigatorPopHandler` that pops the inner navigator. No `GlobalKey` is needed to reach it either:
a `NavigatorObserver` passed to `observers` exposes the `NavigatorState` as `observer.navigator`
(`null` before the first build). The same works for any imperative `Navigator`.

`MaterialApp.builder`'s `child` is the app's root navigator, and an app may return its own
navigator there instead. Do not do that with `AppNavigator`. With no `home` or `routes`,
`MaterialApp` builds no navigator of its own, the system back finds nothing to pop, and on Android
the app closes on the first back press. Keep `AppNavigator` as `home`, and use `builder` for what
wraps every screen (text scaling, a banner), returning `child`.

The sign-in screen is a page too, chosen by a guard when the user is signed out. Showing it from
`builder` in place of the navigator (`user is Unauthenticated ? LoginScreen() : child`) puts it
above the `Navigator`, and so above its `Overlay`: checked, a `Tooltip` there throws "No Overlay
widget found" and `showDialog` finds no `Navigator`; a text field's selection menu needs the same
`Overlay`.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `app_pages.dart`

```dart
// file: app_pages.dart
import 'package:flutter/material.dart';

/// Every screen of the app. Two pages are the same page when their keys are equal.
sealed class AppPage extends MaterialPage<void> {
  const AppPage({
    required String super.name,
    required Map<String, Object?>? super.arguments,
    required super.child,
    required LocalKey super.key,
  });

  @override
  String get name => super.name ?? 'unknown';

  @override
  Map<String, Object?> get arguments => switch (super.arguments) {
    final Map<String, Object?> arguments when arguments.isNotEmpty => arguments,
    _ => const <String, Object?>{},
  };

  @override
  bool operator ==(Object other) => other is AppPage && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The first screen.
final class HomePage extends AppPage {
  const HomePage()
    : super(
        name: 'home',
        arguments: null,
        child: const Text('Home'),
        key: const ValueKey<String>('home'),
      );
}

/// The settings screen.
final class SettingsPage extends AppPage {
  const SettingsPage()
    : super(
        name: 'settings',
        arguments: null,
        child: const Text('Settings'),
        key: const ValueKey<String>('settings'),
      );
}

/// The sign-in screen, shown by a guard while the user is signed out.
final class SignInPage extends AppPage {
  /// [returnTo] is not part of the key: a guard can replace the page without adding a second one.
  const SignInPage({this.returnTo = const <AppPage>[]})
    : super(
        name: 'sign-in',
        arguments: null,
        child: const Text('Sign in'),
        key: const ValueKey<String>('sign-in'),
      );

  /// The stack the user asked for while signed out, shown once they are signed in.
  final List<AppPage> returnTo;
}
```

### `app_navigator.dart`

```dart
// file: app_navigator.dart
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'app_pages.dart';

/// The screen stack.
typedef AppNavigationState = List<AppPage>;

/// Turns the stack a change proposes into the stack to show.
typedef AppNavigatorGuard =
    AppNavigationState Function(BuildContext context, AppNavigationState state);

/// Declarative navigation in one widget: the stack is a list of pages; push, pop and change
/// replace it, and [guards] decide what is shown.
class AppNavigator extends StatefulWidget {
  /// A navigator that starts with [pages] and keeps the stack itself.
  AppNavigator({
    required this.pages,
    this.guards = const <AppNavigatorGuard>[],
    this.observers = const <NavigatorObserver>[],
    this.transitionDelegate = const DefaultTransitionDelegate<Object?>(),
    this.revalidate,
    super.key,
  }) : assert(pages.isNotEmpty, 'pages cannot be empty'),
       controller = null;

  /// A navigator whose stack lives in [controller], for code outside the widget tree.
  AppNavigator.controlled({
    required ValueNotifier<AppNavigationState> this.controller,
    this.guards = const <AppNavigatorGuard>[],
    this.observers = const <NavigatorObserver>[],
    this.transitionDelegate = const DefaultTransitionDelegate<Object?>(),
    this.revalidate,
    super.key,
  }) : assert(controller.value.isNotEmpty, 'controller cannot be empty'),
       pages = controller.value;

  /// The nearest navigator; `null` outside one.
  static AppNavigatorState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AppNavigatorState>();

  /// Replaces the stack with what [fn] returns for the current one.
  static void change(
    BuildContext context,
    AppNavigationState Function(AppNavigationState pages) fn,
  ) => maybeOf(context)?.change(fn);

  /// Shows [page] on top; a page already on the stack moves there (keys stay unique).
  static void push(BuildContext context, AppPage page) => change(
    context,
    (pages) => <AppPage>[
      for (final other in pages)
        if (other != page) other,
      page,
    ],
  );

  /// Removes the top page.
  static void pop(BuildContext context) =>
      change(context, (pages) => pages.isEmpty ? pages : (pages..removeLast()));

  /// Goes back to the pages the navigator started with.
  static void reset(BuildContext context) {
    final navigator = maybeOf(context);
    navigator?.change((_) => navigator.widget.pages);
  }

  /// The stack it starts with.
  final AppNavigationState pages;

  /// Where the stack lives in controlled mode.
  final ValueNotifier<AppNavigationState>? controller;

  /// Run in order on every change.
  final List<AppNavigatorGuard> guards;

  /// Given to the [Navigator].
  final List<NavigatorObserver> observers;

  /// How pages enter and leave.
  final TransitionDelegate<Object?> transitionDelegate;

  /// Runs the guards again whenever it notifies (sign-in, sign-out).
  final Listenable? revalidate;

  @override
  State<AppNavigator> createState() => AppNavigatorState();
}

/// State of [AppNavigator]: the stack on screen.
class AppNavigatorState extends State<AppNavigator> {
  final NavigatorObserver _observer = NavigatorObserver();

  /// The inner [Navigator]; `null` before the first build.
  NavigatorState? get navigator => _observer.navigator;

  late AppNavigationState _state;
  List<NavigatorObserver> _observers = const <NavigatorObserver>[];

  /// The stack on screen.
  AppNavigationState get state => _state;

  @override
  void initState() {
    super.initState();
    _state = widget.pages;
    _observers = <NavigatorObserver>[_observer, ...widget.observers];
    widget.revalidate?.addListener(revalidate);
    widget.controller?.addListener(_onController);
    _onController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    revalidate();
  }

  @override
  void didUpdateWidget(covariant AppNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.revalidate, oldWidget.revalidate)) {
      oldWidget.revalidate?.removeListener(revalidate);
      widget.revalidate?.addListener(revalidate);
    }
    if (!identical(widget.observers, oldWidget.observers)) {
      _observers = <NavigatorObserver>[_observer, ...widget.observers];
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
      _onController();
    }
  }

  @override
  void dispose() {
    widget.revalidate?.removeListener(revalidate);
    widget.controller?.removeListener(_onController);
    super.dispose();
  }

  /// Replaces the stack with what [fn] returns for a copy of the current one.
  void change(AppNavigationState Function(AppNavigationState pages) fn) =>
      _show(fn(_state.toList()));

  /// Runs the guards again on the current stack.
  void revalidate() => _show(_state);

  void _onController() {
    final controller = widget.controller;
    if (controller == null || identical(controller.value, _state)) return;
    _show(controller.value.toList());
  }

  void _show(AppNavigationState proposed) {
    if (!mounted || proposed.isEmpty) return;
    final next = widget.guards.fold(proposed, (pages, guard) => guard(context, pages));
    assert(
      next.map((page) => page.key).toSet().length == next.length,
      'Two pages have the same key: Navigator would refuse the stack.',
    );
    if (next.isEmpty || _isSameStack(next, _state)) {
      _writeController();
      return;
    }
    _state = UnmodifiableListView<AppPage>(next);
    _writeController();
    setState(() {});
  }

  /// The same page objects in the same order. Not `==`, which compares keys: a guard that
  /// replaces a page by one with the same key and new data (`SignInPage(returnTo: ...)`) must be
  /// shown.
  static bool _isSameStack(AppNavigationState a, AppNavigationState b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Keeps the controller equal to the stack on screen without hearing its own write.
  void _writeController() {
    final controller = widget.controller;
    if (controller == null || identical(controller.value, _state)) return;
    controller
      ..removeListener(_onController)
      ..value = _state
      ..addListener(_onController);
  }

  void _onDidRemovePage(Page<Object?> page) =>
      change((pages) => pages..removeWhere((p) => p.key == page.key));

  @override
  Widget build(BuildContext context) {
    // `false` in a tab an IndexedStack does not show: that stack neither takes the system back
    // nor tells the navigators above whether it can pop.
    final visible = Visibility.of(context);
    return NotificationListener<NavigationNotification>(
      onNotification: (_) => !visible,
      child: NavigatorPopHandler<Object?>(
        enabled: visible,
        // The system back reaches the root navigator first; pop this one instead.
        onPopWithResult: (_) {
          if (visible) navigator?.maybePop();
        },
        child: Navigator(
          pages: _state,
          transitionDelegate: widget.transitionDelegate,
          onDidRemovePage: _onDidRemovePage,
          observers: _observers,
        ),
      ),
    );
  }
}
```

### `sign_in_guards.dart`

```dart
// file: sign_in_guards.dart
import 'app_navigator.dart';
import 'app_pages.dart';

/// Pages a signed-out user may see; add sign-up and password reset here.
bool isPublicPage(AppPage page) => page is SignInPage;

/// Two guards: a signed-out user gets [SignInPage], which keeps the stack they asked for; once
/// [isSignedIn], that stack is shown. Put them first, so the guards after them see that stack.
List<AppNavigatorGuard> signInGuards(bool Function() isSignedIn) => <AppNavigatorGuard>[
  // Signed out: only public pages; the rest waits in `returnTo`.
  (context, pages) {
    if (isSignedIn() || pages.every(isPublicPage)) return pages;
    return <AppPage>[
      SignInPage(
        returnTo: List<AppPage>.unmodifiable(<AppPage>[
          for (final page in pages)
            if (!isPublicPage(page)) page,
        ]),
      ),
    ];
  },
  // Signed in: no public pages; what the sign-in page kept, or the pages left, or home.
  (context, pages) {
    if (!isSignedIn() || !pages.any(isPublicPage)) return pages;
    for (final page in pages) {
      if (page is SignInPage && page.returnTo.isNotEmpty) return page.returnTo;
    }
    final rest = <AppPage>[
      for (final page in pages)
        if (!isPublicPage(page)) page,
    ];
    return rest.isEmpty ? const <AppPage>[HomePage()] : rest;
  },
];
```

### `app.dart`

```dart
// file: app.dart
import 'package:flutter/material.dart';

import 'app_navigator.dart';
import 'app_pages.dart';

/// The app: [AppNavigator] as the home (it handles the Android back button itself).
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: AppNavigator(pages: const <AppPage>[HomePage()]));
}
```
