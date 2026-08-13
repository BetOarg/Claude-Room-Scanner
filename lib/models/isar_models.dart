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
enum IsarRoomType { living, cocina, bano, dormitorio, lavadero, pasillo }

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
}

enum IsarFeatureType { door, window }

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
      ..end = end.toIsar();
  }
}

extension IsarWallFeatureMapper on IsarWallFeature {
  WallFeature toDomain() {
    return WallFeature(
      id: id ?? '',
      type: type == IsarFeatureType.door ? FeatureType.door : FeatureType.window,
      start: start.toDomain(),
      end: end.toDomain(),
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