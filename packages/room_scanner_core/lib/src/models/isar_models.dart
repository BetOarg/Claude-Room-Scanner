import 'package:isar/isar.dart';

import 'room_model.dart';

part 'isar_models.g.dart';

/// Colección Principal de Proyectos
@collection
class IsarProject {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  late String name;
  late DateTime createdAt;
  late DateTime updatedAt;

  final rooms = IsarLinks<IsarRoom>();
}

/// Colección de Habitaciones / Ambientes
@collection
class IsarRoom {
  Id id = Isar.autoIncrement;

  late String roomId;
  late String name;

  @enumerated
  IsarRoomType type = IsarRoomType.living;

  List<IsarARPoint> points = [];
  List<IsarWallFeature> features = [];

  bool isClosed = false;

  @Backlink(to: 'rooms')
  final project = IsarLink<IsarProject>();
}

/// Tipo de Habitación
enum IsarRoomType {
  // Mantener el orden histórico para no alterar datos existentes.
  living,
  cocina,
  bano,
  dormitorio,
  lavadero,
  pasillo,

  // Nuevos tipos al final.
  comedor,
  comedorDiario,
  patio,
  hall,
  balcon,
  terraza,
  cochera,
  playroom,
  other,
}

/// Objeto Embebido: Punto AR 3D
@embedded
class IsarARPoint {
  double x;
  double y;
  double z;

  IsarARPoint({this.x = 0.0, this.y = 0.0, this.z = 0.0});
}

/// Objeto Embebido: Elemento (Puerta / Ventana)
@embedded
class IsarWallFeature {
  String? id;

  @enumerated
  IsarFeatureType type = IsarFeatureType.door;

  late IsarARPoint start;
  late IsarARPoint end;

  @enumerated
  IsarDoorHingeSide doorHingeSide = IsarDoorHingeSide.start;

  @enumerated
  IsarDoorSwingSide doorSwingSide = IsarDoorSwingSide.left;

  @enumerated
  IsarDoorOpeningDirection doorOpeningDirection =
      IsarDoorOpeningDirection.interior;

  double? openingHeightMeters;
  double? sillHeightMeters;
}

enum IsarFeatureType { door, window }
enum IsarDoorHingeSide { start, end }
enum IsarDoorSwingSide { left, right }
enum IsarDoorOpeningDirection { interior, exterior }

// ==========================================
// MAPEADORES DE CONVERSIÓN CON ROOMMODEL
// ==========================================

extension ARPointIsarMapper on ARPoint {
  IsarARPoint toIsar() => IsarARPoint(x: x, y: y, z: z);
}

extension IsarARPointMapper on IsarARPoint {
  ARPoint toDomain() => ARPoint(x: x, y: y, z: z);
}

extension WallFeatureIsarMapper on WallFeature {
  IsarWallFeature toIsar() {
    return IsarWallFeature()
      ..id = id
      ..type = type == FeatureType.door ? IsarFeatureType.door : IsarFeatureType.window
      ..start = start.toIsar()
      ..end = end.toIsar()
      ..doorHingeSide = doorHingeSide == DoorHingeSide.start
          ? IsarDoorHingeSide.start
          : IsarDoorHingeSide.end
      ..doorSwingSide = doorSwingSide == DoorSwingSide.left
          ? IsarDoorSwingSide.left
          : IsarDoorSwingSide.right
      ..doorOpeningDirection =
          doorOpeningDirection == DoorOpeningDirection.interior
              ? IsarDoorOpeningDirection.interior
              : IsarDoorOpeningDirection.exterior
      ..openingHeightMeters = openingHeightMeters
      ..sillHeightMeters = sillHeightMeters;
  }
}

extension IsarWallFeatureMapper on IsarWallFeature {
  WallFeature toDomain() {
    return WallFeature(
      id: id ?? '',
      type: type == IsarFeatureType.door ? FeatureType.door : FeatureType.window,
      start: start.toDomain(),
      end: end.toDomain(),
      doorHingeSide: doorHingeSide == IsarDoorHingeSide.start
          ? DoorHingeSide.start
          : DoorHingeSide.end,
      doorSwingSide: doorSwingSide == IsarDoorSwingSide.left
          ? DoorSwingSide.left
          : DoorSwingSide.right,
      doorOpeningDirection:
          doorOpeningDirection == IsarDoorOpeningDirection.interior
              ? DoorOpeningDirection.interior
              : DoorOpeningDirection.exterior,
      openingHeightMeters: openingHeightMeters,
      sillHeightMeters: sillHeightMeters,
    );
  }
}

extension RoomModelIsarMapper on RoomModel {
  IsarRoom toIsar() {
    return IsarRoom()
      ..roomId = id
      ..name = name
      ..type = IsarRoomType.values.firstWhere(
        (e) => e.name == type.name,
        orElse: () => IsarRoomType.living,
      )
      ..points = points.map((p) => p.toIsar()).toList()
      ..features = features.map((f) => f.toIsar()).toList()
      ..isClosed = isClosed;
  }
}

extension IsarRoomMapper on IsarRoom {
  RoomModel toDomain() {
    return RoomModel(
      id: roomId,
      name: name,
      type: RoomType.values.firstWhere(
        (e) => e.name == type.name,
        orElse: () => RoomType.living,
      ),
      points: points.map((p) => p.toDomain()).toList(),
      features: features.map((f) => f.toDomain()).toList(),
      isClosed: isClosed,
    );
  }
}