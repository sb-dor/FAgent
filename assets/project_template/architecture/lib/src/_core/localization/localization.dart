import 'package:flutter/widgets.dart';
import 'package:{{package}}/src/_core/localization/generated/generated_localization.dart';

/// Localization.
///
/// Strings live in `intl_en.arb`; `flutter pub get` regenerates [GeneratedLocalization]
/// (see `l10n.yaml`).
// A namespace on purpose: `Localization.of(context)` reads like `Theme.of(context)`.
// ignore: avoid_classes_with_only_static_members
abstract final class Localization {
  /// Localization delegate.
  static const LocalizationsDelegate<GeneratedLocalization> delegate =
      GeneratedLocalization.delegate;

  /// Get localization instance for the widgets structure.
  static GeneratedLocalization of(BuildContext context) => GeneratedLocalization.of(context);

  /// Get supported locales.
  static List<Locale> get supportedLocales => GeneratedLocalization.supportedLocales;
}
