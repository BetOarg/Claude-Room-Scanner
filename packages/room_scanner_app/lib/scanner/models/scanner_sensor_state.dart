/// Estado actual de los sensores disponibles.
///
/// Los valores se mantienen independientes del motor de escaneo.
/// Esto permite utilizar sensores tanto en Basic Scanner como en futuras
/// funciones de calibración.
class ScannerSensorState {
  final double accelerometerX;
  final double accelerometerY;
  final double accelerometerZ;

  final double gyroscopeX;
  final double gyroscopeY;
  final double gyroscopeZ;

  final double magnetometerX;
  final double magnetometerY;
  final double magnetometerZ;

  final DateTime timestamp;

  const ScannerSensorState({
    this.accelerometerX = 0,
    this.accelerometerY = 0,
    this.accelerometerZ = 0,
    this.gyroscopeX = 0,
    this.gyroscopeY = 0,
    this.gyroscopeZ = 0,
    this.magnetometerX = 0,
    this.magnetometerY = 0,
    this.magnetometerZ = 0,
    required this.timestamp,
  });

  ScannerSensorState copyWith({
    double? accelerometerX,
    double? accelerometerY,
    double? accelerometerZ,
    double? gyroscopeX,
    double? gyroscopeY,
    double? gyroscopeZ,
    double? magnetometerX,
    double? magnetometerY,
    double? magnetometerZ,
    DateTime? timestamp,
  }) {
    return ScannerSensorState(
      accelerometerX: accelerometerX ?? this.accelerometerX,
      accelerometerY: accelerometerY ?? this.accelerometerY,
      accelerometerZ: accelerometerZ ?? this.accelerometerZ,
      gyroscopeX: gyroscopeX ?? this.gyroscopeX,
      gyroscopeY: gyroscopeY ?? this.gyroscopeY,
      gyroscopeZ: gyroscopeZ ?? this.gyroscopeZ,
      magnetometerX: magnetometerX ?? this.magnetometerX,
      magnetometerY: magnetometerY ?? this.magnetometerY,
      magnetometerZ: magnetometerZ ?? this.magnetometerZ,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}