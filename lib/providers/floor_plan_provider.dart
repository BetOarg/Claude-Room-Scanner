import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import '../services/geometry_service.dart';
import '../utils/scan_validator.dart';

/// Firma del callback de persistencia durable.
/// Se conecta en main.dart a ProjectProvider.saveCurrentProject.
typedef ProjectPersister = Future<void> Function({
  required String uuid,
  required String name,
  required List<RoomModel> rooms,
});

/// Estado en memoria del proyecto actualmente abierto.
///
/// La persistencia real continúa delegada al persister conectado desde
/// main.dart. No se agrega ningún sistema de almacenamiento paralelo.
class FloorPlanProvider extends ChangeNotifier {
  String? _projectUuid;
  String _projectName = 'Mi Casa Completa';

  final List<RoomModel> _completedRooms = [];

  /// Callback de persistencia.
  ProjectPersister? persister;

  String? get projectUuid => _projectUuid;

  String get projectName => _projectName;

  List<RoomModel> get completedRooms =>
      List.unmodifiable(_completedRooms);

  /// Carga el proyecto actualmente seleccionado.
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

  /// Persiste el proyecto utilizando el callback configurado.
  Future<void> _persist() async {
    final uuid = _projectUuid;

    if (uuid == null || persister == null) {
      return;
    }

    try {
      await persister!(
        uuid: uuid,
        name: _projectName,
        rooms: _completedRooms,
      );
    } catch (e) {
      debugPrint(
        'No se pudo guardar el proyecto "$_projectName": $e',
      );
    }
  }

  /// Cambia el nombre del proyecto.
  Future<void> setProjectName(
    String name,
  ) async {
    final normalized =
        name.trim();

    if (normalized.isEmpty) {
      return;
    }

    _projectName = normalized;

    notifyListeners();

    await _persist();
  }

  /// Agrega una habitación finalizada.
  Future<void> addCompletedRoom(
    RoomModel room,
  ) async {
    _completedRooms.add(room);

    notifyListeners();

    await _persist();
  }

  /// Carga habitaciones desde una importación.
  Future<void> loadExistingRooms(
    List<RoomModel> rooms,
    String projectName,
  ) async {
    _completedRooms
      ..clear()
      ..addAll(rooms);

    _projectName = projectName;

    notifyListeners();

    await _persist();
  }

  /// Elimina un ambiente por ID.
  Future<void> removeRoom(
    String roomId,
  ) async {
    _completedRooms.removeWhere(
      (room) => room.id == roomId,
    );

    notifyListeners();

    await _persist();
  }

  /// Actualiza el nombre de una habitación.
  Future<void> updateRoomName(
    String roomId,
    String newName,
  ) async {
    final index =
        _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );

    if (index == -1) {
      return;
    }

    final normalized =
        newName.trim();

    if (normalized.isEmpty) {
      return;
    }

    _completedRooms[index] =
        _completedRooms[index].copyWith(
      name: normalized,
    );

    notifyListeners();

