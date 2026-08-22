import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';

/// Contrato común para cualquier tecnología de captura.
///
/// El resto de la aplicación no debe depender directamente de ARCore,
/// ARKit, CameraX, AVFoundation ni de ningún plugin concreto.
abstract class ScannerAdapter {
  /// Modo que implementa este adapter.
  ScannerMode get mode;

  /// Indica si este adapter está disponible en el dispositivo actual.
  bool get isAvailable;

  /// Indica si el tracking/captura está operativo.
  bool get isTracking;

  /// Inicializa los recursos necesarios.
  Future<void> initialize();

  /// Libera recursos.
  Future<void> dispose();

  /// Captura el punto espacial actual.
  ///
  /// Devuelve null cuando todavía no existe una medición válida.
  Future<ScannerPoint?> capturePoint();
}