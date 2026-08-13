import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/permission_service.dart';
import '../utils/ar_stability_filter.dart';
import '../utils/scan_validator.dart';
import 'floor_plan_viewer_screen.dart';

enum AppMode {
  wall,
  door,
  window,
}

class ARScannerScreen extends StatefulWidget {
  /// UUID del proyecto Isar al que pertenece este escaneo. Se usa para
  /// persistir cada habitación cerrada de inmediato (antes las
  /// habitaciones cerradas solo vivían en memoria dentro de
  /// `ScannerProvider` y se perdían en cuanto se salía de esta pantalla).
  final String projectUuid;
  final String projectName;

  const ARScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
  });

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen> {
  AppMode _currentMode = AppMode.wall;

  // Controladores del Plugin AR.
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  // Posición actual estimada del dispositivo/cámara.
  vector.Vector3 _currentCameraPosition = vector.Vector3(0, 0, 0);

  // Suaviza el ruido de la pose de la cámara (media móvil exponencial) para
  // que los vértices capturados no salten con cada micro-temblor del
  // tracking.
  final ARStabilityFilter _stabilityFilter = ARStabilityFilter();

  bool _permissionsGranted = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Antes nadie llamaba a PermissionService: la app dependía de que el
      // plugin de AR pidiera los permisos por su cuenta, lo que en Android
      // puede dejar la cámara en negro sin ningún mensaje si el permiso
      // fue denegado previamente.
      final granted = await PermissionService.requestScannerPermissions();
      if (!mounted) return;

      setState(() {
        _permissionsGranted = granted;
        _checkingPermissions = false;
      });

      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Se necesitan permisos de cámara y ubicación para escanear.',
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (!mounted) return;
      context.read<ScannerProvider>().startNewRoom();
    });
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arSessionManager!.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
      handleTaps: false,
    );

    _arObjectManager!.onInitialize();

    // Notificar al Provider que la vista AR está activa
    // y que comenzó la inicialización del tracking.
    if (mounted) {
      context.read<ScannerProvider>().updateTrackingStatus(true);
    }
  }

  /// Obtiene la posición 3D actual de la cámara, ya suavizada por
  /// [ARStabilityFilter]. Devuelve `null` si el tracking todavía no entregó
  /// ninguna pose válida — en ese caso NO hay que capturar un punto con una
  /// posición inventada (antes se usaba silenciosamente Vector3(0,0,-1) o la
  /// última posición conocida, generando esquinas incorrectas sin avisar).
  Future<vector.Vector3?> _getCurrentCameraPosition() async {
    if (_arSessionManager == null) return null;

    final pose = await _arSessionManager!.getCameraPose();
    if (pose == null) return null;

    final translation = pose.getTranslation();
    _currentCameraPosition = translation;

    final smoothed = _stabilityFilter.filter(translation) ?? translation;
    return smoothed;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();

    if (_checkingPermissions) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Permisos requeridos')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No se otorgaron los permisos de cámara/ubicación. '
              'Habilítalos desde los ajustes del sistema para poder escanear.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ============================================================
          // CAPA 1: VIEWPORT AR REAL
          // ============================================================

          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig:
                PlaneDetectionConfig.horizontalAndVertical,
          ),

          // ============================================================
          // CAPA 2: RETÍCULA CENTRAL
          // ============================================================

          Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: 2,
                ),
              ),
            ),
          ),

          // ============================================================
          // CAPA 3: HUD SUPERIOR DE ESTADO
          // ============================================================

          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  avatar: const Icon(
                    Icons.meeting_room,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    provider.currentRoom?.name ?? 'Nuevo Ambiente',
                  ),
                  backgroundColor: Colors.black87,
                  labelStyle: const TextStyle(
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Ver plano del proyecto',
                      onPressed: _openFloorPlan,
                      icon: const Icon(Icons.map_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      avatar: Icon(
                        Icons.circle,
                        size: 10,
                        color: provider.isTrackingOk
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                      label: Text(
                        provider.isTrackingOk
                            ? 'AR Activo'
                            : 'Calibrando...',
                      ),
                      backgroundColor: Colors.black87,
                      labelStyle: const TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ============================================================
          // CAPA 4: CONTADOR DE PUNTOS
          // ============================================================

          if (provider.currentPointsCount > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                child: Text(
                  'Esquinas: ${provider.currentPointsCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          // ============================================================
          // CAPA 5: CONTROLES INFERIORES
          // ============================================================

          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ------------------------------------------------------
                // SELECTOR DE MODO
                // ------------------------------------------------------

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildModeChip(
                      AppMode.wall,
                      Icons.wallpaper,
                      'Pared',
                    ),
                    const SizedBox(width: 8),
                    _buildModeChip(
                      AppMode.door,
                      Icons.door_front_door,
                      'Puerta',
                    ),
                    const SizedBox(width: 8),
                    _buildModeChip(
                      AppMode.window,
                      Icons.window,
                      'Ventana',
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ------------------------------------------------------
                // SELECTOR DE TIPO DE HABITACIÓN
                // ------------------------------------------------------

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: RoomType.values.map((type) {
                      final isSelected =
                          provider.selectedType == type;

                      return Padding(
                        padding: const EdgeInsets.only(
                          right: 8.0,
                        ),
                        child: ChoiceChip(
                          label: Text(
                            type.name.toUpperCase(),
                          ),
                          selected: isSelected,
                          selectedColor: Colors.blueAccent,
                          backgroundColor: Colors.black87,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();

                            provider.setRoomType(type);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // ------------------------------------------------------
                // BOTONES PRINCIPALES DE ESCANEO
                // ------------------------------------------------------

                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed:
                          provider.currentPointsCount > 0
                              ? () {
                                  HapticFeedback.lightImpact();

                                  provider.removeLastPoint();
                                }
                              : null,
                      icon: const Icon(Icons.undo),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _onCapturePressed(provider),
                        icon: Icon(
                          _currentMode == AppMode.wall
                              ? Icons.add_location_alt_outlined
                              : _currentMode == AppMode.door
                                  ? Icons.door_front_door
                                  : Icons.window,
                        ),
                        label: Text(
                          _currentMode == AppMode.wall
                              ? 'AÑADIR ESQUINA'
                              : _currentMode == AppMode.door
                                  ? 'AÑADIR PUERTA'
                                  : 'AÑADIR VENTANA',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          backgroundColor:
                              _currentMode == AppMode.wall
                                  ? Colors.blueAccent
                                  : _currentMode == AppMode.door
                                      ? Colors.redAccent
                                      : Colors.blue.shade300,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    IconButton.filled(
                      onPressed:
                          provider.currentPointsCount >= 3
                              ? () => _onCloseRoomPressed(provider)
                              : null,
                      icon: const Icon(Icons.check),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            provider.currentPointsCount >= 3
                                ? Colors.green
                                : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // SELECTOR DE MODO
  // ================================================================

  Widget _buildModeChip(
    AppMode mode,
    IconData icon,
    String label,
  ) {
    final isSelected = _currentMode == mode;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected
            ? Colors.white
            : Colors.white70,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: mode == AppMode.wall
          ? Colors.blueAccent
          : mode == AppMode.door
              ? Colors.redAccent
              : Colors.blue.shade300,
      backgroundColor: Colors.black87,
      labelStyle: TextStyle(
        color: isSelected
            ? Colors.white
            : Colors.white70,
        fontWeight: isSelected
            ? FontWeight.bold
            : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (!selected) return;

        HapticFeedback.selectionClick();

        setState(() {
          _currentMode = mode;
        });
      },
    );
  }

  // ================================================================
  // CAPTURA DE PUNTOS / ABERTURAS
  // ================================================================

  Future<void> _onCapturePressed(ScannerProvider provider) async {
    HapticFeedback.lightImpact();

    final pos = await _getCurrentCameraPosition();
    if (!mounted) return;

    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se detectó una posición de cámara válida. Apunta a una '
            'superficie reconocida e intenta de nuevo.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    switch (_currentMode) {
      case AppMode.wall:
        _handleWallPoint(provider, pos);
        break;
      case AppMode.door:
      case AppMode.window:
        _handleFeatureInsertion(provider, _currentMode, pos);
        break;
    }
  }

  void _handleWallPoint(ScannerProvider provider, vector.Vector3 pos) {
    final ValidationResult result = provider.tryAddPoint(pos.x, pos.y, pos.z);

    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Punto inválido.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (result.warningMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.warningMessage!),
          backgroundColor: Colors.amber.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleFeatureInsertion(
    ScannerProvider provider,
    AppMode mode,
    vector.Vector3 position,
  ) {
    if (provider.currentPointsCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas marcar al menos 2 esquinas '
            'antes de agregar una abertura.',
          ),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    final label = mode == AppMode.door ? 'Puerta' : 'Ventana';
    final featureType =
        mode == AppMode.door ? FeatureType.door : FeatureType.window;

    // Las puertas/ventanas se guardan como WallFeature (con su propio punto
    // de inicio/fin), no como un vértice más del contorno: antes se
    // insertaban con `addPoint`, lo que agregaba una esquina falsa al
    // polígono de la habitación por cada puerta o ventana marcada.
    provider.addFeatureToCurrentRoom(
      featureType,
      ARPoint(x: position.x, y: position.y, z: position.z),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label marcada en la posición actual',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ================================================================
  // CIERRE Y PERSISTENCIA DE LA HABITACIÓN
  // ================================================================

  Future<void> _onCloseRoomPressed(ScannerProvider provider) async {
    HapticFeedback.mediumImpact();

    final closedRoom = provider.closeCurrentRoom();

    if (!mounted) return;

    if (closedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.lastCloseError ??
                'No se pudo cerrar la habitación. Revisa los puntos trazados.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Persistir de inmediato: antes la habitación cerrada solo quedaba en
    // memoria dentro de ScannerProvider y se perdía apenas se volvía al
    // dashboard, porque ninguna pantalla llamaba a
    // FloorPlanProvider.addCompletedRoom (que a su vez ya guarda en Isar a
    // través del `persister` conectado en main.dart).
    await context.read<FloorPlanProvider>().addCompletedRoom(closedRoom);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Ambiente guardado correctamente!'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FloorPlanViewerScreen()),
    );
  }
}
