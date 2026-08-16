import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import '../services/geometry_service.dart';
import '../utils/scan_validator.dart';

typedef ProjectPersister = Future<void> Function({
  required String uuid,
  required String name,
  required List<RoomModel> rooms,
});

class FloorPlanProvider extends ChangeNotifier {
  static const double _defaultRoomSpacing = 1.0;

  String? _projectUuid;

  String _projectName = 'Mi Casa Completa';

  final List<RoomModel> _completedRooms = [];

  ProjectPersister? persister;

  static int _lastGeneratedId = 0;

  String? get projectUuid => _projectUuid;

  String get projectName => _projectName;

  List<RoomModel> get completedRooms =>
      List.unmodifiable(
        _completedRooms,
      );

  // ===========================================================================
  // IDENTIFICADORES
  // ===========================================================================

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

  /// Repara IDs vacíos o repetidos.
  ///
  /// Permite abrir proyectos creados antes de incorporar
  /// el generador monotónico de identificadores.
  _RoomNormalizationResult _normalizeRoomIds(
    List<RoomModel> rooms,
  ) {
    final usedIds = <String>{};

    final normalized = <RoomModel>[];

    bool changed = false;

    for (final room in rooms) {
      var id = room.id.trim();

      if (id.isEmpty ||
          usedIds.contains(id)) {
        id = _nextUniqueId();

        changed = true;
      }

      usedIds.add(id);

      if (id != room.id) {
        normalized.add(
          room.copyWith(
            id: id,
          ),
        );
      } else {
        normalized.add(room);
      }
    }

    return _RoomNormalizationResult(
      rooms: normalized,
      changed: changed,
    );
  }

  // ===========================================================================
  // PROYECTO
  // ===========================================================================

  void loadProject({
    required String uuid,
    required String name,
    required List<RoomModel> rooms,
  }) {
    _projectUuid = uuid;

    _projectName = name;

    final normalized =
        _normalizeRoomIds(
      rooms,
    );

    _completedRooms
      ..clear()
      ..addAll(
        normalized.rooms,
      );

    notifyListeners();

    if (normalized.changed) {
      Future<void>.microtask(
        _persist,
      );
    }
  }

