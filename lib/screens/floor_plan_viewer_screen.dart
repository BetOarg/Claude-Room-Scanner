import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../services/geometry_service.dart';
import '../services/import_export_service.dart';
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

  // ===========================================================================
  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<void>
      _openMeasurementEditor({
    String? roomId,
  }) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MeasurementEditorScreen(
          roomId: roomId,
        ),
      ),
    );
  }

  // ===========================================================================
  // ORGANIZACIÓN AUTOMÁTICA
  // ===========================================================================

  Future<void> _organizeRooms() async {
    final provider =
        context.read<
            FloorPlanProvider>();

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
                  true,
                );
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

  @override
  Widget build(
    BuildContext context,
  ) {
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
                        final planePoint =
                            _inverseTransform(
                          details
                              .localPosition,
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
                          vertical: 8,
                        ),
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
                          '${provider.totalProjectArea.toStringAsFixed(2)} m²',
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
  // ===========================================================================

  Future<void>
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
                  'Seleccioná el elemento '
                  'que querés incorporar.',
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
                    FeatureType.door,
                  );
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
            _RoomListAction>(
      context: context,
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

            return SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  16,
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
                          },
                          icon: const Icon(
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

                            final summary =
                                provider
                                    .roomSummaries[
                                  index
                                ];

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
                                '${summary['area']} m²'
                                ' · '
                                '${summary['perimeter']} m perímetro'
                                ' · '
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
            TextButton(
              onPressed: () {
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
          content: Text(
            message,
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

class _EmptyPlanView extends StatelessWidget {
  const _EmptyPlanView();

  @override
  Widget build(
    BuildContext context,
  ) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
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
              'Completá un escaneo para visualizar '
              'el plano general.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
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
// PAINTER
// =============================================================================

class FloorPlanPainter
    extends CustomPainter {
  final List<RoomModel> rooms;

  final Offset Function(
    ARPoint,
  ) transform;

  const FloorPlanPainter({
    required this.rooms,
    required this.transform,
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
                '\n${area.toStringAsFixed(2)} m²',
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

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  void _drawFeatures(
    Canvas canvas,
    RoomModel room,
    Paint doorPaint,
    Paint windowPaint,
  ) {
    for (final feature
        in room.features) {
      final start =
          transform(
        feature.start,
      );

      final end =
          transform(
        feature.end,
      );

      switch (feature.type) {
        case FeatureType.door:
          canvas.drawLine(
            start,
            end,
            doorPaint,
          );
          break;

        case FeatureType.window:
          canvas.drawLine(
            start,
            end,
            windowPaint,
          );
          break;
      }
    }
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