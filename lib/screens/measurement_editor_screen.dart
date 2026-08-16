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
  int? _selectedRoomIndex;

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<FloorPlanProvider>();

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
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten_outlined,
                  size: 64,
                  color: Colors.black38,
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
                SizedBox(height: 8),
                Text(
                  'Primero completá y guardá un ambiente desde el Scanner.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    color:
                        Colors.black54,
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
            child: _buildRoomEditor(
              selectedRoom,
              provider,
              selectedIndex,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SELECCIÓN DE AMBIENTE
  // ===========================================================================

  int _resolveSelectedIndex(
    List<RoomModel> rooms,
  ) {
    final current =
        _selectedRoomIndex;

    if (current != null &&
        current >= 0 &&
        current < rooms.length) {
      return current;
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
        key: ValueKey(
          'room-selector-'
          '${rooms.length}-'
          '$selectedIndex',
        ),
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

            return DropdownMenuItem<int>(
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
              value >= rooms.length) {
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

  // ===========================================================================
  // EDITOR
  // ===========================================================================

  Widget _buildRoomEditor(
    RoomModel room,
    FloorPlanProvider provider,
    int roomIndex,
  ) {
    final area =
        _calculateArea(
      room,
    );

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
          'La dirección actual de la pared se conserva automáticamente.',
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
          (wallIndex) {
            return _buildWallCard(
              room,
              provider,
              roomIndex,
              wallIndex,
            );
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // RESUMEN
  // ===========================================================================

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
        const SizedBox(
          height: 2,
        ),
        Text(
          label,
          textAlign:
              TextAlign.center,
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

  // ===========================================================================
  // PAREDES
  // ===========================================================================

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
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        leading: CircleAvatar(
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
          'Esquina $startIndex → '
          'Esquina $endIndex',
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
                fontSize: 15,
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            IconButton(
              tooltip:
                  'Editar medida',
              icon: const Icon(
                Icons.edit_outlined,
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

  // ===========================================================================
  // EDITAR LONGITUD
  // ===========================================================================

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
                'Editar pared '
                '${wallIndex + 1}',
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'Medida actual: '
                      '${currentLength.toStringAsFixed(2)} m',
                      style:
                          const TextStyle(
                        color:
                            Colors.black54,
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    TextField(
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
                        hintText:
                            'Ejemplo: 3,25',
                        suffixText:
                            'm',
                        errorText:
                            error,
                        prefixIcon:
                            const Icon(
                          Icons.straighten,
                        ),
                        border:
                            const OutlineInputBorder(),
                      ),
                      onSubmitted:
                          (_) {
                        _validateAndCloseDialog(
                          dialogContext:
                              dialogContext,
                          controller:
                              controller,
                          setDialogState:
                              setDialogState,
                          setError:
                              (message) {
                            error =
                                message;
                          },
                        );
                      },
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'La nueva medida modifica la geometría real '
                      'del ambiente. El plano será validado antes '
                      'de guardar el cambio.',
                      style:
                          TextStyle(
                        color:
                            Colors.black54,
                        fontSize: 12,
                        height: 1.35,
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
                    _validateAndCloseDialog(
                      dialogContext:
                          dialogContext,
                      controller:
                          controller,
                      setDialogState:
                          setDialogState,
                      setError:
                          (message) {
                        error =
                            message;
                      },
                    );
                  },
                  icon: const Icon(
                    Icons.check,
                  ),
                  label: const Text(
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

    if (newLength == null ||
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
          'Medida actualizada correctamente.',
    );
  }

  void _validateAndCloseDialog({
    required BuildContext dialogContext,
    required TextEditingController controller,
    required StateSetter setDialogState,
    required void Function(String?)
        setError,
  }) {
    final value =
        _parseNumber(
      controller.text,
    );

    if (value == null) {
      setDialogState(() {
        setError(
          'Ingresá un número válido.',
        );
      });

      return;
    }

    if (!value.isFinite ||
        value <= 0) {
      setDialogState(() {
        setError(
          'La longitud debe ser mayor que 0.',
        );
      });

      return;
    }

    setDialogState(() {
      setError(null);
    });

    Navigator.pop(
      dialogContext,
      value,
    );
  }

  // ===========================================================================
  // CÁLCULOS
  // ===========================================================================

  double _calculateArea(
    RoomModel room,
  ) {
    if (room.points.length < 3) {
      return 0.0;
    }

    double area = 0.0;

    for (
      int i = 0;
      i < room.points.length;
      i++
    ) {
      final next =
          (i + 1) %
              room.points.length;

      area +=
          room.points[i].x *
                  room.points[next].z -
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

    for (
      int i = 0;
      i < room.points.length;
      i++
    ) {
      result +=
          provider.wallLength(
        room,
        i,
      );
    }

    return result;
  }

  // ===========================================================================
  // PARSEO
  // ===========================================================================

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
      'm²',
      '',
    );

    normalized =
        normalized.replaceAll(
      'm',
      '',
    );

    normalized =
        normalized.replaceAll(
      ',',
      '.',
    );

    normalized =
        normalized.trim();

    return double.tryParse(
      normalized,
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
                  ? Colors.red.shade800
                  : Colors.green.shade700,
          duration:
              Duration(
            seconds:
                error ? 4 : 2,
          ),
          content: Row(
            children: [
              Icon(
                error
                    ? Icons
                        .warning_amber_rounded
                    : Icons
                        .check_circle_outline,
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
}