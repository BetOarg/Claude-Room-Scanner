import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

void main() {
  group('transformación rígida de ambientes', () {
    test('traslada como una unidad dos ambientes conectados', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-transform',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 5,
        offsetZ: -2,
      );

      final roomA = provider.completedRooms
          .firstWhere((room) => room.id == 'room-a');
      final roomB = provider.completedRooms
          .firstWhere((room) => room.id == 'room-b');
      final featureA = roomA.features.single;
      final featureB = roomB.features.single;

      expect(roomA.points.first.x, closeTo(5, 0.000001));
      expect(roomA.points.first.z, closeTo(-2, 0.000001));
      expect(roomB.points.first.x, closeTo(7, 0.000001));
      expect(roomB.points.first.z, closeTo(-2, 0.000001));
      _expectSameFeatureGeometry(featureA, featureB);
    });

    test('rota el grupo y conserva longitudes y abertura compartida', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-rotation',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );
      final before = provider.completedRooms;
      final wallLengthBefore = GeometryService.calculateDistance(
        before.first.points[0],
        before.first.points[1],
      );

      await provider.rotateRoom(
        roomId: 'room-a',
        angleDegrees: 90,
      );

      final roomA = provider.completedRooms
          .firstWhere((room) => room.id == 'room-a');
      final roomB = provider.completedRooms
          .firstWhere((room) => room.id == 'room-b');
      final wallLengthAfter = GeometryService.calculateDistance(
        roomA.points[0],
        roomA.points[1],
      );

      expect(wallLengthAfter, closeTo(wallLengthBefore, 0.000001));
      expect(
        GeometryService.calculateArea(roomA.points),
        closeTo(4, 0.000001),
      );
      expect(
        GeometryService.calculateArea(roomB.points),
        closeTo(4, 0.000001),
      );
      _expectSameFeatureGeometry(
        roomA.features.single,
        roomB.features.single,
      );
    });

    test('no transforma ambientes que no pertenecen al grupo', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(
          RoomModel(
            id: 'room-c',
            name: 'Independiente',
            type: RoomType.dormitorio,
            points: [
              ARPoint(x: 10, y: 0, z: 10),
              ARPoint(x: 12, y: 0, z: 10),
              ARPoint(x: 12, y: 0, z: 12),
              ARPoint(x: 10, y: 0, z: 12),
            ],
            isClosed: true,
          ),
        );
      provider.loadProject(
        uuid: 'project-independent',
        name: 'Tres ambientes',
        rooms: rooms,
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 3,
        offsetZ: 4,
      );

      final roomC = provider.completedRooms
          .firstWhere((room) => room.id == 'room-c');
      expect(roomC.points.first.x, closeTo(10, 0.000001));
      expect(roomC.points.first.z, closeTo(10, 0.000001));
    });

    test('sincroniza interior o exterior en una puerta compartida', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-door-opening',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );

      final updated = await provider.updateDoorOrientation(
        featureId: 'shared-door',
        openingDirection: DoorOpeningDirection.exterior,
      );

      expect(updated, isTrue);
      for (final room in provider.completedRooms) {
        expect(
          room.features.single.doorOpeningDirection,
          DoorOpeningDirection.exterior,
        );
      }
    });
  });
}

List<RoomModel> _connectedRooms() {
  final sharedA = WallFeature(
    id: 'shared-door',
    type: FeatureType.door,
    start: ARPoint(x: 2, y: 0, z: 0.5),
    end: ARPoint(x: 2, y: 0, z: 1.5),
    connectedRoomId: 'room-b',
    connectionSide: OpeningConnectionSide.right,
  );
  final sharedB = sharedA.copyWith(
    connectedRoomId: 'room-a',
    connectionSide: OpeningConnectionSide.left,
  );

  return [
    RoomModel(
      id: 'room-a',
      name: 'Ambiente A',
      type: RoomType.living,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 2, y: 0, z: 2),
        ARPoint(x: 0, y: 0, z: 2),
      ],
      features: [sharedA],
      isClosed: true,
    ),
    RoomModel(
      id: 'room-b',
      name: 'Ambiente B',
      type: RoomType.cocina,
      points: [
        ARPoint(x: 2, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 0),
        ARPoint(x: 4, y: 0, z: 2),
        ARPoint(x: 2, y: 0, z: 2),
      ],
      features: [sharedB],
      isClosed: true,
    ),
  ];
}

void _expectSameFeatureGeometry(
  WallFeature first,
  WallFeature second,
) {
  expect(first.id, second.id);
  expect(first.start.x, closeTo(second.start.x, 0.000001));
  expect(first.start.z, closeTo(second.start.z, 0.000001));
  expect(first.end.x, closeTo(second.end.x, 0.000001));
  expect(first.end.z, closeTo(second.end.z, 0.000001));
}
