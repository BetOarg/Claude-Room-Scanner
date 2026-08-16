import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';

class MeasurementEditorScreen extends StatefulWidget {
  final String? roomId;

  const MeasurementEditorScreen({
    super.key,
    this.roomId,
  });

  @override
  State<MeasurementEditorScreen> createState() =>
      _MeasurementEditorScreenState();
}

class _MeasurementEditorScreenState
    extends State<MeasurementEditorScreen> {
  String? _selectedRoomId;

  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.roomId;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FloorPlanProvider>();
    final rooms = provider.completedRooms;

    if (rooms.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Editar medidas'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten_outlined,
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'No hay ambientes para editar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Primero completá y guardá un ambiente desde el Scanner.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedRoom = _resolveSelectedRoom(rooms);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar medidas'),
      ),
      body: Column(
        children: [
          _buildRoomSelector(
            rooms,
            selectedRoom,
          ),
          if (selectedRoom != null)
            Expanded(
              child: _buildRoomEditor(
                selectedRoom,
                provider,
              ),
            ),
        ],
      ),
    );
  }

  RoomModel? _resolveSelectedRoom(
    List<RoomModel> rooms,
  ) {
    if (_selectedRoomId != null) {
      for (final room in rooms) {
        if (room.id == _selectedRoomId) {
          return room;
        }
      }
    }

    _selectedRoomId = rooms.first.id;

    return rooms.first;
  }

  Widget _buildRoomSelector(
    List<RoomModel> rooms,
    RoomModel? selectedRoom,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        16,
        14,
        16,
        12,
      ),
      child: DropdownButtonFormField<String>(
        value: selectedRoom?.id,
        decoration: const InputDecoration(
          labelText: 'Ambiente',
          prefixIcon: Icon(
            Icons.home_outlined,
          ),
          border: OutlineInputBorder(),
        ),
        items: rooms.map((room) {
          return DropdownMenuItem<String>(
            value: room.id,
            child: Text(
              room.name,
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value == null) {
            return;
          }

          setState(() {
            _selectedRoomId = value;
          });
        },
      ),
    );
  }

  Widget _buildRoomEditor(
    RoomModel room,
    FloorPlanProvider provider,
  ) {
    final area = _calculateArea(room);

    final perimeter = _calculatePerimeter(
      room,
      provider,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
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
        const SizedBox(height: 16),
        const Text(
          'Paredes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Seleccioná una pared para corregir su longitud. La dirección de la pared se conserva automáticamente.',
          style: TextStyle(
            color: Colors.black54,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          room.points.length,
          (index) {
            return _buildWallCard(
              room,
              provider,
              index,
            );
          },
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
        padding: const EdgeInsets.all(16),
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
              color: Colors.black12,
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
              color: Colors.black12,
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
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildWallCard(
    RoomModel room,
    FloorPlanProvider provider,
    int wallIndex,
  ) {
    final length = provider.wallLength(
      room,
      wallIndex,
    );

    final startIndex = wallIndex + 1;

    final endIndex =
        ((wallIndex + 1) % room.points.length) + 1;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: CircleAvatar(
          child: Text(
            '${wallIndex + 1}',
          ),
        ),
        title: Text(
          'Pared ${wallIndex + 1}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Esquina $startIndex → Esquina $endIndex',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${length.toStringAsFixed(2)} m',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Editar medida',
              icon: const Icon(
                Icons.edit_outlined,
              ),
              onPressed: () => _editWallLength(
                room,
                provider,
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
    int wallIndex,
    double currentLength,
  ) async {
    final controller = TextEditingController(
      text: currentLength.toStringAsFixed(2),
    );

    String? error;

    final newLength = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: Text(
                'Editar pared ${wallIndex + 1}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medida actual: '
                      '${currentLength.toStringAsFixed(2)} m',
                      style: const TextStyle(
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Nueva longitud',
                        hintText: 'Ejemplo: 3,25',
                        suffixText: 'metros',
                        prefixIcon: const Icon(
                          Icons.straighten,
                        ),
                        errorText: error,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'La dirección de esta pared se mantiene. '
                      'Solo se modifica su longitud.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.3,
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
                  child: const Text(
                    'Cancelar',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final value =
                        _parseNumber(
                      controller.text,
                    );

                    if (value == null ||
                        value <= 0) {
                      setDialogState(() {
                        error =
                            'Ingresá una longitud válida mayor a 0.';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      value,
                    );
                  },
                  icon: const Icon(
                    Icons.check,
                  ),
                  label: const Text(
                    'Continuar',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (newLength == null ||
        !mounted) {
      return;
    }

    final result =
        await provider.updateWallLength(
      roomId: room.id,
      wallIndex: wallIndex,
      lengthMeters: newLength,
    );

    if (!mounted) {
      return;
    }

    if (!result.isValid) {
      _showError(
        result.errorMessage ??
            'La nueva medida no es válida.',
      );
      return;
    }

    _showSuccess(
      result.warningMessage ??
          'Medida actualizada.',
    );
  }

  double _calculateArea(
    RoomModel room,
  ) {
    final points = room.points;

    if (points.length < 3) {
      return 0.0;
    }

    double area = 0.0;

    for (int i = 0;
        i < points.length;
        i++) {
      final next =
          (i + 1) % points.length;

      area +=
          points[i].x *
                  points[next].z -
              points[next].x *
                  points[i].z;
    }

    return area.abs() / 2.0;
  }

  double _calculatePerimeter(
    RoomModel room,
    FloorPlanProvider provider,
  ) {
    double total = 0.0;

    for (int i = 0;
        i < room.points.length;
        i++) {
      total += provider.wallLength(
        room,
        i,
      );
    }

    return total;
  }

  double? _parseNumber(
    String value,
  ) {
    var normalized = value.trim();

    normalized = normalized.replaceAll(
      'm²',
      '',
    );

    normalized = normalized.replaceAll(
      'm',
      '',
    );

    normalized = normalized.replaceAll(
      ',',
      '.',
    );

    normalized = normalized.trim();

    return double.tryParse(
      normalized,
    );
  }

  void _showError(
    String message,
  ) {
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
              const SizedBox(width: 10),
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

  void _showSuccess(
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              Colors.green.shade700,
          duration:
              const Duration(
            seconds: 2,
          ),
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
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
}