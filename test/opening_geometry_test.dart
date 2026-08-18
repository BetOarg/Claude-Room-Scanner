import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/models/room_model.dart';
import 'package:room_scanner_ar/providers/floor_plan_provider.dart';

ARPoint point(double x, double z) => ARPoint(x: x, y: 0, z: z);

RoomModel roomWithFeatures(List<WallFeature> features) {
  return RoomModel(
    id: 'room-1',
    name: 'Ambiente',
    type: RoomType.living,
    points: [
      point(0, 0),
      point(4, 0),
      point(4, 3),
      point(0, 3),
    ],
    features: features,
    isClosed: true,
  );
}

WallFeature opening({
  required String id,
  required double start,
  required double end,
  FeatureType type = FeatureType.door,
}) {
  return WallFeature(
    id: id,
    type: type,
    start: point(start, 0),
    end: point(end, 0),
  );
}

void main() {
  group('Edición geométrica de aberturas', () {
    test('informa ancho, posición y longitud de pared', () {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
            ]),
          ],
        );

      final placement = provider.getOpeningPlacement(
        roomId: 'room-1',
        featureId: 'door',
      );

      expect(placement, isNotNull);
      expect(placement!.widthMeters, closeTo(1, 0.000001));
      expect(
        placement.distanceFromWallStartMeters,
        closeTo(1, 0.000001),
      );
      expect(placement.wallLengthMeters, closeTo(4, 0.000001));
      expect(placement.openingHeightMeters, closeTo(2.10, 0.000001));
      expect(placement.sillHeightMeters, closeTo(0, 0.000001));
    });

    test('actualiza ancho y posición sobre la misma pared', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
            ]),
          ],
        );

      final result = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 0.8,
        distanceFromWallStartMeters: 2,
        openingHeightMeters: 2.20,
        sillHeightMeters: 0.10,
      );
      final updated = provider.findFeature(
        roomId: 'room-1',
        featureId: 'door',
      );

      expect(result.isSuccess, isTrue);
      expect(updated!.start.x, closeTo(2, 0.000001));
      expect(updated.end.x, closeTo(2.8, 0.000001));
      expect(updated.start.z, closeTo(0, 0.000001));
      expect(updated.end.z, closeTo(0, 0.000001));
      expect(updated.openingHeightMeters, closeTo(2.20, 0.000001));
      expect(updated.sillHeightMeters, closeTo(0.10, 0.000001));
    });

    test('rechaza límites de pared y superposiciones', () async {
      final provider = FloorPlanProvider()
        ..loadProject(
          uuid: 'project',
          name: 'Plano',
          rooms: [
            roomWithFeatures([
              opening(id: 'door', start: 1, end: 2),
              opening(
                id: 'window',
                start: 2.5,
                end: 3.2,
                type: FeatureType.window,
              ),
            ]),
          ],
        );

      final outside = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 1,
        distanceFromWallStartMeters: 3.5,
      );
      final overlap = await provider.updateOpeningGeometry(
        roomId: 'room-1',
        featureId: 'door',
        widthMeters: 1,
        distanceFromWallStartMeters: 2,
      );

      expect(outside.isSuccess, isFalse);
      expect(overlap.isSuccess, isFalse);
    });
  });
}