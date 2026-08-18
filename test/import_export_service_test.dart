import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/models/room_model.dart';
import 'package:room_scanner_ar/services/import_export_service.dart';

void main() {
  test('JSON exporta versión, unidad y medidas verticales', () {
    final room = RoomModel(
      id: 'room-1',
      name: 'Dormitorio',
      type: RoomType.dormitorio,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 3),
      ],
      features: [
        WallFeature(
          id: 'window-1',
          type: FeatureType.window,
          start: ARPoint(x: 0.5, y: 0, z: 0),
          end: ARPoint(x: 1.7, y: 0, z: 0),
          openingHeightMeters: 1.1,
          sillHeightMeters: 0.85,
        ),
      ],
      isClosed: true,
    );

    final data = ImportExportService.buildJsonData(
      [room],
      'Casa',
    );
    final rooms = data['rooms'] as List<dynamic>;
    final roomJson = rooms.single as Map<String, dynamic>;
    final features = roomJson['features'] as List<dynamic>;
    final feature = features.single as Map<String, dynamic>;

    expect(data['formatVersion'], 2);
    expect(data['lengthUnit'], 'meters');
    expect(feature['openingHeightMeters'], closeTo(1.1, 0.000001));
    expect(feature['sillHeightMeters'], closeTo(0.85, 0.000001));
  });
}