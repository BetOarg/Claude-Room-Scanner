import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import '../utils/scan_validator.dart';

/// Estado de la sesión de escaneo activa.
///
/// Mantiene la habitación en curso y las habitaciones cerradas durante
/// la sesión. Cada punto nuevo se valida antes de incorporarse.
class ScannerProvider extends ChangeNotifier {
  final List<RoomModel> _rooms = [];

  RoomModel? _currentRoom;
  RoomType _selectedType = RoomType.living;
  bool _isTrackingOk = false;

  /// Último identificador generado.
  ///
  /// Permite garantizar IDs monotónicos incluso si se crean dos entidades
  /// dentro del mismo microsegundo.
  static int _lastGeneratedId = 0;

  List<RoomModel> get rooms => List.unmodifiable(_rooms);

  RoomModel? get currentRoom => _currentRoom;

  RoomType get selectedType => _selectedType;

  bool get isTrackingOk => _isTrackingOk;

  int get currentPointsCount =>
      _currentRoom?.points.length ?? 0;

  /// Genera un identificador único dentro del proceso.
  ///
  /// Se utilizan microsegundos y, si el reloj entrega el mismo valor,
  /// se incrementa manualmente.
  static String _nextUniqueId() {
    final now =
        DateTime.now().microsecondsSinceEpoch;

    if (now > _lastGeneratedId) {
      _lastGeneratedId = now;
    } else {
      _lastGeneratedId++;
    }

    return _lastGeneratedId.toString();
  }

  void updateTrackingStatus(
    bool status,
  ) {
    if (_isTrackingOk == status) {
      return;
    }

    _isTrackingOk = status;

    notifyListeners();
  }

  void setRoomType(
    RoomType type,
  ) {
    _selectedType = type;

    if (_currentRoom != null) {
      _currentRoom =
          _currentRoom!.copyWith(
        type: type,
        name: _getRoomTypeName(type),
      );
    }

    notifyListeners();
  }

  /// Inicia un ambiente nuevo con un ID resistente a colisiones.
  void startNewRoom() {
    _currentRoom = RoomModel(
      id: _nextUniqueId(),
      name:
          _getRoomTypeName(
        _selectedType,
      ),
      type: _selectedType,
      points: [],
    );

    notifyListeners();
  }

  /// Carga las habitaciones guardadas del proyecto.
  void loadRooms(
    List<RoomModel> rooms,
  ) {
    _rooms
      ..clear()
      ..addAll(rooms);

    _currentRoom = null;

    notifyListeners();
  }

  /// Intenta agregar un vértice.
  ValidationResult tryAddPoint(
    double x,
    double y,
    double z,
  ) {
    if (_currentRoom == null) {
      startNewRoom();
    }

    final candidate =
        ARPoint(
      x: x,
      y: y,
      z: z,
    );

    final result =
        ScanValidator
            .validateNewPoint(
      candidate,
      _currentRoom!.points,
    );

    if (!result.isValid) {
      return result;
    }

    final updatedPoints =
        List<ARPoint>.from(
      _currentRoom!.points,
    )..add(candidate);

    _currentRoom =
        _currentRoom!.copyWith(
      points: updatedPoints,
    );

    notifyListeners();

    return result;
  }

  /// Agrega una puerta o ventana al ambiente en curso.
  void addFeatureToCurrentRoom(
    FeatureType type,
    ARPoint location,
  ) {
    if (_currentRoom == null) {
      return;
    }

    final width =
        type == FeatureType.door
            ? 0.8
            : 1.0;

    final end =
        ARPoint(
      x: location.x + width,
      y: location.y,
      z: location.z,
    );

    final feature =
        WallFeature(
      id: _nextUniqueId(),
      type: type,
      start: location,
      end: end,
    );

    final updatedFeatures =
        List<WallFeature>.from(
      _currentRoom!.features,
    )..add(feature);

    _currentRoom =
        _currentRoom!.copyWith(
      features: updatedFeatures,
    );

    notifyListeners();
  }

  void removeLastPoint() {
    if (_currentRoom == null ||
        _currentRoom!.points.isEmpty) {
      return;
    }

    final updatedPoints =
        List<ARPoint>.from(
      _currentRoom!.points,
    )..removeLast();

    _currentRoom =
        _currentRoom!.copyWith(
      points: updatedPoints,
    );

    notifyListeners();
  }

  String? lastCloseError;

  /// Valida y cierra el ambiente actual.
  RoomModel? closeCurrentRoom() {
    lastCloseError = null;

    final room =
        _currentRoom;

    if (room == null) {
      lastCloseError =
          'No hay una habitación en curso.';

      return null;
    }

    final closure =
        ScanValidator
            .validateClosure(
      room.points,
    );

    if (!closure.isValid) {
      lastCloseError =
          closure.errorMessage;

      return null;
    }

    if (ScanValidator
        .hasSelfIntersections(
      room.points,
    )) {
      lastCloseError =
          'El contorno se autointersecta. '
          'Revisa las paredes trazadas.';

      return null;
    }

    final closedRoom =
        room.copyWith(
      isClosed: true,
    );

    _rooms.add(closedRoom);

    _currentRoom = null;

    notifyListeners();

    return closedRoom;
  }

  String _getRoomTypeName(
    RoomType type,
  ) {
    switch (type) {
      case RoomType.living:
        return 'Living';

      case RoomType.cocina:
        return 'Cocina';

      case RoomType.bano:
        return 'Baño';

      case RoomType.dormitorio:
        return 'Dormitorio';

      case RoomType.lavadero:
        return 'Lavadero';

      case RoomType.pasillo:
        return 'Pasillo';
    }
  }
}