import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/room_type_localization.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/scanner_provider.dart';
import '../scanner/adapters/basic_scanner_adapter.dart';
import '../scanner/models/scanner_mode.dart';
import '../scanner/models/scanner_point.dart';
import '../scanner/services/scanner_permission_service.dart';
import '../utils/scan_validator.dart';
import 'floor_plan_viewer_screen.dart';

enum BasicAppMode {
  wall,
  door,
  window,
}

class BasicScannerScreen extends StatefulWidget {
  final String projectUuid;
  final String projectName;
  final ScanContinuationReference? continuationReference;

  const BasicScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
    this.continuationReference,
  });

  @override
  State<BasicScannerScreen> createState() =>
      _BasicScannerScreenState();
}

class _BasicScannerScreenState
    extends State<BasicScannerScreen>
    with WidgetsBindingObserver {
  static const Duration _cameraInitializationTimeout =
      Duration(seconds: 12);
  static const Duration _automaticRetryDelay =
      Duration(milliseconds: 800);

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
  bool _initializationInProgress = false;
  bool _scannerInitialized = false;
  bool _roomStarted = false;

  double _lastAngleDegrees = 90.0;

  String? _initializationError;

  int get _protectedInitialPointCount =>
      0;

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

  Future<void> _initialize({
    bool allowAutomaticRetry = true,
  }) async {
    if (_initializationInProgress) {
      return;
    }

    _initializationInProgress = true;

    if (mounted) {
      setState(() {
        _initializing = true;
        _cameraReady = false;
        _initializationError = null;
      });
    }

    CameraController? controller;

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

      final maximumAttempts =
          allowAutomaticRetry ? 2 : 1;
      Object? lastError;

      for (var attempt = 0;
          attempt < maximumAttempts;
          attempt++) {
        try {
          controller =
              await _createInitializedCameraController();
          lastError = null;
          break;
        } catch (error) {
          lastError = error;

          if (attempt + 1 < maximumAttempts) {
            await Future<void>.delayed(
              _automaticRetryDelay,
            );
          }
        }
      }

      if (controller == null) {
        if (lastError != null) {
          throw lastError;
        }

        throw StateError(
          'No se pudo iniciar la cámara.',
        );
      }

      if (!_scannerInitialized) {
        await _scannerAdapter.initialize();
        _scannerInitialized = true;
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      final scannerProvider =
          context.read<ScannerProvider>();

      if (!_roomStarted) {
        _startScannerRoom(
          scannerProvider,
        );
        _roomStarted = true;
      }

      scannerProvider.updateTrackingStatus(true);

      setState(() {
        _cameraController =
            controller;
        _cameraReady = true;
        _initializing = false;
        _initializationError = null;
      });
    } catch (error) {
      await controller?.dispose();

      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _cameraReady = false;
        _initializationError =
            _cameraErrorMessage(error);
      });

      context
          .read<ScannerProvider>()
          .updateTrackingStatus(false);
    } finally {
      _initializationInProgress = false;
    }
  }

  Future<CameraController>
      _createInitializedCameraController() async {
    final cameras = await availableCameras().timeout(
      _cameraInitializationTimeout,
    );

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

    try {
      await controller.initialize().timeout(
        _cameraInitializationTimeout,
      );
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  String _cameraErrorMessage(
    Object? error,
  ) {
    if (error is TimeoutException) {
      return 'La cámara tardó demasiado en responder. '
          'Podés intentar iniciarla nuevamente.';
    }

    final message =
        error?.toString();

    if (message == null ||
        message.isEmpty) {
      return 'No se pudo iniciar la cámara.';
    }

    return message;
  }

  void _startScannerRoom(
    ScannerProvider provider,
  ) {
    final continuation =
        widget.continuationReference;

    if (continuation == null) {
      provider.startNewRoom();
      return;
    }

    final width = continuation.width;
    final tangentSign =
        continuation.side == OpeningConnectionSide.left
            ? 1.0
            : -1.0;
    final otherX = continuation.startEndpoint ==
            ContinuationStartEndpoint.start
        ? tangentSign * width
        : -tangentSign * width;

    final other = ARPoint(
      x: otherX,
      y: 0.0,
      z: 0.0,
    );
    final origin = ARPoint(
      x: 0.0,
      y: 0.0,
      z: 0.0,
    );
    final sharedFeature = WallFeature(
      id: continuation.featureId,
      type: continuation.featureType,
      start: other,
      end: origin,
    );

    provider.startNewRoom(
      initialFeatures: <WallFeature>[sharedFeature],
    );

    _scannerAdapter.seedPath(
      <ScannerPoint>[
        ScannerPoint(
          x: origin.x,
          y: origin.y,
          z: origin.z,
          source: PointSource.manual,
        ),
      ],
    );
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
      final controller =
          await _createInitializedCameraController();

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
    final completedRooms = context
        .watch<FloorPlanProvider>()
        .completedRooms;

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
          _buildScannerOverlay(
            provider,
            completedRooms,
          ),
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
                height: 20,              ),              const Text(
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
                onPressed: () =>
                    _initialize(
                  allowAutomaticRetry: false,
                ),
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Reintentar cámara',
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
      child: FittedBox(        fit: BoxFit.cover,
        child: SizedBox(
          width:
              controller.value.previewSize?.height ??
                  MediaQuery.of(context)
                      .size
                      .width,
          height:              controller.value.previewSize?.width ??
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
    List<RoomModel> completedRooms,
  ) {
    final room = provider.currentRoom;
    final points =
        room?.points ?? const <ARPoint>[];    final features =        room?.features ?? const <WallFeature>[];

    return IgnorePointer(
      child: CustomPaint(
        painter:
            _ScannerGuidePainter(
          points: points,
          features: features,
          previousRooms:
              widget.continuationReference == null
                  ? const <RoomModel>[]
                  : completedRooms,
          continuationReference:
              widget.continuationReference,
        ),
        size: Size.infinite,
      ),
    );
  }
  Widget _buildTopHud(    ScannerProvider provider,  ) {
    final l10n =
        AppLocalizations.of(context)!;

    final count =
        provider.currentPointsCount;

    final continuation =
        widget.continuationReference;

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
                      _localizedRoomName(
                    provider,
                    l10n,
                  ),
                  subtitle:
                      '$count esquinas',
                  onTap: () =>
                      _showCustomRoomNameDialog(
                    provider,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              _hudIconButton(
                icon:
                    Icons.home_work_outlined,
                tooltip:
                    l10n.roomType,
                onPressed: () =>
                    _showRoomTypeSelector(
                  provider,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              _hudIconButton(
                icon:
                    Icons.map_outlined,
                tooltip:
                    l10n.viewPlan,
                onPressed:
                    _openFloorPlan,
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          if (continuation != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A00).withValues(
                  alpha: 0.88,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.add_road_rounded,
                    color: Colors.white,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Continuación desde una abertura',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                Icon(
                  continuation != null
                      ? Icons.navigation_outlined
                      : Icons.info_outline,
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
                        ? continuation != null
                            ? 'Desde el punto verde, medí la distancia hasta la primera esquina real del ambiente.'
                            : 'Marcá el punto inicial de la habitación.'
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

  String _localizedRoomName(
    ScannerProvider provider,
    AppLocalizations l10n,
  ) {
    final room =
        provider.currentRoom;

    if (room == null) {
      return l10n.newRoom;
    }

    final defaultName =
        room.type.displayName;

    return room.name == defaultName
        ? room.type.localizedName(l10n)
        : room.name;
  }

  Widget _hudCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(14),
        child: Container(
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
                  color: Colors.white,
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
                        color: Colors.white,
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
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.edit_outlined,
                  color: Colors.white60,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomRoomNameDialog(
    ScannerProvider provider,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;

    final controller =
        TextEditingController(
      text: provider.currentRoom?.name ??
          provider.selectedType.localizedName(l10n),
    );

    final name =
        await showDialog<String>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Text(
            l10n.roomName,
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization:
                TextCapitalization.sentences,
            maxLength: 60,
            decoration:
                InputDecoration(
              labelText:
                  l10n.roomDestination,
              hintText:
                  l10n.roomNameExample,
              border:
                  OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final normalized =
                  value.trim();

              if (normalized.isNotEmpty) {
                Navigator.pop(
                  dialogContext,
                  normalized,
                );
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                dialogContext,
              ),
              child: Text(
                l10n.cancel,
              ),
            ),
            FilledButton(
              onPressed: () {
                final normalized =
                    controller.text.trim();

                if (normalized.isEmpty) {
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  normalized,
                );
              },
              child: Text(
                l10n.save,
              ),
            ),
          ],
        );
      },
    );

    await Future<void>.delayed(
      kThemeAnimationDuration,
    );

    controller.dispose();    if (!mounted ||
        name == null ||
        name.trim().isEmpty) {
      return;
    }

    provider.setCurrentRoomName(
      name,
    );
  }

  Future<void> _showRoomTypeSelector(
    ScannerProvider provider,
  ) async {
    final l10n =
        AppLocalizations.of(context)!;

    final selected =
        await showModalBottomSheet<            RoomType>(
      context: context,
      isScrollControlled: true,
      builder: (
        bottomSheetContext,
      ) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(                  l10n.roomType,
                  style:                      TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Flexible(
                  child:
                      ListView.builder(
                    shrinkWrap: true,
                    itemCount:
                        RoomType.values.length,
                    itemBuilder:
                        (
                      context,
                      index,
                    ) {
                      final type =
                          RoomType.values[
                            index
                          ];

                      final selected =
                          provider.selectedType ==
                              type;

                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color:
                              selected
                                  ? Colors.blueAccent
                                  : null,
                        ),
                        title: Text(
                          type.localizedName(l10n),
                        ),
                        onTap: () {
                          Navigator.pop(
                            bottomSheetContext,
                            type,
                          );
                        },
                      );
                    },                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null ||
        !mounted) {
      return;
    }

    provider.setRoomType(
      selected,
    );
  }
  Widget _hudIconButton({    required IconData icon,
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
      bottom: 6,
      child: SafeArea(
        top: false,
        child: Container(
          padding:
              const EdgeInsets.fromLTRB(
            8,
            8,
            8,
            8,
          ),
          decoration:
              BoxDecoration(
            color:
                Colors.black.withValues(
              alpha: 0.88,
            ),
            borderRadius:
                BorderRadius.circular(
              16,
            ),
            border: Border.all(
              color: Colors.white24,
            ),
          ),
          child: Column(
            children: [
              _buildModeSelector(),
              const SizedBox(
                height: 6,
              ),
              Row(
                children: [
                  _buildUndoButton(
                    provider,
                  ),                  const SizedBox(                    width: 6,
                  ),
                  Expanded(
                    child:
                        _buildMainCaptureButton(
                      provider,
                    ),
                  ),
                  const SizedBox(
                    width: 6,
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
    final l10n =        AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _modeButton(
            BasicAppMode.wall,
            Icons.wallpaper,
            l10n.wall,
          ),
        ),
        const SizedBox(
          width: 6,
        ),
        Expanded(
          child: _modeButton(
            BasicAppMode.door,
            Icons.door_front_door,
            l10n.door,          ),        ),
        const SizedBox(
          width: 6,
        ),
        Expanded(
          child: _modeButton(
            BasicAppMode.window,
            Icons.window,
            l10n.window,
          ),
        ),
      ],
    );
  }

  Color _modeColor(
    BasicAppMode mode,
  ) {
    switch (mode) {
      case BasicAppMode.wall:
        return const Color(
          0xFF448AFF,
        );

      case BasicAppMode.door:
        return const Color(
          0xFFFF8A00,
        );

      case BasicAppMode.window:
        return const Color(
          0xFFD500F9,
        );
    }
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
          vertical: 5,
          horizontal: 4,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? _modeColor(mode)
              : Colors.white10,
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: selected
                ? _modeColor(mode)
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
              size: 17,
            ),
            const SizedBox(
              height: 1,
            ),
            Text(
              label,
              style:
                  TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white70,
                fontSize: 10,
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
        provider.currentPointsCount >
            _protectedInitialPointCount;

    return SizedBox(
      width: 42,
      height: 44,
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
          size: 21,
        ),
      ),
    );
  }

  Widget _buildMainCaptureButton(
    ScannerProvider provider,
  ) {
    final l10n =
        AppLocalizations.of(context)!;

    final count =
        provider.currentPointsCount;

    final String label;

    if (_processing) {
      label = l10n.calculating;
    } else if (count == 0) {
      label = widget.continuationReference == null
          ? l10n.markStart
          : 'Medir primera esquina';
    } else if (_currentMode ==
        BasicAppMode.wall) {
      label = l10n.measureNextCorner;
    } else if (_currentMode ==
        BasicAppMode.door) {
      label = l10n.placeDoor;
    } else {
      label = l10n.placeWindow;
    }

    return SizedBox(
      height: 44,
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
          size: 18,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              _modeColor(
            _currentMode,
          ),
          foregroundColor:
              Colors.white,
          disabledBackgroundColor:
              Colors.blueGrey,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
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
      width: 44,
      height: 44,
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
              12,
            ),
          ),
        ),
        icon: const Icon(
          Icons.check,
          size: 22,
        ),
      ),
    );
  }
  Future<void> _capturePressed(
    ScannerProvider provider,
  ) async {
    if (_processing) {
      return;    }
    HapticFeedback.lightImpact();

    if (provider.currentPointsCount == 0) {
      if (widget.continuationReference != null) {
        if (_currentMode != BasicAppMode.wall) {
          _showMessage(
            'Primero medí la primera esquina real del ambiente.',
          );
          return;
        }

        await _captureWallPoint(
          provider,
        );
        return;
      }

      final point =
          _scannerAdapter
              .captureInitialPoint();

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
    );  }

  Future<void> _captureWallPoint(
    ScannerProvider provider,
  ) async {
    final isFirstContinuationCorner =
        widget.continuationReference != null &&
            provider.currentPointsCount == 0;

    final measurement =
        await _showMeasurementDialog(      nextCorner:
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

      final closingDistance =
          _smartClosingDistance(
        provider,
        candidate,
      );

      if (closingDistance != null) {
        final shouldClose =
            await _confirmSmartClose(
          closingDistance,
        );

        if (!mounted) {
          return;
        }

        if (shouldClose) {
          _scannerAdapter
              .cancelPendingMeasurement();

          await _closeRoom(
            provider,
          );
          return;
        }
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

      if (isFirstContinuationCorner) {
        _showMessage(
          'Primera esquina registrada. Continuá midiendo las paredes del ambiente.',
        );
      }

      if (closingDistance == null &&
          result.warningMessage != null) {
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

  double? _smartClosingDistance(
    ScannerProvider provider,
    ScannerPoint candidate,
  ) {
    final points =
        provider.currentRoom?.points;

    if (points == null ||
        points.length < 3) {
      return null;
    }

    final first = points.first;
    final deltaX =
        candidate.x - first.x;
    final deltaZ =
        candidate.z - first.z;
    final distance =
        math.sqrt(
      deltaX * deltaX +
          deltaZ * deltaZ,
    );

    return distance <=
            ScanValidator.autoCloseThreshold
        ? distance
        : null;
  }

  Future<bool> _confirmSmartClose(
    double distance,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          AlertDialog(
        title: const Text(
          'Cerrar ambiente',
        ),
        content: Text(
          'La medición termina a '
          '${distance.toStringAsFixed(2)} metros del punto inicial. '
          '¿Querés ajustar el cierre exactamente al inicio?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child: const Text(
              'Continuar midiendo',
            ),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            icon: const Icon(
              Icons.check_circle_outline,
            ),
            label: const Text(
              'Cerrar ambiente',
            ),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _captureFeature(
    ScannerProvider provider,
  ) async {
    int? preferredWallIndex;

    if (provider.currentPointsCount >= 3) {
      final wallSelection =
          await _showFeatureWallDialog(
        provider.currentPointsCount,
      );

      if (wallSelection == null) {
        return;
      }

      if (wallSelection >= 0) {
        preferredWallIndex =
            wallSelection;
      }
    }

    final measurement =
        await _showMeasurementDialog(
      nextCorner:          provider.currentPointsCount,
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

      final width =
          measurement.featureWidth;

      if (width == null) {
        _scannerAdapter
            .cancelPendingMeasurement();

        _showValidationError(
          'Ingresá el ancho de la abertura.',
        );

        return;
      }

      final result =
          provider
              .addFeatureToCurrentRoom(
        featureType,
        candidate.toARPoint(),
        widthMeters:
            width,
        preferredWallIndex:
            preferredWallIndex,
      );

      // Una abertura no desplaza la última esquina del contorno.
      _scannerAdapter
          .cancelPendingMeasurement();

      if (!result.isValid) {
        _showValidationError(
          result.errorMessage ??
              'No se pudo asociar la abertura a una pared.',
        );

        return;
      }

      _showMessage(
        featureType ==
                FeatureType.door
            ? 'Puerta de ${width.toStringAsFixed(2)} m ajustada a la pared.'
            : 'Ventana de ${width.toStringAsFixed(2)} m ajustada a la pared.',
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

  Future<int?> _showFeatureWallDialog(
    int pointCount,
  ) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {        return AlertDialog(
          title: const Text(
            '¿En qué pared está la abertura?',
          ),
          content: const Text(
            'Elegí la pared de cierre si la puerta o ventana está sobre el tramo que une la última esquina con la primera.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(-1);
              },
              child: const Text(
                'Detectar pared automáticamente',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  pointCount - 1,
                );
              },
              child: const Text(
                'Usar pared de cierre',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<_BasicMeasurement?>
      _showMeasurementDialog({
    required int nextCorner,
    bool featureMode = false,
  }) async {
    final distanceController =
        TextEditingController();

    final angleController = TextEditingController(
      text: _formatAngle(_lastAngleDegrees),    );

    final featureWidthController =        TextEditingController(
      text:
          _currentMode ==
                  BasicAppMode.door
              ? '0,80'
              : '1,00',
    );
    double? distanceError;
    double? angleError;
    double? featureWidthError;

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
                      keyboardType:                          const TextInputType
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
                      onChanged: (_) {
                        setDialogState(() {
                          angleError = null;
                        });
                      },
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
                                ? 'Ingresá una dirección válida'                                : null,
                        border:
                            const OutlineInputBorder(),
                      ),
                    ),
                    if (featureMode) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      TextField(
                        controller:
                            featureWidthController,
                        keyboardType:
                            const TextInputType
                                .numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            InputDecoration(
                          labelText:
                              _currentMode ==
                                      BasicAppMode.door
                                  ? 'Ancho de la puerta'
                                  : 'Ancho de la ventana',
                          hintText:
                              'Ejemplo: 1,20',
                          suffixText:
                              'metros',
                          prefixIcon:
                              const Icon(
                            Icons.width_normal,
                          ),
                          errorText:
                              featureWidthError !=
                                      null
                                  ? 'Ingresá un ancho mínimo de 0,20 m'
                                  : null,
                          border:
                              const OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Dirección rápida:',
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
                    Wrap(                      spacing: 6,                      runSpacing: 6,
                      children: [
                        _angleChip(
                          'Frente',
                          Icons.arrow_upward,
                          0,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          'Derecha',
                          Icons.arrow_forward,
                          90,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          'Atrás',
                          Icons.arrow_downward,
                          180,
                          angleController,
                          setDialogState,
                        ),
                        _angleChip(
                          'Izquierda',
                          Icons.arrow_back,
                          270,
                          angleController,
                          setDialogState,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              -5.0,
                              setDialogState,
                            ),
                            child: const Text('-5°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              -1.0,
                              setDialogState,                            ),
                            child: const Text('-1°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              1.0,
                              setDialogState,
                            ),
                            child: const Text('+1°'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _adjustAngle(
                              angleController,
                              5.0,
                              setDialogState,
                            ),
                            child: const Text('+5°'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _directionPreview(angleController.text),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
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

                    final featureWidth =
                        featureMode
                            ? _parseNumber(
                                featureWidthController
                                    .text,
                              )
                            : null;

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

                      featureWidthError =
                          featureMode &&
                                  (featureWidth ==
                                          null ||
                                      featureWidth <
                                          0.20)
                              ? 1
                              : null;
                    });

                    if (distance == null ||
                        distance <= 0 ||
                        angle == null ||
                        (featureMode &&
                            (featureWidth ==
                                    null ||
                                featureWidth <
                                    0.20))) {
                      return;
                    }

                    _lastAngleDegrees = _normalizeAngle(angle);

                    Navigator.pop(
                      dialogContext,
                      _BasicMeasurement(
                        distance:
                            distance,
                        angle:
                            _lastAngleDegrees,
                        featureWidth:
                            featureWidth,
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
    IconData icon,
    double value,
    TextEditingController controller,
    StateSetter setDialogState,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text('$label ${value.toStringAsFixed(0)}°'),
      onPressed: () {
        controller.text = _formatAngle(value);

        setDialogState(() {});
      },
    );
  }

  void _adjustAngle(
    TextEditingController controller,
    double delta,
    StateSetter setDialogState,
  ) {
    final current = _parseNumber(controller.text) ?? 0.0;
    controller.text = _formatAngle(
      _normalizeAngle(current + delta),
    );
    setDialogState(() {});
  }

  double _normalizeAngle(double value) {
    final normalized = value % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  String _formatAngle(double value) {
    final normalized = _normalizeAngle(value);

    if (normalized == normalized.roundToDouble()) {
      return normalized.toStringAsFixed(0);
    }
    return normalized
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _directionPreview(String rawValue) {
    final parsed = _parseNumber(rawValue);

    if (parsed == null) {
      return 'Ingresá un ángulo válido';
    }

    final angle = _normalizeAngle(parsed);
    const tolerance = 0.001;

    if ((angle - 0.0).abs() < tolerance) {
      return '↑ Frente · 0°';
    }
    if ((angle - 90.0).abs() < tolerance) {
      return '→ Derecha · 90°';
    }
    if ((angle - 180.0).abs() < tolerance) {
      return '↓ Atrás · 180°';
    }
    if ((angle - 270.0).abs() < tolerance) {
      return '← Izquierda · 270°';
    }

    return 'Dirección personalizada · ${_formatAngle(angle)}°';
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
  }  void _showValidationError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              Colors.red.shade800,          duration:
              const Duration(
            seconds: 4,          ),
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

    final continuation =
        widget.continuationReference;

    final floorPlanProvider =
        context.read<FloorPlanProvider>();

    if (continuation != null) {
      final sourceFeature = floorPlanProvider.findFeature(
        roomId: continuation.sourceRoomId,
        featureId: continuation.featureId,
      );

      if (sourceFeature == null || sourceFeature.isConnected) {
        _showValidationError(
          sourceFeature == null
              ? 'La abertura de referencia ya no existe.'
              : 'La abertura ya conecta otro ambiente.',
        );
        return;
      }
    }

    final room =
        provider.closeCurrentRoom();

    if (room == null) {
      _showValidationError(
        provider.lastCloseError ??
            'No se pudo cerrar el ambiente.',
      );
      return;
    }

    final saved = continuation == null
        ? true
        : await floorPlanProvider.addCompletedRoomFromContinuation(
            room: room,
            reference: continuation,
          );

    if (continuation == null) {
      await floorPlanProvider.addCompletedRoom(room);
    }

    if (!saved) {
      _showValidationError(
        'No se pudo conectar el ambiente con la abertura seleccionada.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    _showMessage(
      continuation == null
          ? 'Ambiente guardado correctamente.'
          : 'Ambiente conectado y alineado correctamente.',
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
  final double? featureWidth;

  const _BasicMeasurement({
    required this.distance,
    required this.angle,
    this.featureWidth,
  });
}

class _ScannerGuidePainter
    extends CustomPainter {
  final List<ARPoint> points;
  final List<WallFeature> features;
  final List<RoomModel> previousRooms;
  final ScanContinuationReference? continuationReference;

  const _ScannerGuidePainter({
    required this.points,
    required this.features,
    required this.previousRooms,
    required this.continuationReference,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final previousPoints = <ARPoint>[
      for (final room in previousRooms)
        for (final point in room.points)
          _globalToLocal(point),
    ];

    final visiblePoints = <ARPoint>[
      ...previousPoints,
      ...points,
    ];

    if (visiblePoints.isEmpty) {
      _drawCenterGuide(
        canvas,        size,
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
      visiblePoints,
      size,    );

    final projected =
        points.map((point) {
      return Offset(
        center.dx +
            point.x * scale,
        center.dy +
            point.z * scale,
      );
    }).toList();

    Offset projectPoint(ARPoint point) {
      return Offset(
        center.dx + point.x * scale,
        center.dy + point.z * scale,
      );
    }

    _drawPreviousPlan(
      canvas,
      projectPoint,
    );

    final linePaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = Colors.black.withValues(
            alpha: 0.92,
          )
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

    for (final feature in features) {
      final featurePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            feature.id ==
                    continuationReference?.featureId
                ? 9
                : 8
        ..strokeCap = StrokeCap.round
        ..color = feature.id ==
                continuationReference?.featureId
            ? const Color(0xFF00C853)
            : feature.type == FeatureType.door
                ? const Color(0xFFFF8A00)
                : const Color(0xFFD500F9);

      canvas.drawLine(
        projectPoint(feature.start),
        projectPoint(feature.end),
        featurePaint,
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

    if (continuationReference != null) {
      _drawContinuationPoint(
        canvas,
        projectPoint(
          ARPoint(
            x: 0.0,
            y: 0.0,
            z: 0.0,
          ),
        ),
      );
    }

    _drawCenterGuide(
      canvas,
      size,
      onlyCross: true,
    );
  }

  void _drawPreviousPlan(
    Canvas canvas,
    Offset Function(ARPoint point) project,
  ) {
    if (continuationReference == null) {
      return;
    }

    final wallPaint = Paint()
      ..color = const Color(0xFF448AFF).withValues(
        alpha: 0.55,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    final roomFillPaint = Paint()
      ..color = const Color(0xFF448AFF).withValues(
        alpha: 0.08,
      )
      ..style = PaintingStyle.fill;

    for (final room in previousRooms) {
      if (room.points.length < 2) {
        continue;
      }

      final path = Path();
      final first = project(
        _globalToLocal(room.points.first),
      );
      path.moveTo(first.dx, first.dy);

      for (final point in room.points.skip(1)) {
        final projected = project(
          _globalToLocal(point),
        );
        path.lineTo(
          projected.dx,
          projected.dy,
        );
      }

      if (room.isClosed || room.points.length >= 3) {
        path.close();
        canvas.drawPath(path, roomFillPaint);
      }

      canvas.drawPath(path, wallPaint);

      for (final feature in room.features) {
        final selected =
            room.id == continuationReference!.sourceRoomId &&
                feature.id ==
                    continuationReference!.featureId;

        final featurePaint = Paint()
          ..color = selected
              ? const Color(0xFF00C853)
              : feature.type == FeatureType.door
                  ? const Color(0xFFFF8A00).withValues(
                      alpha: 0.60,
                    )
                  : const Color(0xFFD500F9).withValues(
                      alpha: 0.60,
                    )
          ..strokeWidth = selected ? 9 : 5
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(
          project(_globalToLocal(feature.start)),
          project(_globalToLocal(feature.end)),
          featurePaint,
        );
      }
    }
  }

  ARPoint _globalToLocal(
    ARPoint point,
  ) {
    final reference = continuationReference;

    if (reference == null) {
      return point;
    }

    final openingDx =
        reference.globalEnd.x - reference.globalStart.x;
    final openingDz =
        reference.globalEnd.z - reference.globalStart.z;
    final openingLength =
        math.sqrt(
      openingDx * openingDx + openingDz * openingDz,
    );

    if (openingLength <= 0.000001) {
      return point;
    }

    final tangentX = openingDx / openingLength;
    final tangentZ = openingDz / openingLength;
    final forwardX =
        reference.side == OpeningConnectionSide.left
            ? -tangentZ
            : tangentZ;
    final forwardZ =
        reference.side == OpeningConnectionSide.left
            ? tangentX
            : -tangentX;
    final rightX = forwardZ;
    final rightZ = -forwardX;
    final dx = point.x - reference.origin.x;
    final dz = point.z - reference.origin.z;

    return ARPoint(
      x: dx * rightX + dz * rightZ,
      y: point.y - reference.origin.y,
      z: dx * forwardX + dz * forwardZ,
    );
  }

  void _drawContinuationPoint(
    Canvas canvas,
    Offset point,
  ) {
    canvas.drawCircle(
      point,
      10,
      Paint()..color = const Color(0xFF00C853),
    );
    canvas.drawCircle(
      point,
      4,
      Paint()..color = Colors.white,
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
        center.dx,        center.dy - 20,
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

    final maxAbsoluteX =
        mathMax(minX.abs(), maxX.abs());
    final maxAbsoluteZ =
        mathMax(minZ.abs(), maxZ.abs());

    if (maxAbsoluteX <= 0.000001 &&
        maxAbsoluteZ <= 0.000001) {
      return 80;
    }

    final scaleX = maxAbsoluteX <= 0.000001
        ? double.infinity
        : (size.width * 0.42) / maxAbsoluteX;
    final scaleZ = maxAbsoluteZ <= 0.000001
        ? double.infinity
        : (size.height * 0.27) / maxAbsoluteZ;
    final calculated =
        scaleX < scaleZ ? scaleX : scaleZ;

    return calculated > 90 ? 90 : calculated;
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
            points ||
        oldDelegate.features != features ||
        oldDelegate.previousRooms != previousRooms ||
        oldDelegate.continuationReference !=
            continuationReference;
  }
}