import 'package:permission_handler/permission_handler.dart';

import '../models/scanner_mode.dart';

class ScannerPermissionService {
  const ScannerPermissionService();

  /// Solicita únicamente los permisos necesarios para el modo elegido.
  Future<bool> requestForMode(ScannerMode mode) async {
    switch (mode) {
      case ScannerMode.ar:
        return _requestARPermissions();

      case ScannerMode.basic:
        return _requestBasicPermissions();

      case ScannerMode.manual:
        return true;
    }
  }

  Future<bool> _requestARPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
    ].request();

    final cameraGranted =
        statuses[Permission.camera]?.isGranted ?? false;

    final locationGranted =
        statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    return cameraGranted && locationGranted;
  }

  Future<bool> _requestBasicPermissions() async {
    final status = await Permission.camera.request();

    return status.isGranted;
  }

  Future<bool> hasPermissionsForMode(ScannerMode mode) async {
    switch (mode) {
      case ScannerMode.ar:
        final camera = await Permission.camera.isGranted;
        final location =
            await Permission.locationWhenInUse.isGranted;

        return camera && location;

      case ScannerMode.basic:
        return Permission.camera.isGranted;

      case ScannerMode.manual:
        return true;
    }
  }
}