    await _persist();
  }

  /// Agrega una puerta o ventana a una habitación.
  Future<void> addFeatureToRoom(
    String roomId,
    FeatureType type,
    ARPoint startLocation, [
    ARPoint? endLocation,
  ]) async {
    final index =
        _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );

    if (index == -1) {
      return;
    }

    final room =
        _completedRooms[index];

    final end =
        endLocation ??
            ARPoint(
              x: startLocation.x + 0.8,
              y: startLocation.y,
              z: startLocation.z,
            );

    final feature =
        WallFeature(
      id: DateTime.now()
          .microsecondsSinceEpoch
          .toString(),
      type: type,
      start: startLocation,
      end: end,
    );

    final features =
        List<WallFeature>.from(
      room.features,
    )..add(feature);

    _completedRooms[index] =
        room.copyWith(
      features: features,
    );

    notifyListeners();

    await _persist();
  }

  // ---------------------------------------------------------------------------
  // MÉTRICAS
  // ---------------------------------------------------------------------------

  /// Longitud de una pared.
  ///
  /// wallIndex:
  ///
  /// 0 = punto 1 → punto 2
  /// 1 = punto 2 → punto 3
  /// ...
  /// último = último punto → punto 1
  double wallLength(
    RoomModel room,
    int wallIndex,
  ) {
    final points =
        room.points;

    if (points.length < 2) {
      return 0.0;
    }

    if (wallIndex < 0 ||
        wallIndex >= points.length) {
      return 0.0;
    }

    final start =
        points[wallIndex];

    final end =
        points[
          (wallIndex + 1) %
              points.length
        ];

    return GeometryService
        .calculateDistance(
      start,
      end,
    );
  }

  /// Área total de la propiedad.
  double get totalProjectArea {
    double total = 0.0;

    for (final room
        in _completedRooms) {
      total +=
          GeometryService
              .calculateArea(
        room.points,
      );
    }

    return total;
  }

  /// Resumen de habitaciones.
  List<Map<String, dynamic>>
      get roomSummaries {
    return _completedRooms
        .map(
          (room) => {
            'id': room.id,
            'name': room.name,
            'type': room.type.name,
            'area': GeometryService
                .calculateArea(
                  room.points,
                )
                .toStringAsFixed(2),
            'perimeter': GeometryService
                .calculatePerimeter(
                  room.points,
                )
                .toStringAsFixed(2),
            'pointsCount':
                room.points.length,
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // EDITOR DE MEDIDAS
  // ---------------------------------------------------------------------------

  /// Actualiza la longitud de una pared.
  ///
  /// La dirección de la pared se conserva.
  ///
  /// Para paredes normales:
  ///
  ///   P1 → P2
  ///   P2 → P3
  ///   P3 → P4
  ///
  /// se mueve el vértice final.
  ///
  /// Para la última pared:
  ///
  ///   P4 → P1
  ///
  /// se mueve P4 para conservar P1 como origen del plano.
  ///
  /// Esto es especialmente importante para el Basic Scanner:
  /// el origen no debe desplazarse cuando se edita la última pared.
  Future<ValidationResult>
      updateWallLength({
    required String roomId,
    required int wallIndex,
    required double lengthMeters,
  }) async {
    if (!lengthMeters.isFinite ||
        lengthMeters <= 0) {
      return ValidationResult.invalid(
        'La longitud debe ser mayor que 0.',
      );
    }

    final roomIndex =
        _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );

    if (roomIndex == -1) {
      return ValidationResult.invalid(
        'No se encontró el ambiente.',
      );
    }

    final room =
        _completedRooms[roomIndex];

    final originalPoints =
        room.points;

    if (originalPoints.length < 3) {
      return ValidationResult.invalid(
        'El ambiente necesita al menos 3 esquinas.',
      );
    }

    final pointCount =
        originalPoints.length;

    if (wallIndex < 0 ||
        wallIndex >= pointCount) {
      return ValidationResult.invalid(
        'La pared seleccionada no existe.',
      );
    }

    final points =
        List<ARPoint>.from(
      originalPoints,
    );

    final startIndex =
        wallIndex;

    final endIndex =
        (wallIndex + 1) %
            pointCount;

    final start =
        points[startIndex];

    final end =
        points[endIndex];

    final dx =
        end.x - start.x;

    final dz =
        end.z - start.z;

    final currentLength =
        GeometryService
            .calculateDistance(
      start,
      end,
    );

    if (currentLength <=
        0.000001) {
      return ValidationResult.invalid(
        'La pared seleccionada tiene una longitud inválida.',
      );
    }

    final directionX =
        dx / currentLength;

    final directionZ =
        dz / currentLength;

    final newEnd =
        ARPoint(
      x: start.x +
          directionX *
              lengthMeters,
      y: end.y,
      z: start.z +
          directionZ *
              lengthMeters,
    );

    // -----------------------------------------------------------------------
    // CASO NORMAL
    // -----------------------------------------------------------------------

    if (wallIndex <
        pointCount - 1) {
      points[endIndex] =
          newEnd;

      final validation =
          ScanValidator
              .validatePointUpdate(
        endIndex,
        newEnd,
        points,
        true,
      );

      if (!validation.isValid) {
        return validation;
      }
    }

    // -----------------------------------------------------------------------
    // ÚLTIMA PARED
    //
    // P4 → P1
    //
    // No movemos P1 porque es el origen.
    // Movemos P4 manteniendo la dirección de P4 → P1.
    // -----------------------------------------------------------------------

    else {
      final previous =
          points[startIndex];

      final origin =
          points[endIndex];

      final reverseDx =
          previous.x - origin.x;

      final reverseDz =
          previous.z - origin.z;

      final reverseLength =
          GeometryService
              .calculateDistance(
        origin,
        previous,
      );

      if (reverseLength <=
          0.000001) {
        return ValidationResult.invalid(
          'No se puede recalcular la última pared porque su longitud actual es inválida.',
        );
      }

      final directionFromOriginX =
          reverseDx /
              reverseLength;

      final directionFromOriginZ =
          reverseDz /
              reverseLength;

      final newPrevious =
          ARPoint(
        x: origin.x +
            directionFromOriginX *
                lengthMeters,
        y: previous.y,
        z: origin.z +
            directionFromOriginZ *
                lengthMeters,
      );

      points[startIndex] =
          newPrevious;

      final validation =
          ScanValidator
              .validatePointUpdate(
        startIndex,
        newPrevious,
        points,
        true,
      );

      if (!validation.isValid) {
        return validation;
      }
    }

    // -----------------------------------------------------------------------
    // VALIDACIÓN FINAL DE TODO EL POLÍGONO
    // -----------------------------------------------------------------------

    final closure =
        ScanValidator
            .validateClosure(
      points,
    );

    if (!closure.isValid) {
      return closure;
    }

    if (ScanValidator
        .hasSelfIntersections(
      points,
    )) {
      return ValidationResult.invalid(
        'La nueva medida genera una autointersección. Revisá la longitud.',
      );
    }

    // -----------------------------------------------------------------------
    // GUARDAR
    // -----------------------------------------------------------------------

    _completedRooms[
            roomIndex] =
        room.copyWith(
      points: points,
    );

    notifyListeners();

    await _persist();

    return ValidationResult.warning(
      'Medida actualizada correctamente.',
    );
  }

  /// Limpia el proyecto activo.
  ///
  /// No elimina el proyecto de Isar.
  void clearProject() {
    _projectUuid = null;

    _completedRooms.clear();

    _projectName =
        'Mi Casa Completa';

    notifyListeners();
  }
}