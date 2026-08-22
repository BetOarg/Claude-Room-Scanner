import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../utils/ar_stability_filter.dart';
import '../engine/scanner_adapter.dart';
import '../models/scanner_mode.dart';
import '../models/scanner_point.dart';

/// Adapter del motor AR.
///
/// Encapsula toda la interacción con ar_flutter_plugin_2.
///
/// IMPORTANTE:
/// - No contiene lógica de RoomModel.
/// - No contiene lógica de ScannerProvider.
/// - No contiene UI.
/// - No decide cuándo guardar una habitación.
/// - Solamente administra la sesión AR y entrega ScannerPoint.
class ARScannerAdapter implements ScannerAdapter {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;

  final ARStabilityFilter _stabilityFilter = ARStabilityFilter();

  bool _initialized = false;
  bool _tracking = false;

  vector.Vector3? _lastPosition;

  @override
  ScannerMode get mode => ScannerMode.ar;

  @override
  bool get isAvailable => _sessionManager != null;

  @override
  bool get isTracking => _tracking;

  /// El adapter AR necesita recibir los managers creados por ARView.
  ///
  /// ARView sigue perteneciendo a la UI.
  void attachARSession({
    required ARSessionManager sessionManager,
    required ARObjectManager objectManager,
  }) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;

    _initializeManagers();
  }

  void _initializeManagers() {
    final session = _sessionManager;
    final objects = _objectManager;

    if (session == null || objects == null) {
      return;
    }

    session.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
      handleTaps: false,
    );

    objects.onInitialize();

    _initialized = true;
    _tracking = true;
  }

  @override
  Future<void> initialize() async {
    if (_sessionManager == null) {
      throw StateError(
        'ARScannerAdapter necesita una ARSessionManager. '
        'Conecta primero ARView mediante attachARSession().',
      );
    }

    if (!_initialized) {
      _initializeManagers();
    }
  }

  /// Obtiene la posición actual de la cámara y la transforma en
  /// ScannerPoint.
  ///
  /// Nunca devuelve una posición artificial como (0,0,0).
  @override
  Future<ScannerPoint?> capturePoint() async {
    final session = _sessionManager;

    if (session == null || !_initialized) {
      return null;
    }

    final pose = await session.getCameraPose();

    if (pose == null) {
      return null;
    }

    final translation = pose.getTranslation();

    _lastPosition = translation;

    final filtered =
        _stabilityFilter.filter(translation) ?? translation;

    return ScannerPoint(
      x: filtered.x,
      y: filtered.y,
      z: filtered.z,
      accuracy: _estimateAccuracy(),
      source: PointSource.ar,
    );
  }

  /// Precisión estimada.
  ///
  /// ARCore/ARKit no necesariamente entregan aquí una precisión métrica
  /// directa mediante este plugin, por lo que no inventamos una precisión
  /// falsa. El valor 0 significa "desconocida".
  double _estimateAccuracy() {
    return 0.0;
  }

  vector.Vector3? get lastPosition => _lastPosition;

  /// Notifica al adapter que el tracking se encuentra operativo.
  void setTrackingStatus(bool tracking) {
    _tracking = tracking;
  }

  @override
  Future<void> dispose() async {
    _tracking = false;
    _initialized = false;
    _lastPosition = null;

    final session = _sessionManager;

    _sessionManager = null;
    _objectManager = null;

    await session?.dispose();
  }
}