import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../scanner/adapters/basic_scanner_adapter.dart';
import '../scanner/models/scanner_mode.dart';
import '../scanner/models/scanner_point.dart';
import '../scanner/services/scanner_permission_service.dart';
import 'floor_plan_viewer_screen.dart';

enum BasicAppMode {
  wall,
  door,
  window,
}

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
    extends State<BasicScannerScreen>
    with WidgetsBindingObserver {
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
  bool _processing = false;
  bool _changingLifecycle = false;
  bool _shouldResumeCamera = false;

  String? _initializationError;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addObserver(this);

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
          'El permiso de cámara es necesario '
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
        _cameraController =
            controller;
        _cameraReady = true;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

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
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _shouldResumeCamera = false;
      _pauseCamera();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _shouldResumeCamera = true;
      _resumeCamera();
    }
  }

  Future<void> _pauseCamera() async {
    if (_changingLifecycle) {
      return;
    }

    _changingLifecycle = true;

    final controller =
        _cameraController;

    _cameraController = null;

    if (mounted) {
      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);

      setState(() {
        _cameraReady = false;
        _initializing = true;
      });
    }

    try {
      await controller?.dispose();
    } finally {
      _changingLifecycle = false;

      if (mounted &&
          _shouldResumeCamera) {
        _resumeCamera();
      }
    }
  }

  Future<void> _resumeCamera() async {
    if (_changingLifecycle ||
        _cameraController != null ||
        !_shouldResumeCamera) {
      return;
    }

    _changingLifecycle = true;

    try {
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

      if (!mounted ||
          !_shouldResumeCamera) {
        await controller.dispose();
        return;
      }

      _cameraController =
          controller;

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(true);

      setState(() {
        _cameraReady = true;
        _initializing = false;
        _initializationError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _cameraReady = false;
        _initializing = false;
        _initializationError =
            'No se pudo reanudar la cámara: $error';
      });

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    } finally {
      _changingLifecycle = false;
    }
  }

  @override
  void dispose() {
    _shouldResumeCamera = false;

    WidgetsBinding.instance
        .removeObserver(this);

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
            mainAxisSize:
                MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Preparando cámara...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Scanner Básico',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
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
          _buildScannerOverlay(provider),
          _buildTopHud(provider),
          _buildBottomPanel(provider),
        ],
      ),
    );
  }

  Widget _buildInitializationError() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title:
            const Text('Scanner Básico'),
      ),
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.orange,
                size: 64,
              ),
              const SizedBox(
                height: 20,
              ),
              const Text(
                'No se pudo iniciar la cámara',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                _initializationError ??
                    'Error desconocido.',
                style:
                    const TextStyle(
                  color: Colors.white70,
                ),
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 24,
              ),
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
                  MediaQuery.of(context)
                      .size
                      .width,
          height:
              controller.value.previewSize?.width ??
                  MediaQuery.of(context)
                      .size
                      .height,
          child: CameraPreview(
            controller,
          ),
        ),
      ),
    );
  }

  Widget _buildScannerOverlay(
    ScannerProvider provider,
  ) {
    final points =
        provider.currentRoom?.points ??
            const <ARPoint>[];

    return IgnorePointer(
      child: CustomPaint(
        painter:
            _ScannerGuidePainter(
          points: points,
        ),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildTopHud(
    ScannerProvider provider,
  ) {
    final count =
        provider.currentPointsCount;

    return Positioned(
      top:
          MediaQuery.of(context)
                  .padding
                  .top +
              10,
      left: 12,
      right: 12,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _hudCard(
                  icon:
                      Icons.architecture,
                  title:
                      provider.currentRoom
                              ?.name ??
                          'Nuevo ambiente',
                  subtitle:
                      '$count esquinas',
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              _hudIconButton(
                icon:
                    Icons.map_outlined,
                tooltip:
                    'Ver plano',
                onPressed:
                    _openFloorPlan,
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.black.withValues(
                alpha: 0.78,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              border: Border.all(
                color:
                    Colors.white24,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color:
                      Colors.white70,
                  size: 18,
                ),
                const SizedBox(
                  width: 9,
                ),
                Expanded(
                  child: Text(
                    count == 0
                        ? 'Marcá el punto inicial de la habitación.'
                        : 'Medí la distancia hasta la próxima esquina y elegí su dirección.',
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.black.withValues(
          alpha: 0.78,
        ),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration:
                BoxDecoration(
              color: Colors.blueAccent
                  .withValues(
                alpha: 0.25,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child: Icon(
              icon,
              color:
                  Colors.white,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow:
                      TextOverflow.ellipsis,
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color:
                        Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration:
          BoxDecoration(
        color:
            Colors.black.withValues(
          alpha: 0.78,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildBottomPanel(
    ScannerProvider provider,
  ) {
    final count =        provider.currentPointsCount;

    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: SafeArea(
        top: false,
        child: Container(
          padding:
              const EdgeInsets.fromLTRB(
            12,
            12,
            12,
            12,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.black.withValues(
              alpha: 0.88,
            ),
            borderRadius:
                BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color: Colors.white24,
            ),
          ),
          child: Column(
            children: [
              _buildModeSelector(),
              const SizedBox(
                height: 12,
              ),
              Row(
                children: [
                  _buildUndoButton(
                    provider,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child:
                        _buildMainCaptureButton(
                      provider,
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  _buildFinishButton(
                    provider,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: _modeButton(
            BasicAppMode.wall,
            Icons.wallpaper,
            'Pared',
          ),
        ),
        const SizedBox(
          width: 6,
        ),
        Expanded(
          child: _modeButton(
            BasicAppMode.door,
            Icons.door_front_door,
            'Puerta',
          ),
        ),
        const SizedBox(
          width: 6,
        ),
        Expanded(
          child: _modeButton(
            BasicAppMode.window,
            Icons.window,
            'Ventana',
          ),
        ),
      ],
    );
  }

  Widget _modeButton(
    BasicAppMode mode,
    IconData icon,String label,
  ) {
    final selected =
        _currentMode == mode;

    return InkWell(
      borderRadius:
          BorderRadius.circular(12),
      onTap: () {
        setState(() {
          _currentMode = mode;
        });
      },
      child: AnimatedContainer(
        duration:
            const Duration(
          milliseconds: 160,
        ),
        padding:
            const EdgeInsets.symmetric(
          vertical: 9,
          horizontal: 6,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? Colors.blueAccent
              : Colors.white10,
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: selected
                ? Colors.blueAccent
                : Colors.white12,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? Colors.white
                  : Colors.white70,
              size: 20,
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              label,
              style:
                  TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white70,
                fontSize: 11,
                fontWeight:
                    selected
                        ? FontWeight.bold
                        : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(
    int count,
  ) {
    return Row(
      children: [
        const Icon(
          Icons.polyline,
          color: Colors.white70,
          size: 18,
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                count == 0
                    ? 'Inicio del trazado'
                    : 'Esquina $count registrada',
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              const SizedBox(
                height: 3,
              ),
              Text(
                count < 3
                    ? 'Necesitás al menos 3 esquinas para cerrar.'
                    : 'Podés seguir agregando esquinas o cerrar.',
                style:
                    const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUndoButton(
    ScannerProvider provider,
  ) {
    final enabled =
        provider.currentPointsCount > 0;

    return SizedBox(
      width: 48,
      height: 52,
      child: IconButton(
        onPressed: enabled
            ? () {
                HapticFeedback
                    .lightImpact();

                provider
                    .removeLastPoint();

                _scannerAdapter
                    .removeLastPoint();

                _showMessage(
                  'Última esquina eliminada.',
                );
              }
            : null,
        style:
            IconButton.styleFrom(
          backgroundColor:
              Colors.white10,
          foregroundColor:
              Colors.white,
          disabledForegroundColor:
              Colors.white24,
        ),
        icon: const Icon(
          Icons.undo,
        ),
      ),
    );
  }

  Widget _buildMainCaptureButton(
    ScannerProvider provider,
  ) {
    final count =
        provider.currentPointsCount;

    final String label;

    if (_processing) {
      label = 'CALCULANDO...';
    } else if (count == 0) {
      label = 'MARCAR INICIO';
    } else if (_currentMode ==
        BasicAppMode.wall) {
      label = 'MEDIR SIGUIENTE ESQUINA';
    } else if (_currentMode ==
        BasicAppMode.door) {
      label = 'UBICAR PUERTA';
    } else {
      label = 'UBICAR VENTANA';
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _processing
            ? null
            : () => _capturePressed(
                  provider,
                ),
        icon: Icon(
          count == 0
              ? Icons.location_on
              : Icons.straighten,
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            fontSize: 12,
          ),
        ),
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              Colors.blueAccent,
          foregroundColor:
              Colors.white,
          disabledBackgroundColor:
              Colors.blueGrey,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishButton(
    ScannerProvider provider,
  ) {
    final enabled =
        provider.currentPointsCount >= 3;

    return SizedBox(
      width: 52,
      height: 52,
      child: IconButton(
        onPressed: enabled && !_processing
            ? () => _closeRoom(
                  provider,
                )
            : null,
        style:
            IconButton.styleFrom(
          backgroundColor: enabled
              ? Colors.green
              : Colors.white10,
          foregroundColor:
              Colors.white,
          disabledForegroundColor:
              Colors.white24,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              14,
            ),
          ),
        ),
        icon: const Icon(
          Icons.check,
        ),
      ),
    );
  }

  Future<void> _capturePressed(
    ScannerProvider provider,
  ) async {
    if (_processing) {
      return;
    }

    HapticFeedback.lightImpact();

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
        _scannerAdapter
            .removeLastPoint();

        _showValidationError(
          result.errorMessage ??
              'No se pudo agregar el inicio.',
        );
        return;
      }

      _showMessage(
        'Inicio marcado. Ahora medí la primera pared.',
      );

      return;
    }

    if (_currentMode !=
        BasicAppMode.wall) {
      await _captureFeature(
        provider,
      );
      return;
    }

    await _captureWallPoint(
      provider,
    );
  }

  Future<void> _captureWallPoint(
    ScannerProvider provider,
  ) async {
    final measurement =
        await _showMeasurementDialog(
      nextCorner:
          provider.currentPointsCount + 1,
    );

    if (measurement == null) {
      return;
    }

    setState(() {
      _processing = true;
    });

    try {
      _scannerAdapter
          .setNextMeasurement(
        distanceMeters:
            measurement.distance,
        angleDegrees:
            measurement.angle,
      );

      final candidate =
          _scannerAdapter
              .previewNextPoint();

      if (candidate == null) {
        _showMessage(
          'No se pudo calcular la nueva esquina.',
        );
        return;
      }

      final result =
          provider.tryAddPoint(
        candidate.x,
        candidate.y,
        candidate.z,
      );

      if (!result.isValid) {
        _scannerAdapter
            .cancelPendingMeasurement();

        _showValidationError(
          result.errorMessage ??
              'La esquina no es válida.',
        );

        return;
      }

      _scannerAdapter
          .commitPendingPoint(
        candidate,
      );

      if (result.warningMessage != null) {
        _showMessage(
          result.warningMessage!,
        );
      }
    } catch (error) {
      _scannerAdapter
          .cancelPendingMeasurement();

      _showMessage(
        'No se pudo registrar la medición: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  Future<void> _captureFeature(
    ScannerProvider provider,
  ) async {
    final measurement =
        await _showMeasurementDialog(
      nextCorner:
          provider.currentPointsCount,
      featureMode: true,
    );

    if (measurement == null) {
      return;
    }

    setState(() {
      _processing = true;
    });

    try {
      _scannerAdapter
          .setNextMeasurement(
        distanceMeters:
            measurement.distance,
        angleDegrees:
            measurement.angle,
      );

      final candidate =
          _scannerAdapter
              .previewNextPoint();

      if (candidate == null) {
        _showMessage(
          'No se pudo calcular la ubicación.',
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
        candidate.toARPoint(),
      );

      _scannerAdapter
          .commitPendingPoint(
        candidate,
      );

      _showMessage(
        featureType ==
                FeatureType.door
            ? 'Puerta ubicada correctamente.'
            : 'Ventana ubicada correctamente.',
      );
    } catch (error) {
      _scannerAdapter
          .cancelPendingMeasurement();

      _showMessage(
        'No se pudo registrar la ubicación: $error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  Future<_BasicMeasurement?>
      _showMeasurementDialog({
    required int nextCorner,
    bool featureMode = false,
  }) async {
    final distanceController =
        TextEditingController();

    final angleController =
        TextEditingController(
      text: '90',
    );

    double? distanceError;
    double? angleError;

    return showDialog<_BasicMeasurement>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.straighten,
                    color:
                        Colors.blueAccent,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: Text(
                      featureMode
                          ? 'Ubicar elemento'
                          : 'Medir esquina',
                    ),
                  ),
                ],
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.all(
                        12,
                      ),
                      decoration:
                          BoxDecoration(
                        color: Colors
                            .blueAccent
                            .withValues(
                          alpha: 0.08,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                      child: Text(
                        featureMode
                            ? 'Indicá cuánto hay desde la última posición hasta la puerta o ventana.'
                            : 'Indicá cuánto hay desde la última esquina hasta la nueva esquina.',
                        style:
                            const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    TextField(
                      controller:
                          distanceController,
                      autofocus: true,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          InputDecoration(
                        labelText:                            'Distancia',
                        hintText:
                            'Ejemplo: 3,50',
                        suffixText:
                            'metros',
                        prefixIcon:
                            const Icon(
                          Icons.straighten,
                        ),
                        errorText:
                            distanceError !=
                                    null
                                ? 'Ingresá una distancia mayor a 0'
                                : null,
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
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
                          InputDecoration(
                        labelText:
                            'Dirección',
                        hintText:
                            'Ejemplo: 90',
                        suffixText:
                            'grados',
                        prefixIcon:
                            const Icon(
                          Icons.explore,
                        ),
                        errorText:
                            angleError !=
                                    null
                                ? 'Ingresá una dirección válida'
                                : null,
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Dirección absoluta:',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(
                      height: 7,
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _angleChip('0°',
                          0,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          '90°',
                          90,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          '180°',
                          180,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          '270°',
                          270,
                          angleController,
                          setDialogState,
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      '0° adelante · 90° derecha · '
                      '180° atrás · 270° izquierda',
                      style:
                          TextStyle(
                        color:
                            Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      featureMode
                          ? 'Esto no crea una esquina nueva del ambiente.'
                          : 'La nueva posición se valida antes de incorporarla al plano.',
                      style:
                          const TextStyle(
                        color:
                            Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      const Text(
                    'Cancelar',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final distance =
                        _parseNumber(
                      distanceController
                          .text,
                    );

                    final angle =
                        _parseNumber(
                      angleController
                          .text,
                    );

                    setDialogState(() {
                      distanceError =
                          distance == null ||
                              distance <= 0
                          ? 1
                          : null;

                      angleError =
                          angle == null
                          ? 1
                          : null;
                    });

                    if (distance == null ||
                        distance <= 0 ||
                        angle == null) {
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _BasicMeasurement(
                        distance:
                            distance,
                        angle:
                            angle,
                      ),
                    );
                  },
                  icon:
                      const Icon(
                    Icons.check,
                  ),
                  label:
                      const Text(
                    'Usar medición',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _angleChip(
    String label,
    double value,
    TextEditingController controller,
    StateSetter setDialogState,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        controller.text =
            value.toStringAsFixed(0);

        setDialogState(() {});
      },
    );
  }

  double? _parseNumber(
    String value,
  ) {
    var normalized =
        value.trim().toLowerCase();

    normalized =
        normalized.replaceAll(
      'metros',
      '',
    );

    normalized =
        normalized.replaceAll(
      'metro',
      '',
    );

    normalized =
        normalized.replaceAll(
      'm',
      '',
    );

    normalized =
        normalized.replaceAll(
      'grados',
      '',
    );

    normalized =
        normalized.replaceAll(
      'grado',
      '',
    );

    normalized =
        normalized.replaceAll(
      '°',
      '',
    );

    normalized =
        normalized.trim();

    normalized =
        normalized.replaceAll(
      ',',
      '.',
    );

    return double.tryParse(
      normalized,
    );
  }

  void _showValidationError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              Colors.red.shade800,
          duration:
              const Duration(
            seconds: 4,
          ),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  message,
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _closeRoom(
    ScannerProvider provider,
  ) async {
    if (provider.currentPointsCount <
        3) {
      _showValidationError(
        'Necesitás al menos 3 esquinas para cerrar el ambiente.',
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final room =
        provider.closeCurrentRoom();

    if (room == null) {
      _showValidationError(
        provider.lastCloseError ??
            'No se pudo cerrar el ambiente.',
      );
      return;
    }

    await context
        .read<FloorPlanProvider>()
        .addCompletedRoom(room);

    if (!mounted) {
      return;
    }

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

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior.floating,
          duration:
              const Duration(
            seconds: 2,
          ),
          content: Text(
            message,
          ),
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

class _ScannerGuidePainter
    extends CustomPainter {
  final List<ARPoint> points;

  const _ScannerGuidePainter({
    required this.points,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (points.isEmpty) {
      _drawCenterGuide(
        canvas,
        size,
      );
      return;
    }

    final center =
        Offset(
      size.width / 2,
      size.height / 2,
    );

    final scale =
        _calculateScale(
      points,
      size,
    );

    final projected =
        points.map((point) {
      return Offset(
        center.dx +
            point.x * scale,
        center.dy -
            point.z * scale,
      );
    }).toList();

    final linePaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap =
              StrokeCap.round;

    for (int i = 0;
        i < projected.length - 1;
        i++) {
      canvas.drawLine(
        projected[i],
        projected[i + 1],
        linePaint,
      );
    }

    for (int i = 0;
        i < projected.length;
        i++) {
      final pointPaint =
          Paint()
            ..style =
                PaintingStyle.fill;

      canvas.drawCircle(
        projected[i],
        i == 0 ? 10 : 8,
        pointPaint,
      );

      final textPainter =
          TextPainter(
        text: TextSpan(
          text:
              '${i + 1}',
          style:
              const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        textDirection:
            TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        projected[i] -
            Offset(
              textPainter.width / 2,
              textPainter.height / 2,
            ),
      );
    }

    _drawCenterGuide(
      canvas,
      size,
      onlyCross: true,
    );
  }

  void _drawCenterGuide(
    Canvas canvas,
    Size size, {
    bool onlyCross = false,
  }) {
    final center =
        Offset(
      size.width / 2,
      size.height / 2,
    );

    final paint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawCircle(
      center,
      12,
      paint,
    );

    canvas.drawLine(
      Offset(
        center.dx - 20,
        center.dy,
      ),
      Offset(
        center.dx + 20,
        center.dy,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        center.dx,
        center.dy - 20,
      ),
      Offset(
        center.dx,
        center.dy + 20,
      ),
      paint,
    );
  }

  double _calculateScale(
    List<ARPoint> points,
    Size size,
  ) {
    if (points.length <= 1) {
      return 80;
    }

    double minX = points.first.x;
    double maxX = points.first.x;
    double minZ = points.first.z;
    double maxZ = points.first.z;

    for (final point in points) {
      minX =
          mathMin(
        minX,
        point.x,
      );

      maxX =
          mathMax(
        maxX,
        point.x,
      );

      minZ =
          mathMin(
        minZ,
        point.z,
      );

      maxZ =
          mathMax(
        maxZ,
        point.z,
      );
    }

    final widthMeters =
        (maxX - minX)
            .abs();

    final heightMeters =
        (maxZ - minZ)
            .abs();

    final largest =
        widthMeters >
                heightMeters
            ? widthMeters
            : heightMeters;

    if (largest <= 0) {
      return 80;
    }

    final available =
        size.width < size.height
            ? size.width * 0.45
            : size.height * 0.35;

    return available / largest;
  }

  double mathMin(
    double a,
    double b,
  ) =>
      a < b ? a : b;

  double mathMax(
    double a,
    double b,
  ) =>
      a > b ? a : b;

  @override
  bool shouldRepaint(
    covariant _ScannerGuidePainter oldDelegate,
  ) {
    return oldDelegate.points !=
        points;
  }
}