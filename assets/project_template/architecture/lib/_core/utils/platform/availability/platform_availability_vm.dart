import 'package:flutter/foundation.dart';

// Which features the platform can run. A screen or a dependency checks these instead of
// `Platform.isX`, so the web build (platform_availability_js.dart) has its own answers. Change them
// to what the app supports.

/// Whether the app may ask for the location.
bool get kLocationCompatiblePlatform => defaultTargetPlatform == TargetPlatform.android;

/// Whether a map with the platform's map SDK can be shown.
bool get kMapIntegrationCompatiblePlatform =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Whether this is a desktop build (Windows, macOS, Linux).
bool get kDesktopVM =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Whether documents can be printed.
bool get kPrintingCompatiblePlatform => true;

/// Whether Bluetooth devices can be used.
bool get kBluetoothCompatiblePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Whether secrets can be kept in the platform's secure storage (the "remember me" option).
bool get kSecureStorageCompatiblePlatform =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

/// Whether the store's in-app update can be offered.
bool get kInAppUpdatePlatform => defaultTargetPlatform == TargetPlatform.android;
