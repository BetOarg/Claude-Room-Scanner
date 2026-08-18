import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/models/room_model.dart';

void main() {
  group('Orientación persistente de puertas', () {
    test('usa valores seguros al abrir un proyecto anterior', () {
      final feature = WallFeature.fromJson({
        'id': 'door-1',
        'type': 'door',
        'start': {'x': 0, 'y': 0, 'z': 0},
        'end': {'x': 0.9, 'y': 0, 'z': 0},
      });

      expect(feature.doorHingeSide, DoorHingeSide.start);
      expect(feature.doorSwingSide, DoorSwingSide.left);
      expect(feature.openingHeightMeters, closeTo(2.10, 0.000001));
      expect(feature.sillHeightMeters, closeTo(0, 0.000001));
    });

    test('restaura alturas predeterminadas para ventanas anteriores', () {
      final feature = WallFeature.fromJson({
        'id': 'window-1',
        'type': 'window',
        'start': {'x': 0, 'y': 0, 'z': 0},
        'end': {'x': 1.2, 'y': 0, 'z': 0},
      });

      expect(feature.openingHeightMeters, closeTo(1.20, 0.000001));
      expect(feature.sillHeightMeters, closeTo(0.90, 0.000001));
    });

    test('conserva bisagra y giro al exportar e importar', () {
      final original = WallFeature(
        id: 'door-2',
        type: FeatureType.door,
        start: ARPoint(x: 1, y: 0, z: 2),
        end: ARPoint(x: 1.8, y: 0, z: 2),
        doorHingeSide: DoorHingeSide.end,
        doorSwingSide: DoorSwingSide.right,
        openingHeightMeters: 2.25,
        sillHeightMeters: 0.05,
      );

      final restored = WallFeature.fromJson(original.toJson());

      expect(restored.doorHingeSide, DoorHingeSide.end);
      expect(restored.doorSwingSide, DoorSwingSide.right);
      expect(restored.openingHeightMeters, closeTo(2.25, 0.000001));
      expect(restored.sillHeightMeters, closeTo(0.05, 0.000001));
    });

    test('copyWith cambia solamente la orientación indicada', () {
      final original = WallFeature(
        id: 'door-3',
        type: FeatureType.door,
        start: ARPoint(x: 0, y: 0, z: 0),
        end: ARPoint(x: 1, y: 0, z: 0),
      );

      final updated = original.copyWith(
        doorHingeSide: DoorHingeSide.end,
      );

      expect(updated.doorHingeSide, DoorHingeSide.end);
      expect(updated.doorSwingSide, DoorSwingSide.left);
      expect(updated.start.x, original.start.x);
      expect(updated.end.x, original.end.x);
    });
  });
}