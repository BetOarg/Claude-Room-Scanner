import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';
import 'scanner_adapter.dart';

/// Motor central de captura.
///
/// Coordina el adapter activo y expone una API independiente de la
/// tecnología utilizada para obtener las mediciones.
class ScannerEngine {
  ScannerAdapter? _adapter;

  ScannerMode? get mode => _adapter?.mode;

  bool get isInitialized => _adapter != null;

  bool get isAvailable => _adapter?.isAvailable ?? false;

  bool get isTracking => _adapter?.isTracking ?? false;

  /// Inicializa un adapter concreto.
  Future<void> initialize(ScannerAdapter adapter) async {
    await _adapter?.dispose();

    _adapter = adapter;

    if (!_adapter!.isAvailable) {
      throw StateError(
        'El modo ${adapter.mode.name} no está disponible '
        'en este dispositivo.',
      );
    }

    await _adapter!.initialize();
  }

  /// Captura un punto utilizando el adapter activo.
  Future<ScannerPoint?> capturePoint() async {
    final adapter = _adapter;

    if (adapter == null) {
      throw StateError(
        'ScannerEngine no está inicializado.',
      );
    }

    if (!adapter.isAvailable) {
      return null;
    }

    return adapter.capturePoint();
  }

  /// Cambia de adapter.
  Future<void> switchAdapter(ScannerAdapter adapter) async {
    await initialize(adapter);
  }

  /// Libera todos los recursos.
  Future<void> dispose() async {
    await _adapter?.dispose();
    _adapter = null;
  }
}