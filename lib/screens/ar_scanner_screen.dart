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

import '../l10n/generated/app_localizations.dart';
import '../l10n/room_type_localization.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/measurement_settings_provider.dart';
import '../providers/scanner_provider.dart';
import '../services/permission_service.dart';
import '../utils/measurement_units.dart';
import '../utils/scan_validator.dart';
import '../scanner/adapters/ar_scanner_adapter.dart';
import 'floor_plan_viewer_screen.dart';

enum AppMode {
  wall,
  door,
  window,
}

class ARScannerScreen extends StatefulWidget {
  /// UUID del proyecto Isar al que pertenece este escaneo.
  final String projectUuid;

  final String projectName;

  /// Abertura global seleccionada en el plano 2D para continuar el escaneo.
  ///
  /// En ARCore/ARKit sus extremos se utilizarán como destino global después
  /// de que el usuario vuelva a marcar la abertura en la nueva sesión AR.
  final ScanContinuationReference? continuationReference;

  const ARScannerScreen({
    super.key,
    required this.projectUuid,
    required this.projectName,
    this.continuationReference,
  });

  @override
  State<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends State<ARScannerScreen>
    with WidgetsBindingObserver {
  AppMode _currentMode = AppMode.wall;

  ARPoint? _pendingFeatureStart;
  AppMode? _pendingFeatureMode;

  vector.Vector3? _continuationSessionStart;
  vector.Vector3? _continuationSessionEnd;

  bool get _requiresContinuationCalibration =>
      widget.continuationReference != null;

  bool get _isContinuationCalibrated =>
      !_requiresContinuationCalibration ||
      (_continuationSessionStart != null &&
          _continuationSessionEnd != null);

  // ================================================================
  // CONTROLADORES AR
  // ================================================================

  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  // ================================================================
  // SCANNER ENGINE
  // ================================================================

  /// Adapter responsable de encapsular la interacción con ARCore/ARKit.
  ///
  /// La pantalla no obtiene directamente la pose de la cámara.
  /// Eso ahora pertenece al Scanner Engine.
  final ARScannerAdapter _arScannerAdapter = ARScannerAdapter();

  // Posición actual estimada del dispositivo/cámara.
  vector.Vector3 _currentCameraPosition = vector.Vector3(0, 0, 0);

  bool _permissionsGranted = false;
  bool _checkingPermissions = true;

  // ================================================================
  // CICLO DE VIDA
  // ================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Permisos del modo AR actual.
      final granted =
          await PermissionService.requestScannerPermissions();

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
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _arScannerAdapter
          .setTrackingStatus(false);

      _pendingFeatureStart = null;
      _pendingFeatureMode = null;

      if (_requiresContinuationCalibration) {
        _continuationSessionStart = null;
        _continuationSessionEnd = null;
      }

      if (mounted) {
        context
            .read<ScannerProvider>()
            .updateTrackingStatus(false);
      }

      return;
    }

    if (state == AppLifecycleState.resumed) {
      final sessionAvailable =
          _arSessionManager != null &&
              _arObjectManager != null;

      _arScannerAdapter
          .setTrackingStatus(
        sessionAvailable,
      );

      if (mounted) {
        context
            .read<ScannerProvider>()
            .updateTrackingStatus(
              sessionAvailable,
            );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);

    _arScannerAdapter.dispose();

    _arSessionManager = null;
    _arObjectManager = null;

    super.dispose();
  }

  // ================================================================
  // AR VIEW
  // ================================================================

  void _onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    _arSessionManager = arSessionManager;
    _arObjectManager = arObjectManager;

    _arScannerAdapter.attachARSession(
      sessionManager: arSessionManager,
      objectManager: arObjectManager,
    );

