import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/app_settings/controller/app_settings_controller.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// Gives the widgets below access to [AppSettingsConfigWidgetState].
class AppSettingsConfigInhWidget extends InheritedWidget {
  const AppSettingsConfigInhWidget({super.key, required this.state, required super.child});

  final AppSettingsConfigWidgetState state;

  static AppSettingsConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<AppSettingsConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'AppSettingsConfigInhWidget was not found in element tree');
    return (widget! as AppSettingsConfigInhWidget).state;
  }

  /// Like [of], or `null` when there is no [AppSettingsConfigWidget] above [context].
  static AppSettingsConfigWidgetState? maybeOf(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppSettingsConfigInhWidget>()?.widget
              as AppSettingsConfigInhWidget?)
          ?.state;

  @override
  bool updateShouldNotify(AppSettingsConfigInhWidget oldWidget) => false;
}

/// {@template app_settings_config_widget}
/// Owns the [AppSettingsController] for the whole window.
/// {@endtemplate}
class AppSettingsConfigWidget extends StatefulWidget {
  /// {@macro app_settings_config_widget}
  const AppSettingsConfigWidget({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  State<AppSettingsConfigWidget> createState() => AppSettingsConfigWidgetState();
}

class AppSettingsConfigWidgetState extends State<AppSettingsConfigWidget> {
  late final AppSettingsController controller;

  @override
  void initState() {
    super.initState();
    controller = AppSettingsController(
      repository: AppSettingsRepositoryImpl(database: Dependencies.of(context).database),
    )..watch();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AppSettingsConfigInhWidget(state: this, child: widget.child);
}
