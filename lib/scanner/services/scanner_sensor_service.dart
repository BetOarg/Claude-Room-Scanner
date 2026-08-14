import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../models/scanner_sensor_state.dart';

/// Servicio centralizado de sensores.
///
/// No realiza cálculos geométricos.
/// Solamente captura y mantiene el último estado conocido de los sensores.
class ScannerSensorService {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  double _accelerometerX = 0;
  double _accelerometerY = 0;
  double _accelerometerZ = 0;

  double _gyroscopeX = 0;
  double _gyroscopeY = 0;
  double _gyroscopeZ = 0;

  double _magnetometerX = 0;
  double _magnetometerY = 0;
  double _magnetometerZ = 0;

  DateTime _timestamp = DateTime.now();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  ScannerSensorState get currentState {
    return ScannerSensorState(
      accelerometerX: _accelerometerX,
      accelerometerY: _accelerometerY,
      accelerometerZ: _accelerometerZ,
      gyroscopeX: _gyroscopeX,
      gyroscopeY: _gyroscopeY,
      gyroscopeZ: _gyroscopeZ,
      magnetometerX: _magnetometerX,
      magnetometerY: _magnetometerY,
      magnetometerZ: _magnetometerZ,
      timestamp: _timestamp,
    );
  }

  /// Inicializa los streams disponibles.
  ///
  /// Si un sensor no existe en el dispositivo, el servicio no debe hacer
  /// fallar toda la aplicación.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      _accelerometerSubscription =
          accelerometerEvents.listen(
        (event) {
          _accelerometerX = event.x;
          _accelerometerY = event.y;
          _accelerometerZ = event.z;
          _timestamp = DateTime.now();
        },
        onError: (_) {},
      );
    } catch (_) {
      // Sensor no disponible.
    }

    try {
      _gyroscopeSubscription =
          gyroscopeEvents.listen(
        (event) {
          _gyroscopeX = event.x;
          _gyroscopeY = event.y;
          _gyroscopeZ = event.z;
          _timestamp = DateTime.now();
        },
        onError: (_) {},
      );
    } catch (_) {
      // Sensor no disponible.
    }

    try {
      _magnetometerSubscription =
          magnetometerEvents.listen(
        (event) {
          _magnetometerX = event.x;
          _magnetometerY = event.y;
          _magnetometerZ = event.z;
          _timestamp = DateTime.now();
        },
        onError: (_) {},
      );
    } catch (_) {
      // Sensor no disponible.
    }

    _initialized = true;
  }

  Future<void> dispose() async {
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _magnetometerSubscription?.cancel();

    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _magnetometerSubscription = null;

    _initialized = false;
  }
}