    if (mounted) {
      context.read<ScannerProvider>().updateTrackingStatus(true);
    }
  }

  // ================================================================
  // POSICIÓN DE CÁMARA
  // ================================================================

  Future<vector.Vector3?> _getCurrentCameraPosition() async {
    final point = await _arScannerAdapter.capturePoint();

    if (point == null) {
      return null;
    }

    final position = vector.Vector3(
      point.x,
      point.y,
      point.z,
    );

    _currentCameraPosition = position;

    return position;
  }
  // ================================================================
  // BUILD
  // ================================================================

  @override  Widget build(BuildContext context) {
    final provider = context.watch<ScannerProvider>();
    final measurementSystem = context
        .watch<MeasurementSettingsProvider>()
        .system;
    final l10n = AppLocalizations.of(context)!;

    if (_checkingPermissions) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Permisos requeridos'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'No se otorgaron los permisos de cámara/ubicación. '
              'Habilítalos desde los ajustes del sistema para poder escanear.',
              style: TextStyle(
                color: Colors.white70,
              ),
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
                ActionChip(
                  tooltip:
                      l10n.editRoomName,
                  avatar: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    _localizedRoomName(
                      provider,
                      l10n,
                    ),
                  ),
                  onPressed: () =>
                      _showCustomRoomNameDialog(
                    provider,
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
                      tooltip: l10n.viewPlan,
                      onPressed: _openFloorPlan,
                      icon: const Icon(
                        Icons.map_outlined,
                      ),
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
                            ? Colors.greenAccent                            : Colors.orangeAccent,                      ),
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

          if (_requiresContinuationCalibration)
            Positioned(
              top: MediaQuery.of(context).padding.top + 112,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: _isContinuationCalibrated
                      ? Colors.green.withValues(alpha: 0.88)
                      : const Color(0xFFFF8A00).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isContinuationCalibrated
                          ? Icons.check_circle_outline
                          : Icons.center_focus_strong,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _continuationInstruction(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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
                PopupMenuButton<MeasurementSystem>(
                  tooltip: l10n.measurementSystem,
                  initialValue: measurementSystem,
                  onSelected: (newSystem) {
                    context
                        .read<MeasurementSettingsProvider>()
                        .setSystem(newSystem);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<MeasurementSystem>(
                      value: MeasurementSystem.metric,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.straighten,
                        ),
                        title: Text(
                          l10n.metricSystem,
                        ),
                      ),
                    ),
                    PopupMenuItem<MeasurementSystem>(
                      value: MeasurementSystem.imperial,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.square_foot,
                        ),
                        title: Text(
                          l10n.imperialSystem,
                        ),
                      ),
                    ),
                  ],
                  child: Chip(
                    avatar: Icon(
                      measurementSystem ==
                              MeasurementSystem.metric
                          ? Icons.straighten
                          : Icons.square_foot,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: Text(
                      measurementSystem ==
                              MeasurementSystem.metric
                          ? l10n.metricSystem
                          : l10n.imperialSystem,
                    ),
                    backgroundColor: Colors.black87,
                    labelStyle: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ------------------------------------------------------
                // SELECTOR DE MODO
                // ------------------------------------------------------

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildModeChip(
                      AppMode.wall,
                      Icons.wallpaper,
                      l10n.wall,
                    ),
                    const SizedBox(width: 8),
                    _buildModeChip(
                      AppMode.door,
                      Icons.door_front_door,
                      l10n.door,
                    ),
                    const SizedBox(width: 8),
                    _buildModeChip(
                      AppMode.window,
                      Icons.window,
                      l10n.window,                    ),
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
                            type.localizedName(l10n).toUpperCase(),
                          ),
                          selected: isSelected,
                          selectedColor:
                              Colors.blueAccent,
                          backgroundColor:
                              Colors.black87,
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
                                  HapticFeedback
                                      .lightImpact();

                                  provider.removeLastPoint();
                                }
                              : null,
                      icon: const Icon(
                        Icons.undo,
                      ),
                      style: IconButton.styleFrom(
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
                            _onCapturePressed(                          provider,
                        ),
                        icon: Icon(
                          _currentMode ==
                                  AppMode.wall
                              ? Icons
                                  .add_location_alt_outlined
                              : _currentMode ==
                                      AppMode.door
                                  ? Icons
                                      .door_front_door
                                  : Icons.window,
                        ),
                        label: Text(
                          !_isContinuationCalibrated
                              ? _continuationSessionStart == null
                                  ? 'Marcar extremo A'
                                  : 'Marcar extremo B'
                              : _currentMode ==
                                  AppMode.wall
                              ? l10n.addCorner
                              : _pendingFeatureStart !=
                                      null
                                  ? l10n.markSecondEnd
                                  : _currentMode ==
                                          AppMode.door
                                      ? l10n.measureDoor
                                      : l10n.measureWindow,
                        ),
                        style:
                            ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            vertical: 16,
                          ),
                          backgroundColor:
                              _modeColor(
                            _currentMode,
                          ),
                          foregroundColor:
                              Colors.white,
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    IconButton.filled(
                      onPressed:
                          provider.currentPointsCount >=
                                  3
                              ? () =>
                                  _onCloseRoomPressed(
                                    provider,
                                  )
                              : null,
                      icon: const Icon(
                        Icons.check,
                      ),
                      style: IconButton.styleFrom(
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
    );    await Future<void>.delayed(
      kThemeAnimationDuration,
    );

    controller.dispose();

    if (!mounted ||
        name == null ||
        name.trim().isEmpty) {
      return;
    }

    provider.setCurrentRoomName(
      name,
    );
  }
  String _continuationInstruction() {
    if (_continuationSessionStart == null) {
      return 'Apuntá al extremo A de la abertura y marcá la referencia.';
    }

    if (_continuationSessionEnd == null) {
      return 'Ahora apuntá al extremo B de la misma abertura.';
    }

    return 'Referencia alineada. Ya podés medir el ambiente nuevo.';
  }

  Future<void> _captureContinuationEndpoint() async {
    final position = await _getCurrentCameraPosition();

    if (!mounted) return;

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se detectó un punto válido. Apuntá a la abertura e intentá nuevamente.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_continuationSessionStart == null) {
      setState(() {
        _continuationSessionStart = position;
      });
      return;
    }

    final start = _continuationSessionStart!;
    final dx = position.x - start.x;
    final dz = position.z - start.z;
    final measuredWidth = vector.Vector2(dx, dz).length;

    if (measuredWidth < 0.20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Los extremos están demasiado cerca. Volvé a marcar el extremo B.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _continuationSessionEnd = position;
    });

    final expectedWidth = widget.continuationReference!.width;
    final difference = (measuredWidth - expectedWidth).abs();
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          difference > 0.15
              ? 'Referencia alineada. Atención: la medida de realidad aumentada difiere '
                  '${_formatLength(difference, measurementSystem)} del plano.'
              : 'Referencia alineada correctamente.',
        ),
        backgroundColor:
            difference > 0.15 ? Colors.orange : Colors.green,
      ),
    );
  }

  String _formatLength(
    double meters,
    MeasurementSystem measurementSystem,
  ) {
    final localizations =
        AppLocalizations.of(context)!;

    if (measurementSystem ==
        MeasurementSystem.metric) {
      return '${_formatDecimal(meters)} '
          '${localizations.meters}';
    }

    final imperial =
        MeasurementUnits.metersToFeetAndInches(
      meters,
    );

    return '${imperial.feet} '
        '${localizations.feet.toLowerCase()} '
        '${_formatDecimal(imperial.inches)} '
        '${localizations.inches.toLowerCase()}';
  }

  String _formatDecimal(
    double value,
  ) {
    var formatted = value.toStringAsFixed(2);

    while (formatted.contains('.') &&
        formatted.endsWith('0')) {
      formatted = formatted.substring(
        0,
        formatted.length - 1,
      );
    }

    if (formatted.endsWith('.')) {
      formatted = formatted.substring(
        0,
        formatted.length - 1,
      );
    }

    if (Localizations.localeOf(context)
            .languageCode ==
        'es') {
      formatted = formatted.replaceAll('.', ',');
    }

    return formatted;
  }

  vector.Vector3 _toContinuationLocal(
    vector.Vector3 sessionPoint,
  ) {
    if (!_requiresContinuationCalibration ||
        !_isContinuationCalibrated) {
      return sessionPoint;
    }

    final reference = widget.continuationReference!;
    final start = _continuationSessionStart!;
    final end = _continuationSessionEnd!;
    final sessionOrigin = reference.startEndpoint ==
            ContinuationStartEndpoint.start
        ? start
        : end;
    final tangent = vector.Vector2(
      end.x - start.x,
      end.z - start.z,
    )..normalize();

    final forward = reference.side == OpeningConnectionSide.left
        ? vector.Vector2(-tangent.y, tangent.x)
        : vector.Vector2(tangent.y, -tangent.x);
    final right = vector.Vector2(forward.y, -forward.x);
    final relative = vector.Vector2(
      sessionPoint.x - sessionOrigin.x,
      sessionPoint.z - sessionOrigin.z,
    );

    return vector.Vector3(
      relative.dot(right),
      sessionPoint.y - sessionOrigin.y,
      relative.dot(forward),
    );
  }

  // ================================================================
  // SELECTOR DE MODO
  // ================================================================

  Color _modeColor(
    AppMode mode,
  ) {
    switch (mode) {
      case AppMode.wall:
        return const Color(
          0xFF448AFF,
        );

      case AppMode.door:
        return const Color(
          0xFFFF8A00,
        );

      case AppMode.window:
        return const Color(
          0xFFD500F9,
        );
    }
  }

  Widget _buildModeChip(
    AppMode mode,
    IconData icon,
    String label,
  ) {
    final isSelected = _currentMode == mode;

    return ChoiceChip(      avatar: Icon(
        icon,
        size: 18,
        color: isSelected
            ? Colors.white
            : Colors.white70,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor:
          _modeColor(mode),
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
          _pendingFeatureStart = null;
          _pendingFeatureMode = null;
        });
      },
    );
  }

  // ================================================================
  // CAPTURA DE PUNTOS / ABERTURAS
  // ================================================================

  Future<void> _onCapturePressed(
    ScannerProvider provider,
  ) async {
    HapticFeedback.lightImpact();

    if (!_isContinuationCalibrated) {
      await _captureContinuationEndpoint();
      return;
    }

    final pos =
        await _getCurrentCameraPosition();

    if (!mounted) return;

    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se detectó una posición de cámara válida. '
            'Apunta a una superficie reconocida e intenta de nuevo.',
          ),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    final resolvedPosition =        _toContinuationLocal(pos);

    switch (_currentMode) {
      case AppMode.wall:
        _handleWallPoint(provider, resolvedPosition);
        break;

      case AppMode.door:
      case AppMode.window:
        _handleFeatureInsertion(
          provider,
          _currentMode,
          resolvedPosition,
        );
        break;
    }
  }

  void _handleWallPoint(
    ScannerProvider provider,
    vector.Vector3 pos,
  ) {
    final ValidationResult result =
        provider.tryAddPoint(
      pos.x,
      pos.y,
      pos.z,
    );

    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ??
                'Punto inválido.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    if (result.warningMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warningMessage!,
          ),
          backgroundColor:
              Colors.amber.shade800,
          duration:
              const Duration(seconds: 2),
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
            'antes de medir una abertura.',
          ),
          backgroundColor: Colors.orange,
        ),
      );

      return;
    }

    final currentPoint =
        ARPoint(
      x: position.x,
      y: position.y,
      z: position.z,
    );

    final label =
        mode == AppMode.door
            ? 'Puerta'
            : 'Ventana';

    final pendingStart =
        _pendingFeatureStart;

    if (pendingStart == null ||
        _pendingFeatureMode !=
            mode) {
      setState(() {
        _pendingFeatureStart =
            currentPoint;
        _pendingFeatureMode =
            mode;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Inicio de $label registrado. '
              'Ubicá la cámara en el otro extremo y volvé a pulsar.',
            ),
            duration:
                const Duration(
              seconds: 3,
            ),
          ),
        );

      return;
    }

    final featureType =
        mode == AppMode.door
            ? FeatureType.door
            : FeatureType.window;

    final result =
        provider
            .addFeatureToCurrentRoom(
      featureType,
      pendingStart,
      endLocation:
          currentPoint,
    );

    setState(() {
      _pendingFeatureStart = null;
      _pendingFeatureMode = null;
    });

    if (!result.isValid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ??
                  'No se pudo medir la abertura.',
            ),
            backgroundColor:
                Colors.redAccent,
          ),
        );

      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$label guardada. '
            '${result.warningMessage ?? ''}',
          ),
          duration:
              const Duration(
            seconds: 2,
          ),
        ),
      );
  }

  // ================================================================
  // CIERRE Y PERSISTENCIA DE LA HABITACIÓN
  // ================================================================

  Future<void> _onCloseRoomPressed(
    ScannerProvider provider,
  ) async {
    HapticFeedback.mediumImpact();

    final continuation = widget.continuationReference;
    final floorPlanProvider = context.read<FloorPlanProvider>();

    if (continuation != null) {
      final sourceFeature = floorPlanProvider.findFeature(
        roomId: continuation.sourceRoomId,
        featureId: continuation.featureId,
      );

      if (sourceFeature == null || sourceFeature.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sourceFeature == null
                  ? 'La abertura de referencia ya no existe.'
                  : 'La abertura ya conecta otro ambiente.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final closedRoom =
        provider.closeCurrentRoom();

    if (!mounted) return;

    if (closedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.lastCloseError ??
                'No se pudo cerrar la habitación. '
                'Revisa los puntos trazados.',
          ),
          backgroundColor:
              Colors.redAccent,
        ),
      );

      return;
    }

    final saved = continuation == null
        ? true
        : await floorPlanProvider.addCompletedRoomFromContinuation(
            room: closedRoom,
            reference: continuation,
          );

    if (continuation == null) {
      await floorPlanProvider.addCompletedRoom(closedRoom);
    }

    if (!saved) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo conectar el ambiente con la abertura seleccionada.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          continuation == null
              ? '¡Ambiente guardado correctamente!'
              : '¡Ambiente conectado y alineado correctamente!',
        ),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  // ================================================================
  // PLANO
  // ================================================================

  void _openFloorPlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const FloorPlanViewerScreen(),
      ),
    );
  }
}