import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Solicita permisos de cámara y ubicación en tiempo de ejecución.
  static Future<bool> requestScannerPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
    ].request();

    bool cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    bool locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    return cameraGranted && locationGranted;
  }

  /// Verifica si los permisos requeridos ya fueron concedidos.
  static Future<bool> hasBasicPermissions() async {
    final camera = await Permission.camera.status.isGranted;
    final location = await Permission.locationWhenInUse.status.isGranted;
    return camera && location;
  }
}