  Future<void> _persist() async {
    final uuid = _projectUuid;

    if (uuid == null ||
        persister == null) {
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
        'No se pudo guardar el proyecto '
        '"$_projectName": $e',
      );
    }
  }

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

  // ===========================================================================
  // HABITACIONES
  // ===========================================================================

  /// Agrega una habitación terminada.
  ///
  /// Si ya existen habitaciones en el proyecto, la nueva se posiciona
  /// automáticamente a continuación del plano existente.
  ///
  /// IMPORTANTE:
  ///
  /// Esto es una traslación rígida:
  ///
  ///   x' = x + offsetX
  ///   z' = z + offsetZ
  ///
  /// Por lo tanto NO modifica:
  ///
  /// - longitudes;
  /// - ángulos;
  /// - superficie;
  /// - perímetro;
  /// - forma del ambiente.
  Future<void> addCompletedRoom(
    RoomModel room,
  ) async {
    var roomToAdd = room;

    final duplicate =
        _completedRooms.any(
      (existing) =>
          existing.id == room.id,
    );

    if (room.id.trim().isEmpty ||
        duplicate) {
      roomToAdd =
          room.copyWith(
        id: _nextUniqueId(),
      );
    }

    if (_completedRooms.isNotEmpty &&
        roomToAdd.points.isNotEmpty) {
      roomToAdd =
          _placeRoomAfterExisting(
        roomToAdd,
      );
    }

    _completedRooms.add(
      roomToAdd,
    );

    notifyListeners();

    await _persist();
  }

  Future<void> loadExistingRooms(
    List<RoomModel> rooms,
    String projectName,
  ) async {
    final normalized =
        _normalizeRoomIds(
      rooms,
    );

    _completedRooms
      ..clear()
      ..addAll(
        normalized.rooms,
      );

    _projectName = projectName;

    notifyListeners();

    await _persist();
  }

  Future<void> removeRoom(
    String roomId,
  ) async {
    _completedRooms.removeWhere(
      (room) =>
          room.id == roomId,
    );

    notifyListeners();

    await _persist();
  }

  Future<void> updateRoomName(
    String roomId,
    String newName,
  ) async {
    final index =
        _completedRooms.indexWhere(
      (room) =>
          room.id == roomId,
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
        _completedRooms[index]
            .copyWith(
      name: normalized,
    );

    notifyListeners();

    await _persist();
  }

  // ===========================================================================
  // POSICIONAMIENTO GLOBAL
  // ===========================================================================

  /// Traslada una habitación completa.
  ///
  /// Se trasladan también todas sus puertas y ventanas.
  RoomModel _translateRoom(
    RoomModel room, {
    required double offsetX,
    required double offsetZ,
  }) {
    final translatedPoints =
        room.points.map(
      (point) {
        return ARPoint(
          x: point.x + offsetX,
          y: point.y,
          z: point.z + offsetZ,
        );
      },
    ).toList();

    final translatedFeatures =
        room.features.map(
      (feature) {
        return WallFeature(
          id: feature.id,
          type: feature.type,
          start: ARPoint(
            x:
                feature.start.x +
                    offsetX,
            y: feature.start.y,
            z:
                feature.start.z +
                    offsetZ,
          ),
          end: ARPoint(
            x:
                feature.end.x +
                    offsetX,
            y: feature.end.y,
            z:
                feature.end.z +
                    offsetZ,
          ),
        );
      },
    ).toList();

    return room.copyWith(
      points: translatedPoints,
      features: translatedFeatures,
    );
  }

  /// Posiciona una habitación nueva después de las existentes.
  ///
  /// El comportamiento inicial es deliberadamente simple y predecible:
  ///
  ///   Habitación 1   Habitación 2   Habitación 3
  ///   ┌───────┐      ┌───────┐      ┌───────┐
  ///   │       │ 1 m  │       │ 1 m  │       │
  ///   └───────┘      └───────┘      └───────┘
  RoomModel _placeRoomAfterExisting(
    RoomModel room,
  ) {
    if (_completedRooms.isEmpty ||
        room.points.isEmpty) {
      return room;
    }

    double projectMaxX =
        double.negativeInfinity;

    double projectMinZ =
        double.infinity;

    for (final existing
        in _completedRooms) {
      for (final point
          in existing.points) {
        if (point.x >
            projectMaxX) {
          projectMaxX =
              point.x;
        }

        if (point.z <
            projectMinZ) {
          projectMinZ =
              point.z;
        }
      }
    }

    if (!projectMaxX.isFinite) {
      projectMaxX = 0.0;
    }

    if (!projectMinZ.isFinite) {
      projectMinZ = 0.0;
    }

    double roomMinX =
        double.infinity;

    double roomMinZ =
        double.infinity;

    for (final point
        in room.points) {
      if (point.x < roomMinX) {
        roomMinX =
            point.x;
      }

      if (point.z < roomMinZ) {
        roomMinZ =
            point.z;
      }
    }

    if (!roomMinX.isFinite) {
      roomMinX = 0.0;
    }

    if (!roomMinZ.isFinite) {
      roomMinZ = 0.0;
    }

    final targetMinX =
        projectMaxX +
            _defaultRoomSpacing;

    final offsetX =
        targetMinX -
            roomMinX;

    final offsetZ =
        projectMinZ -
            roomMinZ;

    return _translateRoom(
      room,
      offsetX: offsetX,
      offsetZ: offsetZ,
    );
  }

  /// Organiza todas las habitaciones del proyecto en una fila.
  ///
  /// Esta función corrige proyectos históricos en los que cada habitación
  /// fue escaneada comenzando en (0, 0, 0), produciendo superposición visual.
  ///
  /// La primera habitación comienza en X = 0 y las siguientes se colocan
  /// con [_defaultRoomSpacing] metros entre ellas.
  Future<void> autoArrangeRooms({
    double spacing =
        _defaultRoomSpacing,
  }) async {
    if (_completedRooms.length <=
        1) {
      return;
    }

    final arranged =
        <RoomModel>[];

    double nextX = 0.0;

    for (final room
        in _completedRooms) {
      if (room.points.isEmpty) {
        arranged.add(room);
        continue;
      }

      double minX =
          double.infinity;

      double maxX =
          double.negativeInfinity;

      double minZ =
          double.infinity;

      for (final point
          in room.points) {
        if (point.x < minX) {
          minX = point.x;
        }

        if (point.x > maxX) {
          maxX = point.x;
        }

        if (point.z < minZ) {
          minZ = point.z;
        }
      }

      if (!minX.isFinite ||
          !maxX.isFinite ||
          !minZ.isFinite) {
        arranged.add(room);
        continue;
      }

      final roomWidth =
          maxX - minX;

      final offsetX =
          nextX - minX;

      final offsetZ =
          -minZ;

      final translated =
          _translateRoom(
        room,
        offsetX: offsetX,
        offsetZ: offsetZ,
      );

      arranged.add(
        translated,
      );

      nextX +=
          roomWidth +
              spacing;
    }

    _completedRooms
      ..clear()
      ..addAll(arranged);

    notifyListeners();

    await _persist();
  }

  /// Mueve manualmente un ambiente completo.
  ///
  /// Esta API queda preparada para un editor de distribución posterior.
  Future<void> translateRoom({
    required String roomId,
    required double offsetX,
    required double offsetZ,
  }) async {
    final index =
        _completedRooms.indexWhere(
      (room) =>
          room.id == roomId,
    );

    if (index == -1) {
      return;
    }

    final room =
        _completedRooms[index];

    _completedRooms[index] =
        _translateRoom(
      room,
      offsetX: offsetX,
      offsetZ: offsetZ,
    );

    notifyListeners();

    await _persist();
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  Future<void> addFeatureToRoom(
    String roomId,
    FeatureType type,
    ARPoint startLocation, [
    ARPoint? endLocation,
  ]) async {
    final index =
        _completedRooms.indexWhere(
      (room) =>
          room.id == roomId,
    );

    if (index == -1) {
      return;
    }

    final room =
        _completedRooms[index];

    final end =
        endLocation ??
            ARPoint(
              x:
                  startLocation.x +
                      0.8,
              y: startLocation.y,
              z: startLocation.z,
            );

    final feature =
        WallFeature(
      id: _nextUniqueId(),
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

  // ===========================================================================
  // MÉTRICAS
  // ===========================================================================

  double wallLength(
    RoomModel room,
    int wallIndex,
  ) {
    final points =
        room.points;

    if (points.length < 2 ||
        wallIndex < 0 ||
        wallIndex >=
            points.length) {
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

  List<Map<String, dynamic>>
      get roomSummaries {
    return _completedRooms
        .map(
          (room) => {
            'id': room.id,
            'name': room.name,
            'type':
                room.type.name,
            'area':
                GeometryService
                    .calculateArea(
                      room.points,
                    )
                    .toStringAsFixed(
                      2,
                    ),
            'perimeter':
                GeometryService
                    .calculatePerimeter(
                      room.points,
                    )
                    .toStringAsFixed(
                      2,
                    ),
            'pointsCount':
                room.points.length,
          },
        )
        .toList();
  }

  // ===========================================================================
  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<ValidationResult>
      updateWallLength({
    required String roomId,
    int? roomIndex,
    required int wallIndex,
    required double lengthMeters,
  }) async {
    if (!lengthMeters.isFinite ||
        lengthMeters <= 0) {
      return ValidationResult.invalid(
        'La longitud debe ser mayor que 0.',
      );
    }

    int resolvedRoomIndex =
        -1;

    if (roomIndex != null &&
        roomIndex >= 0 &&
        roomIndex <
            _completedRooms.length) {
      resolvedRoomIndex =
          roomIndex;
    } else {
      resolvedRoomIndex =
          _completedRooms.indexWhere(
        (room) =>
            room.id == roomId,
      );
    }

    if (resolvedRoomIndex ==
        -1) {
      return ValidationResult.invalid(
        'No se encontró el ambiente.',
      );
    }

    final room =
        _completedRooms[
          resolvedRoomIndex
        ];

    final originalPoints =
        room.points;

    if (originalPoints.length <
        3) {
      return ValidationResult.invalid(
        'El ambiente necesita al menos 3 esquinas.',
      );
    }

    final pointCount =
        originalPoints.length;

    if (wallIndex < 0 ||
        wallIndex >=
            pointCount) {
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

    final dx =
        end.x - start.x;

    final dz =
        end.z - start.z;

    final directionX =
        dx / currentLength;

    final directionZ =
        dz / currentLength;

    if (wallIndex <
        pointCount - 1) {
      final newEnd =
          ARPoint(
        x:
            start.x +
                directionX *
                    lengthMeters,
        y: end.y,
        z:
            start.z +
                directionZ *
                    lengthMeters,
      );

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
    } else {
      // Última pared:
      // mantenemos el punto 1 como origen global del ambiente.
      final previous =
          points[startIndex];

      final origin =
          points[0];

      final reverseLength =
          GeometryService
              .calculateDistance(
        origin,
        previous,
      );

      if (reverseLength <=
          0.000001) {
        return ValidationResult.invalid(
          'La última pared tiene una longitud inválida.',
        );
      }

      final directionFromOriginX =
          (previous.x -
                  origin.x) /
              reverseLength;

      final directionFromOriginZ =
          (previous.z -
                  origin.z) /
              reverseLength;

      final newPrevious =
          ARPoint(
        x:
            origin.x +
                directionFromOriginX *
                    lengthMeters,
        y: previous.y,
        z:
            origin.z +
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
        'La nueva medida genera una autointersección. '
        'Revisá la longitud.',
      );
    }

    _completedRooms[
            resolvedRoomIndex] =
        room.copyWith(
      points: points,
    );

    notifyListeners();

    await _persist();

    return ValidationResult.warning(
      'Medida actualizada correctamente.',
    );
  }

  // ===========================================================================
  // RESET
  // ===========================================================================

  void clearProject() {
    _projectUuid = null;

    _completedRooms.clear();

    _projectName =
        'Mi Casa Completa';

    notifyListeners();
  }
}

class _RoomNormalizationResult {
  final List<RoomModel> rooms;

  final bool changed;

  const _RoomNormalizationResult({
    required this.rooms,
    required this.changed,
  });
}