import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:test/test.dart';

void main() {
  group('detección de paredes compartidas', () {
    test('detecta una pared completa entre dos ambientes', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 2),
          _rectangle('room-b', 2, 0, 4, 2),
        ],
      );

      expect(matches, hasLength(1));
      expect(matches.single.firstRoomId, 'room-a');
      expect(matches.single.secondRoomId, 'room-b');
      expect(matches.single.lengthMeters, closeTo(2, 0.000001));
    });

    test('detecta solamente el tramo realmente superpuesto', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 3),
          _rectangle('room-b', 2, 1, 4, 2),
        ],
      );

      expect(matches, hasLength(1));
      expect(matches.single.lengthMeters, closeTo(1, 0.000001));
      expect(matches.single.start.z, closeTo(1, 0.000001));
      expect(matches.single.end.z, closeTo(2, 0.000001));
    });

    test('no relaciona paredes separadas fuera de tolerancia', () {
      final matches = SharedWallService.detect(
        rooms: [
          _rectangle('room-a', 0, 0, 2, 2),
          _rectangle('room-b', 2.05, 0, 4.05, 2),
        ],
      );

      expect(matches, isEmpty);
    });
  });
}

RoomModel _rectangle(
  String id,
  double minX,
  double minZ,
  double maxX,
  double maxZ,
) {
  return RoomModel(
    id: id,
    name: id,
    type: RoomType.living,
    points: [
      ARPoint(x: minX, y: 0, z: minZ),
      ARPoint(x: maxX, y: 0, z: minZ),
      ARPoint(x: maxX, y: 0, z: maxZ),
      ARPoint(x: minX, y: 0, z: maxZ),
    ],
    isClosed: true,
  );
}