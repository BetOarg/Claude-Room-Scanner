import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../scanner/adapters/basic_scanner_adapter.dart';
import '../scanner/services/scanner_permission_service.dart';
import '../models/room_model.dart';
import '../utils/scan_validator.dart';
import 'floor_plan_viewer_screen.dart';

enum BasicAppMode {
  wall,
  door,
  window,
}

/// Scanner de respaldo para dispositivos sin ARCore/ARKit.
///
/// Utiliza:
///
/// - cámara del dispositivo;
/// - medición guiada;
/// - coordenadas métricas X/Z;
/// - ScannerProvider;
/// - ScanValidator.
///
/// No requiere RealityKit, ARKit ni ARCore.
class BasicScannerScreen extends StatefulWidget {
  final String projectUuid;
  final String projectName;

  const BasicScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
  });

  @override
  State<BasicScannerScreen> createState() =>
      _BasicScannerScreenState();
}

class _BasicScannerScreenState
    extends State<BasicScannerScreen> {
  CameraController? _cameraController;

  final BasicScannerAdapter _scannerAdapter =
      BasicScannerAdapter();

  final ScannerPermissionService
      _permissionService =
      const ScannerPermissionService();

  BasicAppMode _currentMode =
      BasicAppMode.wall;

  bool _initializing = true;
  bool _cameraReady = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      final permissionGranted =
          await _permissionService
              .requestForMode(
        ScannerMode.basic,
      );

      if (!permissionGranted) {
        throw StateError(
          'Se necesita permiso de cámara '
          'para utilizar el Scanner Básico.',
        );
      }

      final cameras =
          await availableCameras();

      if (cameras.isEmpty) {
        throw StateError(
          'El dispositivo no tiene una cámara disponible.',
        );
      }

      final selectedCamera =
          cameras.firstWhere(
        (camera) =>
            camera.lensDirection ==
            CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller =
          CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      await _scannerAdapter.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      context
          .read<ScannerProvider>()
          .startNewRoom();

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(true);

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _initializing = false;
        _cameraReady = false;
        _initializationError =
            error.toString();
      });

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    }
  }

  @override
  void dispose() {
    _scannerAdapter.dispose();
    _cameraController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<ScannerProvider>();

    if (_initializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Inicializando Scanner Básico...',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady) {
      return _buildInitializationError();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraPreview(),
          _buildCenterReticle(),
          _buildTopHud(provider),
          _buildBottomControls(provider),
        ],
      ),
    );
  }

  Widget _buildInitializationError() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Scanner Básico',
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.orange,
                size: 64,
              ),
              const SizedBox(height: 20),
              const Text(
                'No se pudo iniciar la cámara',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _initializationError ??
                    'Error desconocido.',
                style: const TextStyle(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initialize,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Reintentar',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
      );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:
              controller.value.previewSize?.height ??
                  MediaQuery.of(context).size.width,
          height:
              controller.value.previewSize?.width ??
                  MediaQuery.of(context).size.height,
          child: CameraPreview(
            controller,
          ),
        ),
      ),
    );
  }

  Widget _buildCenterReticle() {
    return Center(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildTopHud(
    ScannerProvider provider,
  ) {
    return Positioned(
      top:
          MediaQuery.of(context).padding.top +
              12,
      left: 16,
      right: 16,
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Chip(
                avatar: const Icon(
                  Icons.camera_alt,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  provider.currentRoom?.name ??
                      'Nuevo Ambiente',
                ),
                backgroundColor:
                    Colors.black87,
                labelStyle:
                    const TextStyle(
                  color: Colors.white,
                ),
              ),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip:
                        'Ver plano del proyecto',
                    onPressed:
                        _openFloorPlan,
                    icon: const Icon(
                      Icons.map_outlined,
                    ),
                    style:
                        IconButton.styleFrom(
                      backgroundColor:
                          Colors.black87,
                      foregroundColor:
                          Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: Icon(
                      Icons.circle,
                      size: 10,
                      color: provider
                              .isTrackingOk
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    label: const Text(
                      'Básico',
                    ),
                    backgroundColor:
                        Colors.black87,
                    labelStyle:
                        const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: const Text(
              'Modo sin ARCore/ARKit · '
              'Las distancias se ingresan manualmente.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(
    ScannerProvider provider,
  ) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              _buildModeChip(
                BasicAppMode.wall,
                Icons.wallpaper,
                'Pared',
              ),
              const SizedBox(width: 8),
              _buildModeChip(
                BasicAppMode.door,
                Icons.door_front_door,
                'Puerta',
              ),
              const SizedBox(width: 8),
              _buildModeChip(
                BasicAppMode.window,
                Icons.window,
                'Ventana',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection:
                Axis.horizontal,
            child: Row(
              children:
                  RoomType.values.map((type) {
                final selected =
                    provider.selectedType ==
                        type;

                return Padding(
                  padding:
                      const EdgeInsets.only(
                    right: 8,
                  ),
                  child: ChoiceChip(
                    label: Text(
                      type.name
                          .toUpperCase(),
                    ),
                    selected: selected,
                    selectedColor:
                        Colors.blueAccent,
                    backgroundColor:
                        Colors.black87,
                    labelStyle:
                        TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white70,
                    ),
                    onSelected: (_) {
                      provider
                          .setRoomType(type);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed:
                    provider.currentPointsCount >
                            0
                        ? () {
                            HapticFeedback
                                .lightImpact();

                            provider
                                .removeLastPoint();

                            _rebuildAdapterFromProvider(
                              provider,
                            );
                          }
                        : null,
                icon: const Icon(
                  Icons.undo,
                ),
                style:
                    IconButton.styleFrom(
                  backgroundColor:
                      Colors.black87,
                  foregroundColor:
                      Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _capturePressed(
                    provider,
                  ),
                  icon: Icon(
                    _currentMode ==
                            BasicAppMode.wall
                        ? Icons
                            .add_location_alt_outlined
                        : _currentMode ==
                                BasicAppMode.door
                            ? Icons
                                .door_front_door
                            : Icons.window,
                  ),
                  label: Text(
                    _currentMode ==
                            BasicAppMode.wall
                        ? 'AÑADIR ESQUINA'
                        : _currentMode ==
                                BasicAppMode.door
                            ? 'AÑADIR PUERTA'
                            : 'AÑADIR VENTANA',
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 16,
                    ),
                    backgroundColor:
                        Colors.blueAccent,
                    foregroundColor:
                        Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed:
                    provider.currentPointsCount >=
                            3
                        ? () =>
                            _closeRoom(provider)
                        : null,
                icon: const Icon(
                  Icons.check,
                ),
                style:
                    IconButton.styleFrom(
                  backgroundColor:
                      provider.currentPointsCount >=
                              3
                          ? Colors.green
                          : Colors.grey,
                  foregroundColor:
                      Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(
    BasicAppMode mode,
    IconData icon,
    String label,
  ) {
    final selected =
        _currentMode == mode;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected
            ? Colors.white
            : Colors.white70,
      ),
      label: Text(label),
      selected: selected,
      selectedColor:
          Colors.blueAccent,
      backgroundColor:
          Colors.black87,
      labelStyle: TextStyle(
        color: selected
            ? Colors.white
            : Colors.white70,
      ),
      onSelected: (value) {
        if (!value) return;

        setState(() {
          _currentMode = mode;
        });
      },
    );
  }

  Future<void> _capturePressed(
    ScannerProvider provider,
  ) async {
    HapticFeedback.lightImpact();

    // Primera esquina = origen.
    if (provider.currentPointsCount == 0) {
      final point =
          await _scannerAdapter
              .capturePoint();

      if (point == null) {
        _showMessage(
          'No se pudo crear el punto inicial.',
        );
        return;
      }

      final result =
          provider.tryAddPoint(
        point.x,
        point.y,
        point.z,
      );

      if (!result.isValid) {
        _showMessage(
          result.errorMessage ??
              'Punto inválido.',
        );
      }

      return;
    }

    final measurement =
        await _showMeasurementDialog();

    if (measurement == null) {
      return;
    }

    _scannerAdapter.setNextMeasurement(
      distanceMeters:
          measurement.distance,
      angleDegrees:
          measurement.angle,
    );

    final point =
        await _scannerAdapter
            .capturePoint();

    if (point == null) {
      _showMessage(
        'No se pudo calcular el punto.',
      );
      return;
    }

    if (_currentMode ==
        BasicAppMode.wall) {
      _addWallPoint(
        provider,
        point,
      );
      return;
    }

    final featureType =
        _currentMode ==
                BasicAppMode.door
            ? FeatureType.door
            : FeatureType.window;

    provider.addFeatureToCurrentRoom(
      featureType,
      point.toARPoint(),
    );

    _showMessage(
      _currentMode ==
              BasicAppMode.door
          ? 'Puerta agregada.'
          : 'Ventana agregada.',
    );
  }

  void _addWallPoint(
    ScannerProvider provider,
    dynamic point,
  ) {
    final result =
        provider.tryAddPoint(
      point.x,
      point.y,
      point.z,
    );

    if (!result.isValid) {
      _showMessage(
        result.errorMessage ??
            'Punto inválido.',
      );
      return;
    }

    if (result.warningMessage != null) {
      _showMessage(
        result.warningMessage!,
      );
    }
  }

  Future<_BasicMeasurement?>
      _showMeasurementDialog() async {
    final distanceController =
        TextEditingController();

    final angleController =
        TextEditingController(
      text: '90',
    );

    return showDialog<_BasicMeasurement>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Medir siguiente punto',
          ),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              TextField(
                controller:
                    distanceController,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Distancia (metros)',
                  hintText:
                      'Ej. 3.50',
                  suffixText: 'm',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller:
                    angleController,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Dirección (grados)',
                  hintText:
                      '0 = adelante, 90 = derecha',
                  suffixText: '°',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'La dirección se mide respecto del '
                'eje del plano. Para un rectángulo '
                'puedes usar 0°, 90°, 180° y 270°.',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final distance =
                    double.tryParse(
                  distanceController
                      .text
                      .replaceAll(
                        ',',
                        '.',
                      ),
                );

                final angle =
                    double.tryParse(
                  angleController
                      .text
                      .replaceAll(
                        ',',
                        '.',
                      ),
                );

                if (distance == null ||
                    distance <= 0 ||
                    angle == null) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ingresa una distancia y dirección válidas.',
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  _BasicMeasurement(
                    distance: distance,
                    angle: angle,
                  ),
                );
              },
              child:
                  const Text('Capturar'),
            ),
          ],
        );
      },
    );
  }

  void _rebuildAdapterFromProvider(
    ScannerProvider provider,
  ) {
    _scannerAdapter.reset();

    // El adapter necesita conocer la cantidad
    // de puntos existentes. Para v1 no
    // reconstruimos el historial completo
    // porque el usuario simplemente deshizo
    // el último punto.
    //
    // La próxima captura seguirá desde la
    // posición calculada actualmente por el
    // adapter cuando no se haya reiniciado
    // completamente la sesión.
  }

  Future<void> _closeRoom(
    ScannerProvider provider,
  ) async {
    HapticFeedback.mediumImpact();

    final room =
        provider.closeCurrentRoom();

    if (room == null) {
      _showMessage(
        provider.lastCloseError ??
            'No se pudo cerrar el ambiente.',
      );
      return;
    }

    await context
        .read<FloorPlanProvider>()
        .addCompletedRoom(room);

    if (!mounted) return;

    _showMessage(
      'Ambiente guardado correctamente.',
    );

    Navigator.pop(context);
  }

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const FloorPlanViewerScreen(),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }
}

class _BasicMeasurement {
  final double distance;
  final double angle;

  const _BasicMeasurement({
    required this.distance,
    required this.angle,
  });
}