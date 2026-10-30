import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

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
    );
  }

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

  /// The JSON stored in `app_settings`.
  Map<String, Object?> toJson() => <String, Object?>{
    'themeMode': themeMode.name,
    'locale': locale?.languageCode,
    'sidebarVisible': sidebarVisible,
    'rightPaneVisible': rightPaneVisible,
    'rightPaneWidth': rightPaneWidth,
    'defaultAgentId': defaultAgentId,
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
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: resetLocale ? null : locale ?? this.locale,
    sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    rightPaneVisible: resetRightPaneVisible ? null : rightPaneVisible ?? this.rightPaneVisible,
    rightPaneWidth: rightPaneWidth ?? this.rightPaneWidth,
    defaultAgentId: defaultAgentId ?? this.defaultAgentId,
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
          other.defaultAgentId == defaultAgentId;

  @override
  int get hashCode => Object.hash(
    themeMode,
    locale,
    sidebarVisible,
    rightPaneVisible,
    rightPaneWidth,
    defaultAgentId,
  );

  @override
  String toString() => 'AppSettings(${toJson()})';
}
