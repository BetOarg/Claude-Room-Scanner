import 'dart:math' as math;


import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import '../services/geometry_service.dart';
import '../utils/measurement_units.dart';
import '../utils/scan_validator.dart';

typedef ProjectPersister = Future<void> Function({
  required String uuid,
  required String name,
  required List<RoomModel> rooms,
});

class FloorPlanProvider extends ChangeNotifier {
  static const double _defaultRoomSpacing = 1.0;
  static const int _maximumTransformHistoryEntries = 50;

  MeasurementSystem measurementSystem =
      MeasurementSystem.metric;

  String? _projectUuid;

  String _projectName = 'Mi Casa Completa';

  final List<RoomModel> _completedRooms = [];

  final List<_TransformHistoryEntry> _transformUndoHistory = [];
  final List<_TransformHistoryEntry> _transformRedoHistory = [];

  ProjectPersister? persister;

  static int _lastGeneratedId = 0;

  String? get projectUuid => _projectUuid;

  String get projectName => _projectName;

  List<RoomModel> get completedRooms =>
      List.unmodifiable(
        _completedRooms,
      );

  bool get canUndoTransform =>
      _transformUndoHistory.isNotEmpty &&
      _sameRoomSnapshot(
        _transformUndoHistory.last.after,
        _completedRooms,
      );

  bool get canRedoTransform =>
      _transformRedoHistory.isNotEmpty &&
      _sameRoomSnapshot(
        _transformRedoHistory.last.before,
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

    _clearTransformHistory();

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

  /// Guarda un ambiente escaneado desde una puerta o ventana existente.
  ///
  /// El contorno recibido utiliza coordenadas locales del scanner:
  ///
  /// - el origen local se alinea con el extremo A o B elegido;
  /// - +Z apunta hacia el lado elegido para el nuevo ambiente;
  /// - +X conserva la dirección de 90° hacia la derecha.
  ///
  /// La operación actualiza los dos ambientes antes de notificar o persistir,
  /// evitando estados intermedios con una conexión incompleta.
  Future<bool> addCompletedRoomFromContinuation({
    required RoomModel room,
    required ScanContinuationReference reference,
  }) async {
    final sourceRoomIndex = _completedRooms.indexWhere(
      (existing) => existing.id == reference.sourceRoomId,
    );

    if (sourceRoomIndex == -1) {
      return false;
    }

    final sourceRoom = _completedRooms[sourceRoomIndex];
    final sourceFeatureIndex = sourceRoom.features.indexWhere(
      (feature) => feature.id == reference.featureId,
    );

    if (sourceFeatureIndex == -1 ||
        sourceRoom.features[sourceFeatureIndex].isConnected) {
      return false;
    }

    var roomToAdd = room;

    if (roomToAdd.id.trim().isEmpty ||
        _completedRooms.any(
          (existing) => existing.id == roomToAdd.id,
        )) {
      roomToAdd = roomToAdd.copyWith(
        id: _nextUniqueId(),
      );
    }

    roomToAdd = _alignRoomToContinuation(
      roomToAdd,
      reference,
    );

    final sourceFeatures = List<WallFeature>.from(
      sourceRoom.features,
    );
    final sourceFeature = sourceFeatures[sourceFeatureIndex];

    sourceFeatures[sourceFeatureIndex] = sourceFeature.copyWith(
      connectedRoomId: roomToAdd.id,
      connectionSide: reference.side,
    );

    final oppositeSide =
        reference.side == OpeningConnectionSide.left
            ? OpeningConnectionSide.right
            : OpeningConnectionSide.left;

    final sharedFeature = WallFeature(
      id: sourceFeature.id,
      type: sourceFeature.type,
      start: sourceFeature.start,
      end: sourceFeature.end,
      connectedRoomId: sourceRoom.id,
      connectionSide: oppositeSide,
      doorHingeSide: sourceFeature.doorHingeSide,
      doorSwingSide: sourceFeature.doorSwingSide,
      doorOpeningDirection: sourceFeature.doorOpeningDirection,
      openingHeightMeters: sourceFeature.openingHeightMeters,
      sillHeightMeters: sourceFeature.sillHeightMeters,
    );

    final newFeatures = List<WallFeature>.from(
      roomToAdd.features,
    );
    final existingSharedIndex = newFeatures.indexWhere(
      (feature) => feature.id == sharedFeature.id,
    );

    if (existingSharedIndex == -1) {
      newFeatures.add(sharedFeature);
    } else {
      newFeatures[existingSharedIndex] = sharedFeature;
    }

    roomToAdd = roomToAdd.copyWith(
      features: newFeatures,
    );

    _completedRooms[sourceRoomIndex] = sourceRoom.copyWith(
      features: sourceFeatures,
    );
    _completedRooms.add(roomToAdd);

    notifyListeners();
    await _persist();

    return true;
  }

  RoomModel _alignRoomToContinuation(
    RoomModel room,
    ScanContinuationReference reference,
  ) {
    final openingDx =
        reference.globalEnd.x - reference.globalStart.x;
    final openingDz =
        reference.globalEnd.z - reference.globalStart.z;
    final openingLength = math.sqrt(
      openingDx * openingDx + openingDz * openingDz,
    );

    if (openingLength <= 0.000001) {
      return room;
    }

    final tangentX = openingDx / openingLength;
    final tangentZ = openingDz / openingLength;

    final forwardX =
        reference.side == OpeningConnectionSide.left
            ? -tangentZ
            : tangentZ;
    final forwardZ =
        reference.side == OpeningConnectionSide.left
            ? tangentX
            : -tangentX;

    final rightX = forwardZ;
    final rightZ = -forwardX;
    final origin = reference.origin;

    ARPoint transformPoint(ARPoint point) {
      return ARPoint(
        x: origin.x + point.x * rightX + point.z * forwardX,
        y: origin.y + point.y,
        z: origin.z + point.x * rightZ + point.z * forwardZ,
      );
    }

    return room.copyWith(
      points: room.points.map(transformPoint).toList(),
      features: room.features
          .map(
            (feature) => feature.copyWith(
              start: transformPoint(feature.start),
              end: transformPoint(feature.end),
            ),
          )
          .toList(),
    );
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

  // ===========================================================================  // POSICIONAMIENTO GLOBAL  // ===========================================================================

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
        return feature.copyWith(
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
  }  /// Organiza todas las habitaciones del proyecto en una fila.  ///  /// Esta función corrige proyectos históricos en los que cada habitación  /// fue escaneada comenzando en (0, 0, 0), produciendo superposición visual.
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
    if (!offsetX.isFinite ||
        !offsetZ.isFinite ||
        (offsetX.abs() <= 0.000001 &&
            offsetZ.abs() <= 0.000001)) {
      return;
    }

    final connectedIds =
        _connectedRoomIds(roomId);

    if (connectedIds.isEmpty) {
      return;
    }

    final before = List<RoomModel>.from(_completedRooms);

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final room = _completedRooms[index];

      if (!connectedIds.contains(room.id)) {
        continue;
      }

      _completedRooms[index] = _translateRoom(
        room,
        offsetX: offsetX,
        offsetZ: offsetZ,
      );
    }

    _recordTransform(before);

    notifyListeners();

    await _persist();
  }

