/// Capacidades físicas/software relevantes para Scanner Engine.
class ScannerCapabilities {
  final bool hasCamera;
  final bool hasArCore;
  final bool hasArKit;
  final bool hasGyroscope;
  final bool hasAccelerometer;
  final bool hasMagnetometer;

  const ScannerCapabilities({
    this.hasCamera = false,
    this.hasArCore = false,
    this.hasArKit = false,
    this.hasGyroscope = false,
    this.hasAccelerometer = false,
    this.hasMagnetometer = false,
  });

  /// El dispositivo puede utilizar algún motor AR.
  bool get supportsAR => hasArCore || hasArKit;

  /// El dispositivo puede utilizar el scanner básico.
  bool get supportsBasicScanner => hasCamera;

  /// Nivel máximo recomendado.
  ///
  /// AR > BASIC > MANUAL.
  String get recommendedMode {
    if (supportsAR) return 'ar';
    if (supportsBasicScanner) return 'basic';
    return 'manual';
  }

  @override
  String toString() {
    return 'ScannerCapabilities('
        'camera: $hasCamera, '
        'arCore: $hasArCore, '
        'arKit: $hasArKit, '
        'gyro: $hasGyroscope, '
        'accelerometer: $hasAccelerometer, '
        'magnetometer: $hasMagnetometer'
        ')';
  }
}