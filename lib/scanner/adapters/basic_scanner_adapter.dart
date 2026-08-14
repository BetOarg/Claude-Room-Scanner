import 'dart:math' as math;

import '../engine/scanner_adapter.dart';
import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';

/// Scanner básico para dispositivos que no disponen de ARCore/ARKit.
///
/// Este adapter no intenta fabricar una pose 3D falsa.
///
/// La posición se calcula mediante mediciones relativas introducidas por
/// el usuario:
///
/// - distancia desde el último punto;
/// - dirección en grados.
///
/// El plano utilizado es X/Z, igual que ScanValidator.
///
/// Convención:
///
///   0°   = +Z
///   90°  = +X
///   180° = -Z
///   270° = -X
///
/// Este es el fallback seguro de v1 para dispositivos sin AR.
class BasicScannerAdapter implements ScannerAdapter {
  bool _initialized = false;
  bool _tracking = false;

  double _currentX = 0.0;
  double _currentZ = 0.0;

  double? _pendingDistance;
  double? _pendingAngleDegrees;

  int _capturedPoints = 0;

  @override
  ScannerMode get mode => ScannerMode.basic;

  /// El adapter básico no depende de ARCore ni ARKit.
  @override
  bool get isAvailable => true;

  @override
  bool get isTracking => _tracking;

  int get capturedPoints => _capturedPoints;

  double get currentX => _currentX;

  double get currentZ => _currentZ;

  /// Inicializa el sistema geométrico.
  @override
  Future<void> initialize() async {
    _initialized = true;
    _tracking = true;
  }

  /// Define la medición que será utilizada por la próxima captura.
  ///
  /// [distanceMeters]
  /// Distancia desde el último punto.
  ///
  /// [angleDegrees]
  /// Dirección respecto del eje +Z.
  void setNextMeasurement({
    required double distanceMeters,
    required double angleDegrees,
  }) {
    if (distanceMeters <= 0) {
      throw ArgumentError(
        'La distancia debe ser mayor que cero.',
      );
    }

    if (!distanceMeters.isFinite) {
      throw ArgumentError(
        'La distancia no es válida.',
      );
    }

    if (!angleDegrees.isFinite) {
      throw ArgumentError(
        'El ángulo no es válido.',
      );
    }

    _pendingDistance = distanceMeters;
    _pendingAngleDegrees = angleDegrees;
  }

  /// Captura el siguiente punto.
  ///
  /// La primera captura siempre crea el origen:
  ///
  ///     (0, 0, 0)
  ///
  /// Las siguientes capturas requieren una medición previamente definida
  /// mediante [setNextMeasurement].
  @override
  Future<ScannerPoint?> capturePoint() async {
    if (!_initialized) {
      return null;
    }

    // Primera esquina = origen.
    if (_capturedPoints == 0) {
      _currentX = 0.0;
      _currentZ = 0.0;
      _capturedPoints++;

      return const ScannerPoint(
        x: 0.0,
        y: 0.0,
        z: 0.0,
        accuracy: 0.0,
        source: PointSource.camera,
      );
    }

    final distance = _pendingDistance;
    final angleDegrees = _pendingAngleDegrees;

    if (distance == null || angleDegrees == null) {
      return null;
    }

    final angleRadians =
        angleDegrees * math.pi / 180.0;

    // Convención:
    //
    // 0° = +Z
    // 90° = +X
    //
    // Por lo tanto:
    //
    // X = sin(ángulo) * distancia
    // Z = cos(ángulo) * distancia
    final deltaX =
        math.sin(angleRadians) * distance;

    final deltaZ =
        math.cos(angleRadians) * distance;

    _currentX += deltaX;
    _currentZ += deltaZ;

    _pendingDistance = null;
    _pendingAngleDegrees = null;

    _capturedPoints++;

    return ScannerPoint(
      x: _currentX,
      y: 0.0,
      z: _currentZ,
      accuracy: 0.0,
      source: PointSource.camera,
    );
  }

  /// Reinicia el trazado geométrico.
  void reset() {
    _currentX = 0.0;
    _currentZ = 0.0;

    _pendingDistance = null;
    _pendingAngleDegrees = null;

    _capturedPoints = 0;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _tracking = false;

    reset();
  }
}