  /// Rota rígidamente un ambiente y todo su grupo conectado.
  ///
  /// El centro de giro es el centro geométrico común de los puntos del grupo.
  /// Las puertas y ventanas se transforman junto con los contornos, por lo que
  /// las copias de una abertura compartida conservan el mismo ID y posición.
  Future<void> rotateRoom({
    required String roomId,
    required double angleDegrees,
  }) async {
    if (!angleDegrees.isFinite ||
        angleDegrees.abs() <= 0.000001) {
      return;
    }

    final connectedIds = _connectedRoomIds(roomId);
    if (connectedIds.isEmpty) {
      return;
    }

    final groupPoints = <ARPoint>[
      for (final room in _completedRooms)
        if (connectedIds.contains(room.id)) ...room.points,
    ];

    if (groupPoints.isEmpty) {
      return;
    }

    final before = List<RoomModel>.from(_completedRooms);

    final centerX = groupPoints
            .map((point) => point.x)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final centerZ = groupPoints
            .map((point) => point.z)
            .reduce((value, element) => value + element) /
        groupPoints.length;
    final radians = angleDegrees * math.pi / 180.0;

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final room = _completedRooms[index];

      if (!connectedIds.contains(room.id)) {
        continue;
      }

      _completedRooms[index] = _rotateRoom(
        room,
        centerX: centerX,
        centerZ: centerZ,
        radians: radians,
      );
    }

    _recordTransform(before);

