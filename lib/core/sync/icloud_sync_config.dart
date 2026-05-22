class ICloudSyncConfig {
  const ICloudSyncConfig._();

  // Optional via build flag setzen:
  // flutter run --dart-define=ICLOUD_CONTAINER_ID=iCloud.com.example.arrowops
  static const String containerId = String.fromEnvironment(
    'ICLOUD_CONTAINER_ID',
    defaultValue: '',
  );
}
