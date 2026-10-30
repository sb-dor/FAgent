import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';

/// {@template run_device_chip}
/// The chip of the device the app runs on, with the menu of the devices (running ones first, then
/// the ones that can be launched). The Run tab and the title bar both show it.
/// {@endtemplate}
class RunDeviceChip extends StatelessWidget {
  /// {@macro run_device_chip}
  const RunDeviceChip({
    required this.devices,
    required this.selectedDeviceId,
    required this.onSelected,
    super.key,
  });

  /// The devices known right now.
  final List<Device> devices;

  /// The chosen device; `null` while none is chosen.
  final String? selectedDeviceId;

  /// Called with the id of the device the user chose.
  final ValueChanged<String> onSelected;

  static const String _argumentsValue = '';

  static IconData _platformIcon(DevicePlatform platform) => switch (platform) {
    DevicePlatform.ios => Icons.phone_iphone,
    DevicePlatform.android => Icons.phone_android,
    DevicePlatform.macos => Icons.desktop_mac_outlined,
    DevicePlatform.web => Icons.public,
    DevicePlatform.windows || DevicePlatform.linux => Icons.desktop_windows_outlined,
  };

  AppMenuItem<String> _item(Device device) => AppMenuItem<String>(
    value: device.id,
    title: device.name,
    subtitle: device.detail,
    icon: _platformIcon(device.platform),
    selected: device.id == selectedDeviceId,
  );

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final selected = devices.where((device) => device.id == selectedDeviceId).firstOrNull;
    final running = devices.where((device) => device.kind == DeviceKind.running);
    final available = devices.where((device) => device.kind == DeviceKind.available);
    return SelectorChip<String>(
      label: selected?.name ?? localization.chooseDevice,
      icon: selected == null ? Icons.devices : _platformIcon(selected.platform),
      menuWidth: 300,
      sections: <AppMenuSection<String>>[
        if (running.isNotEmpty)
          AppMenuSection<String>(
            title: localization.devicesRunning,
            items: running.map(_item).toList(growable: false),
          ),
        if (available.isNotEmpty)
          AppMenuSection<String>(
            title: localization.devicesAvailable,
            items: available.map(_item).toList(growable: false),
          ),
        if (devices.isNotEmpty)
          AppMenuSection<String>(
            items: <AppMenuItem<String>>[
              AppMenuItem<String>(
                value: _argumentsValue,
                title: localization.runArguments,
                subtitle: localization.comingInMilestone('M2'),
                icon: Icons.tune,
                enabled: false,
              ),
            ],
          ),
      ],
      onSelected: onSelected,
    );
  }
}
