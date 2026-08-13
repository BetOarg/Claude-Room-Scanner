import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../utils/scan_validator.dart';

/// Estado de la sesión de escaneo activa (habitación en curso + habitaciones
/// ya cerradas durante esta sesión de la app).
///
/// Este provider valida cada punto nuevo con [ScanValidator] antes de
/// aceptarlo, evitando vértices duplicados, autointersecciones y polígonos
/// degenerados en el momento de la captura (antes esta validación existía
/// pero nunca se invocaba desde ningún flujo real de la app).
class ScannerProvider extends ChangeNotifier {
  final List<RoomModel> _rooms = [];
  RoomModel? _currentRoom;
  RoomType _selectedType = RoomType.living;
  bool _isTrackingOk = false;

  List<RoomModel> get rooms => List.unmodifiable(_rooms);
  RoomModel? get currentRoom => _currentRoom;
  RoomType get selectedType => _selectedType;
  bool get isTrackingOk => _isTrackingOk;
  int get currentPointsCount => _currentRoom?.points.length ?? 0;

  void updateTrackingStatus(bool status) {
    if (_isTrackingOk != status) {
      _isTrackingOk = status;
      notifyListeners();
    }
  }

  void setRoomType(RoomType type) {
    _selectedType = type;
    if (_currentRoom != null) {
      _currentRoom = _currentRoom!.copyWith(
        type: type,
        name: _getRoomTypeName(type),
      );
    }
    notifyListeners();
  }

  void startNewRoom() {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentRoom = RoomModel(
      id: newId,
      name: _getRoomTypeName(_selectedType),
      type: _selectedType,
      points: [],
    );
    notifyListeners();
  }

  /// Reemplaza el estado con habitaciones ya guardadas de un proyecto
  /// existente (por ejemplo al reabrir un proyecto desde el dashboard).
  void loadRooms(List<RoomModel> rooms) {
    _rooms
      ..clear()
      ..addAll(rooms);
    _currentRoom = null;
    notifyListeners();
  }

  /// Intenta agregar un vértice de pared a la habitación actual.
  ///
  /// Corre la geometría a través de [ScanValidator] antes de aceptarlo:
  /// rechaza puntos duplicados o demasiado cercanos al anterior, y detecta
  /// autointersecciones con las paredes ya trazadas. Si el resultado es
  /// inválido, el punto NO se agrega y el motivo queda en
  /// [ValidationResult.errorMessage].
  ValidationResult tryAddPoint(double x, double y, double z) {
    if (_currentRoom == null) {
      startNewRoom();
    }

    final candidate = ARPoint(x: x, y: y, z: z);
    final result = ScanValidator.validateNewPoint(candidate, _currentRoom!.points);

    if (!result.isValid) {
      return result;
    }

    final updatedPoints = List<ARPoint>.from(_currentRoom!.points)..add(candidate);
    _currentRoom = _currentRoom!.copyWith(points: updatedPoints);
    notifyListeners();
    return result;
  }

  /// Agrega una puerta/ventana como [WallFeature] sobre la pared actual, en
  /// lugar de insertarla como un vértice más del polígono (lo que antes
  /// deformaba la forma de la habitación: cada puerta/ventana terminaba
  /// contando como una esquina extra).
  ///
  /// [location] es el punto tocado/capturado en AR; el extremo del vano se
  /// aproxima con un ancho fijo (0.8 m puerta, 1.0 m ventana) a lo largo del
  /// eje X, igual que el resto de la app (ver [FloorPlanProvider]). Es una
  /// simplificación de v1: la orientación real del vano sobre la pared
  /// debería derivarse de la pared más cercana.
  void addFeatureToCurrentRoom(FeatureType type, ARPoint location) {
    if (_currentRoom == null) return;

    final width = type == FeatureType.door ? 0.8 : 1.0;
    final end = ARPoint(x: location.x + width, y: location.y, z: location.z);

    final feature = WallFeature(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      start: location,
      end: end,
    );

    final updatedFeatures = List<WallFeature>.from(_currentRoom!.features)..add(feature);
    _currentRoom = _currentRoom!.copyWith(features: updatedFeatures);
    notifyListeners();
  }

  void removeLastPoint() {
    if (_currentRoom == null || _currentRoom!.points.isEmpty) return;
    final updatedPoints = List<ARPoint>.from(_currentRoom!.points)..removeLast();
    _currentRoom = _currentRoom!.copyWith(points: updatedPoints);
    notifyListeners();
  }

  /// Intenta cerrar la habitación actual, validando que el polígono tenga
  /// área suficiente y no se autointersecte antes de aceptarla como
  /// definitiva. Devuelve el [RoomModel] cerrado si tuvo éxito, o `null` si
  /// falló (en cuyo caso [lastCloseError] describe el motivo).
  String? lastCloseError;

  RoomModel? closeCurrentRoom() {
    lastCloseError = null;
    final room = _currentRoom;
    if (room == null) {
      lastCloseError = 'No hay una habitación en curso.';
      return null;
    }

    final closure = ScanValidator.validateClosure(room.points);
    if (!closure.isValid) {
      lastCloseError = closure.errorMessage;
      return null;
    }

    if (ScanValidator.hasSelfIntersections(room.points)) {
      lastCloseError = 'El contorno se autointersecta. Revisa las paredes trazadas.';
      return null;
    }

    final closedRoom = room.copyWith(isClosed: true);
    _rooms.add(closedRoom);
    _currentRoom = null;
    notifyListeners();
    return closedRoom;
  }

  String _getRoomTypeName(RoomType type) {
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
