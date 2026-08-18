import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../providers/measurement_settings_provider.dart';
import '../services/geometry_service.dart';
import '../services/import_export_service.dart';
import '../services/ar_check_service.dart';
import '../utils/measurement_units.dart';
import 'measurement_editor_screen.dart';

class FloorPlanViewerScreen extends StatefulWidget {
  const FloorPlanViewerScreen({
    super.key,
  });

  @override
  State<FloorPlanViewerScreen> createState() =>
      _FloorPlanViewerScreenState();
}

class _FloorPlanViewerScreenState
    extends State<FloorPlanViewerScreen> {
  double _minX = 0.0;
  double _minZ = 0.0;
  double _scale = 1.0;
  double _padding = 20.0;

  String? _selectedRoomId;
  String? _selectedFeatureId;

  // ===========================================================================
  // TRANSFORMACIÓN PLANO ↔ PANTALLA
  // ===========================================================================

  Offset _transformPoint(
    ARPoint point,
  ) {
    final x =
        _padding +
        (point.x - _minX) * _scale;

    final z =
        _padding +
        (point.z - _minZ) * _scale;

    return Offset(x, z);
  }

  ARPoint _inverseTransform(
    Offset screenPosition,
  ) {
    final x =
        (screenPosition.dx - _padding) /
                _scale +
            _minX;

    final z =
        (screenPosition.dy - _padding) /
                _scale +
            _minZ;

    return ARPoint(
      x: x,
      y: 0.0,
      z: z,
    );
  }

  void _calculateTransform(
    Size screenSize,
    List<RoomModel> rooms,
  ) {
    if (rooms.isEmpty) {
      return;
    }

    double minX = double.infinity;
    double maxX =
        double.negativeInfinity;

    double minZ = double.infinity;
    double maxZ =
        double.negativeInfinity;

    bool hasPoints = false;

    for (final room in rooms) {
      for (final point in room.points) {
        hasPoints = true;

        if (point.x < minX) {
          minX = point.x;
        }

        if (point.x > maxX) {
          maxX = point.x;
        }

        if (point.z < minZ) {
          minZ = point.z;
        }

        if (point.z > maxZ) {
          maxZ = point.z;
        }
      }
    }

    if (!hasPoints) {
      _minX = 0.0;
      _minZ = 0.0;
      _scale = 1.0;
      _padding = 20.0;
      return;
    }

    _minX = minX;
    _minZ = minZ;

    _padding =
        screenSize.width * 0.08;

    final contentWidth =
        (maxX - minX).abs();

    final contentHeight =
        (maxZ - minZ).abs();

    final safeWidth =
        contentWidth <= 0.0001
            ? 1.0
            : contentWidth;

    final safeHeight =
        contentHeight <= 0.0001
            ? 1.0
            : contentHeight;

    final availableWidth =
        screenSize.width -
            (_padding * 2);

    final availableHeight =
        screenSize.height -
            (_padding * 2);

    final widthScale =
        availableWidth / safeWidth;

    final heightScale =
        availableHeight / safeHeight;

    _scale =
        widthScale < heightScale
            ? widthScale
            : heightScale;

    if (!_scale.isFinite ||
        _scale <= 0) {
      _scale = 1.0;
    }
  }

  String? _getRoomAtPosition(
    ARPoint point,
    List<RoomModel> rooms,
  ) {
    for (final room
        in rooms.reversed) {
      if (GeometryService
          .isPointInPolygon(
        point,
        room.points,
      )) {
        return room.id;
      }
    }

    return null;
  }

  _FeatureSelection? _getFeatureAtPosition(
    Offset screenPosition,
    List<RoomModel> rooms,
  ) {
    const touchTolerance = 18.0;

    _FeatureSelection? nearest;
    double nearestDistance = double.infinity;

    for (final room in rooms.reversed) {
      for (final feature in room.features) {
        final distance = _distanceToSegment(
          screenPosition,
          _transformPoint(feature.start),
          _transformPoint(feature.end),
        );

        if (distance <= touchTolerance &&
            distance < nearestDistance) {
          nearestDistance = distance;
          nearest = _FeatureSelection(
            roomId: room.id,
            feature: feature,
          );
        }
      }
    }

    return nearest;
  }

  double _distanceToSegment(
    Offset point,
    Offset start,
    Offset end,
  ) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx +
        segment.dy * segment.dy;

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final fromStart = point - start;
    final rawT =
        (fromStart.dx * segment.dx +
                fromStart.dy * segment.dy) /
            lengthSquared;
    final t = rawT.clamp(0.0, 1.0).toDouble();
    final projection = Offset(
      start.dx + segment.dx * t,
      start.dy + segment.dy * t,
    );

    return (point - projection).distance;
  }

  Future<void> _showFeatureMenu(
    _FeatureSelection selection,
  ) async {
    setState(() {
      _selectedRoomId = selection.roomId;
      _selectedFeatureId = selection.feature.id;
    });

    final feature = selection.feature;
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;
    final localizations = AppLocalizations.of(context)!;
    final label = feature.type == FeatureType.door
        ? 'Puerta'
        : 'Ventana';

    final action = await showModalBottomSheet<_FeatureMenuAction>(
      context: context,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    feature.type == FeatureType.door
                        ? Icons.door_front_door
                        : Icons.window,
                    color: feature.type == FeatureType.door
                        ? const Color(0xFFFF8A00)
                        : const Color(0xFFD500F9),
                  ),
                  title: Text('$label seleccionada'),
                  subtitle: Text(
                    '${feature.isConnected ? 'Conectada' : 'Disponible'} · '
                    '${_formatLength(_featureWidth(feature), measurementSystem)}'
                    '${feature.isConnected ? '' : ' · Inicio en el punto marcado'}',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                      bottomSheetContext,
                      _FeatureMenuAction.editGeometry,
                    ),
                    icon: const Icon(Icons.straighten),
                    label: Text(
                      localizations.editOpeningDimensions,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (feature.type == FeatureType.door) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                        bottomSheetContext,
                        _FeatureMenuAction.toggleHinge,
                      ),
                      icon: const Icon(Icons.flip),
                      label: Text(
                        localizations.changeDoorHingeSide,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                        bottomSheetContext,
                        _FeatureMenuAction.toggleSwing,
                      ),
                      icon: const Icon(Icons.rotate_left),
                      label: Text(
                        localizations.changeDoorOpeningDirection,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: feature.isConnected
                        ? null
                        : () => Navigator.pop(
                              bottomSheetContext,
                              _FeatureMenuAction.continueScanning,
                            ),
                    icon: const Icon(Icons.add_road_rounded),
                    label: Text(
                      feature.isConnected
                          ? 'Esta abertura ya conecta dos ambientes'
                          : 'Continuar escaneo desde aquí',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    if (action == _FeatureMenuAction.editGeometry) {
      await _showOpeningGeometryEditor(selection);
      return;
    }

    if (action == _FeatureMenuAction.toggleHinge) {
      final updated = await context
          .read<FloorPlanProvider>()
          .updateDoorOrientation(
            featureId: feature.id,
            hingeSide:
                feature.doorHingeSide == DoorHingeSide.start
                    ? DoorHingeSide.end
                    : DoorHingeSide.start,
          );

      if (mounted && !updated) {
        _showMessage(
          'La puerta seleccionada ya no está disponible.',
          error: true,
        );
      }
      return;
    }

    if (action == _FeatureMenuAction.toggleSwing) {
      final updated = await context
          .read<FloorPlanProvider>()
          .updateDoorOrientation(
            featureId: feature.id,
            swingSide:
                feature.doorSwingSide == DoorSwingSide.left
                    ? DoorSwingSide.right
                    : DoorSwingSide.left,
          );

      if (mounted && !updated) {
        _showMessage(
          'La puerta seleccionada ya no está disponible.',
          error: true,
        );
      }
      return;
    }

    if (action != _FeatureMenuAction.continueScanning) {
      return;
    }

    final side = await _chooseConnectionSide(feature);

    if (!mounted || side == null) return;

    final provider = context.read<FloorPlanProvider>();
    final reference = provider.createContinuationReference(
      roomId: selection.roomId,
      featureId: feature.id,
      side: side,
      startEndpoint: ContinuationStartEndpoint.start,
    );

    final projectUuid = provider.projectUuid;

    if (reference == null || projectUuid == null) {
      _showMessage(
        'La abertura seleccionada ya no está disponible.',
        error: true,
      );
      return;
    }

    await ArCheckService.abrirEscanerConValidacion(
      context,
      projectUuid: projectUuid,
      projectName: provider.projectName,
      continuationReference: reference,
    );
  }

  Future<void> _showOpeningGeometryEditor(
    _FeatureSelection selection,
  ) async {
    final provider = context.read<FloorPlanProvider>();
    final placement = provider.getOpeningPlacement(
      roomId: selection.roomId,
      featureId: selection.feature.id,
    );
    final localizations = AppLocalizations.of(context)!;
    final measurementSystem = context
        .read<MeasurementSettingsProvider>()
        .system;

    if (placement == null) {
      _showMessage(
        'No se pudo identificar la pared de la abertura.',
        error: true,
      );
      return;
    }

    final widthMetricController = TextEditingController(
      text: _formatDecimal(placement.widthMeters),
    );
    final positionMetricController = TextEditingController(
      text: _formatDecimal(
        placement.distanceFromWallStartMeters,
      ),
    );
    final heightMetricController = TextEditingController(
      text: _formatDecimal(placement.openingHeightMeters),
    );
    final sillMetricController = TextEditingController(
      text: _formatDecimal(placement.sillHeightMeters),
    );
    final widthImperial = MeasurementUnits.metersToFeetAndInches(
      placement.widthMeters,
    );
    final positionImperial =
        MeasurementUnits.metersToFeetAndInches(
      placement.distanceFromWallStartMeters,
    );
    final heightImperial = MeasurementUnits.metersToFeetAndInches(
      placement.openingHeightMeters,
    );
    final sillImperial = MeasurementUnits.metersToFeetAndInches(
      placement.sillHeightMeters,
    );
    final widthFeetController = TextEditingController(
      text: widthImperial.feet.toString(),
    );
    final widthInchesController = TextEditingController(
      text: _formatDecimal(widthImperial.inches),
    );
    final positionFeetController = TextEditingController(
      text: positionImperial.feet.toString(),
    );
    final positionInchesController = TextEditingController(
      text: _formatDecimal(positionImperial.inches),
    );
    final heightFeetController = TextEditingController(
      text: heightImperial.feet.toString(),
    );
    final heightInchesController = TextEditingController(
      text: _formatDecimal(heightImperial.inches),
    );
    final sillFeetController = TextEditingController(
      text: sillImperial.feet.toString(),
    );
    final sillInchesController = TextEditingController(
      text: _formatDecimal(sillImperial.inches),
    );

    double? readLength({
      required TextEditingController metric,
      required TextEditingController feet,
      required TextEditingController inches,
    }) {
      if (measurementSystem == MeasurementSystem.metric) {
        return MeasurementUnits.metricInputToMeters(metric.text);
      }
      return MeasurementUnits.imperialInputToMeters(
        feetInput: feet.text,
        inchesInput: inches.text,
      );
    }

    final input = await showDialog<_OpeningGeometryInput>(
      context: context,
      builder: (dialogContext) {
        String? validationMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget lengthFields({
              required String label,
              required TextEditingController metric,
              required TextEditingController feet,
              required TextEditingController inches,
            }) {
              if (measurementSystem == MeasurementSystem.metric) {
                return TextField(
                  controller: metric,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    suffixText: localizations.meters,
                    border: const OutlineInputBorder(),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: feet,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: localizations.feet,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: inches,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: localizations.inches,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text(localizations.editOpeningDimensions),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(                      '${localizations.wallLength}: '
                      '${_formatLength(placement.wallLengthMeters, measurementSystem)}',
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.openingWidth,
                      metric: widthMetricController,
                      feet: widthFeetController,
                      inches: widthInchesController,
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.distanceFromWallStart,
                      metric: positionMetricController,
                      feet: positionFeetController,
                      inches: positionInchesController,
                    ),
                    const SizedBox(height: 16),
                    lengthFields(
                      label: localizations.openingHeight,
                      metric: heightMetricController,
                      feet: heightFeetController,
                      inches: heightInchesController,
                    ),
                    if (selection.feature.type ==
                        FeatureType.window) ...[
                      const SizedBox(height: 16),
                      lengthFields(
                        label: localizations.sillHeight,
                        metric: sillMetricController,
                        feet: sillFeetController,
                        inches: sillInchesController,
                      ),
                    ],
                    if (validationMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        validationMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(localizations.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final width = readLength(
                      metric: widthMetricController,
                      feet: widthFeetController,
                      inches: widthInchesController,
                    );
                    final position = readLength(
                      metric: positionMetricController,
                      feet: positionFeetController,
                      inches: positionInchesController,
                    );
                    final height = readLength(
                      metric: heightMetricController,
                      feet: heightFeetController,
                      inches: heightInchesController,
                    );
                    final sill = selection.feature.type ==
                            FeatureType.window
                        ? readLength(
                            metric: sillMetricController,
                            feet: sillFeetController,
                            inches: sillInchesController,
                          )
                        : 0.0;

                    if (width == null ||
                        position == null ||
                        height == null ||
                        sill == null) {
                      setDialogState(() {
                        validationMessage =
                            localizations.invalidOpeningMeasurement;
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _OpeningGeometryInput(
                        widthMeters: width,
                        distanceFromWallStartMeters: position,
                        openingHeightMeters: height,
                        sillHeightMeters: sill,
                      ),
                    );
                  },
                  child: Text(localizations.save),
                ),
              ],
            );
          },
        );
      },
    );

    widthMetricController.dispose();
    positionMetricController.dispose();
    widthFeetController.dispose();
    widthInchesController.dispose();
    positionFeetController.dispose();
    positionInchesController.dispose();
    heightMetricController.dispose();
    sillMetricController.dispose();
    heightFeetController.dispose();
    heightInchesController.dispose();
    sillFeetController.dispose();
    sillInchesController.dispose();

    if (!mounted || input == null) return;

    final result = await provider.updateOpeningGeometry(
      roomId: selection.roomId,
      featureId: selection.feature.id,
      widthMeters: input.widthMeters,
      distanceFromWallStartMeters:
          input.distanceFromWallStartMeters,
      openingHeightMeters: input.openingHeightMeters,
      sillHeightMeters: input.sillHeightMeters,
    );

    if (!mounted) return;
    _showMessage(
      result.isSuccess
          ? localizations.openingUpdated
          : result.errorMessage ??
              localizations.invalidOpeningMeasurement,
      error: !result.isSuccess,
    );
  }

  Future<OpeningConnectionSide?> _chooseConnectionSide(
    WallFeature feature,
  ) {
    final start = _transformPoint(feature.start);
    final end = _transformPoint(feature.end);
    final openingDirection = end - start;
    final leftDirection = Offset(
      -openingDirection.dy,
      openingDirection.dx,
    );
    final rightDirection = -leftDirection;

    return showDialog<OpeningConnectionSide>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Hacia dónde continúa el plano?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'El punto verde marca dónde comenzará el nuevo ambiente. '
                'Elegí la flecha que apunta hacia el ambiente que vas a escanear.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 240,
                height: 120,
                child: CustomPaint(
                  painter: _OpeningDirectionPainter(
                    openingDirection: openingDirection,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    OpeningConnectionSide.left,
                  ),
                  icon: Icon(_directionIcon(leftDirection)),
                  label: Text(
                    'Continuar hacia ${_directionLabel(leftDirection)}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    OpeningConnectionSide.right,
                  ),
                  icon: Icon(_directionIcon(rightDirection)),
                  label: Text(
                    'Continuar hacia ${_directionLabel(rightDirection)}',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  String _directionLabel(Offset direction) {
    if (direction.dx.abs() >= direction.dy.abs()) {
      return direction.dx >= 0 ? 'la derecha' : 'la izquierda';
    }

    return direction.dy >= 0 ? 'abajo' : 'arriba';
  }

  IconData _directionIcon(Offset direction) {
    if (direction.dx.abs() >= direction.dy.abs()) {
      return direction.dx >= 0
          ? Icons.arrow_forward
          : Icons.arrow_back;
    }

    return direction.dy >= 0
        ? Icons.arrow_downward
        : Icons.arrow_upward;
  }

  double _featureWidth(WallFeature feature) {
    return GeometryService.calculateDistance(
      feature.start,
      feature.end,
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

  String _formatArea(
    double squareMeters,
    MeasurementSystem measurementSystem,
  ) {
    final localizations =
        AppLocalizations.of(context)!;

    if (measurementSystem ==
        MeasurementSystem.metric) {
      return '${_formatDecimal(squareMeters)} '
          '${localizations.squareMeters}';
    }

    final squareFeet =
        MeasurementUnits.squareMetersToSquareFeet(
      squareMeters,
    );

    return '${_formatDecimal(squareFeet)} '
        '${localizations.squareFeet}';
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
      formatted = formatted.substring(        0,
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

  // ===========================================================================
  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<void>
      _openMeasurementEditor({    String? roomId,
  }) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MeasurementEditorScreen(
          roomId: roomId,        ),
      ),
    );
  }

  // ===========================================================================
  // ORGANIZACIÓN AUTOMÁTICA
  // ===========================================================================
  Future<void> _organizeRooms() async {
    final provider =        context.read<            FloorPlanProvider>();

    if (provider.completedRooms.length <=
        1) {
      _showMessage(
        'No hay suficientes ambientes para organizar.',
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.grid_view_rounded,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Organizar ambientes',
                ),
              ),
            ],
          ),
          content: const Text(
            'Los ambientes se distribuirán automáticamente '
            'uno junto a otro, manteniendo intactas sus '
            'medidas, superficies, puertas y ventanas.\n\n'
            'Esta operación modifica únicamente su posición '
            'en el plano general.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,                );
              },
              icon: const Icon(
                Icons.auto_awesome,
              ),
              label: const Text(
                'Organizar',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    await provider.autoArrangeRooms();

    if (!mounted) {
      return;
    }

    _showMessage(
      'Ambientes organizados correctamente.',
    );
  }
  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override  Widget build(
    BuildContext context,
  ) {
    final measurementSystem = context
        .watch<MeasurementSettingsProvider>()
        .system;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Plano General 2D',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.grid_view_rounded,
            ),
            tooltip:
                'Organizar ambientes',
            onPressed:
                _organizeRooms,
          ),
          IconButton(
            icon: const Icon(
              Icons.straighten_outlined,
            ),
            tooltip:
                'Editar medidas',
            onPressed: () =>
                _openMeasurementEditor(),
          ),
          PopupMenuButton<
              _FloorPlanAction>(
            tooltip: 'Más opciones',
            onSelected: (action) {
              switch (action) {
                case _FloorPlanAction
                      .importJson:
                  _importJson();
                  break;

                case _FloorPlanAction
                      .shareJson:
                  _shareJson();
                  break;

                case _FloorPlanAction
                      .exportPdf:
                  _exportPdf();
                  break;
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value:
                      _FloorPlanAction
                          .importJson,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.file_upload,
                    ),
                    title: Text(
                      'Importar plano',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value:
                      _FloorPlanAction
                          .shareJson,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.share,
                    ),
                    title: Text(
                      'Compartir JSON',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value:
                      _FloorPlanAction
                          .exportPdf,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.picture_as_pdf,
                    ),
                    title: Text(
                      'Exportar PDF',
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),

      floatingActionButton:
          FloatingActionButton.extended(
        tooltip:
            'Ambientes registrados',
        onPressed:
            _showRoomListDialog,
        icon: const Icon(
          Icons.meeting_room_outlined,
        ),
        label: const Text(
          'Ambientes',
        ),
      ),

      body: Consumer<
          FloorPlanProvider>(
        builder: (
          context,
          provider,
          child,
        ) {
          final rooms =
              provider.completedRooms;

          if (rooms.isEmpty) {
            return const _EmptyPlanView();
          }

          return LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              final size =
                  constraints.biggest;

              _calculateTransform(
                size,
                rooms,
              );

              return Stack(
                children: [
                  InteractiveViewer(
                    constrained: true,
                    boundaryMargin:
                        const EdgeInsets.all(
                      200,
                    ),
                    minScale: 0.2,
                    maxScale: 6.0,
                    child:
                        GestureDetector(
                      behavior:
                          HitTestBehavior
                              .opaque,
                      onTapUp: (
                        details,
                      ) {
                        final featureSelection =
                            _getFeatureAtPosition(
                          details.localPosition,
                          rooms,
                        );

                        if (featureSelection != null) {
                          _showFeatureMenu(
                            featureSelection,
                          );
                          return;
                        }

                        final planePoint =
                            _inverseTransform(
                          details                              .localPosition,
                        );

                        final roomId =
                            _getRoomAtPosition(
                          planePoint,
                          rooms,
                        );

                        if (roomId ==
                            null) {
                          _showMessage(
                            'Tocá dentro de un ambiente para '
                            'añadir una puerta o ventana.',
                          );
                          return;
                        }

                        _showAddFeatureMenu(
                          roomId:
                              roomId,
                          location:
                              planePoint,
                        );
                      },
                      child:
                          SizedBox.expand(
                        child:
                            CustomPaint(
                          painter:
                              FloorPlanPainter(
                            rooms:
                                rooms,
                            transform:
                                _transformPoint,
                            selectedRoomId:
                                _selectedRoomId,
                            selectedFeatureId:
                                _selectedFeatureId,
                            formatArea: (area) =>
                                _formatArea(
                              area,
                              measurementSystem,
                            ),
                            formatLength: (length) =>
                                _formatLength(
                              length,
                              measurementSystem,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 12,
                    top: 12,
                    child:
                        IgnorePointer(
                      child: Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 12,
                          vertical: 8,                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors
                              .black
                              .withOpacity(
                            0.72,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                        ),
                        child: Text(
                          '${rooms.length} '
                          '${rooms.length == 1 ? 'ambiente' : 'ambientes'}'
                          ' · '
                          '${_formatArea(provider.totalProjectArea, measurementSystem)}',
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================================================
  // IMPORTAR / EXPORTAR
  // ===========================================================================

  Future<void> _importJson() async {
    final provider =
        context.read<
            FloorPlanProvider>();

    final success =
        await ImportExportService
            .importFromJson(
      provider,
    );

    if (!mounted) {
      return;
    }

    _showMessage(
      success
          ? 'Plano importado correctamente.'
          : 'Importación cancelada o no válida.',
      error: !success,
    );
  }

  Future<void> _shareJson() async {
    final provider =
        context.read<
            FloorPlanProvider>();

    await ImportExportService
        .exportToJson(
      provider.completedRooms,
      provider.projectName,
    );
  }

  Future<void> _exportPdf() async {
    final provider =
        context.read<
            FloorPlanProvider>();

    await ImportExportService
        .exportToPdf(
      provider.completedRooms,
      provider.projectName,
    );
  }
  // ===========================================================================
  // PUERTAS / VENTANAS
  // ===========================================================================  Future<void>
      _showAddFeatureMenu({
    required String roomId,
    required ARPoint location,
  }) async {
    final selected =
        await showModalBottomSheet<
            FeatureType>(
      context: context,
      builder: (
        bottomSheetContext,
      ) {
        return SafeArea(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(
                  Icons
                      .add_location_alt,
                ),
                title: Text(
                  'Agregar elemento',
                ),
                subtitle: Text(
                  'Seleccioná el elemento '                  'que querés incorporar.',
                ),
              ),
              const Divider(
                height: 1,
              ),
              ListTile(
                leading:
                    const Icon(
                  Icons
                      .door_front_door,
                  color:
                      Colors.red,
                ),
                title:
                    const Text(
                  'Puerta',
                ),
                onTap: () {
                  Navigator.pop(
                    bottomSheetContext,
                    FeatureType.door,                  );
                },
              ),
              ListTile(
                leading:
                    const Icon(
                  Icons.window,
                  color:
                      Colors.blue,
                ),
                title:
                    const Text(
                  'Ventana',
                ),
                onTap: () {
                  Navigator.pop(
                    bottomSheetContext,
                    FeatureType.window,
                  );
                },
              ),
              const SizedBox(
                height: 8,
              ),
            ],
          ),
        );
      },
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    final width =
        selected ==
                FeatureType.door
            ? 0.8
            : 1.0;

    final endPoint = ARPoint(
      x: location.x + width,
      y: location.y,
      z: location.z,
    );

    await context
        .read<FloorPlanProvider>()
        .addFeatureToRoom(
          roomId,
          selected,
          location,
          endPoint,
        );
  }

    Future<void>
      _showRoomListDialog() async {
    final action =
        await showModalBottomSheet<
            _RoomListAction>(      context: context,
      isScrollControlled: true,
      builder: (
        bottomSheetContext,
      ) {
        return Consumer<
            FloorPlanProvider>(
          builder: (
            context,
            provider,
            child,
          ) {
            final rooms =
                provider.completedRooms;
            final measurementSystem = context
                .watch<MeasurementSettingsProvider>()
                .system;

            return SafeArea(
              child: Padding(
                padding:                    const EdgeInsets
                        .fromLTRB(                  16,
                  16,
                  16,
                  24,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ambientes registrados',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () {
                            Navigator.pop(
                              bottomSheetContext,
                            );
                          },                          icon: const Icon(
                            Icons.close,
                          ),
                        ),
                      ],                    ),
                    const SizedBox(
                      height: 8,
                    ),

                    if (rooms.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(
                          vertical: 32,
                        ),
                        child: Center(
                          child: Text(
                            'No hay ambientes aún.',
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child:
                            ListView.separated(
                          shrinkWrap: true,
                          itemCount:
                              rooms.length,
                          separatorBuilder:
                              (
                            context,
                            index,
                          ) =>
                                  const Divider(
                            height: 1,
                          ),
                          itemBuilder:
                              (
                            context,
                            index,
                          ) {
                            final room =
                                rooms[index];

                            final area =
                                GeometryService
                                    .calculateArea(
                              room.points,
                            );
                            final perimeter =
                                GeometryService
                                    .calculatePerimeter(
                              room.points,
                            );

                            return ListTile(
                              contentPadding:
                                  EdgeInsets.zero,
                              leading:
                                  CircleAvatar(
                                child: Text(
                                  '${index + 1}',
                                ),
                              ),
                              title: Text(
                                room.name,
                              ),
                              subtitle: Text(
                                '${_formatArea(area, measurementSystem)} · '
                                '${_formatLength(perimeter, measurementSystem)} de perímetro'                                ' · '
                                '${room.points.length} esquinas',
                              ),
                              trailing:
                                  PopupMenuButton<
                                      _RoomListActionType>(
                                tooltip:
                                    'Acciones',
                                onSelected:
                                    (
                                  type,
                                ) {
                                  Navigator.pop(
                                    bottomSheetContext,
                                    _RoomListAction(
                                      type: type,
                                      roomId:
                                          room.id,
                                    ),
                                  );
                                },
                                itemBuilder:
                                    (
                                  context,
                                ) {
                                  return const [
                                    PopupMenuItem(
                                      value:
                                          _RoomListActionType
                                              .editMeasurements,
                                      child:
                                          ListTile(
                                        dense: true,
                                        leading:
                                            Icon(
                                          Icons
                                              .straighten_outlined,
                                        ),
                                        title:
                                            Text(
                                          'Editar medidas',
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value:
                                          _RoomListActionType
                                              .rename,
                                      child:
                                          ListTile(
                                        dense: true,
                                        leading:
                                            Icon(
                                          Icons
                                              .edit_outlined,
                                        ),
                                        title:
                                            Text(
                                          'Renombrar',
                                        ),
                                      ),
                                    ),
                                  ];
                                },
                              ),
                            );
                          },
                        ),
                      ),

                    if (rooms.length >
                        1) ...[
                      const SizedBox(
                        height: 12,
                      ),
                      SizedBox(
                        width:
                            double.infinity,
                        child:
                            OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              bottomSheetContext,
                              const _RoomListAction(
                                type:
                                    _RoomListActionType
                                        .organize,
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons
                                .grid_view_rounded,
                          ),
                          label: const Text(
                            'Organizar ambientes',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (action == null ||
        !mounted) {
      return;
    }

    switch (action.type) {
      case _RoomListActionType
            .editMeasurements:
        await _openMeasurementEditor(
          roomId:
              action.roomId,
        );
        break;

      case _RoomListActionType
            .rename:
        final room =
            _findRoom(
          action.roomId,
        );

        if (room != null) {
          await _editRoomName(
            room,
          );
        }
        break;

      case _RoomListActionType
            .organize:
        await _organizeRooms();
        break;
    }
  }

  RoomModel? _findRoom(
    String? roomId,
  ) {
    if (roomId == null) {
      return null;
    }

    final rooms =
        context
            .read<
                FloorPlanProvider>()
            .completedRooms;

    for (final room in rooms) {
      if (room.id ==
          roomId) {
        return room;
      }
    }

    return null;
  }

  // ===========================================================================
  // RENOMBRAR AMBIENTE
  // ===========================================================================

  Future<void> _editRoomName(
    RoomModel room,
  ) async {
    final controller =
        TextEditingController(
      text: room.name,
    );

    final newName =
        await showDialog<String>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Renombrar ambiente',
          ),
          content: TextField(
            controller:
                controller,
            autofocus: true,
            textCapitalization:
                TextCapitalization
                    .sentences,
            decoration:
                const InputDecoration(
              labelText: 'Nombre',
              hintText:
                  'Ej. Dormitorio principal',
              border:
                  OutlineInputBorder(),
            ),
            onSubmitted:
                (value) {
              Navigator.pop(
                dialogContext,
                value.trim(),
              );
            },
          ),
          actions: [
            TextButton(              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  controller.text
                      .trim(),
                );
              },
              child: const Text(
                'Guardar',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newName == null ||
        newName.trim().isEmpty ||
        !mounted) {
      return;
    }

    await context
        .read<FloorPlanProvider>()
        .updateRoomName(
          room.id,
          newName.trim(),
        );
  }

  // ===========================================================================
  // MENSAJES
  // ===========================================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
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
              error
                  ? Colors.red.shade700
                  : null,
          content: Text(            message,
          ),
        ),
      );
  }
}
// =============================================================================
// ACCIONES
// =============================================================================
enum _FloorPlanAction {
  importJson,
  shareJson,
  exportPdf,
}
enum _RoomListActionType {
  editMeasurements,
  rename,
  organize,
}
class _RoomListAction {
  final _RoomListActionType type;

  final String? roomId;

  const _RoomListAction({
    required this.type,
    this.roomId,
  });
}

enum _FeatureMenuAction {
  continueScanning,
  editGeometry,
  toggleHinge,
  toggleSwing,
}

class _OpeningGeometryInput {
  final double widthMeters;
  final double distanceFromWallStartMeters;
  final double openingHeightMeters;
  final double sillHeightMeters;

  const _OpeningGeometryInput({
    required this.widthMeters,
    required this.distanceFromWallStartMeters,
    required this.openingHeightMeters,
    required this.sillHeightMeters,
  });
}

class _FeatureSelection {
  final String roomId;
  final WallFeature feature;

  const _FeatureSelection({
    required this.roomId,
    required this.feature,
  });
}

class _OpeningDirectionPainter extends CustomPainter {
  final Offset openingDirection;

  const _OpeningDirectionPainter({
    required this.openingDirection,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final midpoint = Offset(
      size.width / 2.0,
      size.height / 2.0,
    );
    final length = openingDirection.distance;
    final tangent = length <= 0.000001
        ? const Offset(1, 0)
        : openingDirection / length;
    final normal = Offset(-tangent.dy, tangent.dx);
    final halfOpening = size.shortestSide * 0.42;
    final arrowLength = size.shortestSide * 0.35;
    final start = midpoint - tangent * halfOpening;
    final end = midpoint + tangent * halfOpening;

    final openingPaint = Paint()
      ..color = const Color(0xFFFF8A00)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final arrowPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, openingPaint);
    _drawArrow(
      canvas,
      midpoint,
      midpoint + normal * arrowLength,
      arrowPaint,
    );
    _drawArrow(
      canvas,
      midpoint,
      midpoint - normal * arrowLength,
      arrowPaint,
    );
    canvas.drawCircle(
      start,
      9,
      Paint()..color = const Color(0xFF00C853),
    );
    canvas.drawCircle(
      start,
      3,
      Paint()..color = Colors.white,
    );
  }

  void _drawArrow(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    canvas.drawLine(start, end, paint);
    final delta = end - start;
    final length = delta.distance;

    if (length <= 0.000001) {
      return;
    }

    final direction = delta / length;
    final perpendicular = Offset(-direction.dy, direction.dx);
    canvas.drawLine(
      end,
      end - direction * 10 + perpendicular * 8,
      paint,
    );
    canvas.drawLine(
      end,
      end - direction * 10 - perpendicular * 8,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _OpeningDirectionPainter oldDelegate,
  ) => false;
}

class _EmptyPlanView extends StatelessWidget {
  const _EmptyPlanView();

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Center(
      child: Padding(        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .architecture_outlined,
              size: 72,
              color: Colors.black38,
            ),
            SizedBox(
              height: 16,
            ),
            Text(
              'No hay ambientes escaneados',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            SizedBox(
              height: 8,
            ),
            Text(
              'Completá un escaneo para visualizar '              'el plano general.',
              textAlign:
                  TextAlign.center,              style: TextStyle(
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PAINTER// =============================================================================
class FloorPlanPainter
    extends CustomPainter {
  final List<RoomModel> rooms;

  final Offset Function(
    ARPoint,
  ) transform;

  final String? selectedRoomId;
  final String? selectedFeatureId;
  final String Function(double)
      formatArea;
  final String Function(double)
      formatLength;

  const FloorPlanPainter({
    required this.rooms,
    required this.transform,
    required this.formatArea,
    required this.formatLength,
    this.selectedRoomId,
    this.selectedFeatureId,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (rooms.isEmpty) {
      return;
    }

    final wallPaint =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          )
          ..strokeWidth = 3.0
          ..style =
              PaintingStyle.stroke
          ..strokeJoin =
              StrokeJoin.round
          ..strokeCap =
              StrokeCap.round;

    final roomFill =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          ).withOpacity(
            0.10,
          )
          ..style =
              PaintingStyle.fill;

    final pointPaint =
        Paint()
          ..color =
              const Color(
            0xFF448AFF,
          )
          ..style =
              PaintingStyle.fill;
    final doorPaint =
        Paint()
          ..color =
              const Color(
            0xFFFF8A00,
          )
          ..strokeWidth = 5.0
          ..style =
              PaintingStyle.stroke
          ..strokeCap =
              StrokeCap.square;

    final windowPaint =
        Paint()
          ..color =
              const Color(
            0xFFD500F9,
          )
          ..strokeWidth = 5.0
          ..style =
              PaintingStyle.stroke
          ..strokeCap =
              StrokeCap.square;

    final selectedPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 11.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final referencePaint = Paint()
      ..color = const Color(0xFF00C853)
      ..style = PaintingStyle.fill;
    final dimensionedFeatureIds =
        <String>{};
    final featureOwnerRoomIds = <String, String>{};

    for (final room in rooms) {
      for (final feature in room.features) {
        featureOwnerRoomIds.putIfAbsent(
          feature.id,
          () => room.id,
        );

        if (room.id == selectedRoomId &&
            feature.id == selectedFeatureId) {
          featureOwnerRoomIds[feature.id] = room.id;
        }
      }
    }

    for (final room in rooms) {
      _drawRoom(
        canvas,
        room,
        wallPaint,
        roomFill,
        pointPaint,
      );

      _drawRoomLabel(
        canvas,
        room,
      );

      _drawFeatures(
        canvas,
        room,
        doorPaint,
        windowPaint,
        selectedPaint,
        referencePaint,
        featureOwnerRoomIds,
      );
      _drawWallDimensions(
        canvas,
        room,
      );

      _drawOpeningDimensions(
        canvas,
        room,
        dimensionedFeatureIds,
      );
    }
  }

  // ===========================================================================
  // HABITACIÓN
  // ===========================================================================

  void _drawRoom(
    Canvas canvas,
    RoomModel room,
    Paint wallPaint,
    Paint roomFill,
    Paint pointPaint,
  ) {
    if (room.points.length < 2) {
      return;
    }

    final path = Path();

    final start =
        transform(
      room.points.first,
    );

    path.moveTo(
      start.dx,
      start.dy,
    );

    for (
      int i = 1;
      i < room.points.length;
      i++
    ) {
      final next =
          transform(
        room.points[i],
      );

      path.lineTo(
        next.dx,
        next.dy,
      );
    }

    if (room.isClosed ||
        room.points.length >= 3) {
      path.close();
    }

    if (room.points.length >= 3) {
      canvas.drawPath(
        path,
        roomFill,
      );
    }

    canvas.drawPath(
      path,
      wallPaint,
    );

    for (final point
        in room.points) {
      canvas.drawCircle(
        transform(point),
        4.0,
        pointPaint,
      );
    }
  }

  // ===========================================================================
  // NOMBRE Y SUPERFICIE
  // ===========================================================================

  void _drawRoomLabel(
    Canvas canvas,
    RoomModel room,
  ) {
    if (room.points.isEmpty) {
      return;
    }

    double x = 0.0;
    double y = 0.0;

    for (final point
        in room.points) {
      final transformed =
          transform(point);

      x += transformed.dx;
      y += transformed.dy;
    }

    final center = Offset(
      x / room.points.length,
      y / room.points.length,
    );

    final area =
        GeometryService
            .calculateArea(
      room.points,
    );

    final textPainter =
        TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: room.name,
            style:
                const TextStyle(
              color:
                  Colors.black87,
              fontSize: 13,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          TextSpan(
            text:
                '\n${formatArea(area)}',
            style:
                const TextStyle(
              color:
                  Colors.black54,
              fontSize: 10,
              fontWeight:
                  FontWeight.w500,
            ),
          ),
        ],
      ),
      textAlign:
          TextAlign.center,
      textDirection:
          TextDirection.ltr,
      maxLines: 2,
    )..layout(
        maxWidth: 140,
      );

    final backgroundRect =
        Rect.fromCenter(
      center: center,
      width:
          textPainter.width + 14,
      height:
          textPainter.height + 10,
    );

    final backgroundPaint =
        Paint()
          ..color = Colors.white
              .withOpacity(
            0.86,
          )
          ..style =
              PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        backgroundRect,
        const Radius.circular(
          7,
        ),
      ),
      backgroundPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        center.dx -
            textPainter.width / 2,
        center.dy -
            textPainter.height / 2,
      ),
    );
  }

  // ===========================================================================  // COTAS DE PAREDES
  // ===========================================================================

  void _drawWallDimensions(
    Canvas canvas,
    RoomModel room,
  ) {
    if (room.points.length < 3) {
      return;
    }

    final screenPoints = room.points
        .map(transform)
        .toList(growable: false);
    final signedArea =
        _screenSignedArea(screenPoints);

    if (signedArea.abs() < 0.000001) {
      return;
    }

    final dimensionPaint = Paint()
      ..color = const Color(0xFF174EA6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: 0.94,
      )
      ..style = PaintingStyle.fill;

    for (var index = 0;
        index < room.points.length;
        index++) {
      final nextIndex =
          (index + 1) % room.points.length;
      final start = screenPoints[index];
      final end = screenPoints[nextIndex];
      final direction = end - start;
      final screenLength = direction.distance;

      if (screenLength < 30) {
        continue;
      }

      final tangent = direction / screenLength;
      final outwardNormal = signedArea > 0
          ? Offset(tangent.dy, -tangent.dx)
          : Offset(-tangent.dy, tangent.dx);
      const dimensionOffset = 19.0;
      const extensionStartOffset = 5.0;
      const extensionEndOffset = 24.0;
      const endMarkHalfLength = 4.0;      final dimensionStart =
          start + outwardNormal * dimensionOffset;
      final dimensionEnd =
          end + outwardNormal * dimensionOffset;

      canvas.drawLine(
        start + outwardNormal * extensionStartOffset,
        start + outwardNormal * extensionEndOffset,
        dimensionPaint,
      );
      canvas.drawLine(
        end + outwardNormal * extensionStartOffset,
        end + outwardNormal * extensionEndOffset,
        dimensionPaint,
      );      canvas.drawLine(
        dimensionStart,
        dimensionEnd,
        dimensionPaint,
      );
      canvas.drawLine(
        dimensionStart -
            outwardNormal * endMarkHalfLength,
        dimensionStart +
            outwardNormal * endMarkHalfLength,
        dimensionPaint,
      );
      canvas.drawLine(
        dimensionEnd -
            outwardNormal * endMarkHalfLength,
        dimensionEnd +
            outwardNormal * endMarkHalfLength,
        dimensionPaint,
      );

      final wallLength =
          GeometryService.calculateDistance(
        room.points[index],
        room.points[nextIndex],
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: formatLength(wallLength),
          style: const TextStyle(
            color: Color(0xFF174EA6),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final center = Offset(
        (dimensionStart.dx + dimensionEnd.dx) / 2,
        (dimensionStart.dy + dimensionEnd.dy) / 2,
      );
      var angle = math.atan2(
        tangent.dy,
        tangent.dx,
      );

      if (angle > math.pi / 2 ||
          angle < -math.pi / 2) {
        angle += math.pi;
      }

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final backgroundRect = Rect.fromCenter(
        center: Offset.zero,
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          backgroundRect,
          const Radius.circular(4),
        ),
        backgroundPaint,
      );
      textPainter.paint(
        canvas,
        Offset(
          -textPainter.width / 2,
          -textPainter.height / 2,
        ),
      );
      canvas.restore();
    }
  }

  double _screenSignedArea(
    List<Offset> points,
  ) {
    var area = 0.0;

    for (var index = 0;
        index < points.length;
        index++) {
      final nextIndex =
          (index + 1) % points.length;
      area += points[index].dx *
              points[nextIndex].dy -
          points[nextIndex].dx *
              points[index].dy;
    }

    return area / 2;
  }

  // ===========================================================================
  // COTAS DE PUERTAS Y VENTANAS
  // ===========================================================================

  void _drawOpeningDimensions(
    Canvas canvas,
    RoomModel room,
    Set<String> dimensionedFeatureIds,
  ) {
    if (room.points.length < 3 ||        room.features.isEmpty) {
      return;
    }

    final roomScreenPoints = room.points
        .map(transform)
        .toList(growable: false);
    final signedArea =
        _screenSignedArea(roomScreenPoints);

    if (signedArea.abs() < 0.000001) {
      return;
    }

    for (final feature in room.features) {
      if (!dimensionedFeatureIds.add(feature.id)) {
        continue;
      }

      final featureStart =
          transform(feature.start);
      final featureEnd =
          transform(feature.end);
      final featureDirection =
          featureEnd - featureStart;
      final featureScreenLength =
          featureDirection.distance;

      if (featureScreenLength < 8) {
        continue;
      }

      final midpoint = Offset(
        (featureStart.dx + featureEnd.dx) / 2,
        (featureStart.dy + featureEnd.dy) / 2,
      );
      final wallIndex = _nearestWallIndex(
        midpoint,
        roomScreenPoints,
      );

      if (wallIndex < 0) {
        continue;
      }

      final nextWallIndex =
          (wallIndex + 1) % roomScreenPoints.length;
      final wallDirection =
          roomScreenPoints[nextWallIndex] -
              roomScreenPoints[wallIndex];
      final wallScreenLength =
          wallDirection.distance;

      if (wallScreenLength < 0.000001) {
        continue;
      }

      final wallTangent =
          wallDirection / wallScreenLength;
      final outwardNormal = signedArea > 0
          ? Offset(
              wallTangent.dy,
              -wallTangent.dx,
            )
          : Offset(
              -wallTangent.dy,
              wallTangent.dx,
            );
      final inwardNormal = -outwardNormal;
      final featureTangent =
          featureDirection / featureScreenLength;
      const dimensionOffset = 14.0;
      const extensionEndOffset = 18.0;
      const endMarkHalfLength = 3.5;
      final dimensionStart =
          featureStart +
              inwardNormal * dimensionOffset;
      final dimensionEnd =
          featureEnd +
              inwardNormal * dimensionOffset;
      final color =
          feature.type == FeatureType.door
              ? const Color(0xFFE65100)
              : const Color(0xFFAA00CC);
      final dimensionPaint = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square;

      canvas.drawLine(
        featureStart,
        featureStart +
            inwardNormal * extensionEndOffset,
        dimensionPaint,
      );
      canvas.drawLine(
        featureEnd,
        featureEnd +
            inwardNormal * extensionEndOffset,
        dimensionPaint,
      );
      canvas.drawLine(
        dimensionStart,
        dimensionEnd,
        dimensionPaint,
      );
      canvas.drawLine(
        dimensionStart -
            inwardNormal * endMarkHalfLength,
        dimensionStart +
            inwardNormal * endMarkHalfLength,
        dimensionPaint,
      );
      canvas.drawLine(
        dimensionEnd -
            inwardNormal * endMarkHalfLength,
        dimensionEnd +
            inwardNormal * endMarkHalfLength,
        dimensionPaint,
      );

      final openingWidth =
          GeometryService.calculateDistance(
        feature.start,
        feature.end,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: formatLength(openingWidth),
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final center = Offset(
        (dimensionStart.dx + dimensionEnd.dx) / 2,
        (dimensionStart.dy + dimensionEnd.dy) / 2,
      );
      var angle = math.atan2(
        featureTangent.dy,
        featureTangent.dx,
      );

      if (angle > math.pi / 2 ||
          angle < -math.pi / 2) {
        angle += math.pi;
      }
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final backgroundRect = Rect.fromCenter(
        center: Offset.zero,
        width: textPainter.width + 7,
        height: textPainter.height + 4,
      );
      final backgroundPaint = Paint()
        ..color = Colors.white.withValues(
          alpha: 0.94,
        )
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          backgroundRect,
          const Radius.circular(4),
        ),
        backgroundPaint,
      );
      textPainter.paint(
        canvas,
        Offset(
          -textPainter.width / 2,
          -textPainter.height / 2,
        ),
      );
      canvas.restore();

      final wallStartPoint =
          room.points[wallIndex];
      final wallEndPoint =
          room.points[nextWallIndex];
      final wallDx =
          wallEndPoint.x - wallStartPoint.x;
      final wallDz =
          wallEndPoint.z - wallStartPoint.z;
      final wallLengthSquared =
          wallDx * wallDx + wallDz * wallDz;

      if (wallLengthSquared <= 0.000001) {
        continue;
      }

      double projectionFor(
        ARPoint point,
      ) {
        return (((point.x - wallStartPoint.x) *
                        wallDx +
                    (point.z - wallStartPoint.z) *
                        wallDz) /
                wallLengthSquared)
            .clamp(0.0, 1.0)
            .toDouble();
      }

      final firstProjection =
          projectionFor(feature.start);
      final secondProjection =
          projectionFor(feature.end);
      final openingStartProjection =
          math.min(
        firstProjection,
        secondProjection,
      );
      final openingEndProjection =
          math.max(
        firstProjection,
        secondProjection,
      );
      final wallLength =
          math.sqrt(wallLengthSquared);      final openingStartOnWall =
          roomScreenPoints[wallIndex] +
              wallDirection *
                  openingStartProjection;
      final openingEndOnWall =
          roomScreenPoints[wallIndex] +
              wallDirection *
                  openingEndProjection;

      _drawCornerDistanceDimension(
        canvas: canvas,
        start: roomScreenPoints[wallIndex],
        end: openingStartOnWall,
        tangent: wallTangent,
        inwardNormal: inwardNormal,
        distanceMeters:
            wallLength * openingStartProjection,
      );
      _drawCornerDistanceDimension(
        canvas: canvas,
        start: openingEndOnWall,
        end: roomScreenPoints[nextWallIndex],
        tangent: wallTangent,
        inwardNormal: inwardNormal,
        distanceMeters:
            wallLength *
                (1.0 - openingEndProjection),
      );
    }
  }

  void _drawCornerDistanceDimension({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Offset tangent,
    required Offset inwardNormal,
    required double distanceMeters,
  }) {
    final screenLength =
        (end - start).distance;

    if (distanceMeters < 0.005 ||
        screenLength < 24) {
      return;
    }

    const dimensionOffset = 30.0;
    const extensionEndOffset = 34.0;
    const endMarkHalfLength = 3.0;
    const color = Color(0xFF455A64);
    final dimensionStart =
        start + inwardNormal * dimensionOffset;
    final dimensionEnd =
        end + inwardNormal * dimensionOffset;
    final dimensionPaint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(
      start,
      start +
          inwardNormal * extensionEndOffset,
      dimensionPaint,
    );
    canvas.drawLine(
      end,
      end +
          inwardNormal * extensionEndOffset,
      dimensionPaint,
    );
    canvas.drawLine(
      dimensionStart,
      dimensionEnd,
      dimensionPaint,
    );
    canvas.drawLine(
      dimensionStart -
          inwardNormal * endMarkHalfLength,
      dimensionStart +
          inwardNormal * endMarkHalfLength,
      dimensionPaint,
    );
    canvas.drawLine(
      dimensionEnd -
          inwardNormal * endMarkHalfLength,
      dimensionEnd +
          inwardNormal * endMarkHalfLength,
      dimensionPaint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: formatLength(distanceMeters),
        style: const TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final center = Offset(
      (dimensionStart.dx + dimensionEnd.dx) / 2,
      (dimensionStart.dy + dimensionEnd.dy) / 2,
    );
    var angle = math.atan2(
      tangent.dy,
      tangent.dx,
    );

    if (angle > math.pi / 2 ||
        angle < -math.pi / 2) {
      angle += math.pi;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final backgroundRect = Rect.fromCenter(
      center: Offset.zero,
      width: textPainter.width + 6,
      height: textPainter.height + 3,
    );
    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: 0.94,
      )
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        backgroundRect,
        const Radius.circular(3),
      ),
      backgroundPaint,
    );
    textPainter.paint(
      canvas,
      Offset(
        -textPainter.width / 2,
        -textPainter.height / 2,
      ),
    );
    canvas.restore();
  }

  int _nearestWallIndex(
    Offset point,
    List<Offset> wallPoints,
  ) {
    var nearestIndex = -1;
    var nearestDistance = double.infinity;

    for (var index = 0;
        index < wallPoints.length;
        index++) {
      final nextIndex =
          (index + 1) % wallPoints.length;
      final distance = _distanceToSegment(
        point,
        wallPoints[index],
        wallPoints[nextIndex],
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    return nearestIndex;
  }

  double _distanceToSegment(
    Offset point,
    Offset start,
    Offset end,
  ) {
    final segment = end - start;
    final lengthSquared =
        segment.dx * segment.dx +
            segment.dy * segment.dy;

    if (lengthSquared <= 0.000001) {
      return (point - start).distance;
    }

    final fromStart = point - start;
    final projection =
        (fromStart.dx * segment.dx +
                fromStart.dy * segment.dy) /
            lengthSquared;
    final clampedProjection =        projection.clamp(0.0, 1.0).toDouble();
    final closest = Offset(
      start.dx + segment.dx * clampedProjection,
      start.dy + segment.dy * clampedProjection,
    );

    return (point - closest).distance;
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  void _drawFeatures(
    Canvas canvas,
    RoomModel room,
    Paint doorPaint,
    Paint windowPaint,
    Paint selectedPaint,
    Paint referencePaint,
    Map<String, String> featureOwnerRoomIds,
  ) {
    for (final feature
        in room.features) {
      if (featureOwnerRoomIds[feature.id] != room.id) {
        continue;
      }

      final start =
          transform(
        feature.start,
      );

      final end =
          transform(
        feature.end,
      );

      final isSelected =
          room.id == selectedRoomId &&
              feature.id == selectedFeatureId;

      if (isSelected) {
        canvas.drawLine(
          start,
          end,
          selectedPaint,
        );
      }

      switch (feature.type) {
        case FeatureType.door:
          _drawProfessionalDoor(
            canvas: canvas,
            feature: feature,
            start: start,
            end: end,
            paint: doorPaint,
          );
          break;

        case FeatureType.window:
          _drawProfessionalWindow(
            canvas: canvas,
            start: start,
            end: end,
            paint: windowPaint,          );
          break;
      }

      if (!feature.isConnected) {
        _drawContinuationPoint(
          canvas,
          start,
          referencePaint,
          selected: isSelected,
        );
      }
    }
  }

  void _drawProfessionalDoor({
    required Canvas canvas,
    required WallFeature feature,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final leftNormal = Offset(-tangent.dy, tangent.dx);
    final swingNormal =
        feature.doorSwingSide == DoorSwingSide.left
            ? leftNormal
            : -leftNormal;
    final hinge = feature.doorHingeSide == DoorHingeSide.start
        ? start
        : end;
    final latch = feature.doorHingeSide == DoorHingeSide.start
        ? end
        : start;
    final closedDirection = (latch - hinge) / width;
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final leafEnd = hinge + swingNormal * width;

    // Interrumpe gráficamente la pared en el ancho real de la puerta.
    canvas.drawLine(start, end, erasePaint);

    // Hoja abierta a 90 grados según la orientación elegida.
    canvas.drawLine(hinge, leafEnd, symbolPaint);
    canvas.drawCircle(
      hinge,
      2.5,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );

    final startAngle = math.atan2(
      closedDirection.dy,
      closedDirection.dx,
    );
    final inwardAngle = math.atan2(
      swingNormal.dy,
      swingNormal.dx,
    );
    final sweepAngle = _shortestSweep(
      startAngle,
      inwardAngle,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: hinge,
        radius: width,
      ),
      startAngle,
      sweepAngle,
      false,
      symbolPaint,
    );
  }

  void _drawProfessionalWindow({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint paint,
  }) {
    final opening = end - start;
    final width = opening.distance;

    if (width <= 0.000001) {
      return;
    }

    final tangent = opening / width;
    final normal = Offset(-tangent.dy, tangent.dx);
    final erasePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final symbolPaint = Paint()
      ..color = paint.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const railOffset = 2.5;

    canvas.drawLine(start, end, erasePaint);
    canvas.drawLine(
      start + normal * railOffset,
      end + normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(
      start - normal * railOffset,
      end - normal * railOffset,
      symbolPaint,
    );
    canvas.drawLine(
      start - normal * 5,
      start + normal * 5,
      symbolPaint,
    );
    canvas.drawLine(
      end - normal * 5,
      end + normal * 5,
      symbolPaint,
    );
  }

  double _shortestSweep(
    double startAngle,
    double endAngle,
  ) {
    var sweep = endAngle - startAngle;

    while (sweep > math.pi) {
      sweep -= math.pi * 2;
    }

    while (sweep < -math.pi) {
      sweep += math.pi * 2;
    }

    return sweep;
  }

  void _drawContinuationPoint(
    Canvas canvas,
    Offset point,
    Paint referencePaint, {
    required bool selected,
  }) {
    canvas.drawCircle(
      point,
      selected ? 10 : 8,
      referencePaint,
    );

    canvas.drawCircle(
      point,
      selected ? 4 : 3,
      Paint()..color = Colors.white,
    );
  }

  // ===========================================================================
  // REPAINT
  // ===========================================================================

  @override
  bool shouldRepaint(
    covariant FloorPlanPainter
        oldDelegate,
  ) {
    return true;
  }
}