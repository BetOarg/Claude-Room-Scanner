import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import '../utils/measurement_units.dart';
import '../utils/scan_validator.dart';

/// Estado de la sesión de escaneo activa.
///
/// Mantiene la habitación en curso y las habitaciones cerradas durante
/// la sesión. Cada punto nuevo se valida antes de incorporarse.
class ScannerProvider extends ChangeNotifier {
  MeasurementSystem measurementSystem =
      MeasurementSystem.metric;

  final List<RoomModel> _rooms = [];

  RoomModel? _currentRoom;
  RoomType _selectedType = RoomType.living;
  bool _hasCustomRoomName = false;
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
        name: _hasCustomRoomName
            ? _currentRoom!.name
            : _getRoomTypeName(type),
      );
    }

    notifyListeners();
  }

  /// Cambia el nombre visible del ambiente sin alterar su tipo técnico.
  ///
  /// El nombre personalizado se conserva aunque después se cambie el tipo.
  void setCurrentRoomName(
    String name,
  ) {
    final normalized =
        name.trim();

    if (_currentRoom == null ||
        normalized.isEmpty ||
        _currentRoom!.name == normalized) {
      return;
    }

    _hasCustomRoomName = true;

    _currentRoom =
        _currentRoom!.copyWith(
      name: normalized,
    );

    notifyListeners();
  }

  /// Inicia un ambiente nuevo con un ID resistente a colisiones.
  void startNewRoom({
    List<ARPoint> initialPoints = const <ARPoint>[],
    List<WallFeature> initialFeatures = const <WallFeature>[],
  }) {
    _hasCustomRoomName = false;

    _currentRoom = RoomModel(
      id: _nextUniqueId(),
      name:
          _getRoomTypeName(
        _selectedType,
      ),
      type: _selectedType,
      points: List<ARPoint>.from(initialPoints),
      features: List<WallFeature>.from(initialFeatures),
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

  /// Agrega una puerta o ventana sobre la pared medida más cercana.
  ///
  /// Basic Scanner utiliza [widthMeters] y una ubicación central aproximada.
  /// ARCore/ARKit utilizan [endLocation] para medir los dos extremos mediante
  /// la cámara. Ambos caminos producen el mismo WallFeature persistente.
  ValidationResult addFeatureToCurrentRoom(
    FeatureType type,
    ARPoint location, {
    double? widthMeters,
    ARPoint? endLocation,
    int? preferredWallIndex,
  }) {
    final room =
        _currentRoom;

    if (room == null) {
      return ValidationResult.invalid(
        'No hay un ambiente en curso.',
      );
    }

    final points =
        room.points;

    if (points.length < 2) {
      return ValidationResult.invalid(
        'Medí al menos una pared antes de agregar una abertura.',
      );
    }

    final isCameraMeasurement =
        endLocation != null;

    if (!isCameraMeasurement &&
        (widthMeters == null ||
            !widthMeters.isFinite ||
            widthMeters < 0.20)) {
      return ValidationResult.invalid(
        'Ingresá un ancho mínimo de '
        '${_formatLength(0.20)}.',
      );
    }

    final referencePoint =
        isCameraMeasurement
            ? ARPoint(
                x:
                    (location.x +
                            endLocation!.x) /
                        2.0,
                y:
                    (location.y +
                            endLocation!.y) /
                        2.0,
                z:
                    (location.z +
                            endLocation!.z) /
                        2.0,
              )
            : location;

    int nearestWallIndex = -1;
    double nearestDistanceSquared =
        double.infinity;

    // Con tres o más esquinas también existe el tramo de cierre entre la
    // última esquina y la primera. Debe participar antes de cerrar el ambiente
    // para poder colocar puertas o ventanas sobre esa pared.
    final wallCount = points.length >= 3
        ? points.length
        : points.length - 1;

    if (preferredWallIndex != null &&
        (preferredWallIndex < 0 ||
            preferredWallIndex >= wallCount)) {
      return ValidationResult.invalid(
        'La pared seleccionada no es válida.',
      );
    }

    for (int index = 0;
        index < wallCount;
        index++) {
      if (preferredWallIndex != null &&
          index != preferredWallIndex) {
        continue;
      }
      final start =
          points[index];

      final end =
          points[(index + 1) % points.length];

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
          ((referencePoint.x - start.x) * dx +
                  (referencePoint.z - start.z) * dz) /
              lengthSquared;

      final projectedT =
          rawT.clamp(0.0, 1.0)
              .toDouble();

      final projectedX =
          start.x + dx * projectedT;

      final projectedZ =
          start.z + dz * projectedT;

      final distanceX =
          referencePoint.x -
              projectedX;

      final distanceZ =
          referencePoint.z -
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
      }
    }

    if (nearestWallIndex < 0) {
      return ValidationResult.invalid(
        'No se encontró una pared válida.',
      );
    }

    final wallStart =
        points[nearestWallIndex];

    final wallEnd =
        points[(nearestWallIndex + 1) % points.length];

    final wallDx =
        wallEnd.x - wallStart.x;

    final wallDz =
        wallEnd.z - wallStart.z;

    final wallLengthSquared =
        wallDx * wallDx +
            wallDz * wallDz;

    final wallLength =
        math.sqrt(
      wallLengthSquared,
    );

    if (wallLength <=
        0.000001) {
      return ValidationResult.invalid(
        'La pared seleccionada no tiene una longitud válida.',
      );
    }

    double projectToWall(
      ARPoint point,
    ) {
      return (((point.x - wallStart.x) * wallDx +
                  (point.z - wallStart.z) * wallDz) /
              wallLengthSquared)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    late double startT;
    late double endT;
    late double measuredWidth;

    if (isCameraMeasurement) {
      final firstT =
          projectToWall(
        location,
      );

      final secondT =
          projectToWall(
        endLocation!,
      );

      startT =
          math.min(
        firstT,
        secondT,
      ).toDouble();

      endT =
          math.max(
        firstT,
        secondT,
      ).toDouble();

      measuredWidth =          (endT - startT) *
              wallLength;

      if (measuredWidth <
          0.20) {
        return ValidationResult.invalid(
          'Los dos puntos de la abertura están demasiado cerca. '
          'Medida detectada: '
          '${_formatLength(measuredWidth)}.',
        );
      }
    } else {
      measuredWidth =
          widthMeters!;

      if (measuredWidth >
          wallLength) {
        return ValidationResult.invalid(
          'La abertura mide '
          '${_formatLength(measuredWidth)}, '
          'pero la pared mide '
          '${_formatLength(wallLength)}.',
        );
      }

      final centerT =
          projectToWall(
        location,
      );

      final fraction =
          measuredWidth /
              wallLength;

      final maximumStartT =
          1.0 - fraction;

      startT =
          (centerT -
                  fraction / 2.0)
              .clamp(
                0.0,
                maximumStartT,
              )
              .toDouble();

      endT =
          startT +
              fraction;
    }

    final featureStart =
        ARPoint(
      x:
          wallStart.x +
              wallDx * startT,
      y:
          wallStart.y +
              (wallEnd.y -
                      wallStart.y) *
                  startT,
      z:
          wallStart.z +
              wallDz * startT,
    );

    final featureEnd =
        ARPoint(
      x:
          wallStart.x +
              wallDx * endT,
      y:
          wallStart.y +
              (wallEnd.y -
                      wallStart.y) *
                  endT,
      z:
          wallStart.z +
              wallDz * endT,
    );

    // Impide que dos aberturas ocupen el mismo tramo de pared.
    for (final existing
        in room.features) {
      double rawProjection(
        ARPoint point,
      ) {
        return ((point.x - wallStart.x) * wallDx +
                (point.z - wallStart.z) * wallDz) /
            wallLengthSquared;
      }

      bool belongsToWall(
        ARPoint point,
      ) {
        final rawT =
            rawProjection(point);

        if (rawT < -0.01 ||
            rawT > 1.01) {
          return false;
        }

        final projectedX =
            wallStart.x +
                wallDx * rawT;

        final projectedZ =
            wallStart.z +
                wallDz * rawT;

        final distanceX =
            point.x -
                projectedX;

        final distanceZ =
            point.z -
                projectedZ;

        return distanceX * distanceX +
                distanceZ * distanceZ <=
            0.0025;
      }

      if (!belongsToWall(
            existing.start,
          ) ||
          !belongsToWall(
            existing.end,
          )) {
        continue;
      }

      final existingStartT =
          rawProjection(
        existing.start,
      ).clamp(0.0, 1.0)
              .toDouble();

      final existingEndT =
          rawProjection(
        existing.end,
      ).clamp(0.0, 1.0)
              .toDouble();

      final existingMinT =          math.min(
        existingStartT,
        existingEndT,
      ).toDouble();

      final existingMaxT =
          math.max(
        existingStartT,
        existingEndT,
      ).toDouble();

      const separation =
          0.02;

      final overlaps =
          startT <
                  existingMaxT -
                      separation &&
              existingMinT <
                  endT -
                      separation;

      if (overlaps) {
        return ValidationResult.invalid(
          'La abertura se superpone con otra puerta o ventana. '
          'Elegí otra posición sobre la pared.',
        );
      }
    }

    final feature =
        WallFeature(
      id: _nextUniqueId(),
      type: type,
      start: featureStart,
      end: featureEnd,
    );

    final updatedFeatures =
        List<WallFeature>.from(
      room.features,
    )..add(feature);

    _currentRoom =
        room.copyWith(
      features: updatedFeatures,
    );

    notifyListeners();
    return ValidationResult.warning(
      'Abertura medida: '
      '${_formatLength(measuredWidth)}.',
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
    return type.displayName;
  }
}