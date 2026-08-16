import 'dart:math' as math;

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
        'Ingresá un ancho mínimo de 0,20 m.',
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

    for (int index = 0;
        index < points.length - 1;
        index++) {
      final start =
          points[index];

      final end =
          points[index + 1];

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
        points[nearestWallIndex + 1];

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

      measuredWidth =
          (endT - startT) *
              wallLength;

      if (measuredWidth <
          0.20) {
        return ValidationResult.invalid(
          'Los dos puntos de la abertura están demasiado cerca. '
          'Medida detectada: '
          '${measuredWidth.toStringAsFixed(2)} m.',
        );
      }
    } else {
      measuredWidth =
          widthMeters!;

      if (measuredWidth >
          wallLength) {
        return ValidationResult.invalid(
          'La abertura mide '
          '${measuredWidth.toStringAsFixed(2)} m, '
          'pero la pared mide '
          '${wallLength.toStringAsFixed(2)} m.',
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
      '${measuredWidth.toStringAsFixed(2)} m.',
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