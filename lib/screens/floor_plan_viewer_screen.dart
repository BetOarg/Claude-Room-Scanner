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

  Offset _transformPoint(
    ARPoint p,
  ) {
    final x =
        _padding +
        (p.x - _minX) * _scale;

    final z =
        _padding +
        (p.z - _minZ) * _scale;

    return Offset(x, z);
  }

  ARPoint _inverseTransform(
    Offset screenPos,
  ) {
    final x =
        (screenPos.dx - _padding) /
                _scale +
            _minX;

    final z =
        (screenPos.dy - _padding) /
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

    double minX =
        double.infinity;

    double maxX =
        double.negativeInfinity;

    double minZ =
        double.infinity;

    double maxZ =
        double.negativeInfinity;

    for (final room in rooms) {
      for (final point in room.points) {
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

    _minX = minX;
    _minZ = minZ;

    _padding =
        screenSize.width * 0.1;

    final contentWidth =
        (maxX - minX) == 0
            ? 1.0
            : (maxX - minX);

    final contentHeight =
        (maxZ - minZ) == 0
            ? 1.0
            : (maxZ - minZ);

    final widthScale =
        (screenSize.width -
                2 * _padding) /
            contentWidth;

    final heightScale =
        (screenSize.height -
                2 * _padding) /
            contentHeight;

    _scale = widthScale
        .clamp(
          0.0,
          heightScale,
        );
  }

  String? _getRoomAtPosition(
    ARPoint point,
    List<RoomModel> rooms,
  ) {
    for (final room in rooms) {
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

  // ---------------------------------------------------------------------------
  // EDITOR DE MEDIDAS
  // ---------------------------------------------------------------------------

  Future<void> _openMeasurementEditor({
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
          // -----------------------------------------------------------------
          // EDITAR MEDIDAS
          // -----------------------------------------------------------------
          IconButton(
            icon: const Icon(
              Icons.straighten_outlined,
            ),
            tooltip:
                'Editar medidas',
            onPressed: () =>
                _openMeasurementEditor(),
          ),

          // -----------------------------------------------------------------
          // IMPORTAR
          // -----------------------------------------------------------------
          IconButton(
            icon: const Icon(
              Icons.file_upload,
            ),
            tooltip:
                'Importar Plano',
            onPressed: () async {
              final provider =
                  context.read<
                      FloorPlanProvider>();

              final success =
                  await ImportExportService
                      .importFromJson(
                provider,
              );

              if (!context.mounted) {
                return;
              }

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Plano importado con éxito'
                        : 'Error o importación cancelada',
                  ),
                  backgroundColor:
                      success
                          ? Colors.green
                          : Colors.orange,
                ),
              );
            },
          ),

          // -----------------------------------------------------------------
          // COMPARTIR JSON
          // -----------------------------------------------------------------
          IconButton(
            icon: const Icon(
              Icons.share,
            ),
            tooltip:
                'Compartir JSON',
            onPressed: () async {
              final provider =
                  context.read<
                      FloorPlanProvider>();

              await ImportExportService
                  .exportToJson(
                provider.completedRooms,
                provider.projectName,
              );
            },
          ),

          // -----------------------------------------------------------------
          // EXPORTAR PDF
          // -----------------------------------------------------------------
          IconButton(
            icon: const Icon(
              Icons.picture_as_pdf,
            ),
            tooltip:
                'Exportar PDF',
            onPressed: () async {
              final provider =
                  context.read<
                      FloorPlanProvider>();

              await ImportExportService
                  .exportToPdf(
                provider.completedRooms,
                provider.projectName,
              );
            },
          ),
        ],
      ),

      // ---------------------------------------------------------------------
      // LISTA DE AMBIENTES
      // ---------------------------------------------------------------------
      floatingActionButton:
          FloatingActionButton(
        tooltip:
            'Ambientes registrados',
        onPressed: () =>
            _showRoomListDialog(
          context,
        ),
        child: const Icon(
          Icons.edit_note,
        ),
      ),

      // ---------------------------------------------------------------------
      // PLANO
      // ---------------------------------------------------------------------
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
            return const Center(
              child: Text(
                'No hay ambientes escaneados aún.',
              ),
            );
          }

          return LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              _calculateTransform(
                constraints.biggest,
                rooms,
              );

              return InteractiveViewer(
                boundaryMargin:
                    const EdgeInsets.all(
                  100,
                ),
                minScale: 0.1,
                maxScale: 4.0,
                child: GestureDetector(
                  onTapUp: (
                    details,
                  ) {
                    final localOffset =
                        details.localPosition;

                    final planePoint =
                        _inverseTransform(
                      localOffset,
                    );

                    final roomId =
                        _getRoomAtPosition(
                      planePoint,
                      rooms,
                    );

                    if (roomId != null) {
                      _showAddFeatureMenu(
                        context,
                        roomId,
                        planePoint,
                      );
                    } else {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Toca dentro de un ambiente para añadir puertas o ventanas',
                          ),
                          duration:
                              Duration(
                            seconds: 2,
                          ),
                        ),
                      );
                    }
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter:
                        FloorPlanPainter(
                      rooms: rooms,
                      transform:
                          _transformPoint,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PUERTAS / VENTANAS
  // ---------------------------------------------------------------------------

  void _showAddFeatureMenu(
    BuildContext context,
    String roomId,
    ARPoint location,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Agregar elemento a esta habitación',
              ),
              leading: Icon(
                Icons.add_location_alt,
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.door_front_door,
                color: Colors.red,
              ),
              title: const Text(
                'Puerta',
              ),
              onTap: () {
                Navigator.pop(
                  context,
                );

                final endPoint =
                    ARPoint(
                  x: location.x + 0.8,
                  y: location.y,
                  z: location.z,
                );

                context
                    .read<
                        FloorPlanProvider>()
                    .addFeatureToRoom(
                      roomId,
                      FeatureType.door,
                      location,
                      endPoint,
                    );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.window,
                color: Colors.blue,
              ),
              title: const Text(
                'Ventana',
              ),
              onTap: () {
                Navigator.pop(
                  context,
                );

                final endPoint =
                    ARPoint(
                  x: location.x + 1.0,
                  y: location.y,
                  z: location.z,
                );

                context
                    .read<
                        FloorPlanProvider>()
                    .addFeatureToRoom(
                      roomId,
                      FeatureType.window,
                      location,
                      endPoint,
                    );
              },
            ),
            const SizedBox(
              height: 8,
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // LISTA DE AMBIENTES
  // ---------------------------------------------------------------------------

  void _showRoomListDialog(
    BuildContext context,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Consumer<
            FloorPlanProvider>(
          builder: (
            context,
            provider,
            child,
          ) {
            return Padding(
              padding:
                  const EdgeInsets.all(
                16.0,
              ),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ambientes registrados',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  if (provider
                      .completedRooms
                      .isEmpty)
                    const Center(
                      child: Text(
                        'No hay ambientes aún.',
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics:
                          const NeverScrollableScrollPhysics(),
                      itemCount: provider
                          .completedRooms
                          .length,
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final room =
                            provider
                                .completedRooms[
                          index
                        ];

                        final summary =
                            provider
                                .roomSummaries[
                          index
                        ];

                        return ListTile(
                          leading:
                              const Icon(
                            Icons.house,
                          ),
                          title: Text(
                            room.name,
                          ),
                          subtitle:
                              Text(
                            'Área: ${summary['area']} m² · ${room.points.length} pts · ${room.features.length} elementos',
                          ),
                          trailing:
                              Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip:
                                    'Editar medidas',
                                icon:
                                    const Icon(
                                  Icons
                                      .straighten_outlined,
                                ),
                                onPressed:
                                    () {
                                  Navigator.pop(
                                    context,
                                  );

                                  _openMeasurementEditor(
                                    roomId:
                                        room.id,
                                  );
                                },
                              ),
                              IconButton(
                                tooltip:
                                    'Renombrar',
                                icon:
                                    const Icon(
                                  Icons.edit,
                                ),
                                onPressed:
                                    () =>
                                        _editRoomName(
                                  context,
                                  room,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(
                    height: 16,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RENOMBRAR AMBIENTE
  // ---------------------------------------------------------------------------

  Future<void> _editRoomName(
    BuildContext context,
    RoomModel room,
  ) async {
    final controller =
        TextEditingController(
      text: room.name,
    );

    await showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
        title: const Text(
          'Renombrar Ambiente',
        ),
        content: TextField(
          controller:
              controller,
          autofocus: true,
          decoration:
              const InputDecoration(
            hintText:
                'Nuevo nombre',
            border:
                OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
            ),
            child: const Text(
              'Cancelar',
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final newName =
                  controller.text
                      .trim();

              if (newName
                  .isNotEmpty) {
                context
                    .read<
                        FloorPlanProvider>()
                    .updateRoomName(
                      room.id,
                      newName,
                    );
              }

              Navigator.pop(
                context,
              );
            },
            child: const Text(
              'Guardar',
            ),
          ),
        ],
      ),
    );

    controller.dispose();
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
              Colors.blueAccent
          ..strokeWidth = 3.0
          ..style =
              PaintingStyle.stroke;

    final roomFill =
        Paint()
          ..color = Colors
              .blueAccent
              .withOpacity(
            0.1,
          )
          ..style =
              PaintingStyle.fill;

    final doorPaint =
        Paint()
          ..color = Colors.red
          ..strokeWidth = 4.0
          ..style =
              PaintingStyle.stroke;

    final windowPaint =
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 4.0
          ..style =
              PaintingStyle.stroke;

    for (final room
        in rooms) {
      if (room.points.length >=
          2) {
        final path =
            Path();

        final start =
            transform(
          room.points.first,
        );

        path.moveTo(
          start.dx,
          start.dy,
        );

        for (
          var i = 1;
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

        path.close();

        canvas.drawPath(
          path,
          roomFill,
        );

        canvas.drawPath(
          path,
          wallPaint,
        );
      }

      // -----------------------------------------------------------------------
      // NOMBRE DEL AMBIENTE
      // -----------------------------------------------------------------------

      if (room.points.isNotEmpty) {
        final labelPos =
            transform(
          room.points.first,
        );

        final textSpan =
            TextSpan(
          text: room.name,
          style:
              const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight:
                FontWeight.bold,
          ),
        );

        final textPainter =
            TextPainter(
          text: textSpan,
          textDirection:
              TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          labelPos +
              const Offset(
                5,
                5,
              ),
        );
      }

      // -----------------------------------------------------------------------
      // PUERTAS / VENTANAS
      // -----------------------------------------------------------------------

      for (final feature
          in room.features) {
        final pStart =
            transform(
          feature.start,
        );

        final pEnd =
            transform(
          feature.end,
        );

        if (feature.type ==
            FeatureType.door) {
          canvas.drawLine(
            pStart,
            pEnd,
            doorPaint,
          );
        } else {
          canvas.drawLine(
            pStart,
            pEnd,
            windowPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return true;
  }
}