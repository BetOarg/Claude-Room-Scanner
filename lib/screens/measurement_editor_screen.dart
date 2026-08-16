import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';

class MeasurementEditorScreen
    extends StatefulWidget {
  final String? roomId;

  const MeasurementEditorScreen({
    super.key,
    this.roomId,
  });

  @override
  State<MeasurementEditorScreen>
      createState() =>
          _MeasurementEditorScreenState();
}

class _MeasurementEditorScreenState
    extends State<
        MeasurementEditorScreen> {
  int? _selectedRoomIndex;

  @override
  Widget build(
    BuildContext context,
  ) {
    final provider =
        context.watch<
            FloorPlanProvider>();

    final rooms =
        provider.completedRooms;

    if (rooms.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Editar medidas',
          ),
        ),
        body: const Center(
          child: Padding(
            padding:
                EdgeInsets.all(24),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .straighten_outlined,
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'No hay ambientes para editar.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedIndex =
        _resolveSelectedIndex(
      rooms,
    );

    final selectedRoom =
        rooms[selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Editar medidas',
        ),
      ),
      body: Column(
        children: [
          _buildRoomSelector(
            rooms,
            selectedIndex,
          ),
          Expanded(
            child:
                _buildRoomEditor(
              selectedRoom,
              provider,
              selectedIndex,
            ),
          ),
        ],
      ),
    );
  }

  int _resolveSelectedIndex(
    List<RoomModel> rooms,
  ) {
    if (_selectedRoomIndex !=
            null &&
        _selectedRoomIndex! >=
            0 &&
        _selectedRoomIndex! <
            rooms.length) {
      return _selectedRoomIndex!;
    }

    if (widget.roomId != null) {
      final index =
          rooms.indexWhere(
        (room) =>
            room.id ==
            widget.roomId,
      );

      if (index >= 0) {
        _selectedRoomIndex =
            index;

        return index;
      }
    }

    _selectedRoomIndex = 0;

    return 0;
  }

  Widget _buildRoomSelector(
    List<RoomModel> rooms,
    int selectedIndex,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        14,
        16,
        12,
      ),
      child:
          DropdownButtonFormField<int>(
        value: selectedIndex,
        isExpanded: true,
        decoration:
            const InputDecoration(
          labelText: 'Ambiente',
          prefixIcon: Icon(
            Icons.home_outlined,
          ),
          border:
              OutlineInputBorder(),
        ),
        items: List.generate(
          rooms.length,
          (index) {
            final room =
                rooms[index];

            return DropdownMenuItem<
                int>(
              value: index,
              child: Text(
                '${index + 1}. ${room.name}',
                overflow:
                    TextOverflow.ellipsis,
              ),
            );
          },
        ),
        onChanged: (value) {
          if (value == null ||
              value < 0 ||
              value >=
                  rooms.length) {
            return;
          }

          setState(() {
            _selectedRoomIndex =
                value;
          });
        },
      ),
    );
  }

  Widget _buildRoomEditor(
    RoomModel room,
    FloorPlanProvider provider,
    int roomIndex,
  ) {
    final area =
        _calculateArea(room);

    final perimeter =
        _calculatePerimeter(
      room,
      provider,
    );

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        32,
      ),
      children: [
        _buildSummaryCard(
          room,
          area,
          perimeter,
        ),
        const SizedBox(
          height: 16,
        ),
        const Text(
          'Paredes',
          style: TextStyle(
            fontSize: 20,
            fontWeight:
                FontWeight.bold,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        const Text(
          'Seleccioná una pared para corregir su longitud. '
          'La dirección se conserva automáticamente.',
          style: TextStyle(
            color:
                Colors.black54,
            height: 1.3,
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        ...List.generate(
          room.points.length,
          (wallIndex) =>
              _buildWallCard(
            room,
            provider,
            roomIndex,
            wallIndex,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    RoomModel room,
    double area,
    double perimeter,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Row(
          children: [
            Expanded(
              child: _metric(
                Icons.square_foot,
                'Superficie',
                '${area.toStringAsFixed(2)} m²',
              ),
            ),
            Container(
              width: 1,
              height: 48,
              color:
                  Colors.black12,
            ),
            Expanded(
              child: _metric(
                Icons.timeline,
                'Perímetro',
                '${perimeter.toStringAsFixed(2)} m',
              ),
            ),
            Container(
              width: 1,
              height: 48,
              color:
                  Colors.black12,
            ),
            Expanded(
              child: _metric(
                Icons.polyline,
                'Esquinas',
                '${room.points.length}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          size: 22,
        ),
        const SizedBox(
          height: 6,
        ),
        Text(
          value,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(
          label,
          style:
              const TextStyle(
            color:
                Colors.black54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildWallCard(
    RoomModel room,
    FloorPlanProvider provider,
    int roomIndex,
    int wallIndex,
  ) {
    final length =
        provider.wallLength(
      room,
      wallIndex,
    );

    final startIndex =
        wallIndex + 1;

    final endIndex =
        ((wallIndex + 1) %
                room.points.length) +
            1;

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        leading:
            CircleAvatar(
          child: Text(
            '${wallIndex + 1}',
          ),
        ),
        title: Text(
          'Pared ${wallIndex + 1}',
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Esquina $startIndex → Esquina $endIndex',
        ),
        trailing: Row(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              '${length.toStringAsFixed(2)} m',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons
                    .edit_outlined,
              ),
              onPressed: () =>
                  _editWallLength(
                room,
                provider,
                roomIndex,
                wallIndex,
                length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editWallLength(
    RoomModel room,
    FloorPlanProvider provider,
    int roomIndex,
    int wallIndex,
    double currentLength,
  ) async {
    final controller =
        TextEditingController(
      text:
          currentLength
              .toStringAsFixed(2),
    );

    String? error;

    final newLength =
        await showDialog<double>(
      context: context,
      barrierDismissible:
          false,
      builder:
          (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                'Editar pared ${wallIndex + 1}',
              ),
              content: TextField(
                controller:
                    controller,
                autofocus: true,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    InputDecoration(
                  labelText:
                      'Nueva longitud',
                  suffixText:
                      'metros',
                  errorText:
                      error,
                  prefixIcon:
                      const Icon(
                    Icons.straighten,
                  ),
                  border:
                      const OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                    dialogContext,
                  ),
                  child:
                      const Text(
                    'Cancelar',
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final value =
                        _parseNumber(
                      controller
                          .text,
                    );

                    if (value ==
                            null ||
                        value <=
                            0) {
                      setDialogState(
                        () {
                          error =
                              'Ingresá una longitud válida mayor a 0.';
                        },
                      );

                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      value,
                    );
                  },
                  child:
                      const Text(
                    'Guardar',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (newLength ==
            null ||
        !mounted) {
      return;
    }

    final result =
        await provider
            .updateWallLength(
      roomId: room.id,
      roomIndex:
          roomIndex,
      wallIndex:
          wallIndex,
      lengthMeters:
          newLength,
    );

    if (!mounted) {
      return;
    }

    if (!result.isValid) {
      _showMessage(
        result.errorMessage ??
            'La nueva medida no es válida.',
        error: true,
      );

      return;
    }

    _showMessage(
      result.warningMessage ??
          'Medida actualizada.',
    );
  }

  double _calculateArea(
    RoomModel room,
  ) {
    if (room.points.length <
        3) {
      return 0.0;
    }

    double area = 0.0;

    for (int i = 0;
        i < room.points.length;
        i++) {
      final next =
          (i + 1) %
              room.points.length;

      area +=
          room.points[i].x *
                  room.points[next]
                      .z -
              room.points[next].x *
                  room.points[i].z;
    }

    return area.abs() / 2.0;
  }

  double _calculatePerimeter(
    RoomModel room,
    FloorPlanProvider provider,
  ) {
    double result = 0.0;

    for (int i = 0;
        i < room.points.length;
        i++) {
      result +=
          provider.wallLength(
        room,
        i,
      );
    }

    return result;
  }

  double? _parseNumber(
    String value,
  ) {
    final normalized =
        value
            .trim()
            .replaceAll(
              'm²',
              '',
            )
            .replaceAll(
              'm',
              '',
            )
            .replaceAll(
              ',',
              '.',
            )
            .trim();

    return double.tryParse(
      normalized,
    );
  }

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(
      context,
    )
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior
                  .floating,
          backgroundColor:
              error
                  ? Colors.red
                      .shade800
                  : Colors.green
                      .shade700,
          content:
              Text(message),
        ),
      );
  }
}