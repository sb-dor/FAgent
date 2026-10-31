import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// How tightly the chat feed packs its rows.
enum FeedDensity {
  /// The default spacing.
  comfortable,

  /// Rows closer together.
  compact,
}

/// What a new project starts from.
enum NewProjectTemplate {
  /// The architecture skeleton of the project instructions.
  architecture,

  /// A plain `flutter create` project.
  plain,

  /// A plain project with a git repository.
  git,
}

/// Where Flutter DevTools opens.
enum DevToolsTarget {
  /// The system browser.
  browser,

  /// A window of the app.
  app,
}

/// Window-level settings: theme, language, panels and the default agent.
@immutable
final class AppSettings {
  /// Creates settings; every field has a default.
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.sidebarVisible = true,
    this.rightPaneVisible,
    this.rightPaneWidth = defaultRightPaneWidth,
    this.defaultAgentId = 'claude',
    this.sessionDefaults = const <String, Map<String, String>>{},
    this.reloadAfterTurn = false,
    this.askBeforeQuit = true,
    this.feedDensity = FeedDensity.comfortable,
    this.projectOrg = defaultProjectOrg,
    this.projectTemplate = NewProjectTemplate.architecture,
    this.devToolsTarget = DevToolsTarget.browser,
  });

  /// Reads settings from stored JSON. Never throws: anything unreadable becomes the default.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) return const AppSettings();
    final themeName = json['themeMode'];
    final localeCode = json['locale'];
    final width = json['rightPaneWidth'];
    final agentId = json['defaultAgentId'];
    final sidebarVisible = json['sidebarVisible'];
    final rightPaneVisible = json['rightPaneVisible'];
    final reloadAfterTurn = json['reloadAfterTurn'];
    final askBeforeQuit = json['askBeforeQuit'];
    final projectOrg = json['projectOrg'];
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      locale: localeCode is String
          ? Localization.supportedLocales
                .where((locale) => locale.languageCode == localeCode)
                .firstOrNull
          : null,
      sidebarVisible: sidebarVisible is! bool || sidebarVisible,
      rightPaneVisible: rightPaneVisible is bool ? rightPaneVisible : null,
      rightPaneWidth: width is num && width.isFinite
          ? width.toDouble().clamp(minRightPaneWidth, maxRightPaneWidth)
          : defaultRightPaneWidth,
      defaultAgentId: agentId is String && agentId.isNotEmpty ? agentId : 'claude',
      sessionDefaults: _readSessionDefaults(json['sessionDefaults']),
      reloadAfterTurn: reloadAfterTurn is bool && reloadAfterTurn,
      askBeforeQuit: askBeforeQuit is! bool || askBeforeQuit,
      feedDensity: FeedDensity.values.firstWhere(
        (density) => density.name == json['feedDensity'],
        orElse: () => FeedDensity.comfortable,
      ),
      projectOrg: projectOrg is String && orgPattern.hasMatch(projectOrg)
          ? projectOrg
          : defaultProjectOrg,
      projectTemplate: NewProjectTemplate.values.firstWhere(
        (template) => template.name == json['projectTemplate'],
        orElse: () => NewProjectTemplate.architecture,
      ),
      devToolsTarget: DevToolsTarget.values.firstWhere(
        (target) => target.name == json['devToolsTarget'],
        orElse: () => DevToolsTarget.browser,
      ),
    );
  }

  /// Keeps string-to-string entries only and drops `mode: bypassPermissions`.
  static Map<String, Map<String, String>> _readSessionDefaults(Object? json) {
    if (json is! Map<Object?, Object?>) return const <String, Map<String, String>>{};
    return _sanitize(<String, Map<Object?, Object?>>{
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is Map<Object?, Object?>) key: value,
    });
  }

  static Map<String, Map<String, String>> _sanitize(Map<String, Map<Object?, Object?>> raw) =>
      <String, Map<String, String>>{
        for (final MapEntry(:key, :value) in raw.entries)
          key: <String, String>{
            for (final MapEntry(key: configId, value: choice) in value.entries)
              if (configId is String &&
                  choice is String &&
                  !(configId == 'mode' && choice == _bypassMode))
                configId: choice,
          },
      };

  static const String _bypassMode = 'bypassPermissions';

  /// A reverse-domain organization, as `flutter create --org` takes it.
  static final RegExp orgPattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

  /// The organization of a new project until the user changes it.
  static const String defaultProjectOrg = 'com.example';

  /// Narrowest right pane.
  static const double minRightPaneWidth = 340;

  /// Widest right pane.
  static const double maxRightPaneWidth = 560;

  /// Right pane width until the user drags it.
  static const double defaultRightPaneWidth = 380;

  /// Light, dark, or follow the system.
  final ThemeMode themeMode;

  /// The app language; `null` follows the system.
  final Locale? locale;

  /// Whether the project sidebar is shown.
  final bool sidebarVisible;

  /// Whether the right pane is shown; `null` decides by the window width.
  final bool? rightPaneVisible;

  /// Right pane width, within [minRightPaneWidth]–[maxRightPaneWidth].
  final double rightPaneWidth;

  /// The agent a new chat starts with.
  final String defaultAgentId;

  /// Config option values a new chat starts with: agent id → config id → value (model, mode, …).
  ///
  /// `mode: bypassPermissions` is never stored; it needs the user's consent in each chat.
  final Map<String, Map<String, String>> sessionDefaults;

  /// Whether the running app is hot-reloaded after the agent finishes a turn.
  final bool reloadAfterTurn;

  /// Whether quitting while agents work asks first.
  final bool askBeforeQuit;

  /// How tightly the chat feed packs its rows.
  final FeedDensity feedDensity;

  /// The organization (`--org`) of a new project.
  final String projectOrg;

  /// What a new project starts from.
  final NewProjectTemplate projectTemplate;

  /// Where Flutter DevTools opens.
  final DevToolsTarget devToolsTarget;

  /// The JSON stored in `app_settings`.
  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode.name,
    'locale': locale?.languageCode,
    'sidebarVisible': sidebarVisible,
    'rightPaneVisible': rightPaneVisible,
    'rightPaneWidth': rightPaneWidth,
    'defaultAgentId': defaultAgentId,
    'sessionDefaults': sessionDefaults,
    'reloadAfterTurn': reloadAfterTurn,
    'askBeforeQuit': askBeforeQuit,
    'feedDensity': feedDensity.name,
    'projectOrg': projectOrg,
    'projectTemplate': projectTemplate.name,
    'devToolsTarget': devToolsTarget.name,
  };

  /// A copy with the given fields replaced.
  ///
  /// [locale] and [rightPaneVisible] can be reset to `null` through their `Reset` flags.
  AppSettings copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    bool resetLocale = false,
    bool? sidebarVisible,
    bool? rightPaneVisible,
    bool resetRightPaneVisible = false,
    double? rightPaneWidth,
    String? defaultAgentId,
    Map<String, Map<String, String>>? sessionDefaults,
    bool? reloadAfterTurn,
    bool? askBeforeQuit,
    FeedDensity? feedDensity,
    String? projectOrg,
    NewProjectTemplate? projectTemplate,
    DevToolsTarget? devToolsTarget,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: resetLocale ? null : locale ?? this.locale,
    sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    rightPaneVisible: resetRightPaneVisible ? null : rightPaneVisible ?? this.rightPaneVisible,
    rightPaneWidth: rightPaneWidth ?? this.rightPaneWidth,
    defaultAgentId: defaultAgentId ?? this.defaultAgentId,
    sessionDefaults: sessionDefaults == null
        ? this.sessionDefaults
        : _sanitize(<String, Map<Object?, Object?>>{
            for (final MapEntry(:key, :value) in sessionDefaults.entries) key: value,
          }),
    reloadAfterTurn: reloadAfterTurn ?? this.reloadAfterTurn,
    askBeforeQuit: askBeforeQuit ?? this.askBeforeQuit,
    feedDensity: feedDensity ?? this.feedDensity,
    projectOrg: projectOrg ?? this.projectOrg,
    projectTemplate: projectTemplate ?? this.projectTemplate,
    devToolsTarget: devToolsTarget ?? this.devToolsTarget,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.themeMode == themeMode &&
          other.locale == locale &&
          other.sidebarVisible == sidebarVisible &&
          other.rightPaneVisible == rightPaneVisible &&
          other.rightPaneWidth == rightPaneWidth &&
          other.defaultAgentId == defaultAgentId &&
          other.reloadAfterTurn == reloadAfterTurn &&
          other.askBeforeQuit == askBeforeQuit &&
          other.feedDensity == feedDensity &&
          other.projectOrg == projectOrg &&
          other.projectTemplate == projectTemplate &&
          other.devToolsTarget == devToolsTarget &&
          const DeepCollectionEquality().equals(other.sessionDefaults, sessionDefaults);

  @override
  int get hashCode => Object.hash(
    themeMode,
    locale,
    sidebarVisible,
    rightPaneVisible,
    rightPaneWidth,
    defaultAgentId,
    const DeepCollectionEquality().hash(sessionDefaults),
    reloadAfterTurn,
    askBeforeQuit,
    feedDensity,
    projectOrg,
    projectTemplate,
    devToolsTarget,
  );

  @override
  String toString() => 'AppSettings(${toJson()})';
}
