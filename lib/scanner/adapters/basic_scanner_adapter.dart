import 'dart:math' as math;

import '../engine/scanner_adapter.dart';
import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';

/// Scanner básico para dispositivos que no disponen de ARCore/ARKit.
///
/// No intenta simular tracking AR.
///
/// La posición se obtiene mediante mediciones introducidas por el usuario:
///
/// - distancia desde la última esquina;
/// - dirección absoluta en grados.
///
/// Convención:
///
///   0°   = +Z
///   90°  = +X
///   180° = -Z
///   270° = -X
///
/// El adapter utiliza un modelo transaccional:
///
/// 1. calcula una posición candidata;
/// 2. ScannerProvider valida la geometría;
/// 3. solamente si la geometría es válida se confirma el punto.
///
/// Esto evita que una medición rechazada contamine las mediciones siguientes.
class BasicScannerAdapter implements ScannerAdapter {
  bool _initialized = false;
  bool _tracking = false;

  double _currentX = 0.0;
  double _currentZ = 0.0;

  double? _pendingDistance;
  double? _pendingAngleDegrees;

  final List<ScannerPoint> _history = [];

  @override
  ScannerMode get mode => ScannerMode.basic;

  @override
  bool get isAvailable => true;

  @override
  bool get isTracking => _tracking;

  int get capturedPoints => _history.length;

  double get currentX => _currentX;

  double get currentZ => _currentZ;

  @override
  Future<void> initialize() async {
    _initialized = true;
    _tracking = true;

    reset();
  }

  /// Define la medición para la próxima esquina.
  void setNextMeasurement({
    required double distanceMeters,
    required double angleDegrees,
  }) {
    if (!distanceMeters.isFinite || distanceMeters <= 0) {
      throw ArgumentError(
        'La distancia debe ser mayor que 0.',
      );
    }

    if (!angleDegrees.isFinite) {
      throw ArgumentError(
        'La dirección debe ser un número válido.',
      );
    }

    _pendingDistance = distanceMeters;
    _pendingAngleDegrees = angleDegrees;
  }

  /// Calcula el próximo punto sin modificar el estado.
  ///
  /// El punto debe ser confirmado mediante [commitPendingPoint]
  /// solamente después de que ScannerProvider lo haya validado.
  ScannerPoint? previewNextPoint() {
    if (!_initialized) {
      return null;
    }

    // Primera esquina = origen.
    if (_history.isEmpty) {
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

    final deltaX =
        math.sin(angleRadians) * distance;

    final deltaZ =
        math.cos(angleRadians) * distance;

    return ScannerPoint(
      x: _currentX + deltaX,
      y: 0.0,
      z: _currentZ + deltaZ,
      accuracy: 0.0,
      source: PointSource.camera,
    );
  }

  /// Confirma el punto después de que el provider lo haya aceptado.
  void commitPendingPoint(
    ScannerPoint point,
  ) {
    if (!_initialized) {
      return;
    }

    _currentX = point.x;
    _currentZ = point.z;

    _history.add(point);

    _pendingDistance = null;
    _pendingAngleDegrees = null;
  }

  /// Carga un tramo inicial ya conocido sin solicitar una nueva medición.
  ///
  /// Se utiliza al continuar desde una abertura: el historial contiene el
  /// extremo opuesto y, al final, el extremo A o B elegido por el usuario.
  void seedPath(
    List<ScannerPoint> points,
  ) {
    if (!_initialized) {
      return;
    }

    _history
      ..clear()
      ..addAll(points);

    _pendingDistance = null;
    _pendingAngleDegrees = null;

    if (_history.isEmpty) {
      _currentX = 0.0;
      _currentZ = 0.0;
      return;
    }

    final last = _history.last;
    _currentX = last.x;
    _currentZ = last.z;
  }

  /// Captura y confirma directamente un punto.
  ///
  /// Se conserva para compatibilidad con ScannerAdapter.
  @override
  Future<ScannerPoint?> capturePoint() async {
    final point = previewNextPoint();

    if (point == null) {
      return null;
    }

    commitPendingPoint(point);

    return point;
  }

  /// Elimina la última esquina confirmada.
  ///
  /// Se utiliza junto con ScannerProvider.removeLastPoint().
  void removeLastPoint() {
    if (_history.isEmpty) {
      return;
    }

    _history.removeLast();

    _pendingDistance = null;
    _pendingAngleDegrees = null;

    if (_history.isEmpty) {
      _currentX = 0.0;
      _currentZ = 0.0;
      return;
    }

    final last = _history.last;

    _currentX = last.x;
    _currentZ = last.z;
  }

  /// Cancela una medición pendiente sin modificar la geometría.
  void cancelPendingMeasurement() {
    _pendingDistance = null;
    _pendingAngleDegrees = null;
  }

  /// Reinicia completamente el trazado.
  void reset() {
    _currentX = 0.0;
    _currentZ = 0.0;

    _pendingDistance = null;
    _pendingAngleDegrees = null;

    _history.clear();
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _tracking = false;

    reset();
  }
}