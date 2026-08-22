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

  bool get supportsAR {
    return hasArCore || hasArKit;
  }

  bool get supportsBasicScanner {
    return hasCamera;
  }

  bool get hasIMU {
    return hasGyroscope || hasAccelerometer;
  }

  bool get hasCompleteIMU {
    return hasGyroscope &&
        hasAccelerometer &&
        hasMagnetometer;
  }

  bool get supportsManualScanner {
    return true;
  }

  String get recommendedMode {
    if (supportsAR) {
      return 'ar';
    }

    if (supportsBasicScanner) {
      return 'basic';
    }

    return 'manual';
  }

  @override
  String toString() {
    return 'ScannerCapabilities('
        'camera=$hasCamera, '
        'arCore=$hasArCore, '
        'arKit=$hasArKit, '
        'gyroscope=$hasGyroscope, '
        'accelerometer=$hasAccelerometer, '
        'magnetometer=$hasMagnetometer'
        ')';
  }
}