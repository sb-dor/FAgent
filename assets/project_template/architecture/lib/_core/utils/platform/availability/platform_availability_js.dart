// The web's answers to platform_availability_vm.dart: see there.

/// Whether the app may ask for the location.
bool get kLocationCompatiblePlatform => false;

/// Whether a map with the platform's map SDK can be shown.
bool get kMapIntegrationCompatiblePlatform => false;

/// Whether this is a desktop build (Windows, macOS, Linux).
bool get kDesktopVM => false;

/// Whether documents can be printed.
bool get kPrintingCompatiblePlatform => false;

/// Whether Bluetooth devices can be used.
bool get kBluetoothCompatiblePlatform => false;

/// Whether secrets can be kept in the platform's secure storage (the "remember me" option).
bool get kSecureStorageCompatiblePlatform => false;

/// Whether the store's in-app update can be offered.
bool get kInAppUpdatePlatform => false;
