// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';

/// Localization.
///
/// Strings live in `intl_en.arb` / `intl_ru.arb`; `flutter pub get` regenerates
/// [GeneratedLocalization] (see `l10n.yaml`).
abstract final class Localization {
  /// Localization delegate.
  static const LocalizationsDelegate<GeneratedLocalization> delegate =
      GeneratedLocalization.delegate;

  /// Get localization instance for the widgets structure.
  static GeneratedLocalization of(BuildContext context) => GeneratedLocalization.of(context);

  /// Get supported locales.
  static List<Locale> get supportedLocales => GeneratedLocalization.supportedLocales;
}
