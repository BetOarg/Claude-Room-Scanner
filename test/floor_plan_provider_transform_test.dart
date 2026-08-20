import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/models/room_model.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';
import 'package:room_scanner_ar/services/geometry_service.dart';

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

    test('deshace y rehace movimientos y giros en orden', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-history',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );
      final originalFirstPoint = provider.completedRooms.first.points.first;

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 3,
        offsetZ: -1,
      );
      final translatedFirstPoint =
          provider.completedRooms.first.points.first;
      await provider.rotateRoom(
        roomId: 'room-a',
        angleDegrees: 90,
      );
      final rotatedFirstPoint = provider.completedRooms.first.points.first;

      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(translatedFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(translatedFirstPoint.z, 0.000001),
      );

      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(originalFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(originalFirstPoint.z, 0.000001),
      );
      expect(provider.canUndoTransform, isFalse);
      expect(provider.canRedoTransform, isTrue);

      expect(await provider.redoTransform(), isTrue);
      expect(await provider.redoTransform(), isTrue);
      expect(
        provider.completedRooms.first.points.first.x,
        closeTo(rotatedFirstPoint.x, 0.000001),
      );
      expect(
        provider.completedRooms.first.points.first.z,
        closeTo(rotatedFirstPoint.z, 0.000001),
      );
      _expectSameFeatureGeometry(
        provider.completedRooms[0].features.single,
        provider.completedRooms[1].features.single,
      );
    });

    test('invalida el historial si el plano recibe otra edición', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-safe-history',
        name: 'Casa conectada',
        rooms: _connectedRooms(),
      );

      await provider.translateRoom(
        roomId: 'room-a',
        offsetX: 1,
        offsetZ: 0,
      );
      await provider.updateRoomName('room-a', 'Living principal');

      expect(provider.canUndoTransform, isFalse);
      expect(await provider.undoTransform(), isFalse);
      expect(provider.completedRooms.first.name, 'Living principal');
    });

    test('alinea paredes cercanas sin separar el grupo conectado', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 4.2));
      provider.loadProject(
        uuid: 'project-alignment',
        name: 'Casa para alinear',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(0.2, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4.2, 0.000001));
      expect(provider.completedRooms[2].points.first.x, closeTo(4.2, 0.000001));
      _expectSameFeatureGeometry(
        provider.completedRooms[0].features.single,
        provider.completedRooms[1].features.single,
      );

      expect(provider.canUndoTransform, isTrue);
      expect(await provider.undoTransform(), isTrue);
      expect(provider.completedRooms[0].points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('rechaza la alineación cuando no hay paredes cercanas', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 10));
      provider.loadProject(
        uuid: 'project-no-alignment',
        name: 'Casa separada',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isFalse);
      expect(provider.canUndoTransform, isFalse);
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('rechaza una alineación que solaparía otro ambiente', () async {
      final provider = FloorPlanProvider();
      final rooms = _connectedRooms()
        ..add(_independentRoom(offsetX: 4.2))
        ..add(_diamondObstacle());
      provider.loadProject(
        uuid: 'project-overlap-safe-alignment',
        name: 'Casa con obstáculo',
        rooms: rooms,
      );

      final aligned = await provider.alignRoomToNearestWall(
        roomId: 'room-b',
      );

      expect(aligned, isFalse);
      expect(provider.canUndoTransform, isFalse);
      expect(provider.completedRooms[0].points.first.x, closeTo(0, 0.000001));
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
    });

    test('corrige un hueco pequeño entre paredes candidatas', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-small-gap',
        name: 'Casa con hueco pequeño',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.05)),
      );

      final result = await provider.correctSmallWallGap(
        roomId: 'room-b',
      );

      expect(result, WallAlignmentResult.aligned);
      expect(
        provider.completedRooms[0].points.first.x,
        closeTo(0.05, 0.000001),
      );
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4.05, 0.000001),
      );
      expect(
        provider.completedRooms[2].points.first.x,
        closeTo(4.05, 0.000001),
      );
      expect(provider.canUndoTransform, isTrue);
    });

    test('ignora una separación mayor que el límite de hueco pequeño', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-large-gap',
        name: 'Casa con separación amplia',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.15)),
      );

      final result = await provider.correctSmallWallGap(
        roomId: 'room-b',
      );

      expect(result, WallAlignmentResult.noCandidate);
      expect(provider.completedRooms[1].points[1].x, closeTo(4, 0.000001));
      expect(provider.canUndoTransform, isFalse);
    });

    test(
      'informa cuando evita una corrección que produciría solapamiento',
      () async {
        final provider = FloorPlanProvider();
        provider.loadProject(
          uuid: 'project-small-gap-overlap',
          name: 'Casa con corrección bloqueada',
          rooms: _connectedRooms()
            ..add(_independentRoom(offsetX: 4.05))
            ..add(_diamondObstacle()),
        );

        final result = await provider.correctSmallWallGap(
          roomId: 'room-b',
        );

        expect(result, WallAlignmentResult.overlapPrevented);
        expect(
          provider.completedRooms[0].points.first.x,
          closeTo(0, 0.000001),
        );
        expect(
          provider.completedRooms[1].points[1].x,
          closeTo(4, 0.000001),
        );
        expect(provider.canUndoTransform, isFalse);
      },
    );

    test('mueve y ajusta automáticamente como una sola operación', () async {
      final provider = FloorPlanProvider();
      provider.loadProject(
        uuid: 'project-automatic-adjustment',
        name: 'Casa con ajuste automático',
        rooms: _connectedRooms()
          ..add(_independentRoom(offsetX: 4.15)),
      );

      final result = await provider.translateRoomAutomatically(
        roomId: 'room-b',
        offsetX: 0.10,
        offsetZ: 0,
      );

      expect(result, AutomaticRoomMoveResult.movedAndAdjusted);
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4.15, 0.000001),
      );
      expect(await provider.undoTransform(), isTrue);
      expect(
        provider.completedRooms[1].points[1].x,
        closeTo(4, 0.000001),
      );
    });
  });
}

RoomModel _diamondObstacle() {
  return RoomModel(
    id: 'room-d',
    name: 'Obstáculo geométrico',
    type: RoomType.pasillo,
    points: [
      ARPoint(x: 4.10, y: 0, z: 0.90),
      ARPoint(x: 4.18, y: 0, z: 1.00),
      ARPoint(x: 4.10, y: 0, z: 1.10),
      ARPoint(x: 4.02, y: 0, z: 1.00),
    ],
    isClosed: true,
  );
}

RoomModel _independentRoom({required double offsetX}) {
  return RoomModel(
    id: 'room-c',
    name: 'Ambiente C',
    type: RoomType.dormitorio,
    points: [
      ARPoint(x: offsetX, y: 0, z: 0),
      ARPoint(x: offsetX + 2, y: 0, z: 0),
      ARPoint(x: offsetX + 2, y: 0, z: 2),
      ARPoint(x: offsetX, y: 0, z: 2),
    ],
    isClosed: true,
  );
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