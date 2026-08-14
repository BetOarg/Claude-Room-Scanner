import 'dart:io';

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';

import '../engine/scanner_capabilities.dart';

/// Detecta las capacidades relevantes del dispositivo.
///
/// AR es una capacidad opcional. La ausencia de ARCore/ARKit nunca debe
/// impedir que la aplicación funcione en modo Basic o Manual.
class DeviceCapabilitiesService {
  DeviceCapabilitiesService._();

  static Future<ScannerCapabilities> detect() async {
    bool hasArCore = false;
    bool hasArKit = false;

    try {
      if (Platform.isAndroid) {
        hasArCore = await ArFlutterPlugin.isArCoreSupported;
      } else if (Platform.isIOS) {
        // ar_flutter_plugin_2 no expone aquí una comprobación ARKit
        // equivalente de forma multiplataforma.
        //
        // Se deja false hasta implementar el detector nativo iOS.
        hasArKit = false;
      }
    } catch (_) {
      // AR es opcional.
      //
      // Si la consulta falla, NO debemos impedir el uso de Basic Scanner.
      hasArCore = false;
      hasArKit = false;
    }

    return ScannerCapabilities(
      hasCamera: true,
      hasArCore: hasArCore,
      hasArKit: hasArKit,
      hasGyroscope: false,
      hasAccelerometer: false,
      hasMagnetometer: false,
    );
  }
}