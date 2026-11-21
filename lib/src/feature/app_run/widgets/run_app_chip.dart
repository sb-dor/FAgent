import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:path/path.dart' as p;

/// {@template run_app_chip}
/// The chip of the app a monorepo runs (`desktop`), with the menu of its Flutter apps under
/// `apps/`. While the selected run configuration fixes the app ([locked]) the chip shows that app
/// and opens no menu. Without any Flutter app it says so instead.
/// {@endtemplate}
class RunAppChip extends StatelessWidget {
  /// {@macro run_app_chip}
  const RunAppChip({
    required this.apps,
    required this.appFolder,
    required this.locked,
    required this.onSelected,
    super.key,
  });

  /// The folders of the apps, relative to the project (`apps/desktop`).
  final List<String> apps;

  /// The folder of the app shown; `''` while none is.
  final String appFolder;

  /// Whether the selected run configuration fixes the app, so it cannot be changed here.
  final bool locked;

  /// Called with the folder of the app the user chose.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    if (apps.isEmpty) {
      return Text(
        localization.runNoApps,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.colors.muted),
      );
    }
    return SelectorChip<String>(
      label: appFolder.isEmpty ? localization.runApp : p.posix.basename(appFolder),
      icon: Icons.apps,
      tooltip: locked ? appFolder : localization.runApp,
      menuWidth: 240,
      sections: locked
          ? null
          : <AppMenuSection<String>>[
              AppMenuSection<String>(
                title: localization.runApp,
                items: <AppMenuItem<String>>[
                  for (final app in apps)
                    AppMenuItem<String>(
                      value: app,
                      title: p.posix.basename(app),
                      subtitle: app,
                      selected: app == appFolder,
                    ),
                ],
              ),
            ],
      onSelected: onSelected,
    );
  }
}