    notifyListeners();
    await _persist();
  }

  /// Alinea rígidamente el ambiente seleccionado con la pared externa más
  /// cercana que sea paralela y tenga una superposición longitudinal útil.
  /// El grupo conectado se transforma como una sola unidad.
  Future<bool> alignRoomToNearestWall({
    required String roomId,
    double maximumDistanceMeters = 0.30,
    double maximumAngleDegrees = 5.0,
    double minimumOverlapMeters = 0.20,
  }) async {
    final sourceRoomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (sourceRoomIndex == -1 ||
        maximumDistanceMeters <= 0 ||
        maximumAngleDegrees <= 0) {
      return false;
    }

    final sourceRoom = _completedRooms[sourceRoomIndex];
    final connectedIds = _connectedRoomIds(roomId);
    if (sourceRoom.points.length < 2 || connectedIds.isEmpty) {
      return false;
    }

    _WallAlignmentCandidate? bestCandidate;
    final maximumAngleRadians =
        maximumAngleDegrees * math.pi / 180.0;

    for (var sourceIndex = 0;
        sourceIndex < sourceRoom.points.length;
        sourceIndex++) {
      final sourceStart = sourceRoom.points[sourceIndex];
      final sourceEnd = sourceRoom.points[
        (sourceIndex + 1) % sourceRoom.points.length
      ];
      final sourceDx = sourceEnd.x - sourceStart.x;
      final sourceDz = sourceEnd.z - sourceStart.z;
      final sourceLength = math.sqrt(
        sourceDx * sourceDx + sourceDz * sourceDz,
      );
      if (sourceLength <= 0.000001) {
        continue;
      }

      final sourceUnitX = sourceDx / sourceLength;
      final sourceUnitZ = sourceDz / sourceLength;
      final sourceMidX = (sourceStart.x + sourceEnd.x) / 2.0;
      final sourceMidZ = (sourceStart.z + sourceEnd.z) / 2.0;

      for (final targetRoom in _completedRooms) {
        if (connectedIds.contains(targetRoom.id) ||
            targetRoom.points.length < 2) {
          continue;
        }

        for (var targetIndex = 0;
            targetIndex < targetRoom.points.length;
            targetIndex++) {
          final targetStart = targetRoom.points[targetIndex];
          final targetEnd = targetRoom.points[
            (targetIndex + 1) % targetRoom.points.length
          ];
          final targetDx = targetEnd.x - targetStart.x;
          final targetDz = targetEnd.z - targetStart.z;
          final targetLength = math.sqrt(
            targetDx * targetDx + targetDz * targetDz,
          );
          if (targetLength <= 0.000001) {
            continue;
          }

          var targetUnitX = targetDx / targetLength;
          var targetUnitZ = targetDz / targetLength;
          var targetOriginX = targetStart.x;
          var targetOriginZ = targetStart.z;
          var directionDot =
              sourceUnitX * targetUnitX + sourceUnitZ * targetUnitZ;
          if (directionDot < 0) {
            targetUnitX = -targetUnitX;
            targetUnitZ = -targetUnitZ;
            targetOriginX = targetEnd.x;
            targetOriginZ = targetEnd.z;
            directionDot = -directionDot;
          }
          final angleRadians = math.acos(
            directionDot.clamp(-1.0, 1.0).toDouble(),
          );
          if (angleRadians > maximumAngleRadians) {
            continue;
          }

          final targetNormalX = -targetUnitZ;
          final targetNormalZ = targetUnitX;
          final signedDistance =
              (sourceMidX - targetOriginX) * targetNormalX +
                  (sourceMidZ - targetOriginZ) * targetNormalZ;
          if (signedDistance.abs() > maximumDistanceMeters) {
            continue;
          }

          final cross =
              sourceUnitX * targetUnitZ - sourceUnitZ * targetUnitX;
          final rotationRadians = math.atan2(cross, directionDot);
          final sourceProjectionCenter =
              (sourceMidX - targetOriginX) * targetUnitX +
                  (sourceMidZ - targetOriginZ) * targetUnitZ;
          final sourceProjectionStart =
              sourceProjectionCenter - sourceLength / 2.0;
          final sourceProjectionEnd =
              sourceProjectionCenter + sourceLength / 2.0;
          final overlap = math.min(
                sourceProjectionEnd,
                targetLength,
              ) -
              math.max(sourceProjectionStart, 0.0);
          final requiredOverlap = math.min(
            minimumOverlapMeters,
            math.min(sourceLength, targetLength) * 0.25,
          );
          if (overlap < requiredOverlap) {
            continue;
          }

          final sourceCenter = _roomCenter(sourceRoom);
          final targetCenter = _roomCenter(targetRoom);
          final cosine = math.cos(rotationRadians);
          final sine = math.sin(rotationRadians);
          final relativeCenterX = sourceCenter.x - sourceMidX;
          final relativeCenterZ = sourceCenter.z - sourceMidZ;
          final rotatedCenterX = sourceMidX +
              relativeCenterX * cosine - relativeCenterZ * sine;
          final rotatedCenterZ = sourceMidZ +
              relativeCenterX * sine + relativeCenterZ * cosine;
          final offsetX = -signedDistance * targetNormalX;
          final offsetZ = -signedDistance * targetNormalZ;
          final sourceSide =
              (rotatedCenterX + offsetX - targetOriginX) *
                      targetNormalX +
                  (rotatedCenterZ + offsetZ - targetOriginZ) *
                      targetNormalZ;
          final targetSide =
              (targetCenter.x - targetOriginX) * targetNormalX +
                  (targetCenter.z - targetOriginZ) * targetNormalZ;
          if (sourceSide * targetSide >= -0.000001) {
            continue;
          }

          final score =
              signedDistance.abs() + angleRadians * 0.10;
          if (bestCandidate == null ||
              score < bestCandidate.score) {
            bestCandidate = _WallAlignmentCandidate(
              centerX: sourceMidX,
              centerZ: sourceMidZ,
              rotationRadians: rotationRadians,
              offsetX: offsetX,
              offsetZ: offsetZ,
              score: score,
            );
          }
        }
      }
    }

    final candidate = bestCandidate;
    if (candidate == null ||
        (candidate.rotationRadians.abs() <= 0.000001 &&
            candidate.offsetX.abs() <= 0.000001 &&
            candidate.offsetZ.abs() <= 0.000001)) {
      return false;
    }

    final before = List<RoomModel>.from(_completedRooms);
    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final room = _completedRooms[index];
      if (!connectedIds.contains(room.id)) {
        continue;
      }
      final rotated = _rotateRoom(
        room,
        centerX: candidate.centerX,
        centerZ: candidate.centerZ,
        radians: candidate.rotationRadians,
      );
      _completedRooms[index] = _translateRoom(
        rotated,
        offsetX: candidate.offsetX,
        offsetZ: candidate.offsetZ,
      );
    }

    _recordTransform(before);
    notifyListeners();
    await _persist();
    return true;
  }

  ARPoint _roomCenter(RoomModel room) {
    final totalX = room.points.fold<double>(
      0.0,
      (sum, point) => sum + point.x,
    );
    final totalZ = room.points.fold<double>(
      0.0,
      (sum, point) => sum + point.z,
    );
    return ARPoint(
      x: totalX / room.points.length,
      y: 0.0,
      z: totalZ / room.points.length,
    );
  }

  Future<bool> undoTransform() async {
    if (!canUndoTransform) {
      _clearTransformHistory();
      return false;
    }

    final entry = _transformUndoHistory.removeLast();
    _completedRooms
      ..clear()
      ..addAll(entry.before);
    _transformRedoHistory.add(entry);

    notifyListeners();
    await _persist();
    return true;
  }

  Future<bool> redoTransform() async {
    if (!canRedoTransform) {
      _clearTransformHistory();
      return false;
    }

    final entry = _transformRedoHistory.removeLast();
    _completedRooms
      ..clear()
      ..addAll(entry.after);
    _transformUndoHistory.add(entry);

    notifyListeners();
    await _persist();
    return true;
  }

  void _recordTransform(List<RoomModel> before) {
    _transformUndoHistory.add(
      _TransformHistoryEntry(
        before: before,
        after: List<RoomModel>.from(_completedRooms),
      ),
    );
    if (_transformUndoHistory.length >
        _maximumTransformHistoryEntries) {
      _transformUndoHistory.removeAt(0);
    }
    _transformRedoHistory.clear();
  }

  void _clearTransformHistory() {
    _transformUndoHistory.clear();
    _transformRedoHistory.clear();
  }

  bool _sameRoomSnapshot(
    List<RoomModel> first,
    List<RoomModel> second,
  ) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) {
        return false;
      }    }
    return true;
  }

  RoomModel _rotateRoom(
    RoomModel room, {
    required double centerX,
    required double centerZ,
    required double radians,
  }) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);

    ARPoint rotatePoint(ARPoint point) {
      final relativeX = point.x - centerX;
      final relativeZ = point.z - centerZ;

      return ARPoint(
        x: centerX + relativeX * cosine - relativeZ * sine,
        y: point.y,
        z: centerZ + relativeX * sine + relativeZ * cosine,
      );
    }

    return room.copyWith(
      points: room.points.map(rotatePoint).toList(),
      features: room.features
          .map(
            (feature) => feature.copyWith(
              start: rotatePoint(feature.start),
              end: rotatePoint(feature.end),
            ),
          )
          .toList(),
    );
  }

  Set<String> _connectedRoomIds(String initialRoomId) {
    if (!_completedRooms.any((room) => room.id == initialRoomId)) {
      return <String>{};
    }

    final knownRoomIds = _completedRooms.map((room) => room.id).toSet();
    final connectedIds = <String>{initialRoomId};
    final pending = <String>[initialRoomId];

    while (pending.isNotEmpty) {
      final currentId = pending.removeLast();
      final room = _completedRooms.firstWhere(
        (candidate) => candidate.id == currentId,
      );

      for (final feature in room.features) {
        final connectedRoomId = feature.connectedRoomId;

        if (connectedRoomId == null ||
            !knownRoomIds.contains(connectedRoomId) ||
            !connectedIds.add(connectedRoomId)) {
          continue;
        }

        pending.add(connectedRoomId);
      }
    }

    return connectedIds;
  }

  // ===========================================================================
  // PUERTAS Y VENTANAS
  // ===========================================================================

  /// Busca una puerta o ventana persistida dentro de un ambiente.
  ///
  /// La búsqueda utiliza los identificadores estables del proyecto y no
  /// depende de coordenadas de pantalla ni de una sesión AR determinada.
  WallFeature? findFeature({
    required String roomId,
    required String featureId,
  }) {
    final roomIndex =
        _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );

    if (roomIndex == -1) {
      return null;
    }

    final room =
        _completedRooms[roomIndex];

    for (final feature in room.features) {
      if (feature.id == featureId) {
        return feature;
      }
    }

    return null;
  }

  /// Actualiza la representación de una puerta en todos los ambientes que
  /// comparten su identificador y la persiste como una única abertura.
  Future<bool> updateDoorOrientation({
    required String featureId,
    DoorHingeSide? hingeSide,
    DoorSwingSide? swingSide,
    DoorOpeningDirection? openingDirection,
  }) async {
    var changed = false;

    for (var roomIndex = 0;
        roomIndex < _completedRooms.length;
        roomIndex++) {
      final room = _completedRooms[roomIndex];
      final featureIndex = room.features.indexWhere(
        (feature) =>
            feature.id == featureId &&
            feature.type == FeatureType.door,
      );

      if (featureIndex == -1) {
        continue;
      }

      final features = List<WallFeature>.from(room.features);
      final feature = features[featureIndex];
      features[featureIndex] = feature.copyWith(
        doorHingeSide: hingeSide,
        doorSwingSide: swingSide,
        doorOpeningDirection: openingDirection,
      );
      _completedRooms[roomIndex] = room.copyWith(
        features: features,
      );
      changed = true;
    }

    if (!changed) {
      return false;
    }

    notifyListeners();
    await _persist();
    return true;
  }

  OpeningPlacement? getOpeningPlacement({
    required String roomId,
    required String featureId,
  }) {
    final roomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (roomIndex == -1) return null;

    final room = _completedRooms[roomIndex];
    final feature = findFeature(
      roomId: roomId,
      featureId: featureId,
    );
    if (feature == null) return null;

    final wall = _nearestWallProjection(room.points, feature);
    if (wall == null) return null;

    final first = wall.projection(feature.start);
    final second = wall.projection(feature.end);
    return OpeningPlacement(
      widthMeters: GeometryService.calculateDistance(
        feature.start,
        feature.end,
      ),
      distanceFromWallStartMeters:
          math.min(first, second) * wall.length,
      wallLengthMeters: wall.length,
      openingHeightMeters: feature.openingHeightMeters,
      sillHeightMeters: feature.sillHeightMeters,
    );
  }

  /// Edita el ancho y la posición sin sacar la abertura de su pared.
  /// También actualiza cualquier copia compartida que conserve el mismo ID.
  Future<OpeningGeometryUpdateResult> updateOpeningGeometry({
    required String roomId,
    required String featureId,
    required double widthMeters,
    required double distanceFromWallStartMeters,
    double? openingHeightMeters,
    double? sillHeightMeters,
  }) async {
    if (!widthMeters.isFinite || widthMeters < 0.20) {
      return const OpeningGeometryUpdateResult.invalid(
        'El ancho debe ser de al menos 0,20 metros.',
      );
    }
    if (!distanceFromWallStartMeters.isFinite ||
        distanceFromWallStartMeters < 0) {
      return const OpeningGeometryUpdateResult.invalid(
        'La distancia desde la esquina no puede ser negativa.',
      );
    }
    if (openingHeightMeters != null &&
        (!openingHeightMeters.isFinite ||
            openingHeightMeters < 0.20)) {
      return const OpeningGeometryUpdateResult.invalid(
        'La altura debe ser de al menos 0,20 metros.',
      );
    }
    if (sillHeightMeters != null &&
        (!sillHeightMeters.isFinite || sillHeightMeters < 0)) {
      return const OpeningGeometryUpdateResult.invalid(
        'La altura desde el piso no puede ser negativa.',
      );
    }

    final roomIndex = _completedRooms.indexWhere(
      (room) => room.id == roomId,
    );
    if (roomIndex == -1) {
      return const OpeningGeometryUpdateResult.invalid(
        'El ambiente seleccionado ya no está disponible.',
      );
    }

    final room = _completedRooms[roomIndex];
    final featureIndex = room.features.indexWhere(
      (feature) => feature.id == featureId,
    );
    if (featureIndex == -1) {
      return const OpeningGeometryUpdateResult.invalid(
        'La abertura seleccionada ya no está disponible.',
      );
    }

    final feature = room.features[featureIndex];
    final wall = _nearestWallProjection(room.points, feature);
    if (wall == null) {
      return const OpeningGeometryUpdateResult.invalid(
        'No se pudo identificar la pared de la abertura.',
      );
    }

    final openingEndDistance =
        distanceFromWallStartMeters + widthMeters;
    if (openingEndDistance > wall.length + 0.000001) {
      return OpeningGeometryUpdateResult.invalid(
        'La abertura termina fuera de la pared de '
        '${_formatLength(wall.length)}.',
      );
    }

    final startT = distanceFromWallStartMeters / wall.length;
    final endT = openingEndDistance / wall.length;
    for (final existing in room.features) {
      if (existing.id == featureId ||
          !wall.contains(existing.start) ||
          !wall.contains(existing.end)) {
        continue;
      }

      final existingStart = math.min(
            wall.projection(existing.start),
            wall.projection(existing.end),
          ) *
          wall.length;
      final existingEnd = math.max(
            wall.projection(existing.start),
            wall.projection(existing.end),
          ) *
          wall.length;
      const minimumSeparation = 0.02;
      final overlaps = distanceFromWallStartMeters <
              existingEnd - minimumSeparation &&
          existingStart < openingEndDistance - minimumSeparation;
      if (overlaps) {
        return const OpeningGeometryUpdateResult.invalid(
          'La abertura se superpone con otra puerta o ventana.',
        );
      }
    }

    final preservesDirection = wall.projection(feature.start) <=
        wall.projection(feature.end);
    final lowerPoint = wall.pointAt(startT);
    final upperPoint = wall.pointAt(endT);
    final updatedStart = preservesDirection ? lowerPoint : upperPoint;
    final updatedEnd = preservesDirection ? upperPoint : lowerPoint;
    var changed = false;

    for (var index = 0;
        index < _completedRooms.length;
        index++) {
      final candidateRoom = _completedRooms[index];
      final candidateFeatureIndex = candidateRoom.features.indexWhere(
        (candidate) => candidate.id == featureId,
      );
      if (candidateFeatureIndex == -1) continue;

      final features = List<WallFeature>.from(candidateRoom.features);
      features[candidateFeatureIndex] =
          features[candidateFeatureIndex].copyWith(
        start: updatedStart,
        end: updatedEnd,
        openingHeightMeters: openingHeightMeters,
        sillHeightMeters: sillHeightMeters,
      );
      _completedRooms[index] = candidateRoom.copyWith(
        features: features,
      );
      changed = true;
    }

    if (!changed) {
      return const OpeningGeometryUpdateResult.invalid(
        'No se pudo actualizar la abertura.',
      );
    }

    notifyListeners();
    await _persist();
    return const OpeningGeometryUpdateResult.success();
  }

  _WallProjection? _nearestWallProjection(
    List<ARPoint> points,
    WallFeature feature,
  ) {
    if (points.length < 2) return null;

    final midpoint = ARPoint(
      x: (feature.start.x + feature.end.x) / 2,
      y: (feature.start.y + feature.end.y) / 2,
      z: (feature.start.z + feature.end.z) / 2,
    );
    _WallProjection? nearest;
    var nearestDistanceSquared = double.infinity;

    for (var index = 0; index < points.length; index++) {
      final candidate = _WallProjection.create(
        points[index],
        points[(index + 1) % points.length],
      );
      if (candidate == null) continue;

      final projected = candidate.pointAt(
        candidate.projection(midpoint),
      );
      final dx = midpoint.x - projected.x;
      final dz = midpoint.z - projected.z;
      final distanceSquared = dx * dx + dz * dz;
      if (distanceSquared < nearestDistanceSquared) {
        nearestDistanceSquared = distanceSquared;
        nearest = candidate;
      }
    }
    return nearest;
  }

  /// Construye la referencia común que utilizarán el plano 2D, Basic Scanner,
  /// ARCore y ARKit para continuar el relevamiento desde una abertura.
  ///
  /// Devuelve `null` si el ambiente o la abertura ya no existen. Esto evita
  /// iniciar un escaneo con una selección desactualizada.
  ScanContinuationReference? createContinuationReference({
    required String roomId,
    required String featureId,
    required OpeningConnectionSide side,
    required ContinuationStartEndpoint startEndpoint,
  }) {
    final feature = findFeature(
      roomId: roomId,
      featureId: featureId,
    );

    if (feature == null) {
      return null;
    }

    return ScanContinuationReference.fromFeature(
      sourceRoomId: roomId,
      feature: feature,
      side: side,
      startEndpoint: startEndpoint,
    );
  }
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
    final feature =        WallFeature(
      id: _nextUniqueId(),
      type: type,
      start: startLocation,
      end: end,
    );

    final features =
        List<WallFeature>.from(
      room.features,
    )..add(feature);

    _completedRooms[index] =        room.copyWith(
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
  }  // ===========================================================================
  // REAJUSTE DE ABERTURAS
  // ===========================================================================

  _FeatureRemapResult _remapFeatures({
    required List<WallFeature> features,
    required List<ARPoint> originalPoints,
    required List<ARPoint> updatedPoints,
  }) {
    if (features.isEmpty) {
      return const _FeatureRemapResult(
        features: [],
      );
    }

    final remapped =
        <WallFeature>[];

    for (final feature
        in features) {
      final midpoint =
          ARPoint(
        x:
            (feature.start.x +
                    feature.end.x) /
                2.0,
        y:
            (feature.start.y +
                    feature.end.y) /
                2.0,        z:
            (feature.start.z +
                    feature.end.z) /
                2.0,
      );

      int nearestWallIndex =          -1;

      double nearestDistanceSquared =
          double.infinity;

      double originalCenterT =
          0.0;

      for (int index = 0;
          index <
              originalPoints.length;
          index++) {
        final start =            originalPoints[index];

        final end =
            originalPoints[
              (index + 1) %
                  originalPoints.length
            ];

        final dx =
            end.x - start.x;

        final dz =
            end.z - start.z;

        final lengthSquared =
            dx * dx + dz * dz;

        if (lengthSquared <=
            0.000001) {
          continue;
        }

        final rawT =
            ((midpoint.x - start.x) * dx +
                    (midpoint.z - start.z) * dz) /
                lengthSquared;

        final projectedT =
            rawT.clamp(0.0, 1.0)
                .toDouble();

        final projectedX =
            start.x +
                dx * projectedT;

        final projectedZ =
            start.z +
                dz * projectedT;

        final distanceX =
            midpoint.x -
                projectedX;

        final distanceZ =
            midpoint.z -
                projectedZ;

        final distanceSquared =
            distanceX * distanceX +
                distanceZ * distanceZ;

        if (distanceSquared <
            nearestDistanceSquared) {
          nearestDistanceSquared =
              distanceSquared;

          nearestWallIndex =
              index;

          originalCenterT =
              projectedT;
        }
      }

      if (nearestWallIndex < 0) {
        return const _FeatureRemapResult(
          errorMessage:
              'No se pudo identificar la pared de una abertura.',
        );
      }

      final featureWidth =
          GeometryService
              .calculateDistance(
        feature.start,
        feature.end,
      );

      final newWallStart =
          updatedPoints[
            nearestWallIndex
          ];

      final newWallEnd =
          updatedPoints[
            (nearestWallIndex + 1) %
                updatedPoints.length
          ];

      final newDx =
          newWallEnd.x -
              newWallStart.x;

      final newDz =
          newWallEnd.z -
              newWallStart.z;

      final newWallLength =
          math.sqrt(
        newDx * newDx +
            newDz * newDz,
      );

      if (newWallLength <=
          0.000001) {
        return const _FeatureRemapResult(
          errorMessage:
              'La edición genera una pared sin longitud.',
        );
      }

      if (featureWidth >
          newWallLength +
              0.000001) {
        return _FeatureRemapResult(
          errorMessage:
              'La nueva pared es más corta que una puerta o ventana '
              'de ${_formatLength(featureWidth)}.',
        );
      }

      final featureFraction =
          featureWidth /
              newWallLength;

      final maximumStartT =
          1.0 -
              featureFraction;

      final startT =
          (originalCenterT -
                  featureFraction / 2.0)
              .clamp(
                0.0,
                maximumStartT,
              )
              .toDouble();
      final endT =
          startT +
              featureFraction;

      ARPoint pointAt(
        double t,
      ) {
        return ARPoint(
          x:
              newWallStart.x +
                  newDx * t,
          y:
              newWallStart.y +
                  (newWallEnd.y -
                          newWallStart.y) *
                      t,
          z:
              newWallStart.z +
                  newDz * t,
        );
      }

      remapped.add(
        feature.copyWith(
          start:
              pointAt(startT),
          end:
              pointAt(endT),
        ),
      );
    }

    return _FeatureRemapResult(
      features: remapped,
    );
  }

  String _formatLength(
    double meters,
  ) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: 'metros',
      feetLabel: 'pies',
      inchesLabel: 'pulgadas',
      decimalSeparator: ',',
    );
  }

  // ===========================================================================
  // EDITOR DE MEDIDAS
  // ===========================================================================

  Future<ValidationResult>      updateWallLength({
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

    final remappedFeatures =
        _remapFeatures(
      features:
          room.features,
      originalPoints:
          originalPoints,
      updatedPoints:
          points,
    );

    if (!remappedFeatures.isValid) {
      return ValidationResult.invalid(
        remappedFeatures.errorMessage ??
            'No se pudieron reajustar las aberturas.',
      );
    }

    _completedRooms[
            resolvedRoomIndex] =
        room.copyWith(
      points: points,
      features:
          remappedFeatures.features,
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
    _clearTransformHistory();
    _projectName =
        'Mi Casa Completa';

    notifyListeners();
  }
}

class _TransformHistoryEntry {
  final List<RoomModel> before;
  final List<RoomModel> after;

  const _TransformHistoryEntry({
    required this.before,
    required this.after,
  });
}

class _WallAlignmentCandidate {
  final double centerX;
  final double centerZ;
  final double rotationRadians;
  final double offsetX;
  final double offsetZ;
  final double score;

  const _WallAlignmentCandidate({
    required this.centerX,
    required this.centerZ,
    required this.rotationRadians,
    required this.offsetX,
    required this.offsetZ,
    required this.score,
  });
}

class _FeatureRemapResult {
  final List<WallFeature> features;
  final String? errorMessage;

  const _FeatureRemapResult({
    this.features = const [],
    this.errorMessage,
  });

  bool get isValid =>
      errorMessage == null;
}

class _RoomNormalizationResult {
  final List<RoomModel> rooms;

  final bool changed;

  const _RoomNormalizationResult({
    required this.rooms,
    required this.changed,
  });
}

class OpeningPlacement {
  final double widthMeters;
  final double distanceFromWallStartMeters;
  final double wallLengthMeters;
  final double openingHeightMeters;
  final double sillHeightMeters;

  const OpeningPlacement({
    required this.widthMeters,
    required this.distanceFromWallStartMeters,
    required this.wallLengthMeters,
    required this.openingHeightMeters,
    required this.sillHeightMeters,
  });
}

class OpeningGeometryUpdateResult {
  final bool isSuccess;
  final String? errorMessage;

  const OpeningGeometryUpdateResult.success()
      : isSuccess = true,
        errorMessage = null;

  const OpeningGeometryUpdateResult.invalid(this.errorMessage)
      : isSuccess = false;}

class _WallProjection {
  final ARPoint start;
  final ARPoint end;
  final double dx;
  final double dz;
  final double lengthSquared;
  final double length;

  const _WallProjection._({
    required this.start,
    required this.end,
    required this.dx,
    required this.dz,
    required this.lengthSquared,
    required this.length,
  });

  static _WallProjection? create(ARPoint start, ARPoint end) {
    final dx = end.x - start.x;
    final dz = end.z - start.z;
    final lengthSquared = dx * dx + dz * dz;
    if (lengthSquared <= 0.000001) return null;

    return _WallProjection._(
      start: start,
      end: end,
      dx: dx,
      dz: dz,
      lengthSquared: lengthSquared,
      length: math.sqrt(lengthSquared),
    );
  }

  double projection(ARPoint point) {
    return (((point.x - start.x) * dx +
                (point.z - start.z) * dz) /
            lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  ARPoint pointAt(double t) {
    return ARPoint(
      x: start.x + dx * t,
      y: start.y + (end.y - start.y) * t,
      z: start.z + dz * t,
    );
  }

  bool contains(ARPoint point) {
    final rawProjection =
        ((point.x - start.x) * dx +
                (point.z - start.z) * dz) /
            lengthSquared;
    if (rawProjection < -0.01 || rawProjection > 1.01) {
      return false;
    }

    final projected = pointAt(rawProjection);
    final distanceX = point.x - projected.x;
    final distanceZ = point.z - projected.z;
    return distanceX * distanceX + distanceZ * distanceZ <=
        0.0025;
  }
}