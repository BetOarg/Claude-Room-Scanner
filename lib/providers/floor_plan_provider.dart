import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../services/geometry_service.dart';

/// Firma del callback de persistencia durable. Se conecta en `main.dart` a
/// `ProjectProvider.saveCurrentProject`, que escribe en Isar (y sincroniza
/// con Supabase si hay sesión activa).
typedef ProjectPersister = Future<void> Function({
  required String uuid,
  required String name,
  required List<RoomModel> rooms,
});

/// Estado en memoria del proyecto actualmente abierto (sus habitaciones
/// terminadas, listas para ver/editar en el plano 2D o exportar).
///
/// IMPORTANTE: este provider ya NO tiene su propio mecanismo de guardado en
/// disco. Antes escribía un archivo JSON plano por su cuenta
/// (`auto_save_project.json`, un único proyecto sin id) mientras
/// `ProjectProvider` guardaba en Isar con soporte multi‑proyecto: dos
/// sistemas de persistencia que no se enteraban entre sí y ninguno de los
/// dos llegaba a invocarse realmente desde las pantallas activas, así que
/// las habitaciones escaneadas nunca quedaban guardadas.
///
/// Ahora `FloorPlanProvider` es solo el estado en memoria del proyecto
/// abierto; cada cambio se persiste a través de [persister] (Isar es la
/// única fuente de verdad).
class FloorPlanProvider extends ChangeNotifier {
  String? _projectUuid;
  String _projectName = 'Mi Casa Completa';
  final List<RoomModel> _completedRooms = [];

  /// Conectado desde `main.dart` a `ProjectProvider.saveCurrentProject`.
  ProjectPersister? persister;

  String? get projectUuid => _projectUuid;
  String get projectName => _projectName;
  List<RoomModel> get completedRooms => List.unmodifiable(_completedRooms);

  /// Carga el estado en memoria a partir de un proyecto ya existente (o
  /// recién creado) en Isar.
  void loadProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) {
    _projectUuid = uuid;
    _projectName = name;
    _completedRooms
      ..clear()
      ..addAll(rooms);
    notifyListeners();
  }

  /// Persiste el estado actual a través de [persister]. No hace nada si
  /// todavía no se cargó/creó un proyecto (evita escrituras sin uuid).
  Future<void> _persist() async {
    final uuid = _projectUuid;
    if (uuid == null || persister == null) return;
    try {
      await persister!(uuid: uuid, name: _projectName, rooms: _completedRooms);
    } catch (e) {
      debugPrint('No se pudo guardar el proyecto "$_projectName": $e');
    }
  }

  /// Cambia el nombre del proyecto
  Future<void> setProjectName(String name) async {
    _projectName = name;
    notifyListeners();
    await _persist();
  }

  /// Agrega una habitación finalizada
  Future<void> addCompletedRoom(RoomModel room) async {
    _completedRooms.add(room);
    notifyListeners();
    await _persist();
  }

  /// Carga habitaciones desde una importación (sobrescribe el proyecto actual)
  Future<void> loadExistingRooms(List<RoomModel> rooms, String projectName) async {
    _completedRooms
      ..clear()
      ..addAll(rooms);
    _projectName = projectName;
    notifyListeners();
    await _persist();
  }

  /// Elimina un ambiente por su ID
  Future<void> removeRoom(String roomId) async {
    _completedRooms.removeWhere((room) => room.id == roomId);
    notifyListeners();
    await _persist();
  }

  /// Actualiza el nombre de una habitación existente
  Future<void> updateRoomName(String roomId, String newName) async {
    final index = _completedRooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      _completedRooms[index] = _completedRooms[index].copyWith(name: newName);
      notifyListeners();
      await _persist();
    }
  }

  /// Agrega una característica (puerta/ventana) a una habitación específica
  Future<void> addFeatureToRoom(
    String roomId,
    FeatureType type,
    ARPoint startLocation, [
    ARPoint? endLocation,
  ]) async {
    final index = _completedRooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      final room = _completedRooms[index];

      // Si no se proporciona un punto final, usaremos un desplazamiento básico
      final end = endLocation ??
          ARPoint(
            x: startLocation.x + 0.8,
            y: startLocation.y,
            z: startLocation.z,
          );

      final newFeature = WallFeature(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        start: startLocation,
        end: end,
      );

      final updatedFeatures = List<WallFeature>.from(room.features)..add(newFeature);
      _completedRooms[index] = room.copyWith(features: updatedFeatures);
      notifyListeners();
      await _persist();
    }
  }

  /// Calcula el área total de la propiedad (m²)
  double get totalProjectArea {
    double totalArea = 0.0;
    for (var room in _completedRooms) {
      totalArea += GeometryService.calculateArea(room.points);
    }
    return totalArea;
  }

  /// Resumen de métricas de cada habitación
  List<Map<String, dynamic>> get roomSummaries {
    return _completedRooms.map((room) {
      return {
        'id': room.id,
        'name': room.name,
        'type': room.type.name,
        'area': GeometryService.calculateArea(room.points).toStringAsFixed(2),
        'perimeter': GeometryService.calculatePerimeter(room.points).toStringAsFixed(2),
        'pointsCount': room.points.length,
      };
    }).toList();
  }

  /// Limpia todo el proyecto activo (no borra el proyecto de Isar; para eso
  /// está `ProjectProvider.deleteProject`).
  void clearProject() {
    _projectUuid = null;
    _completedRooms.clear();
    _projectName = 'Mi Casa Completa';
    notifyListeners();
  }
}
